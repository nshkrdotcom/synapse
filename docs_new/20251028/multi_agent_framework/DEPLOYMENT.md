# Deployment Guide

## Production Deployment

### Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- PostgreSQL (future - not required for Stage 0)

### Building a Release

```bash
# Set environment
export MIX_ENV=prod

# Get dependencies
mix deps.get --only prod

# Compile
mix compile

# Build release
mix release

# Release will be in _build/prod/rel/synapse/
```

### Running the Release

```bash
# Start in foreground
_build/prod/rel/synapse/bin/synapse start

# Start as daemon
_build/prod/rel/synapse/bin/synapse daemon

# Connect to running release
_build/prod/rel/synapse/bin/synapse remote
```

### Configuration

#### Environment Variables

```bash
# Required
export SECRET_KEY_BASE="your-secret-key"
export PHX_HOST="your-domain.com"

# Optional - Jido configuration
export JIDO_DEFAULT_TIMEOUT="60000"
export JIDO_MAX_RETRIES="3"

# Optional - Logging
export LOG_LEVEL="info"
```

#### Runtime Configuration

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :synapse,
    signal_bus: :synapse_bus,
    agent_registry: :synapse_registry

  config :logger,
    level: String.to_atom(System.get_env("LOG_LEVEL", "info"))

  config :jido,
    default_timeout: String.to_integer(System.get_env("JIDO_DEFAULT_TIMEOUT", "60000")),
    default_max_retries: String.to_integer(System.get_env("JIDO_MAX_RETRIES", "3"))
end
```

## Container Deployment

### Dockerfile

```dockerfile
FROM elixir:1.18-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Copy dependency manifests
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY lib lib
COPY priv priv
COPY config config

# Compile application
RUN mix compile

# Build release
RUN mix release

# Prepare release image
FROM alpine:3.18 AS app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

# Copy release from build stage
COPY --from=build /app/_build/prod/rel/synapse ./

# Set runtime user
RUN adduser -D synapse
USER synapse

# Expose Phoenix port
EXPOSE 4000

# Set environment
ENV MIX_ENV=prod

# Start the release
CMD ["bin/synapse", "start"]
```

### Build and Run

```bash
# Build image
docker build -t synapse:latest .

# Run container
docker run -d \
  --name synapse \
  -p 4000:4000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST="localhost" \
  synapse:latest

# View logs
docker logs -f synapse

# Connect to running container
docker exec -it synapse bin/synapse remote
```

## Kubernetes Deployment

### Deployment Manifest

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: synapse
  labels:
    app: synapse
spec:
  replicas: 3
  selector:
    matchLabels:
      app: synapse
  template:
    metadata:
      labels:
        app: synapse
    spec:
      containers:
      - name: synapse
        image: synapse:latest
        ports:
        - containerPort: 4000
        env:
        - name: PHX_HOST
          value: "synapse.example.com"
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: synapse-secrets
              key: secret-key-base
        - name: LOG_LEVEL
          value: "info"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: synapse
spec:
  selector:
    app: synapse
  ports:
  - port: 80
    targetPort: 4000
  type: LoadBalancer
```

### Deploy to Kubernetes

```bash
# Create secret
kubectl create secret generic synapse-secrets \
  --from-literal=secret-key-base="$(mix phx.gen.secret)"

# Apply deployment
kubectl apply -f k8s/deployment.yaml

# Check status
kubectl get pods -l app=synapse
kubectl logs -l app=synapse --tail=100 -f
```

## Monitoring

### Health Check Endpoint

Add to Phoenix router:

```elixir
# lib/synapse_web/router.ex
scope "/", SynapseWeb do
  get "/health", HealthController, :index
end
```

```elixir
# lib/synapse_web/controllers/health_controller.ex
defmodule SynapseWeb.HealthController do
  use SynapseWeb, :controller

  def index(conn, _params) do
    case Synapse.Examples.Stage0Demo.health_check() do
      {:ok, message} ->
        json(conn, %{status: "healthy", message: message})

      {:warning, message} ->
        conn
        |> put_status(503)
        |> json(%{status: "degraded", message: message})

      {:error, message} ->
        conn
        |> put_status(503)
        |> json(%{status: "unhealthy", message: message})
    end
  end
end
```

### Prometheus Metrics

```elixir
# Add to dependencies
{:prom_ex, "~> 1.9"}

# config/config.exs
config :synapse, Synapse.PromEx,
  manual_metrics_start_delay: :no_delay,
  grafana: :disabled,
  metrics_server: :disabled

# lib/synapse/prom_ex.ex
defmodule Synapse.PromEx do
  use PromEx, otp_app: :synapse

  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: SynapseWeb.Router}
    ]
  end

  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"}
    ]
  end
end
```

### Custom Metrics

```elixir
# Attach telemetry handlers
:telemetry.attach_many(
  "synapse-metrics",
  [
    [:jido, :exec, :stop],
    [:jido, :signal, :publish]
  ],
  &Synapse.Telemetry.handle_event/4,
  %{}
)

# lib/synapse/telemetry.ex
defmodule Synapse.Telemetry do
  def handle_event([:jido, :exec, :stop], measurements, metadata, _config) do
    :telemetry.execute(
      [:synapse, :action, :duration],
      %{duration_ms: measurements.duration / 1_000_000},
      %{action: metadata.action}
    )
  end

  def handle_event([:jido, :signal, :publish], measurements, metadata, _config) do
    :telemetry.execute(
      [:synapse, :signal, :published],
      %{count: measurements.count},
      %{bus: metadata.bus}
    )
  end
end
```

