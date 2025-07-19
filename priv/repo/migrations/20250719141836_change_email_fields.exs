defmodule SmartSort.Repo.Migrations.ChangeEmailFields do
  use Ecto.Migration

  def change do
    rename table(:emails), :body_preview, to: :body
  end
end
