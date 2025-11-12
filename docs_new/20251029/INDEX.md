# Synapse Multi-Agent Framework Documentation
**Date**: October 29, 2025
**Status**: Stage 2 Complete + LLM Integration Live
**Version**: 0.2.0

This documentation supersedes all previous documentation in `docs/20251028/`.

---

## Quick Navigation

### Current Status
- [**PROJECT_STATUS.md**](PROJECT_STATUS.md) - Complete snapshot of what works now
- [**TECHNICAL_ARCHITECTURE.md**](TECHNICAL_ARCHITECTURE.md) - System design & components

### Roadmap & Planning
- [**ROADMAP.md**](ROADMAP.md) - Complete phase breakdown (Stage 3 → Stage 6+)

### Implementation Details
- [**implementation/STAGE_2_COMPLETE.md**](implementation/STAGE_2_COMPLETE.md) - Multi-agent orchestration
- [**implementation/LLM_INTEGRATION.md**](implementation/LLM_INTEGRATION.md) - ReqLLM + Gemini/OpenAI
- [**implementation/ORCHESTRATOR_STATUS.md**](implementation/ORCHESTRATOR_STATUS.md) - Config-driven agents
- [**implementation/MULTI_AGENT_SYSTEM.md**](implementation/MULTI_AGENT_SYSTEM.md) - Current agent architecture

### Future Phases
- [**roadmap/STAGE_3_ADVANCED.md**](roadmap/STAGE_3_ADVANCED.md) - Resilience & Learning
- [**roadmap/STAGE_4_MARKETPLACE.md**](roadmap/STAGE_4_MARKETPLACE.md) - Agent Marketplace
- [**roadmap/STAGE_5_LEARNING_MESH.md**](roadmap/STAGE_5_LEARNING_MESH.md) - Shared Knowledge
- [**roadmap/STAGE_6_PLANETARY.md**](roadmap/STAGE_6_PLANETARY.md) - Scale & Self-Improvement

---

## What's New (Oct 29, 2025)

### ✅ Completed
1. **LLM Integration Live**
   - ReqLLM multi-provider client working
   - Gemini `gemini-flash-lite-latest` verified live
   - OpenAI support ready
   - Response times: 200-500ms typical

2. **Stage 2 Multi-Agent Orchestration**
   - CoordinatorAgent spawns specialists dynamically
   - SecurityAgent + PerformanceAgent running in parallel
   - Result aggregation working
   - 207 tests passing, 0 failures

3. **Declarative Orchestrator** (Partial)
   - AgentConfig with NimbleOptions validation
   - Runtime GenServer with reconciliation
   - Skill system with lazy loading
   - AgentFactory (simplified implementation)

### 🚧 In Progress
- Full Jido.Agent.Server integration in AgentFactory
- Hot reload configuration
- Agent discovery API

### 📋 Next Up (Stage 3)
- Timeout handling for specialists
- Telemetry & metrics dashboard
- Scar tissue learning system
- Directive.Enqueue work distribution

---

## System Metrics (Current)

| Metric | Value |
|--------|-------|
| **Total Tests** | 207 passing, 0 failures |
| **Source Files** | 42 Elixir modules |
| **Documentation** | 50+ files (20+ guides) |
| **Agents** | 3 (Coordinator, Security, Performance) |
| **Actions** | 8 (Review, Security, Performance) |
| **LLM Providers** | 2 (OpenAI, Gemini) |
| **Review Speed** | 50-100ms multi-agent |
| **LLM Speed** | 200-500ms typical |

---

## Core Capabilities

### Multi-Agent Code Review
```elixir
# Autonomous review workflow
iex> Synapse.Examples.Stage2Demo.run()

# Output:
# ✓ Coordinator spawns specialists
# ✓ Security + Performance analyze in parallel
# ✓ Results aggregated in 50-100ms
# ✓ Comprehensive findings returned
```

### Live LLM Analysis
```elixir
# Real-time LLM code review
iex> Synapse.ReqLLM.chat_completion(
  %{prompt: "Review this code: #{code}", messages: []},
  profile: :gemini
)

# Returns detailed security analysis in ~300ms
```

