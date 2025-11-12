defmodule Synapse.Signal.Schema do
  @moduledoc """
  Shared helpers for defining signal schemas backed by `NimbleOptions`.

  Modules `use`-ing this helper only need to provide a keyword list schema.
  Validation will accept either maps or keyword lists, apply defaults, and
  raise descriptive errors when the payload does not conform.
  """

  @doc false
  defmacro __using__(opts) do
    schema_definition = Keyword.fetch!(opts, :schema)

    quote bind_quoted: [schema_definition: schema_definition] do
      @schema_definition schema_definition
      @schema NimbleOptions.new!(@schema_definition)
      @type payload :: map()

      @spec schema() :: NimbleOptions.t()
      def schema, do: @schema

      @spec validate!(payload() | keyword()) :: payload()
      def validate!(payload) when is_map(payload) do
        payload
        |> Map.to_list()
        |> do_validate!()
      end

      def validate!(payload) when is_list(payload) do
        do_validate!(payload)
      end

      defp do_validate!(payload) do
        payload
        |> NimbleOptions.validate!(@schema)
        |> Map.new()
      rescue
        e in NimbleOptions.ValidationError ->
          reraise ArgumentError,
                  ["invalid signal payload: ", e.message],
                  __STACKTRACE__
      end
    end
  end
end
