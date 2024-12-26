defmodule AxonCore.PydanticHTTPClient do
  @moduledoc """
  HTTP client for communicating with the Python pydantic-ai agent wrapper.
  Uses Finch for better performance and connection pooling.
  """
  
  require Logger
  alias AxonCore.JSONCodec

  @pool_size 50
  @connect_timeout 5_000
  @receive_timeout 30_000

  def child_spec(_opts) do
    children = [
      {Finch, name: __MODULE__, pools: %{
        default: [size: @pool_size, count: 1]
      }}
    ]

    %{
      id: __MODULE__,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  @doc """
  Makes a POST request to the given URL with JSON body.
  """
  @spec post(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def post(url, body) do
    headers = [{"content-type", "application/json"}]
    
    with {:ok, json} <- JSONCodec.encode(body),
         {:ok, %Finch.Response{status: status, body: response_body}} 
           when status in 200..299 <- do_request(:post, url, headers, json),
         {:ok, decoded} <- JSONCodec.decode(response_body) do
      {:ok, decoded}
    else
      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("HTTP request failed with status #{status}: #{body}")
        {:error, {:http_error, status, body}}
      {:error, reason} = error ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Makes a POST request that returns a stream of server-sent events.
  """
  @spec post_stream(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def post_stream(url, body) do
    headers = [
      {"content-type", "application/json"},
      {"accept", "text/event-stream"}
    ]

    with {:ok, json} <- JSONCodec.encode(body) do
      # Spawn a process to handle the streaming response
      {:ok, spawn_link(fn -> stream_request(url, headers, json) end)}
    end
  end

  # Private Functions

  defp do_request(method, url, headers, body) do
    Finch.build(method, url, headers, body)
    |> Finch.request(__MODULE__, 
      receive_timeout: @receive_timeout,
      connect_timeout: @connect_timeout
    )
  end

  defp stream_request(url, headers, body) do
    # Set up streaming request
    req = Finch.build(:post, url, headers, body)
    
    case Finch.stream(req, __MODULE__, self(), []) do
      {:ok, conn_ref} ->
        handle_stream(conn_ref)
      {:error, reason} = error ->
        Logger.error("Failed to start stream: #{inspect(reason)}")
        send(self(), {:error, reason})
    end
  end

  defp handle_stream(conn_ref) do
    receive do
      {:status, ^conn_ref, status} when status in 200..299 ->
        handle_stream(conn_ref)
        
      {:headers, ^conn_ref, _headers} ->
        handle_stream(conn_ref)
        
      {:data, ^conn_ref, data} ->
        case parse_sse(data) do
          {:ok, chunk} -> send(self(), {:chunk, chunk})
          :done -> send(self(), {:end_stream})
          {:error, reason} -> send(self(), {:error, reason})
        end
        handle_stream(conn_ref)
        
      {:done, ^conn_ref} ->
        send(self(), {:end_stream})
        
      {:error, ^conn_ref, reason} ->
        Logger.error("Stream error: #{inspect(reason)}")
        send(self(), {:error, reason})
    end
  end

  defp parse_sse(data) do
    case String.trim(data) do
      "data: [DONE]" -> :done
      "data: " <> chunk -> {:ok, chunk}
      "error: " <> error -> {:error, error}
      _ -> {:error, :invalid_sse}
    end
  end
end
