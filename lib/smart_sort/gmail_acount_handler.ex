defmodule SmartSort.GmailAccountHandler do
  require Logger
  alias SmartSort.AI.EmailProcessor
  alias SmartSort.Accounts.Category
  alias SmartSort.Accounts.Email
  alias SmartSort.Helpers.PersistEnv
  alias SmartSort.Accounts.ConnectedAccount
  alias SmartSort.Helpers.WithHelpers

  def start_gmail_notifications(%ConnectedAccount{} = account) do
    account = ensure_fresh_token(account)

    url = "https://gmail.googleapis.com/gmail/v1/users/me/watch"

    headers = [
      {"Authorization", "Bearer #{account.access_token}"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "topicName" => "projects/#{PersistEnv.project_id()}/topics/gmail-notifications",
        "labelIds" => ["INBOX"],
        "labelFilterAction" => "include"
      })

    case HTTPoison.post(url, body, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"historyId" => history_id, "expiration" => expiration}} ->
            if is_nil(account.last_gmail_history_id) do
              update_last_history_id(account, history_id)
            end

            {:ok, %{history_id: history_id, expiration: expiration}}

          {:error, reason} ->
            Logger.error("Failed to parse Gmail watch response: #{inspect(reason)}")
            {:error, "parse_failed"}
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Gmail watch failed for #{account.email}: #{status} - #{body}")
        {:error, "http_error_#{status}"}

      {:error, reason} ->
        Logger.error("Gmail watch request failed for #{account.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def stop_gmail_notifications(%ConnectedAccount{} = account) do
    account = ensure_fresh_token(account)
    url = "https://gmail.googleapis.com/gmail/v1/users/me/stop"

    headers = [
      {"Authorization", "Bearer #{account.access_token}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post(url, "", headers) do
      {:ok, %{status_code: 204}} ->
        :ok

      {:ok, %{status_code: status, body: body}} ->
        Logger.warning("Gmail stop failed for #{account.email}: #{status} - #{body}")
        {:error, "http_error_#{status}"}

      {:error, reason} ->
        Logger.error("Gmail stop request failed for #{account.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def start_all_gmail_notifications do
    case ConnectedAccount.all() do
      {:ok, accounts} ->
        results =
          Enum.map(accounts, fn account ->
            case start_gmail_notifications(account) do
              {:ok, %{expiration: expiration} = result} ->
                {account.email, :ok, result}

              {:error, reason} ->
                {account.email, :error, reason}
            end
          end)

        successful = Enum.count(results, fn {_, status, _} -> status == :ok end)
        total = length(results)

        Logger.info("Gmail notifications setup complete: #{successful}/#{total} accounts")
        {:ok, results}

      {:error, reason} ->
        Logger.error("Failed to get Gmail accounts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def fetch_email_changes(%ConnectedAccount{} = acc, current_history_id) do
    acc = ensure_fresh_token(acc)
    conn = GoogleApi.Gmail.V1.Connection.new(acc.access_token)

    case acc.last_gmail_history_id do
      nil ->
        setup_initial_baseline(conn, acc, current_history_id)

      last_history_id when last_history_id == current_history_id ->
        :ok

      last_history_id ->
        fetch_history_changes(conn, acc, last_history_id, current_history_id)
    end
  end

  def refresh_access_token(acc) do
    with {:ok, response} <- make_token_request(acc.refresh_token),
         {:ok, body} <- validate_response_status(response),
         {:ok, token_data} <- parse_token_response(body),
         {:ok, updated_acc} <- update_account_tokens(acc, token_data) do
      {:ok, updated_acc, token_data.access_token}
    else
      {:error, :http_request_failed} = error ->
        Logger.error("HTTP request failed during token refresh for #{acc.email}")
        error

      {:error, :invalid_status, status, body} ->
        Logger.error("Token refresh failed for #{acc.email} with status #{status}: #{body}")
        {:error, {:http_error, status, body}}

      {:error, :json_decode_failed} = error ->
        Logger.error("Failed to decode token response for #{acc.email}")
        error

      {:error, :missing_access_token} = error ->
        Logger.error("Access token missing from response for #{acc.email}")
        error

      {:error, reason} = error ->
        Logger.error("Token refresh failed for #{acc.email}: #{inspect(reason)}")
        error
    end
  end

  defp make_token_request(refresh_token) do
    params = %{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => PersistEnv.google_client_id(),
      "client_secret" => PersistEnv.google_client_secret()
    }

    headers = [{"Content-Type", "application/json"}]

    case Tesla.post("https://oauth2.googleapis.com/token", Jason.encode!(params),
           headers: headers
         ) do
      {:ok, response} -> {:ok, response}
      {:error, _reason} -> {:error, :http_request_failed}
    end
  end

  defp validate_response_status(%{status: 200, body: body}), do: {:ok, body}

  defp validate_response_status(%{status: status, body: body}),
    do: {:error, :invalid_status, status, body}

  defp parse_token_response(body) do
    case Jason.decode(body) do
      {:ok, %{"access_token" => access_token} = response} ->
        expires_in = Map.get(response, "expires_in", 3600)
        expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

        {:ok,
         %{
           access_token: access_token,
           expires_at: expires_at
         }}

      {:ok, _response} ->
        {:error, :missing_access_token}

      {:error, _reason} ->
        {:error, :json_decode_failed}
    end
  end

  defp update_account_tokens(acc, %{access_token: access_token, expires_at: expires_at}) do
    case ConnectedAccount.update(acc, %{
           access_token: access_token,
           access_token_expires_at: expires_at
         }) do
      {:ok, updated_acc} -> {:ok, updated_acc}
      {:error, reason} -> {:error, reason}
    end
  end

  defp setup_initial_baseline(conn, acc, current_history_id) do
    case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_list(
           conn,
           "me",
           labelIds: ["INBOX"],
           maxResults: 1
         ) do
      {:ok, %{messages: [%{id: message_id}]}} ->
        fetch_message_content(conn, acc, message_id)

      {:ok, %{messages: []}} ->
        Logger.debug("No recent messages found for #{acc.email}")

      {:error, reason} ->
        Logger.warning("Failed to fetch triggering message for #{acc.email}: #{inspect(reason)}")
    end

    update_last_history_id(acc, current_history_id)
  end

  defp fetch_history_changes(conn, acc, start_history_id, current_history_id) do
    case GoogleApi.Gmail.V1.Api.Users.gmail_users_history_list(
           conn,
           "me",
           startHistoryId: start_history_id,
           historyTypes: ["messageAdded"]
         ) do
      {:ok, %{history: history}} when is_list(history) ->
        Enum.each(history, fn history_item ->
          process_history_item(conn, acc, history_item)
        end)

        update_last_history_id(acc, current_history_id)

      {:ok, _response} ->
        Logger.debug("No new Gmail messages in range for #{acc.email}")
        update_last_history_id(acc, current_history_id)

      {:error, reason} ->
        Logger.error("Failed to fetch Gmail history changes for #{acc.email}: #{inspect(reason)}")
    end
  end

  defp process_history_item(conn, acc, %GoogleApi.Gmail.V1.Model.History{
         messagesAdded: messages
       })
       when is_list(messages) do
    Enum.each(messages, fn %{message: %{id: message_id}} ->
      fetch_message_content(conn, acc, message_id)
    end)
  end

  defp fetch_message_content(conn, acc, message_id) do
    case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_get(conn, "me", message_id,
           format: "full"
         ) do
      {:ok, message} ->
        email_data = extract_email_data(message)
        Logger.info("New email received for #{acc.email}: #{email_data.subject}")
        Logger.debug("Email details for #{acc.email}", email_data: email_data)
        handle_new_email(acc, email_data)

      {:error, %Tesla.Env{status: 404}} ->
        Logger.warning(
          "Gmail message #{message_id} for #{acc.email} not found (may have been deleted or moved)"
        )

        :not_found

      {:error, reason} ->
        Logger.error(
          "Failed to fetch Gmail message #{message_id} for #{acc.email}: #{inspect(reason)}"
        )
    end
  end

  defp extract_email_data(message) do
    headers = get_headers(message)
    body_data = extract_email_body(message.payload)

    %{
      id: message.id,
      thread_id: message.threadId,
      subject: get_header_value(headers, "Subject"),
      from: get_header_value(headers, "From"),
      to: get_header_value(headers, "To"),
      date: get_header_value(headers, "Date"),
      snippet: message.snippet,
      body: body_data.content,
      body_type: body_data.type,
      labels: message.labelIds || []
    }
  end

  defp extract_email_body(payload) do
    extract_body_from_parts([payload])
  end

  defp extract_body_from_parts(parts) do
    {plain_text, html_content} =
      parts
      |> Enum.reduce({nil, nil}, fn part, {plain_acc, html_acc} ->
        case part do
          %{mimeType: "text/plain", body: %{data: data}} ->
            decoded = decode_gmail_body_data(data)
            {decoded || plain_acc, html_acc}

          %{mimeType: "text/html", body: %{data: data}} ->
            decoded = decode_gmail_body_data(data)
            {plain_acc, decoded || html_acc}

          %{parts: subparts} when is_list(subparts) ->
            sub_result = extract_body_from_parts(subparts)

            case sub_result do
              %{type: "text/plain", content: content} ->
                {content || plain_acc, html_acc}

              %{type: "text/html", content: content} ->
                {plain_acc, content || html_acc}

              _ ->
                {plain_acc, html_acc}
            end

          _ ->
            {plain_acc, html_acc}
        end
      end)

    cond do
      not is_nil(html_content) -> %{type: "text/html", content: html_content}
      not is_nil(plain_text) -> %{type: "text/plain", content: plain_text}
      true -> %{type: "text/plain", content: ""}
    end
  end

  defp decode_gmail_body_data(data) when is_binary(data) do
    data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> pad_base64()
    |> Base.decode64()
    |> case do
      {:ok, binary} -> handle_encoding(binary)
      _ -> nil
    end
  end

  defp decode_gmail_body_data(_), do: nil

  defp pad_base64(data) do
    rem = rem(String.length(data), 4)
    if rem == 0, do: data, else: data <> String.duplicate("=", 4 - rem)
  end

  defp handle_encoding(binary) do
    if String.valid?(binary),
      do: binary,
      else: :unicode.characters_to_binary(binary, :latin1, :utf8)
  end

  defp get_headers(%{payload: %{headers: headers}}) when is_list(headers), do: headers
  defp get_headers(_), do: []

  defp get_header_value(headers, name) do
    case Enum.find(headers, &(&1.name == name)) do
      %{value: value} -> value
      _ -> nil
    end
  end

  defp handle_new_email(connected_account, email_data) do
    %{
      id: gmail_id,
      date: date_string,
      snippet: snippet,
      labels: labels,
      to: to,
      from: from,
      subject: subject,
      thread_id: thread_id,
      body: body
    } = email_data

    {from_email, from_name} = parse_email_address(from)
    {to_email, _} = parse_email_address(to)

    params = %{
      gmail_id: gmail_id,
      thread_id: thread_id,
      subject: subject,
      body: body,
      from_email: from_email,
      from_name: from_name,
      to_email: to_email,
      snippet: snippet,
      received_at: parse_email_date(date_string),
      is_read: not Enum.member?(labels, "UNREAD"),
      is_archived: false,
      user_id: connected_account.user_id,
      connected_account_id: connected_account.id
    }

    with :ok <- WithHelpers.check(not Enum.member?(labels, "DRAFT"), :is_draft),
         {:ok, email} <- Email.create(params) do
      categories = Category.get_all_by(%{user_id: connected_account.user_id})

      if not Enum.empty?(categories) do
        archive_email_on_gmail(email)
        Task.start(fn -> EmailProcessor.process_email(email, categories) end)
      end
    end
  end

  defp parse_email_address(email_string) do
    case Regex.run(~r/^(.+?)\s*<(.+?)>$/, email_string) do
      [_, name, email] -> {String.trim(email), String.trim(name)}
      nil -> {String.trim(email_string), nil}
    end
  end

  defp parse_email_date(date_string) do
    case Timex.parse(date_string, "{RFC1123}") do
      {:ok, datetime} ->
        Timex.to_datetime(datetime, "UTC")

      {:error, _} ->
        DateTime.utc_now()
    end
  end

  defp update_last_history_id(acc, history_id) do
    case ConnectedAccount.update(acc, %{last_gmail_history_id: to_string(history_id)}) do
      {:ok, updated_acc} ->
        updated_acc

      {:error, reason} ->
        Logger.error(
          "Failed to update last Gmail history ID for #{acc.email}: #{inspect(reason)}"
        )

        acc
    end
  end

  defp ensure_fresh_token(acc) do
    if token_expires_soon?(acc) do
      case refresh_access_token(acc) do
        {:ok, new_acc, _new_token} ->
          new_acc

        {:error, reason} ->
          Logger.warning(
            "Failed to refresh token for #{acc.email}, using existing token: #{inspect(reason)}"
          )

          acc
      end
    else
      acc
    end
  end

  defp token_expires_soon?(acc, threshold_seconds \\ 300) do
    case acc.access_token_expires_at do
      nil ->
        true

      expires_at ->
        seconds_until_expiry = DateTime.diff(expires_at, DateTime.utc_now())
        expires_soon = seconds_until_expiry < threshold_seconds

        if expires_soon do
          status = if seconds_until_expiry <= 0, do: "expired", else: "expires soon"

          Logger.debug(
            "Token for #{acc.email} #{status} (#{seconds_until_expiry}s), will refresh"
          )
        end

        expires_soon
    end
  end

  defp archive_email_on_gmail(%Email{} = email) do
    case ConnectedAccount.get(email.connected_account_id) do
      {:ok, account} ->
        account = ensure_fresh_token(account)

        conn = GoogleApi.Gmail.V1.Connection.new(account.access_token)

        case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_modify(
               conn,
               "me",
               email.gmail_id,
               body: %GoogleApi.Gmail.V1.Model.ModifyMessageRequest{
                 removeLabelIds: ["INBOX"]
               }
             ) do
          {:ok, _response} ->
            Logger.info(
              "Successfully archived email #{email.gmail_id} in Gmail for #{account.email}"
            )

            {:ok, :archived}

          {:error, reason} ->
            Logger.error(
              "Failed to archive email #{email.gmail_id} in Gmail for #{account.email}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(
          "Failed to get connected account #{email.connected_account_id} for archiving email: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
