defmodule SmartSort.GmailAccountHandlerNotifications do
  require Logger
  use Broadway

  alias SmartSort.Helpers.PersistEnv
  alias SmartSort.Accounts.ConnectedAccount
  alias Broadway.Message

  def start_link(_opts) do
    subscription = "projects/#{PersistEnv.project_id()}/subscriptions/gmail-notifications-sub"

    Logger.info(
      "Starting Gmail notifications Broadway pipeline for subscription: #{subscription}"
    )

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayCloudPubSub.Producer, goth: SmartSort.Goth, subscription: subscription}
      ],
      processors: [default: [concurrency: 5]],
      batchers: [default: [batch_size: 10, batch_timeout: 2_000]]
    )
  end

  def handle_message(_, %Message{data: data} = message, _) do
    Logger.debug("Received Gmail notification message")

    case decode_notification(data) do
      {:ok, %{"emailAddress" => email, "historyId" => history_id}} ->
        Logger.debug("Processing Gmail notification for #{email}, historyId: #{history_id}")
        handle_email_notification(email, history_id)
        message

      {:ok, invalid_data} ->
        Logger.warning("Received Gmail notification with invalid format",
          notification_data: invalid_data
        )

        Message.failed(message, "Invalid notification format")

      {:error, reason} ->
        Logger.error("Failed to decode Gmail notification: #{reason}")
        Message.failed(message, "Notification decode failed")
    end
  end

  def handle_batch(_, messages, _, _) do
    Logger.debug("Processing batch of #{length(messages)} Gmail notifications")
    messages
  end

  defp decode_notification(data) do
    case Jason.decode(data) do
      {:ok, json} when is_map(json) ->
        if Map.has_key?(json, "emailAddress") and Map.has_key?(json, "historyId") do
          {:ok, json}
        else
          {:error, "missing_required_fields"}
        end

      {:ok, _invalid} ->
        {:error, "invalid_json_structure"}

      {:error, jason_error} ->
        {:error, "json_decode_error: #{inspect(jason_error)}"}
    end
  end

  defp handle_email_notification(email, history_id) do
    Logger.debug("Looking up connected account for email: #{email}")

    case ConnectedAccount.get_by(%{email: email}, [:user]) do
      {:ok, %ConnectedAccount{access_token: token} = acc} when not is_nil(token) ->
        Logger.debug("Found valid connected account for #{email}")
        process_user_emails(acc, history_id)

      {:ok, _acc} ->
        Logger.warning("Connected account found for #{email} but no valid access token available")

      {:error, reason} ->
        Logger.warning("No connected account found for #{email}: #{inspect(reason)}")
    end
  end

  defp process_user_emails(acc, history_id) do
    Logger.info("Processing Gmail changes for #{acc.email}, historyId: #{history_id}")

    try do
      SmartSort.GmailAccountHandler.fetch_email_changes(acc, history_id)
      Logger.debug("Successfully processed Gmail changes for #{acc.email}")
    rescue
      error ->
        Logger.error("Error processing Gmail changes for #{acc.email}: #{inspect(error)}")
    end
  end
end
