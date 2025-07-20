defmodule SmartSort.Helpers.WithHelpers do
  def check(true, _), do: :ok
  def check(false, error_message), do: {:error, error_message}
end
