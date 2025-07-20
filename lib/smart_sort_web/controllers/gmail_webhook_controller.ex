defmodule SmartSortWeb.GmailWebhookController do
  use SmartSortWeb, :controller
  require Logger

  alias SmartSort.Accounts.ConnectedAccount

  def receive(conn, %{"message" => %{"data" => data}}) do
    case decode_gmail_data(data) do
      {:ok, %{"emailAddress" => email, "historyId" => history_id}} ->
        Task.start(fn -> process_gmail_change(email, history_id) end)

      {:ok, _data} ->
        Logger.error("Invalid Gmail notification format: missing required fields")

      {:error, reason} ->
        Logger.error("Failed to decode Gmail notification: #{inspect(reason)}")
    end

    json(conn, %{status: "ok"})
  end

  def receive(conn, params) do
    Logger.error("Unexpected Gmail webhook format: #{inspect(params)}")
    json(conn, %{status: "ok"})
  end

  defp decode_gmail_data(base64_data) when is_binary(base64_data) do
    with {:ok, data} <- Base.decode64(base64_data),
         {:ok, data} <- Jason.decode(data) do
      {:ok, data}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp decode_gmail_data(_), do: {:error, :invalid_data}

  defp process_gmail_change(email, history_id) do
    case ConnectedAccount.get_by(%{email: email}, [:user]) do
      {:ok, %ConnectedAccount{access_token: token} = acc} when not is_nil(token) ->
        SmartSort.GmailAccountHandler.fetch_email_changes(acc, history_id)

      _ ->
        Logger.error("No valid account found for #{email}")
    end
  end
end
