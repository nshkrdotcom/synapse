defmodule AxonCore.Error do
  require Logger

  def log_error(error) do
    Logger.error("#{inspect(error)}")
    error
  end

  defmodule PythonEnvError do
    defexception [:message, :context]

    @impl true
    def exception(opts) do
      msg = Keyword.fetch!(opts, :message)
      context = Keyword.get(opts, :context, %{})
      %__MODULE__{message: msg, context: context}
    end

    def new(reason, context \\ %{}) do
      exception(message: to_string(reason), context: context)
    end
  end
end
