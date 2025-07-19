defmodule SmartSort.Repo.Migrations.AddLastGmailHistory do
  use Ecto.Migration

  def change do
    alter table(:connected_accounts) do
      add :last_gmail_history_id, :string
    end
  end
end
