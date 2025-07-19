defmodule SmartSort.Accounts.ConnectedAccount do
  use SmartSort.Macros.DefaultModel

  import Ecto.Changeset

  schema "connected_accounts" do
    field :email, :string
    field :provider, :string
    field :provider_id, :string
    field :access_token, :string, redact: true
    field :refresh_token, :string, redact: true
    field :is_primary, :boolean, default: false
    field :last_gmail_history_id, :string
    field :access_token_expires_at, :utc_datetime

    belongs_to :user, SmartSort.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(connected_account, attrs \\ %{}) do
    connected_account
    |> cast(attrs, [
      :email,
      :user_id,
      :provider,
      :provider_id,
      :access_token,
      :refresh_token,
      :is_primary,
      :last_gmail_history_id,
      :access_token_expires_at
    ])
    |> validate_required([:email, :provider, :provider_id, :user_id])
    |> unique_constraint([:provider, :provider_id])
    |> unique_constraint([:user_id, :email])
  end
end
