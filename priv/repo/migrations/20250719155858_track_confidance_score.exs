defmodule SmartSort.Repo.Migrations.TrackConfidanceScore do
  use Ecto.Migration

  def change do
    alter table(:emails) do
      add :confidence_score, :float
    end
  end
end
