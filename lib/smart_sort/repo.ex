defmodule SmartSort.Repo do
  use Ecto.Repo,
    otp_app: :smart_sort,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 10
end
