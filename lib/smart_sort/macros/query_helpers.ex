defmodule SmartSort.Macros.QueryHelpers do
  import Ecto.Query, warn: false

  def where_clause(search_terms) do
    Enum.reduce(search_terms, true, &where_match_clause(&1, &2, %{}))
  end

  def where_match_clause({k, vs}, conditions, _) when is_map(vs) do
    Enum.reduce(vs, conditions, &where_match_clause(&1, &2, %{binding: k}))
  end

  def where_match_clause({k, vs}, conditions, %{binding: binding})
      when is_list(vs) and is_atom(binding) do
    dynamic([{^binding, q}], field(q, ^convert_field_name(k)) in ^vs and ^conditions)
  end

  def where_match_clause({k, vs}, conditions, _) when is_list(vs) do
    dynamic([q], field(q, ^convert_field_name(k)) in ^vs and ^conditions)
  end

  def where_match_clause({_k, ""}, conditions, _) do
    conditions
  end

  def where_match_clause({k, v}, conditions, %{binding: binding}) when is_atom(binding) do
    dynamic([{^binding, q}], field(q, ^convert_field_name(k)) == ^v and ^conditions)
  end

  def where_match_clause({k, v}, conditions, _) when is_nil(v) do
    dynamic([q], is_nil(field(q, ^convert_field_name(k))) and ^conditions)
  end

  def where_match_clause({k, v}, conditions, _) do
    dynamic([q], field(q, ^convert_field_name(k)) == ^v and ^conditions)
  end

  defp convert_field_name(field) when is_atom(field), do: field
  defp convert_field_name(field) when is_binary(field), do: String.to_existing_atom(field)
end
