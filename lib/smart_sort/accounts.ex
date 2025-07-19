defmodule SmartSort.Accounts do
  import Ecto.Query, warn: false
  alias SmartSort.Macros.NotFound
  alias SmartSort.Accounts.Category
  alias SmartSort.Repo
  alias SmartSort.Accounts.{User, ConnectedAccount}

  def get_user_connected_accounts(user_id) do
    ConnectedAccount
    |> where([ca], ca.user_id == ^user_id and ca.is_primary == false)
    |> order_by([ca], desc: ca.is_primary, asc: ca.inserted_at)
    |> Repo.all()
  end

  defp create_connected_account(user, attrs) do
    %ConnectedAccount{}
    |> ConnectedAccount.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  defp update_connected_account(%ConnectedAccount{} = account, attrs) do
    account
    |> ConnectedAccount.changeset(attrs)
    |> Repo.update()
  end

  def find_or_create_user_from_oauth(auth) do
    with {:ok, connected_account} <-
           ConnectedAccount.get_one_by(%{provider: "google", provider_id: auth.uid}),
         {:ok, updated_account} <-
           ConnectedAccount.update(
             connected_account,
             %{
               access_token: auth.credentials.token,
               refresh_token: auth.credentials.refresh_token
             },
             [:user]
           ) do
      {:ok, updated_account.user, connected_account}
    else
      {:error, %NotFound{}} ->
        case User.get_one_by(%{email: auth.info.email}) do
          {:ok, user} ->
            add_connected_account_to_user(user, auth)

          {:error, %NotFound{}} ->
            create_user_with_oauth(auth)
        end
    end
  end

  def add_email_account_to_existing_user(existing_user, auth) do
    case ConnectedAccount.get_one_by(%{provider: "google", provider_id: auth.uid}) do
      {:ok, %ConnectedAccount{} = secondary_connected_account} ->
        ConnectedAccount.update(secondary_connected_account, %{
          is_primary: false,
          access_token: auth.credentials.token,
          refresh_token: auth.credentials.refresh_token
        })

        update_connected_account_tokens(secondary_connected_account, auth)
        {:ok, secondary_connected_account}

      {:error, %NotFound{}} ->
        case ConnectedAccount.get_one_by(%{user_id: existing_user.id, email: auth.info.email}) do
          {:error, %NotFound{}} ->
            account_attrs = %{
              email: auth.info.email,
              provider: "google",
              provider_id: auth.uid,
              access_token: auth.credentials.token,
              expires_at: auth.credentials.expires_at,
              refresh_token: auth.credentials.refresh_token,
              is_primary: false
            }

            create_connected_account(existing_user, account_attrs)

          {:ok, %ConnectedAccount{}} ->
            {:error, :already_connected}
        end
    end
  end

  def list_users_with_expiring_tokens do
    expiry_threshold = DateTime.add(DateTime.utc_now(), 10 * 60, :second)

    from(u in ConnectedAccount,
      where:
        not is_nil(u.access_token) and
          not is_nil(u.refresh_token) and
          (is_nil(u.access_token_expires_at) or u.access_token_expires_at <= ^expiry_threshold)
    )
    |> Repo.all()
  end

  defp create_user_with_oauth(auth) do
    Repo.transaction(fn ->
      user_attrs = %{
        email: auth.info.email,
        name: auth.info.name,
        avatar: auth.info.image
      }

      {:ok, user} = User.create(user_attrs)

      account_attrs = %{
        email: auth.info.email,
        provider: "google",
        provider_id: auth.uid,
        access_token: auth.credentials.token,
        refresh_token: auth.credentials.refresh_token,
        is_primary: true
      }

      {:ok, connected_account} = create_connected_account(user, account_attrs)

      {:ok, user, connected_account}
    end)
    |> case do
      {:ok, response} -> response
      error -> error
    end
  end

  defp add_connected_account_to_user(user, auth) do
    account_attrs = %{
      email: auth.info.email,
      provider: "google",
      provider_id: auth.uid,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      is_primary: false
    }

    case create_connected_account(user, account_attrs) do
      {:ok, connected_account} -> {:ok, user, connected_account}
      error -> error
    end
  end

  defp update_connected_account_tokens(connected_account, auth) do
    attrs = %{
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token
    }

    case update_connected_account(connected_account, attrs) do
      {:ok, updated_account} -> {:ok, updated_account.user}
      error -> error
    end
  end
end
