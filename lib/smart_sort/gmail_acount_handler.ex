defmodule SmartSort.GmailAccountHandler do
  require Logger
  alias SmartSort.Helpers.PersistEnv
  alias SmartSort.Accounts.ConnectedAccount

  def start_watching_inbox(acc) do
    new_acc = ensure_fresh_token(acc)
    conn = GoogleApi.Gmail.V1.Connection.new(new_acc.access_token)

    watch_request = %GoogleApi.Gmail.V1.Model.WatchRequest{
      topicName: "projects/#{PersistEnv.project_id()}/topics/gmail-notifications",
      labelIds: ["INBOX"]
    }

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_watch(conn, "me", body: watch_request) do
      {:ok, response} ->
        Logger.info("Started watching Gmail inbox for #{new_acc.email}")
        {:ok, response}

      {:error, reason} ->
        Logger.error(
          "Failed to start watching Gmail inbox for #{new_acc.email}: #{inspect(reason)}"
        )

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
    Logger.debug("Refreshing access token for #{acc.email}")

    with {:ok, response} <- make_token_request(acc.refresh_token),
         {:ok, body} <- validate_response_status(response),
         {:ok, token_data} <- parse_token_response(body),
         {:ok, updated_acc} <- update_account_tokens(acc, token_data) do
      Logger.info("Successfully refreshed access token for #{acc.email}")
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
        Logger.info("Found #{length(history)} Gmail history changes for #{acc.email}")

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
    case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_get(conn, "me", message_id) do
      {:ok, message} ->
        email_data = extract_email_data(message)
        Logger.info("New email received for #{acc.email}: #{email_data.subject}")
        Logger.debug("Email details for #{acc.email}", email_data: email_data)

        handle_new_email(acc, email_data)

      {:error, reason} ->
        Logger.error(
          "Failed to fetch Gmail message #{message_id} for #{acc.email}: #{inspect(reason)}"
        )
    end
  end

  defp extract_email_data(message) do
    headers = get_headers(message)

    %{
      id: message.id,
      thread_id: message.threadId,
      subject: get_header_value(headers, "Subject"),
      from: get_header_value(headers, "From"),
      to: get_header_value(headers, "To"),
      date: get_header_value(headers, "Date"),
      snippet: message.snippet,
      labels: message.labelIds || []
    }
  end

  defp get_headers(%{payload: %{headers: headers}}) when is_list(headers), do: headers
  defp get_headers(_), do: []

  defp get_header_value(headers, name) do
    case Enum.find(headers, &(&1.name == name)) do
      %{value: value} -> value
      _ -> nil
    end
  end

  defp handle_new_email(_acc, email_data) do
    IO.inspect(email_data)

    # TODO: PROCESS EMAILS
    # - Store in database
    # - Run AI analysis
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
end
