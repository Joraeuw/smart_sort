defmodule SmartSort.Macros.NotFound do
  @type t :: %__MODULE__{
          entity: module()
        }

  defstruct [:entity]

  defimpl String.Chars do
    def to_string(%SmartSort.Macros.NotFound{entity: entity}) do
      "#{module_name(entity)}_not_found"
    end

    defp module_name(module) do
      module
      |> Atom.to_string()
      |> String.split(".")
      |> List.last()
      |> (fn name ->
            name
            |> String.last()
            |> case do
              "s" -> String.slice(name, 0..-2//1)
              _ -> name
            end
          end).()
      |> Macro.underscore()
      |> String.downcase()
    end
  end

  defimpl Jason.Encoder do
    def encode(%SmartSort.Macros.NotFound{} = error, opts) do
      Jason.Encode.string(to_string(error), opts)
    end
  end
end
