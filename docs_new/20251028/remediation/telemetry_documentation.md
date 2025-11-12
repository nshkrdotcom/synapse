# Synapse LLM Telemetry Guide

## Overview

The `Synapse.ReqLLM` module emits telemetry events for observability into LLM request lifecycle, performance, costs, and errors.

## Telemetry Events

### Request Start: `[:synapse, :llm, :request, :start]`

Emitted when an LLM request begins.

**Measurements:**
```elixir
%{
  system_time: System.system_time()  # Wall clock time in native units
}
```

**Metadata:**
```elixir
%{
  request_id: "abc123",           # Unique identifier for this request
  profile: :openai,               # Profile name used
  model: "gpt-4o-mini",          # Model requested
  provider: :openai              # Provider type (:openai or :gemini)
}
```

### Request Stop: `[:synapse, :llm, :request, :stop]`

Emitted when an LLM request completes successfully.

**Measurements:**
```elixir
%{
  duration: 1_234_567_890  # Request duration in native time units
}
```

**Metadata:**
```elixir
%{
  request_id: "abc123",
  profile: :openai,
  model: "gpt-4o-mini",
  provider: :openai,
  token_usage: %{              # Token usage (may be nil)
    total_tokens: 150,
    prompt_tokens: nil,
    completion_tokens: nil
  },
  finish_reason: "stop"        # Completion reason from provider
}
```

### Request Exception: `[:synapse, :llm, :request, :exception]`

Emitted when an LLM request fails (HTTP errors, timeouts, configuration errors, etc.).

**Measurements:**
```elixir
%{
  duration: 1_234_567_890  # Request duration in native time units
}
```

**Metadata:**
```elixir
%{
  request_id: "abc123",
  profile: :openai,          # May be missing for config errors
  model: "gpt-4o-mini",      # May be missing for config errors
  provider: :openai,         # May be missing for config errors
  error_type: :execution_error,  # Jido.Error type
  error_message: "LLM request was rate limited for profile openai"
}
```

## Attaching Telemetry Handlers

### Example: Logger Handler

```elixir
# In your application.ex or a dedicated telemetry module

defmodule MyApp.Telemetry do
  require Logger

  def setup do
    :telemetry.attach_many(
      "synapse-llm-telemetry",
      [
        [:synapse, :llm, :request, :start],
        [:synapse, :llm, :request, :stop],
        [:synapse, :llm, :request, :exception]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:synapse, :llm, :request, :start], measurements, metadata, _config) do
    Logger.info("LLM request started",
      request_id: metadata.request_id,
      profile: metadata.profile,
      model: metadata.model,
      provider: metadata.provider
    )
  end

  def handle_event([:synapse, :llm, :request, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("LLM request completed",
      request_id: metadata.request_id,
      profile: metadata.profile,
      model: metadata.model,
      duration_ms: duration_ms,
      total_tokens: get_in(metadata, [:token_usage, :total_tokens]),
      finish_reason: metadata.finish_reason
    )
  end

  def handle_event([:synapse, :llm, :request, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error("LLM request failed",
      request_id: metadata.request_id,
      profile: metadata[:profile],
      model: metadata[:model],
      duration_ms: duration_ms,
      error_type: metadata.error_type,
      error_message: metadata.error_message
    )
  end
end

# In application.ex start/2:
MyApp.Telemetry.setup()
```

### Example: Metrics Collection (Prometheus/StatsD)

```elixir
defmodule MyApp.LLMMetrics do
  def setup do
    :telemetry.attach_many(
      "synapse-llm-metrics",
      [
        [:synapse, :llm, :request, :stop],
        [:synapse, :llm, :request, :exception]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:synapse, :llm, :request, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Increment request counter
    :telemetry.execute(
      [:my_app, :llm, :requests],
      %{count: 1},
      %{profile: metadata.profile, provider: metadata.provider, status: "success"}
    )

    # Record duration histogram
    :telemetry.execute(
      [:my_app, :llm, :duration],
      %{duration: duration_ms},
      %{profile: metadata.profile, provider: metadata.provider}
    )

    # Record token usage
    if tokens = get_in(metadata, [:token_usage, :total_tokens]) do
      :telemetry.execute(
        [:my_app, :llm, :tokens],
        %{tokens: tokens},
        %{profile: metadata.profile, model: metadata.model}
      )
    end
  end

  def handle_event([:synapse, :llm, :request, :exception], measurements, metadata, _config) do
    # Increment error counter
    :telemetry.execute(
      [:my_app, :llm, :requests],
      %{count: 1},
      %{
        profile: metadata[:profile] || "unknown",
        provider: metadata[:provider] || "unknown",
        status: "error",
        error_type: metadata.error_type
      }
    )
  end
end
```

