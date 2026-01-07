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
      alias Synapse.Signal.Schema, as: SignalSchema

      @schema_definition schema_definition
      @schema NimbleOptions.new!(@schema_definition)
      @type payload :: map()

      @spec schema() :: NimbleOptions.t()
      def schema, do: @schema

      @spec validate!(payload() | keyword()) :: payload()
      def validate!(payload) when is_map(payload) do
        payload
        |> SignalSchema.normalize_payload()
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
          message = Exception.message(e)

          reraise ArgumentError,
                  "invalid signal payload: #{message}",
                  __STACKTRACE__
      end
    end
  end

  @doc """
  Creates a validator function from a NimbleOptions schema definition.
  """
  @spec compile_schema(keyword()) :: (map() -> map())
  def compile_schema(schema_def) when is_list(schema_def) do
    compiled = NimbleOptions.new!(schema_def)

    fn payload ->
      try do
        payload
        |> normalize_payload()
        |> NimbleOptions.validate!(compiled)
        |> Map.new()
      rescue
        e in NimbleOptions.ValidationError ->
          message = Exception.message(e)

          reraise ArgumentError, "invalid signal payload: #{message}", __STACKTRACE__
      end
    end
  end

  @doc false
  def normalize_payload(payload) when is_map(payload), do: Map.to_list(payload)
  def normalize_payload(payload) when is_list(payload), do: payload
end
