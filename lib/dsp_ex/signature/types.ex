defmodule DSPEx.Signature.Types do
  @moduledoc """
  Type definitions for DSPy signatures.
  """

  @type field_type :: :string | :integer | :float | :boolean | :list | :map

  @type field :: %{
    name: atom(),
    type: field_type(),
    type_params: list(),
    optional: boolean(),
    direction: :input | :output,
    position: non_neg_integer(),
    raw_definition: String.t()
  }

  defmodule Field do
    @moduledoc """
    Represents a single field in a DSPy signature.
    """
    
    defstruct [
      :name,           # atom() - field name
      :type,           # field_type() - basic type
      :type_params,    # list() - additional type parameters (e.g., for list[str])
      :optional,       # boolean() - whether field is optional
      :direction,      # :input | :output
      :position,       # non_neg_integer() - position in signature
      :raw_definition  # String.t() - original definition string
    ]

    @type t :: %__MODULE__{
      name: atom(),
      type: atom(),
      type_params: list(),
      optional: boolean(),
      direction: :input | :output,
      position: non_neg_integer(),
      raw_definition: String.t()
    }
  end
end