### Example: Cost Tracking

```elixir
defmodule MyApp.LLMCostTracker do
  @pricing %{
    "gpt-4o-mini" => %{input: 0.00015, output: 0.0006},  # per 1K tokens
    "gemini-2.0-flash-exp" => %{input: 0.0, output: 0.0}
  }

  def setup do
    :telemetry.attach(
      "synapse-llm-cost-tracker",
      [:synapse, :llm, :request, :stop],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:synapse, :llm, :request, :stop], _measurements, metadata, _config) do
    with %{total_tokens: tokens} when is_integer(tokens) <- metadata.token_usage,
         %{input: input_cost, output: output_cost} <- Map.get(@pricing, metadata.model) do

      # Simplified cost calculation (assumes 50/50 split)
      estimated_cost = (tokens / 1000) * ((input_cost + output_cost) / 2)

      # Record to your cost tracking system
      record_cost(metadata.request_id, metadata.profile, metadata.model, estimated_cost, tokens)
    end
  end

  defp record_cost(request_id, profile, model, cost, tokens) do
    # Store in database, send to analytics, etc.
    Logger.info("LLM cost",
      request_id: request_id,
      profile: profile,
      model: model,
      cost_usd: cost,
      tokens: tokens
    )
  end
end
```

## Converting Time Units

Telemetry measurements use native time units for performance. Convert to human-readable units:

```elixir
# Milliseconds
duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

# Seconds
duration_s = System.convert_time_unit(measurements.duration, :native, :second)

# Microseconds
duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)
```

## Integration with TelemetryMetrics

For automatic metrics reporting to Prometheus, StatsD, or LiveDashboard:

```elixir
# In your telemetry.ex module:

defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      # Telemetry poller for periodic measurements
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},

      # Export metrics to your backend
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Request counters
      counter("synapse.llm.request.start.count",
        tags: [:profile, :model, :provider]
      ),

      counter("synapse.llm.request.stop.count",
        tags: [:profile, :model, :provider, :finish_reason]
      ),

      counter("synapse.llm.request.exception.count",
        tags: [:profile, :provider, :error_type]
      ),

      # Duration distribution
      distribution("synapse.llm.request.stop.duration",
        unit: {:native, :millisecond},
        tags: [:profile, :provider],
        reporter_options: [buckets: [10, 100, 500, 1000, 5000, 10000]]
      ),

      # Token usage summary
      sum("synapse.llm.request.stop.total_tokens",
        tags: [:profile, :model],
        tag_values: &extract_token_count/1
      )
    ]
  end

  defp extract_token_count(%{token_usage: %{total_tokens: count}}) when is_integer(count) do
    %{total_tokens: count}
  end
  defp extract_token_count(_), do: %{total_tokens: 0}

  defp periodic_measurements do
    []
  end
end
```

## Best Practices

1. **Always attach handlers in application.ex** - Ensure telemetry handlers are set up before any LLM requests
2. **Use structured logging** - Include request_id in logs for correlation
3. **Monitor error rates** - Alert on high exception rates by error_type
4. **Track costs** - Monitor token usage trends to prevent runaway costs
5. **Measure P95/P99 latency** - Use distribution metrics to catch performance degradation
6. **Tag by provider** - Compare performance across OpenAI vs Gemini
7. **Correlate with business metrics** - Join request_id with your domain events

## Troubleshooting

### Handlers not triggering

Ensure handlers are attached before making requests:
```elixir
# Check attached handlers
:telemetry.list_handlers([:synapse, :llm, :request, :start])
```

### Missing metadata fields

Early configuration errors may omit profile/model fields. Always handle optional fields:
```elixir
profile = metadata[:profile] || "unknown"
```

### High cardinality

Avoid using request_id in metric tags (creates unbounded cardinality). Use it only in logs.

## Future Enhancements

Planned telemetry additions:
- Retry attempt counts and backoff durations
- Circuit breaker state transitions
- Cache hit/miss rates (when caching is implemented)
- Budget quota remaining
- Provider-specific metadata (rate limit headers, request IDs)
