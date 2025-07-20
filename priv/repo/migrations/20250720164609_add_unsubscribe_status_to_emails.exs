defmodule SmartSort.Repo.Migrations.AddUnsubscribeStatusToEmails do
  use Ecto.Migration

  def change do
    alter table(:emails) do
      add :unsubscribe_status, :string
      add :unsubscribe_attempted_at, :utc_datetime
      add :unsubscribe_completed_at, :utc_datetime
      add :unsubscribe_details, :text
    end
  end
end
