defmodule Synapse.Workflow.Spec do
  @moduledoc """
  Declarative workflow specification consumed by `Synapse.Workflow.Engine`.

  Provides helper builders for steps and outputs plus validation to ensure
  dependencies reference known step identifiers.
  """

  defmodule Step do
    @moduledoc """
    Represents a single workflow step (action invocation) and its metadata.
    """

    @type on_error_mode :: :halt | :continue

    @type t :: %__MODULE__{
            id: atom(),
            action: module(),
            params: map() | keyword() | (map() -> map()),
            label: String.t() | nil,
            description: String.t() | nil,
            timeout: pos_integer() | nil,
            requires: [atom()],
            retry: %{max_attempts: pos_integer(), backoff: non_neg_integer()},
            metadata: map(),
            on_error: on_error_mode
          }

    defstruct [
      :id,
      :action,
      :params,
      :label,
      :description,
      :timeout,
      requires: [],
      retry: %{max_attempts: 1, backoff: 0},
      metadata: %{},
      on_error: :halt
    ]

    @doc """
    Normalizes a step definition into a struct.
    """
    @spec new(t() | map() | keyword()) :: t()
    def new(%__MODULE__{} = step), do: step

    def new(attrs) when is_map(attrs) do
      attrs |> Map.to_list() |> new()
    end

    def new(attrs) when is_list(attrs) do
      id = Keyword.fetch!(attrs, :id)
      action = Keyword.fetch!(attrs, :action)

      struct!(__MODULE__,
        id: id,
        action: action,
        params: Keyword.get(attrs, :params),
        label: Keyword.get(attrs, :label),
        description: Keyword.get(attrs, :description),
        timeout: Keyword.get(attrs, :timeout),
        requires:
          attrs |> Keyword.get(:requires, []) |> List.wrap() |> Enum.map(&normalize_dependency!/1),
        retry: attrs |> Keyword.get(:retry, %{}) |> normalize_retry(),
        metadata: Keyword.get(attrs, :metadata, %{}),
        on_error: attrs |> Keyword.get(:on_error, :halt) |> normalize_on_error()
      )
    end

    defp normalize_dependency!(dep) when is_atom(dep), do: dep

    defp normalize_dependency!(dep) do
      raise ArgumentError, "workflow dependencies must be atoms, got: #{inspect(dep)}"
    end

    defp normalize_retry(retry) when retry in [%{}, nil], do: %{max_attempts: 1, backoff: 0}

    defp normalize_retry(%{} = retry) do
      to_retry_map(Map.to_list(retry))
    end

    defp normalize_retry(retry) when is_list(retry) do
      to_retry_map(retry)
    end

    defp to_retry_map(opts) do
      max_attempts = Keyword.get(opts, :max_attempts, 1)
      backoff = Keyword.get(opts, :backoff, 0)

      if max_attempts < 1 do
        raise ArgumentError, "retry max_attempts must be >= 1"
      end

      if backoff < 0 do
        raise ArgumentError, "retry backoff must be >= 0"
      end

      %{max_attempts: max_attempts, backoff: backoff}
    end

    defp normalize_on_error(mode) when mode in [:halt, :continue], do: mode

    defp normalize_on_error(mode) do
      raise ArgumentError,
            "workflow step on_error must be :halt or :continue, got: #{inspect(mode)}"
    end
  end

  defmodule Output do
    @moduledoc """
    Maps a step result into the final workflow response payload.
    """

    @type t :: %__MODULE__{
            key: atom(),
            from: atom(),
            path: [term()] | nil,
            transform: (term() -> term()) | (term(), map() -> term()) | nil,
            description: String.t() | nil
          }

    defstruct [:key, :from, :path, :transform, :description]
  end

  alias __MODULE__.{Output, Step}

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t() | nil,
          steps: [Step.t()],
          outputs: [Output.t()],
          metadata: map()
        }

  defstruct [:name, :description, steps: [], outputs: [], metadata: %{}]

  @doc """
  Builds a workflow spec from keyword options.

    * `:name` - atom identifier used in telemetry/audit (default: `:workflow`)
    * `:description` - optional human readable description
    * `:steps` - required list of step structs/definitions
    * `:outputs` - optional list of outputs mapping results to response keys
    * `:metadata` - arbitrary map stored on the spec
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    raw_steps = Keyword.get(opts, :steps, [])

    if Enum.empty?(raw_steps) do
      raise ArgumentError, "workflow spec requires at least one step"
    end

    steps =
      raw_steps
      |> Enum.map(&Step.new/1)
      |> validate_unique_ids!()
      |> validate_dependencies!()

    outputs =
      opts
      |> Keyword.get(:outputs, [])
      |> Enum.map(&build_output/1)
      |> validate_outputs!(steps)

    %__MODULE__{
      name: Keyword.get(opts, :name, :workflow),
      description: Keyword.get(opts, :description),
      steps: steps,
      outputs: outputs,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp build_output(%Output{} = output), do: output
  defp build_output(opts) when is_list(opts), do: output(Keyword.fetch!(opts, :key), opts)
  defp build_output(%{key: key} = map), do: output(key, Map.to_list(map))

  @doc """
  Convenience helper for creating an output mapping.
  """
  @spec output(atom(), keyword()) :: Output.t()
  def output(key, opts) when is_atom(key) and is_list(opts) do
    from = Keyword.fetch!(opts, :from)

    unless is_atom(from) do
      raise ArgumentError, "workflow outputs must reference atom step ids"
    end

    %Output{
      key: key,
      from: from,
      path: Keyword.get(opts, :path),
      transform: Keyword.get(opts, :transform),
      description: Keyword.get(opts, :description)
    }
  end

  defp validate_unique_ids!(steps) do
    Enum.reduce(steps, {MapSet.new(), []}, fn step, {ids, acc} ->
      if MapSet.member?(ids, step.id) do
        raise ArgumentError, "duplicate workflow step id #{inspect(step.id)}"
      else
        {MapSet.put(ids, step.id), [step | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp validate_dependencies!(steps) do
    id_set = MapSet.new(Enum.map(steps, & &1.id))

    Enum.each(steps, &validate_step_dependencies(&1, id_set))

    steps
  end

  defp validate_step_dependencies(step, id_set) do
    Enum.each(step.requires, fn dependency ->
      unless MapSet.member?(id_set, dependency) do
        raise ArgumentError,
              "workflow step #{inspect(step.id)} requires unknown dependency #{inspect(dependency)}"
      end
    end)
  end

  defp validate_outputs!(outputs, steps) do
    id_set = MapSet.new(Enum.map(steps, & &1.id))

    Enum.each(outputs, fn output ->
      unless MapSet.member?(id_set, output.from) do
        raise ArgumentError,
              "workflow output #{inspect(output.key)} references unknown step #{inspect(output.from)}"
      end
    end)

    outputs
  end
end
