defmodule SmartSort.Repo.Migrations.AddEmailBodyType do
  use Ecto.Migration

  def change do
    alter table(:emails) do
      add :body_type, :string
    end
  end
end
