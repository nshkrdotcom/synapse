defmodule SynapseCore.HTTPClient do
  @moduledoc """
  HTTP client for making requests.
  """

  require Logger
  alias SynapseCore.JSONCodec

  def post(url, body) when is_binary(url) do
    headers = [{"content-type", "application/json"}]
    
    case Finch.build(:post, url, headers, JSONCodec.encode!(body))
         |> Finch.request(SynapseFinch) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body}}
      
      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def post_stream(url, body) when is_binary(url) do
    headers = [{"content-type", "application/json"}]
    
    case Finch.build(:post, url, headers, JSONCodec.encode!(body))
         |> Finch.request(SynapseFinch) do
      {:ok, response} when response.status in 200..299 ->
        {:ok, response.body}
      
      {:ok, response} ->
        {:error, {:http_error, response.status, response.body}}
      
      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
