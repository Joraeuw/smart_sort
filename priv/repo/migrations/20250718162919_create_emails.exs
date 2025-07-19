defmodule SmartSort.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :connected_account_id, references(:connected_accounts, on_delete: :delete_all),
        null: false

      add :category_id, references(:categories, on_delete: :nilify_all)
      add :gmail_id, :string, null: false
      add :thread_id, :string
      add :subject, :string
      add :from_email, :string
      add :from_name, :string
      add :to_email, :string
      add :snippet, :text
      add :body_preview, :text
      add :ai_summary, :text
      add :received_at, :utc_datetime
      add :is_archived, :boolean, default: false
      add :is_read, :boolean, default: false

      timestamps()
    end

    create index(:emails, [:user_id])
    create index(:emails, [:connected_account_id])
    create index(:emails, [:category_id])
    create unique_index(:emails, [:connected_account_id, :gmail_id])
    create index(:emails, [:received_at])
  end
end
