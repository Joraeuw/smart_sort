defmodule SmartSort.Macros.DefaultModel do
  alias SmartSort.Macros.QueryHelpers

  @moduledoc false
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import Ecto.Query, warn: false
      alias SmartSort.Repo
      alias SmartSort.Macros.NotFound

      @schema_prefix "public"
      def create(attrs, preloads \\ []) do
        case struct(__MODULE__, %{})
             |> changeset(attrs)
             |> Repo.insert() do
          {:ok, res} ->
            {:ok, res |> Repo.preload(preloads)}

          error ->
            error
        end
      end

      def update_changeset(params, attrs), do: changeset(params, attrs)

      def update(entry, params, preloads \\ [])

      def update(entry, params, preloads)
          when :erlang.map_get(:__struct__, entry) == __MODULE__ do
        with {:ok, result} <- Repo.update(update_changeset(entry, params)) do
          {:ok, result |> Repo.preload(preloads)}
        end
      end

      def update(id, params, preloads) do
        with {:ok, entry} <- get(id),
             {:ok, result} <- Repo.update(update_changeset(entry, params)) do
          {:ok, result |> Repo.preload(preloads)}
        end
      end

      def update!(entry, params, preloads \\ [])

      def update!(entry, params, preloads)
          when :erlang.map_get(:__struct__, entry) == __MODULE__ do
        entry |> update_changeset(params) |> Repo.update!() |> Repo.preload(preloads)
      end

      def update!(id, params, preloads) do
        with {:ok, entry} <- get(id) do
          update!(entry, params, preloads)
        end
      end

      def update_all(%{} = params) do
        params =
          params
          |> Map.put(:updated_at, NaiveDateTime.utc_now())
          |> Map.to_list()

        pkey_name = __MODULE__.__schema__(:primary_key)

        from(m in __MODULE__, select: ^pkey_name)
        |> Repo.update_all(set: params)
        |> case do
          entry when not is_nil(entry) ->
            {:ok, entry}

          _ ->
            {:error, %NotFound{entity: __MODULE__}}
        end
      end

      def update_assoc(id, params, preloads \\ []) do
        with {:ok, entry} <- get(id, preloads),
             {:ok, result} <- Repo.update(changeset(entry, params)),
             {:ok, updated_entry} <- get(id, preloads) do
          {:ok, updated_entry}
        else
          error ->
            error
        end
      end

      def all(limit, offset, preloads \\ []) do
        case from(p in __MODULE__, limit: ^limit, offset: ^offset)
             |> Repo.all()
             |> Repo.preload(preloads) do
          entry when not is_nil(entry) ->
            {:ok, entry}

          _ ->
            {:error, %NotFound{entity: __MODULE__}}
        end
      end

      def all(preloads \\ []) do
        case __MODULE__
             |> Repo.all()
             |> Repo.preload(preloads) do
          entry when not is_nil(entry) ->
            {:ok, entry}

          _ ->
            {:error, %NotFound{entity: __MODULE__}}
        end
      end

      def get(id, preloads \\ []) do
        case Repo.get(__MODULE__, id) |> Repo.preload(preloads) do
          entry when not is_nil(entry) ->
            {:ok, entry}

          _ ->
            {:error, %NotFound{entity: __MODULE__}}
        end
      end

      def get!(id, preloads \\ []) do
        __MODULE__
        |> Repo.get!(id)
        |> Repo.preload(preloads)
      end

      def get_last(preloads \\ []) do
        from(item in __MODULE__, preload: ^preloads)
        |> last(:inserted_at)
        |> Repo.one()
      end

      def get_by(search_terms, preloads \\ []) do
        case build_query(search_terms, preloads) |> limit(1) |> Repo.one() do
          entry when not is_nil(entry) ->
            {:ok, entry}

          _ ->
            {:error, %NotFound{entity: __MODULE__}}
        end
      end

      def get_one_by(search_terms, preloads \\ []) do
        search_terms
        |> build_query(preloads)
        |> Repo.one()
        |> case do
          entry when not is_nil(entry) ->
            {:ok, entry}

          _ ->
            {:error, %NotFound{entity: __MODULE__}}
        end
      end

      def get_all_by(search_terms, order \\ nil, preloads \\ []) do
        search_terms
        |> build_query(preloads)
        |> order_by(^order)
        |> Repo.all()
      end

      # def get_all_by(search_terms, order \\ nil, page \\ 1, page_size \\ 100, preloads \\ []) do
      #   entries =
      #     build_query(search_terms, preloads)
      #     |> order_by(^order)
      #     |> Repo.paginate(
      #       page: page,
      #       page_size: page_size,
      #       options: [allow_overflow_page_number: true]
      #     )

      #   case entries do
      #     %Scrivener.Page{
      #       entries: e,
      #       total_entries: total_entries,
      #       page_size: page_size,
      #       page_number: page_number
      #     }
      #     when not is_nil(e) ->
      #       {:ok, e, entries.total_entries}

      #     _ ->
      #       {:error, %NotFound{entity: __MODULE__}}
      #   end
      # end

      def delete(entry, preloads \\ [])

      def delete(entry, preloads)
          when :erlang.map_get(:__struct__, entry) == __MODULE__ do
        with {:ok, entry} <- Repo.delete(__MODULE__.changeset(entry)) do
          {:ok, entry |> Repo.preload(preloads)}
        end
      end

      def delete(id, preloads) do
        with {:ok, entry} <- get(id),
             {:ok, entry} <- Repo.delete(__MODULE__.changeset(entry)) do
          {:ok, entry |> Repo.preload(preloads)}
        end
      end

      defp build_query(search_terms, preloads) do
        where_clause = QueryHelpers.where_clause(search_terms)
        from(item in __MODULE__, preload: ^preloads, where: ^where_clause)
      end

      defp convert_field_name(field) when is_atom(field), do: field
      defp convert_field_name(field) when is_binary(field), do: String.to_existing_atom(field)

      defoverridable(
        update_changeset: 2,
        create: 1,
        create: 2,
        update: 2,
        update: 3,
        delete: 1,
        delete: 2
      )
    end
  end
end
