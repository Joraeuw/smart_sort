defmodule SmartSort.Accounts.User do
  use SmartSort.Macros.DefaultModel
  import Ecto.Changeset

  @attrs [
    :email,
    :name,
    :avatar
  ]
  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar, :string

    has_many :connected_accounts, SmartSort.Accounts.ConnectedAccount
    has_many :categories, SmartSort.Accounts.Category

    timestamps()
  end

  @doc false
  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, @attrs)
    |> validate_required([:email, :name])
    |> unique_constraint(:email)
    |> unique_constraint([:provider, :provider_id])
  end

  def oauth_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, @attrs)
    |> validate_required([:email, :provider, :provider_id])
    |> unique_constraint(:email)
    |> unique_constraint([:provider, :provider_id])
  end

  def create_oauth_user(attrs \\ %{}) do
    %__MODULE__{}
    |> oauth_changeset(attrs)
    |> Repo.insert()
  end
end
