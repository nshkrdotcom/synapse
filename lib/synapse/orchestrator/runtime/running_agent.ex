defmodule Synapse.Orchestrator.Runtime.RunningAgent do
  @moduledoc """
  Runtime record representing a running agent process managed by the orchestrator.

  The struct is intentionally lightweight but provides enough metadata for the
  reconciler to detect crashes, restart processes, and surface observability
  details.
  """

  alias NimbleOptions.ValidationError
  alias Synapse.Orchestrator.AgentConfig

  @typedoc """
  Normalised runtime state for an individual agent process.
  """
  @type t :: %__MODULE__{
          agent_id: AgentConfig.agent_id(),
          pid: pid(),
          config: AgentConfig.t(),
          monitor_ref: reference(),
          spawned_at: DateTime.t(),
          spawn_count: pos_integer(),
          last_error: term() | nil,
          metadata: map()
        }

  @enforce_keys [:agent_id, :pid, :config, :monitor_ref, :spawned_at, :spawn_count]
  defstruct [
    :agent_id,
    :pid,
    :config,
    :monitor_ref,
    :spawned_at,
    :spawn_count,
    last_error: nil,
    metadata: %{}
  ]

  @doc """
  Returns the NimbleOptions schema for runtime agent records.
  """
  @spec schema() :: NimbleOptions.schema()
  def schema do
    [
      agent_id: [
        type: :atom,
        required: true,
        doc: "Agent identifier"
      ],
      pid: [
        type: {:custom, __MODULE__, :validate_pid, []},
        required: true,
        doc: "PID of the running agent process"
      ],
      config: [
        type: {:custom, __MODULE__, :validate_config, []},
        required: true,
        doc: "Validated agent configuration struct"
      ],
      monitor_ref: [
        type: {:custom, __MODULE__, :validate_reference, []},
        required: true,
        doc: "Monitor reference created for the agent PID"
      ],
      spawned_at: [
        type: {:custom, __MODULE__, :validate_datetime, []},
        required: true,
        doc: "UTC timestamp when the agent was spawned"
      ],
      spawn_count: [
        type: {:custom, __MODULE__, :validate_spawn_count, []},
        required: true,
        doc: "Number of times the agent has been spawned"
      ],
      last_error: [
        type: :any,
        doc: "Last error encountered by the agent (if any)",
        default: nil
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Arbitrary runtime metadata"
      ]
    ]
  end

  @doc """
  Builds a `%RunningAgent{}` struct from a keyword list or map, validating
  required runtime fields.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, ValidationError.t()}
  def new(attrs) when is_map(attrs), do: attrs |> Map.to_list() |> new()

  def new(attrs) when is_list(attrs) do
    with {:ok, validated} <- NimbleOptions.validate(attrs, schema()) do
      {:ok, struct(__MODULE__, Map.new(validated))}
    end
  end

  def new(_invalid) do
    {:error,
     ValidationError.exception(
       keys_path: [],
       message: "runtime agent attributes must be provided as a map or keyword list",
       value: nil
     )}
  end

  @doc false
  def validate_pid(pid) when is_pid(pid), do: {:ok, pid}
  def validate_pid(_), do: {:error, "must be a PID"}

  @doc false
  def validate_reference(ref) when is_reference(ref), do: {:ok, ref}
  def validate_reference(_), do: {:error, "must be a monitor reference"}

  @doc false
  def validate_datetime(%DateTime{} = dt), do: {:ok, dt}

  def validate_datetime(_),
    do: {:error, "must be a DateTime struct in UTC"}

  @doc false
  def validate_spawn_count(count) when is_integer(count) and count > 0, do: {:ok, count}
  def validate_spawn_count(_), do: {:error, "must be a positive integer"}

  @doc false
  def validate_config(%AgentConfig{} = config), do: {:ok, config}

  def validate_config(_),
    do: {:error, "must be a Synapse.Orchestrator.AgentConfig struct"}
end
