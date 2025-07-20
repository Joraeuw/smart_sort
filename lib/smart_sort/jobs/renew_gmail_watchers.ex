defmodule SmartSort.Jobs.RenewGmailWatches do
  require Logger

  use Oban.Worker,
    queue: :renew_gmail_watches,
    max_attempts: 3

  alias SmartSort.Macros.NotFound
  alias SmartSort.GmailAccountHandler
  alias SmartSort.Accounts.ConnectedAccount
  alias SmartSort.Accounts

  def schedule(connected_account) do
    schedule_in_seconds = 6 * 24 * 60 * 60

    case %{account_id: connected_account.id}
         |> __MODULE__.new(schedule_in: schedule_in_seconds)
         |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to schedule Gmail watch renewal job",
          account_id: connected_account.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    case ConnectedAccount.get(account_id) do
      {:ok, %{access_token: access_token} = acc} when not is_nil(access_token) ->
        renew_gmail_watch(acc)

      {:error, %NotFound{}} ->
        Logger.warning("Gmail watch renewal failed: account not found for ID #{account_id}")
        {:error, :account_not_found}

      {:ok, acc} ->
        Logger.warning("Gmail watch renewal skipped: no access token for #{acc.email}")
        {:error, :no_access_token}
    end
  end

  defp renew_gmail_watch(acc) do
    case GmailAccountHandler.start_gmail_notifications(acc) do
      {:ok, %{expiration: new_expiration}} ->
        schedule(acc)

        {:ok, new_expiration}

      {:error, reason} ->
        Logger.error("Failed to renew Gmail watch for #{acc.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
