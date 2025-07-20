defmodule SmartSort.Accounts.Email do
  use SmartSort.Macros.DefaultModel
  import Ecto.Changeset

  alias SmartSort.Accounts.Category
  alias SmartSort.Accounts.User
  alias SmartSort.Accounts.ConnectedAccount

  @required_params [
    :gmail_id,
    :thread_id,
    :subject,
    :from_email,
    :received_at,
    :user_id,
    :connected_account_id
  ]
  @available_params [
    :from_name,
    :to_email,
    :snippet,
    :body,
    :ai_summary,
    :confidence_score,
    :is_archived,
    :category_id,
    :is_read,
    :body_type,
    :unsubscribe_status,
    :unsubscribe_attempted_at,
    :unsubscribe_completed_at,
    :unsubscribe_details,
    :is_selected
    | @required_params
  ]

  schema "emails" do
    field :gmail_id, :string
    field :thread_id, :string
    field :subject, :string
    field :from_email, :string
    field :from_name, :string
    field :to_email, :string
    field :snippet, :string
    field :body, :string
    field :body_type, :string
    field :ai_summary, :string
    field :confidence_score, :float
    field :received_at, :utc_datetime
    field :is_archived, :boolean, default: false
    field :is_read, :boolean, default: false
    field :unsubscribe_status, :string
    field :unsubscribe_attempted_at, :utc_datetime
    field :unsubscribe_completed_at, :utc_datetime
    field :unsubscribe_details, :string
    field :is_selected, :boolean, virtual: true, default: false

    belongs_to :user, User
    belongs_to :connected_account, ConnectedAccount
    belongs_to :category, Category

    timestamps()
  end

  @doc false
  def changeset(email, attrs \\ %{}) do
    email
    |> cast(attrs, @available_params)
    |> validate_required(@required_params)
    |> validate_format(:from_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_format(:to_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:subject, max: 500)
    |> validate_length(:snippet, max: 1000)
    |> validate_length(:ai_summary, max: 2000)
    |> unique_constraint([:connected_account_id, :gmail_id],
      message: "Email already exists for this account"
    )
  end

  def assign_to_category(email, category_id, ai_summary, confidence_score) do
    result =
      __MODULE__.update(
        email,
        %{
          category_id: category_id,
          ai_summary: ai_summary,
          confidence_score: confidence_score
        }
      )

    case result do
      {:ok, updated_email} ->
        if not is_nil(category_id) do
          broadcast_category_update(category_id, :inc)
        end

        {:ok, updated_email}

      error ->
        error
    end
  end

  def delete(email, preloads \\ []) do
    result = super(email, preloads)

    case result do
      {:ok, %__MODULE__{category_id: category_id}} when not is_nil(category_id) ->
        broadcast_category_update(category_id, :dec)
        result

      {:ok, _email} ->
        result

      _ ->
        result
    end
  end

  @spec filter_where(map()) :: Ecto.Query.dynamic_expr()
  def filter_where(params) do
    Enum.reduce(params, dynamic(true), fn
      {:search_query, value}, dynamic when is_binary(value) and value != "" ->
        search_term = "%#{value}%"

        dynamic(
          [email: e],
          ^dynamic and
            (ilike(e.subject, ^search_term) or
               ilike(e.snippet, ^search_term) or
               ilike(e.body, ^search_term) or
               ilike(e.from_email, ^search_term) or
               ilike(e.from_name, ^search_term))
        )

      {:is_read, value}, dynamic when is_boolean(value) ->
        dynamic([email: e], ^dynamic and e.is_read == ^value)

      {:is_archived, value}, dynamic when is_boolean(value) ->
        dynamic([email: e], ^dynamic and e.is_archived == ^value)

      {:category_id, value}, dynamic when not is_nil(value) ->
        dynamic([email: e], ^dynamic and e.category_id == ^value)

      {:user_id, value}, dynamic when not is_nil(value) ->
        dynamic([email: e], ^dynamic and e.user_id == ^value)

      {:connected_account_id, value}, dynamic when not is_nil(value) ->
        dynamic([email: e], ^dynamic and e.connected_account_id == ^value)

      {:thread_id, value}, dynamic when not is_nil(value) ->
        dynamic([email: e], ^dynamic and e.thread_id == ^value)

      {:from_email, value}, dynamic when is_binary(value) and value != "" ->
        dynamic([email: e], ^dynamic and e.from_email == ^value)

      {:confidence_score_gte, value}, dynamic when is_number(value) ->
        dynamic([email: e], ^dynamic and e.confidence_score >= ^value)

      {:confidence_score_lte, value}, dynamic when is_number(value) ->
        dynamic([email: e], ^dynamic and e.confidence_score <= ^value)

      {:received_after, %DateTime{} = value}, dynamic ->
        dynamic([email: e], ^dynamic and e.received_at >= ^value)

      {:received_before, %DateTime{} = value}, dynamic ->
        dynamic([email: e], ^dynamic and e.received_at <= ^value)

      {_key, value}, dynamic when is_nil(value) or value == "" ->
        dynamic

      {field, value}, dynamic
      when field in [
             :gmail_id,
             :thread_id,
             :subject,
             :from_name,
             :to_email
           ] ->
        dynamic([email: e], ^dynamic and field(e, ^field) == ^value)

      {_key, _value}, dynamic ->
        dynamic
    end)
  end

  @spec order_entity_by(Ecto.Query.t(), list()) :: Ecto.Query.t()
  def order_entity_by(query, order_params) when is_list(order_params) do
    Enum.reduce(order_params, query, fn
      {:received_at, direction}, query when direction in [:asc, :desc] ->
        order_by(query, [email: e], [{^direction, e.received_at}])

      {:subject, direction}, query when direction in [:asc, :desc] ->
        order_by(query, [email: e], [{^direction, e.subject}, {:desc, e.received_at}])

      {:from_email, direction}, query when direction in [:asc, :desc] ->
        order_by(query, [email: e], [{^direction, e.from_email}, {:desc, e.received_at}])

      {:from_name, direction}, query when direction in [:asc, :desc] ->
        order_by(query, [email: e], [{^direction, e.from_name}, {:desc, e.received_at}])

      {:confidence_score, direction}, query when direction in [:asc, :desc] ->
        order_by(query, [email: e], [{^direction, e.confidence_score}, {:desc, e.received_at}])

      {:inserted_at, direction}, query when direction in [:asc, :desc] ->
        order_by(query, [email: e], [{^direction, e.inserted_at}])

      {"newest", _}, query ->
        order_by(query, [email: e], desc: e.received_at)

      {"oldest", _}, query ->
        order_by(query, [email: e], asc: e.received_at)

      {"sender", _}, query ->
        order_by(query, [email: e], asc: e.from_email, desc: e.received_at)

      {"subject", _}, query ->
        order_by(query, [email: e], asc: e.subject, desc: e.received_at)

      {_field, _direction}, query ->
        query
    end)
  end

  def order_entity_by(query, order_atom) when is_atom(order_atom) do
    case order_atom do
      :newest -> order_by(query, [email: e], desc: e.received_at)
      :oldest -> order_by(query, [email: e], asc: e.received_at)
      :sender -> order_by(query, [email: e], asc: e.from_email, desc: e.received_at)
      :subject -> order_by(query, [email: e], asc: e.subject, desc: e.received_at)
      _ -> order_by(query, [email: e], desc: e.received_at)
    end
  end

  def order_entity_by(query, sort_string) when is_binary(sort_string) do
    case sort_string do
      "newest" -> order_by(query, [email: e], desc: e.received_at)
      "oldest" -> order_by(query, [email: e], asc: e.received_at)
      "sender" -> order_by(query, [email: e], asc: e.from_email, desc: e.received_at)
      "subject" -> order_by(query, [email: e], asc: e.subject, desc: e.received_at)
      _ -> order_by(query, [email: e], desc: e.received_at)
    end
  end

  def get_all_by_paginated(
        search_terms,
        order_by \\ [received_at: :desc],
        page \\ 1,
        page_size \\ 10,
        preloads \\ []
      ) do
    try do
      query = from(e in __MODULE__, as: :email)

      query =
        query
        |> where(^filter_where(search_terms))
        |> order_entity_by(order_by)

      query = if preloads != [], do: preload(query, ^preloads), else: query

      total_count =
        query
        |> exclude(:order_by)
        |> exclude(:preload)
        |> select([email: e], count(e.id))
        |> Repo.one()

      offset = (page - 1) * page_size

      emails =
        query
        |> limit(^page_size)
        |> offset(^offset)
        |> Repo.all()

      {:ok, emails, total_count}
    rescue
      error ->
        {:error, error}
    end
  end

  def get_emails_for_category_paginated(category_id, opts \\ []) do
    search_query = Keyword.get(opts, :search_query, "")
    read_status = Keyword.get(opts, :read_status, "all")
    sort_by = Keyword.get(opts, :sort_by, "newest")
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    search_terms = %{
      category_id: category_id,
      is_archived: false
    }

    search_terms =
      if search_query != "" do
        Map.put(search_terms, :search_query, search_query)
      else
        search_terms
      end

    search_terms =
      case read_status do
        "read" -> Map.put(search_terms, :is_read, true)
        "unread" -> Map.put(search_terms, :is_read, false)
        _ -> search_terms
      end

    order =
      case sort_by do
        "oldest" -> [received_at: :asc]
        "sender" -> [from_email: :asc]
        "subject" -> [subject: :asc]
        _ -> [received_at: :desc]
      end

    case get_all_by_paginated(search_terms, order, page, page_size, [
           :category,
           :connected_account,
           :user
         ]) do
      {:ok, emails, total_count} ->
        {:ok, %{emails: emails, total_count: total_count}}

      error ->
        error
    end
  end

  @doc """
  Sets the unsubscribe status to processing
  """
  def start_unsubscribe(email) do
    attrs = %{
      unsubscribe_status: "processing",
      unsubscribe_attempted_at: DateTime.utc_now()
    }

    __MODULE__.update(email, attrs)
  end

  @doc """
  Sets the unsubscribe status to success with details
  """
  def complete_unsubscribe_success(email, details \\ "") do
    attrs = %{
      unsubscribe_status: "success",
      unsubscribe_completed_at: DateTime.utc_now(),
      unsubscribe_details: details
    }

    __MODULE__.update(email, attrs)
  end

  @doc """
  Sets the unsubscribe status to failed with details
  """
  def complete_unsubscribe_failure(email, details \\ "") do
    attrs = %{
      unsubscribe_status: "failed",
      unsubscribe_completed_at: DateTime.utc_now(),
      unsubscribe_details: details
    }

    __MODULE__.update(email, attrs)
  end

  @doc """
  Checks if unsubscribe is currently processing
  """
  def unsubscribe_processing?(email) do
    email.unsubscribe_status == "processing"
  end

  defp broadcast_category_update(category_id, :inc) do
    {:ok, updated_category} = Category.increment_email_count(category_id)

    Phoenix.PubSub.broadcast(
      SmartSort.PubSub,
      "update:categories",
      {:category_updated, updated_category}
    )
  end

  defp broadcast_category_update(category_id, :dec) do
    {:ok, updated_category} = Category.decrement_email_count(category_id)

    Phoenix.PubSub.broadcast(
      SmartSort.PubSub,
      "update:categories",
      {:category_updated, updated_category}
    )
  end
end
