defmodule SmartSort.Jobs.RefreshGoogleTokens do
  require Logger
  use Oban.Worker, queue: :default, max_attempts: 3

  alias SmartSort.Macros.NotFound
  alias SmartSort.GmailAccountHandler
  alias SmartSort.Accounts.ConnectedAccount
  alias SmartSort.Accounts

  def schedule(connected_account) do
    case %{account_id: connected_account.id}
         |> __MODULE__.new(schedule_in: 55 * 60)
         |> Oban.insert() do
      {:ok, _job} ->
        Logger.debug("Scheduled token refresh job", account_id: connected_account.id)

      {:error, reason} ->
        Logger.error("Failed to schedule token refresh job",
          account_id: connected_account.id,
          reason: inspect(reason)
        )
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    Logger.debug("Processing token refresh job for account ID: #{account_id}")

    case ConnectedAccount.get(account_id) do
      {:ok, %{refresh_token: refresh_token} = acc} when not is_nil(refresh_token) ->
        refresh_acc_token(acc)

      {:error, %NotFound{}} ->
        Logger.warning("Token refresh failed: account not found for ID #{account_id}")
        {:error, :account_not_found}
    end
  end

  def perform(%Oban.Job{args: %{}}) do
    Logger.info("Starting bulk token refresh for expiring tokens")

    users_needing_refresh = Accounts.list_users_with_expiring_tokens()
    user_count = length(users_needing_refresh)

    Logger.info("Found #{user_count} accounts with expiring tokens")

    results =
      Enum.map(users_needing_refresh, fn user ->
        refresh_acc_token(user)
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Bulk token refresh complete", %{
      total: user_count,
      successful: successful,
      failed: failed
    })

    :ok
  end

  defp refresh_acc_token(acc) do
    Logger.debug("Refreshing token for account: #{acc.email}")

    case GmailAccountHandler.refresh_access_token(acc) do
      {:ok, _new_acc, new_token} ->
        {:ok, new_token}

      {:error, reason} ->
        Logger.error("Failed to refresh token for #{acc.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
