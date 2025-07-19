defmodule SmartSort.Repo.Migrations.AddAccessTokenExpiry do
  use Ecto.Migration

  def change do
    alter table(:connected_accounts) do
      add :access_token_expires_at, :utc_datetime
    end
  end
end
