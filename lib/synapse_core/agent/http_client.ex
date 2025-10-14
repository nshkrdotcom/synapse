defmodule SynapseCore.Agent.HTTPClient do
  @moduledoc """
  HTTP client for making requests to Python agents.
  """

  require Logger

  def post(url, headers, body) when is_binary(url) do
    case Finch.build(:post, url, headers, body)
         |> Finch.request(SynapseFinch) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{status: status, body: body}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HTTP request failed with status #{status}: #{body}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