### Signal-Driven Communication
```elixir
# CloudEvents-compliant pub/sub
review.request → CoordinatorAgent
  → Spawns: SecurityAgent, PerformanceAgent
  → Parallel execution
  → review.result × 2
  → Aggregation
  → review.summary (final output)
```

---

## Technology Stack

### Core
- **Language**: Elixir 1.18+
- **Framework**: Phoenix 1.8.1
- **Agent Framework**: Jido 1.2.0
- **HTTP Client**: Req 0.5.15
- **Validation**: NimbleOptions

### Infrastructure
- **Signal Bus**: Jido.Signal.Bus (CloudEvents)
- **Agent Registry**: Custom GenServer registry
- **LLM Providers**: OpenAI, Google Gemini
- **Testing**: ExUnit (207 tests)

### Deployment
- **Platform**: BEAM VM
- **Environment**: WSL2 / Linux
- **Concurrency**: BEAM processes (lightweight)

---

## Getting Started

### Prerequisites
```bash
# Required
elixir >= 1.18
erlang >= 26

# API Keys (optional but recommended)
export GEMINI_API_KEY="your-key"
export OPENAI_API_KEY="your-key"
```

### Quick Start
```bash
# Clone and setup
git clone <repo>
cd synapse
mix deps.get

# Run tests
mix test
# 207 tests, 0 failures

# Start interactive shell
iex -S mix

# Run demos
iex> Synapse.Examples.Stage0Demo.run()  # Single agent
iex> Synapse.Examples.Stage2Demo.run()  # Multi-agent orchestration

# Test LLM integration
iex> Synapse.ReqLLM.chat_completion(
  %{prompt: "Hello!", messages: []},
  profile: :gemini
)
```

---

## Documentation Structure

```
docs/20251029/
├── INDEX.md                          ← You are here
├── PROJECT_STATUS.md                 ← Current state
├── ROADMAP.md                        ← Future phases
├── TECHNICAL_ARCHITECTURE.md         ← System design
│
├── implementation/                   ← What's built
│   ├── STAGE_2_COMPLETE.md
│   ├── LLM_INTEGRATION.md
│   ├── ORCHESTRATOR_STATUS.md
│   └── MULTI_AGENT_SYSTEM.md
│
└── roadmap/                          ← What's next
    ├── STAGE_3_ADVANCED.md
    ├── STAGE_4_MARKETPLACE.md
    ├── STAGE_5_LEARNING_MESH.md
    └── STAGE_6_PLANETARY.md
```

---

## Key Concepts

### Agents
Autonomous entities with:
- **State**: Learned patterns, review history, scar tissue
- **Actions**: Registered Jido actions they can execute
- **Signals**: Subscribe/emit patterns for communication
- **Lifecycle**: Supervised GenServers with auto-restart

### Actions
Jido actions are composable units of work:
- Schema-validated inputs
- Pure function execution
- Compensation on failure
- Telemetry integration

### Orchestration
Two approaches coexist:
1. **Hardcoded GenServers** (Current, Stage 2)
   - SecurityAgentServer, PerformanceAgentServer, CoordinatorAgentServer
   - Explicit signal subscriptions and routing
   - ~900 lines of boilerplate

2. **Declarative Config** (Partial, Stage 2+)
   - AgentConfig defines agents as data
   - Runtime spawns and manages agents
   - ~150 lines to replace 900

### Signal Flow
CloudEvents-compliant pub/sub:
```
Signal.Bus (global message router)
  ↓
Pattern-based routing (e.g., "review.*")
  ↓
Agent subscriptions
  ↓
Action execution
  ↓
Result emission
```

---

## Contributing

See [ROADMAP.md](ROADMAP.md) for priority features and [PROJECT_STATUS.md](PROJECT_STATUS.md) for current gaps.

### Priority Areas (Stage 3)
1. Timeout handling
2. Telemetry dashboard
3. Scar tissue learning
4. Hot reload configuration

---

## Support

- **Issues**: File in project repo
- **Questions**: See inline code documentation
- **Examples**: `lib/synapse/examples/`

---

**Last Updated**: 2025-10-29
**Next Review**: Stage 3 kickoff
