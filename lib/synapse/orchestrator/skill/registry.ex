defmodule Synapse.Orchestrator.Skill.Registry do
  @moduledoc """
  Discovers and caches skills from well-known directories.

  The registry keeps metadata in memory and lazily loads instruction bodies
  when a caller requests them, allowing the runtime to follow the progressive
  disclosure model described in the design docs.
  """

  use GenServer

  require Logger

  alias Synapse.Orchestrator.Skill

  @type option :: {:directories, [String.t()]}

  # Public API ----------------------------------------------------------------

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec list(pid() | atom()) :: [Skill.t()]
  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  @spec get(pid() | atom(), String.t()) :: {:ok, Skill.t()} | :error
  def get(server \\ __MODULE__, skill_id) do
    GenServer.call(server, {:get, skill_id})
  end

  @spec load_body(pid() | atom(), String.t()) :: {:ok, Skill.t()} | {:error, term()}
  def load_body(server \\ __MODULE__, skill_id) do
    GenServer.call(server, {:load_body, skill_id})
  end

  @doc """
  Returns a metadata summary suitable for embedding in a system prompt.
  """
  @spec metadata_summary(pid() | atom()) :: String.t()
  def metadata_summary(server \\ __MODULE__) do
    list(server)
    |> Enum.map(fn skill ->
      "- #{skill.name}: #{skill.description}\n  (Load: bash cat #{skill.instructions_path})"
    end)
    |> Enum.join("\n")
  end

  # GenServer callbacks -------------------------------------------------------

  @impl true
  def init(opts) do
    directories = Keyword.get(opts, :directories, default_directories())

    skills =
      directories
      |> Enum.flat_map(&discover_directory/1)
      |> Map.new(&{&1.id, &1})

    {:ok, %{skills: skills}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.skills), state}
  end

  @impl true
  def handle_call({:get, skill_id}, _from, state) do
    case Map.fetch(state.skills, skill_id) do
      {:ok, skill} -> {:reply, {:ok, skill}, state}
      :error -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:load_body, skill_id}, _from, state) do
    with {:ok, skill} <- Map.fetch(state.skills, skill_id),
         {:ok, skill_with_body} <- ensure_body(skill) do
      {:reply, {:ok, skill_with_body},
       %{state | skills: Map.put(state.skills, skill_id, skill_with_body)}}
    else
      :error -> {:reply, {:error, :not_found}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # Discovery helpers ---------------------------------------------------------

  defp default_directories do
    cwd = File.cwd!()
    home = System.get_env("HOME")

    [
      home && Path.join(home, ".synapse/skills"),
      Path.join(cwd, ".synapse/skills"),
      home && Path.join(home, ".claude/skills"),
      Path.join(cwd, ".claude/skills")
    ]
    |> Enum.filter(&(&1 && File.dir?(&1)))
  end

  defp discover_directory(dir) do
    source =
      if String.contains?(dir, ".claude"), do: :claude, else: :synapse

    with {:ok, entries} <- File.ls(dir) do
      entries
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(&load_skill(&1, source))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, skill} -> skill end)
    else
      {:error, reason} ->
        Logger.debug("Unable to read skills directory", path: dir, reason: inspect(reason))
        []
    end
  end

  defp load_skill(path, source) do
    instructions_path = Path.join(path, "SKILL.md")

    with true <- File.exists?(instructions_path) || {:error, :missing_skill_file},
         {:ok, content} <- File.read(instructions_path),
         {:ok, meta, _body} <- parse_skill_content(content) do
      id = Path.basename(path)
      name = Map.get(meta, "name", id)
      description = Map.get(meta, "description", "No description provided")

      {:ok,
       %Skill{
         id: id,
         name: name,
         description: description,
         version: Map.get(meta, "version"),
         allowed_tools: Map.get(meta, "allowed-tools", []),
         dependencies: Map.get(meta, "dependencies", []),
         metadata: meta,
         source: source,
         path: path,
         instructions_path: instructions_path
       }}
    else
      {:error, reason} ->
        Logger.warning("Failed to load skill", path: path, reason: inspect(reason))
        {:error, reason}

      false ->
        {:error, :missing_skill_file}
    end
  end

  defp ensure_body(%Skill{body_loaded?: true} = skill), do: {:ok, skill}

  defp ensure_body(%Skill{instructions_path: path} = skill) do
    case File.read(path) do
      {:ok, content} ->
        case parse_skill_content(content) do
          {:ok, _meta, body} ->
            {:ok, %{skill | body: body, body_loaded?: true}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parsing utilities ---------------------------------------------------------

  @spec parse_skill_content(String.t()) :: {:ok, map(), String.t()} | {:error, term()}
  defp parse_skill_content(content) do
    with true <- String.starts_with?(content, "---\n") || {:error, :missing_frontmatter},
         [frontmatter, body] <-
           String.split(String.replace_prefix(content, "---\n", ""), "\n---\n", parts: 2) do
      metadata = parse_frontmatter(String.split(frontmatter, "\n"))
      {:ok, metadata, String.trim_leading(body)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_frontmatter}
    end
  end

  defp parse_frontmatter(lines) do
    parse_frontmatter(lines, %{}, nil)
  end

  defp parse_frontmatter([], acc, _current_key), do: acc

  defp parse_frontmatter([line | rest], acc, current_key) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_frontmatter(rest, acc, current_key)

      String.starts_with?(trimmed, "- ") and current_key ->
        value = String.trim_leading(trimmed, "- ") |> parse_value()
        updated = Map.update(acc, current_key, [value], &[value | &1])
        parse_frontmatter(rest, updated, current_key)

      match = Regex.run(~r/^([A-Za-z0-9_-]+):\s*(.*)$/, trimmed, capture: :all_but_first) ->
        case match do
          [key, ""] ->
            parse_frontmatter(rest, Map.put(acc, key, []), key)

          [key, value] ->
            value = parse_value(value)
            parse_frontmatter(rest, Map.put(acc, key, value), nil)
        end

      true ->
        parse_frontmatter(rest, acc, current_key)
    end
  end

  defp parse_value(value) do
    trimmed = String.trim(value)

    cond do
      trimmed in ["true", "false"] -> trimmed == "true"
      Regex.match?(~r/^\d+$/, trimmed) -> String.to_integer(trimmed)
      true -> trimmed
    end
  end
end
