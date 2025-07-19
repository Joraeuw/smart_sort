defmodule SmartSort.Accounts.Email do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emails" do
    field :gmail_id, :string
    field :thread_id, :string
    field :subject, :string
    field :from_email, :string
    field :from_name, :string
    field :to_email, :string
    field :snippet, :string
    field :body_preview, :string
    field :ai_summary, :string
    field :received_at, :utc_datetime
    field :is_archived, :boolean, default: false
    field :is_read, :boolean, default: false

    belongs_to :user, SmartSort.Accounts.User
    belongs_to :connected_account, SmartSort.Accounts.ConnectedAccount
    belongs_to :category, SmartSort.Accounts.Category

    timestamps()
  end

  @doc false
  def changeset(email, attrs) do
    email
    |> cast(attrs, [
      :gmail_id,
      :thread_id,
      :subject,
      :from_email,
      :from_name,
      :to_email,
      :snippet,
      :body_preview,
      :ai_summary,
      :received_at,
      :is_archived,
      :is_read
    ])
    |> validate_required([:gmail_id, :subject, :from_email, :received_at])
    |> validate_format(:from_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_format(:to_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:subject, max: 500)
    |> validate_length(:snippet, max: 1000)
    |> validate_length(:body_preview, max: 5000)
    |> validate_length(:ai_summary, max: 2000)
    |> unique_constraint([:connected_account_id, :gmail_id],
      message: "Email already exists for this account"
    )
  end

  def gmail_changeset(email, attrs) do
    email
    |> cast(attrs, [
      :gmail_id,
      :thread_id,
      :subject,
      :from_email,
      :from_name,
      :to_email,
      :snippet,
      :body_preview,
      :received_at
    ])
    |> validate_required([:gmail_id, :subject, :from_email, :received_at])
    |> validate_format(:from_email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_format(:to_email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint([:connected_account_id, :gmail_id])
  end

  def ai_summary_changeset(email, ai_summary) do
    email
    |> cast(%{ai_summary: ai_summary}, [:ai_summary])
    |> validate_length(:ai_summary, max: 2000)
  end

  def archive_changeset(email, is_archived) do
    email
    |> cast(%{is_archived: is_archived}, [:is_archived])
    |> validate_inclusion(:is_archived, [true, false])
  end

  def read_changeset(email, is_read) do
    email
    |> cast(%{is_read: is_read}, [:is_read])
    |> validate_inclusion(:is_read, [true, false])
  end

  def categorize_changeset(email, category_id) do
    email
    |> cast(%{category_id: category_id}, [:category_id])
  end
end
