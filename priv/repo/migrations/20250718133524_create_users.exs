defmodule SmartSort.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string, null: false
      add :avatar, :string

      timestamps()
    end

    create unique_index(:users, [:email])

    # Create connections
    create table(:connected_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :provider, :string, null: false
      add :provider_id, :string, null: false
      add :access_token, :text
      add :refresh_token, :text
      add :is_primary, :boolean, default: false

      timestamps()
    end

    create index(:connected_accounts, [:user_id])
    create unique_index(:connected_accounts, [:provider, :provider_id])
    create unique_index(:connected_accounts, [:user_id, :email])

    # Creating categories
    create table(:categories) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :email_count, :integer, default: 0

      timestamps()
    end

    create index(:categories, [:user_id])
    create unique_index(:categories, [:user_id, :name])
  end
end
