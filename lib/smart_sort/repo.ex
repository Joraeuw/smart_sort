defmodule SmartSort.Repo do
  use Ecto.Repo,
    otp_app: :smart_sort,
    adapter: Ecto.Adapters.Postgres
end
