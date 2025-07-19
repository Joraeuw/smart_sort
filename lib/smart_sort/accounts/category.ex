defmodule SmartSort.Accounts.Category do
  use SmartSort.Macros.DefaultModel
  import Ecto.Changeset

  @required_attrs [:name, :user_id]
  @available_attrs [:name, :description, :user_id]

  schema "categories" do
    field :name, :string
    field :description, :string
    field :email_count, :integer, default: 0

    belongs_to :user, SmartSort.Accounts.User
    has_many :emails, SmartSort.Accounts.Email

    timestamps()
  end

  @doc false
  def changeset(category, attrs \\ %{}) do
    category
    |> cast(attrs, @available_attrs)
    |> validate_required(@required_attrs)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_number(:email_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :name], message: "You already have a category with this name")
  end

  def increment_email_count(category_id) do
    category = get!(category_id)

    category
    |> Ecto.Changeset.change(email_count: category.email_count + 1)
    |> SmartSort.Repo.update()
  end

  def decrement_email_count(category_id) do
    category = get!(category_id)

    category
    |> Ecto.Changeset.change(email_count: category.email_count - 1)
    |> SmartSort.Repo.update()
  end
end