## Performance Tuning

### Agent Pooling

For high-throughput scenarios:

```elixir
# config/prod.exs
config :synapse,
  security_agent_pool_size: 10,
  performance_agent_pool_size: 10

# lib/synapse/agent_pool.ex
defmodule Synapse.AgentPool do
  def child_spec(opts) do
    pool_size = Keyword.fetch!(opts, :size)
    agent_module = Keyword.fetch!(opts, :agent_module)

    children = for i <- 1..pool_size do
      Supervisor.child_spec(
        {agent_module, [id: "#{agent_module}_#{i}"]},
        id: {agent_module, i}
      )
    end

    %{
      id: __MODULE__,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end
end

# In Application.start/2
children = [
  # ...
  {Synapse.AgentPool, size: 10, agent_module: SecurityAgentServer}
]
```

### Signal.Bus Tuning

```elixir
# Larger signal history for replay
{Jido.Signal.Bus, name: :synapse_bus, max_history: 10_000}

# With middleware for metrics
{Jido.Signal.Bus,
 name: :synapse_bus,
 middleware: [
   {Jido.Signal.Bus.Middleware.Logger, level: :info},
   {Synapse.Middleware.Metrics, []}
 ]}
```

## Security Considerations

### Network Security

- Use HTTPS for Phoenix endpoints
- Configure firewall rules
- Use VPC/private networks for agent communication

### Signal Authentication

```elixir
# Add authentication middleware to bus
defmodule Synapse.Middleware.Auth do
  use Jido.Signal.Bus.Middleware

  def before_publish(signals, _context, state) do
    # Verify signal source
    if authorized?(signals) do
      {:cont, signals, state}
    else
      {:halt, {:error, :unauthorized}, state}
    end
  end
end
```

### Rate Limiting

```elixir
# Limit review requests per source
defmodule Synapse.RateLimiter do
  use GenServer

  def check_rate(source) do
    GenServer.call(__MODULE__, {:check, source})
  end

  def handle_call({:check, source}, _from, state) do
    # Implement token bucket or sliding window
    {:reply, :ok, state}
  end
end
```

## Scaling

### Horizontal Scaling

**Current**: Single-node deployment

**Future** (Stage 4+):
- Distributed Signal.Bus
- Agent sharding by review_id
- Coordinator election
- Shared state via PostgreSQL/Redis

### Vertical Scaling

**Current Limits**:
- Single agent: ~100 reviews/sec
- Signal.Bus: ~1000 signals/sec

**Optimization**:
- Increase agent pool size
- Parallelize action execution
- Use faster regex libraries

## Backup and Recovery

### State Backup

Currently state is in-memory. For production:

**Option 1**: Periodic snapshots
```elixir
# Scheduled task to dump agent state
defmodule Synapse.StateBackup do
  def backup_agent_states do
    agents = Synapse.AgentRegistry.list_agents()

    Enum.each(agents, fn {id, pid} ->
      state = :sys.get_state(pid)
      File.write!("backups/#{id}.etf", :erlang.term_to_binary(state))
    end)
  end
end
```

**Option 2**: Event sourcing (Stage 3+)
- Store all signals in PostgreSQL
- Rebuild agent state from signal history

### Disaster Recovery

1. **Signal Replay**: Jido.Signal.Bus maintains history
2. **Agent Restart**: Supervision tree handles crashes
3. **State Recovery**: Restore from backups (when implemented)

## Maintenance

### Log Rotation

```elixir
# config/prod.exs
config :logger,
  backends: [{LoggerFileBackend, :file_log}]

config :logger, :file_log,
  path: "/var/log/synapse/app.log",
  level: :info,
  rotate: %{max_bytes: 10_485_760, keep: 5}  # 10MB, keep 5 files
```

### Database Maintenance (Future)

When persistent storage is added:
- Regular VACUUM
- Index maintenance
- Partition old signal data

## Rollback Procedure

```bash
# Stop current release
_build/prod/rel/synapse/bin/synapse stop

# Deploy previous version
# (Assuming version tagged releases)

# Start previous release
_build/prod/rel/synapse_v1.0.0/bin/synapse start

# Verify
curl http://localhost:4000/health
```

## Monitoring Checklist

- [ ] Health endpoint responding
- [ ] Signal.Bus processing signals
- [ ] Agents subscribing successfully
- [ ] Results being emitted
- [ ] No error spike in logs
- [ ] Memory usage stable
- [ ] Response times < 100ms

## Production Best Practices

1. **Start Small**: Deploy single SecurityAgent first
2. **Monitor Closely**: Watch logs and metrics first week
3. **Rate Limit**: Protect against request floods
4. **Set Timeouts**: Prevent runaway action execution
5. **Log Strategically**: Info for lifecycle, debug for troubleshooting
6. **Test Failover**: Kill agents, verify recovery
7. **Backup State**: Implement state persistence early
8. **Scale Gradually**: Add agents as load increases

## Support

For issues not covered here:
- Check [Troubleshooting Guide](TROUBLESHOOTING.md)
- Review [Architecture](ARCHITECTURE.md)
- Run demo: `Synapse.Examples.Stage0Demo.run()`
- Check test examples in `test/synapse/integration/`
