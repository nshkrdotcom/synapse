# Agents Reference

## Local Agent Workspace

- `/agentjido/` is kept out of version control via the `.gitignore` entry at `/agentjido/`, but it is available locally for experimentation.
- The directory contains three sibling libraries that power our agent work: `agentjido/jido`, `agentjido/jido_signal`, and `agentjido/jido_action`.
- The Jido guides live under `agentjido/jido/guides` (explore that folder for detailed walkthroughs).

● **Agents vs Pipelines: The Architecture of World Domination 🌍**

You're asking the right question. Let me break down the fundamental differences and show you how to actually build toward multi-agent dominance.

---

**Core Concepts**

**Pipelines (Runners)**

What: Static, deterministic data transformations  
Decision-making: Zero - always follows the same path  
Tools: No - just pure functions chained together

```elixir
# Pipeline: Always does A -> B -> C
input
|> validate()
|> transform()
|> format()
|> output()
```

When to use:
- You know the exact steps beforehand
- No decisions needed
- Same path every time
- Performance critical

**Agents**

What: Autonomous entities with state, goals, and decision-making  
Decision-making: High - chooses actions based on context  
Tools: Yes - can select and use different tools

```elixir
# Agent: Decides what to do based on input
agent
|> observe(situation)
|> reason() # "Is this simple? Complex? Urgent?"
|> decide_action() # Pick: quick_review OR deep_analysis OR escalate
|> use_tool(selected_action)
|> learn_from_result()
```

When to use:
- Need decision-making
- Adapt to different scenarios
- Learn from experience
- Coordinate with other agents

---

**The Fundamental Difference**

Pipeline: "Do these steps"

```elixir
# Always the same, no choices
def pipeline(input) do
  input
  |> step1()
  |> step2()
  |> step3()
end
```

Agent: "Achieve this goal"

```elixir
# Different paths based on reasoning
def agent_decide(input, agent_state) do
  case analyze_situation(input) do
    :simple ->
      agent |> use_tool(QuickReview)

    :complex ->
      agent
      |> use_tool(DeepAnalysis)
      |> maybe(use_tool(SecurityCheck))
      |> maybe(use_tool(PerformanceCheck))

    :urgent ->
      agent
      |> use_tool(FastTrack)
      |> signal_other_agent(:escalate)
  end
end
```

---

**Your Current State (Honest Assessment)**

What You Have Now

```elixir
# This is a PIPELINE dressed as agents
def evaluate(input) do
  input
  |> SimpleExecutor.cmd(Echo)        # Always echo
  |> CriticAgent.cmd(CriticReview)   # Always review
  |> GenerateCritique.run()          # Always LLM
end
```

Reality: This is a static pipeline using agent infrastructure. The current Synapse runtime already ships with a declarative
orchestrator (`priv/orchestrator_agents.exs`) that decides which specialists run for each review. Instead of hand-written
GenServers like `CoordinatorAgentServer` or `SecurityAgentServer`, every agent is now described as configuration.

```elixir
# priv/orchestrator_agents.exs (excerpt)
%{
  id: :coordinator,
  type: :orchestrator,
  actions: [Synapse.Actions.Review.ClassifyChange],
  orchestration: %{
    classify_fn: &Synapse.Orchestrator.Config.Classifier.fast_or_deep/1,
    spawn_specialists: [:security_specialist, :performance_specialist],
    aggregation_fn: &Synapse.Orchestrator.Config.Aggregation.combine/2
  },
  signals: %{subscribes: [:review_request, :review_result], emits: [:review_summary]}
}
```

That declarative Config is what the runtime executes today; the rest of this document explains how to evolve it into
multi-agent dominance (specialist negotiation, learning, etc.).

What You Should Have (Multi-Agent)

```elixir
# Real multi-agent: the declarative runtime decides everything
defmodule Synapse.Orchestrator.Config do
  def coordinator_spec do
    %{
      id: :coordinator,
      type: :orchestrator,
      actions: [Synapse.Actions.Review.ClassifyChange],
      orchestration: %{
        classify_fn: &Strategies.classify/1,
        spawn_specialists: &Strategies.choose_team/2,
        fast_path_fn: &Strategies.fast_path/2,
        aggregation_fn: &Strategies.aggregate/2,
        negotiate_fn: &Strategies.resolve_conflicts/2
      },
      signals: %{subscribes: [:review_request, :review_result], emits: [:review_summary]}
    }
  end
end
```

```elixir
# Runtime consumes that config – no GenServers required
{:ok, _runtime} =
  Synapse.Orchestrator.Runtime.start_link(
    config_source: {:priv, "orchestrator_agents.exs"},
    include_types: :all,
    router: :synapse_router,
    registry: :synapse_registry
  )

# Sending a review request is just a signal publish
Synapse.SignalRouter.publish(
  :synapse_router,
  :review_request,
  %{review_id: "123", diff: diff, labels: ["security"]}
)

# RunConfig + Workflow.Engine classify, spawn specialists, and emit review.summary
```

---

**Tools: The Agent's Superpowers**

What Are Tools?

In agent systems: Tools are capabilities an agent can choose to use.

```elixir
# Agent has a toolbox
defmodule CriticAgent do
  use Jido.Agent,
    actions: [
      # These are TOOLS the agent can use
      StaticAnalysis,
      SecurityScan,
      PerformanceBenchmark,
      LLMReview,
      GitBlame,
      RunTests,
      CheckCoverage
    ]
end
```

```elixir
# Agent DECIDES which tool to use
def decide_tools(code, context) do
  cond do
    security_sensitive?(code) ->
      [SecurityScan, LLMReview, GitBlame]

    performance_critical?(code) ->
      [PerformanceBenchmark, RunTests]

    simple_change?(code) ->
      [StaticAnalysis]
  end
end
```

Pipelines Don't Have Tools

```elixir
# Pipeline: No choices, no tools
def pipeline(code) do
  code
  |> lint()        # Always runs
  |> format()      # Always runs
  |> validate()    # Always runs
end
```

---

**Mixing Agents and Pipelines**

Yes, they work together! Here's how:

Pattern 1: Agents Orchestrate Pipelines

```elixir
defmodule OrchestratorAgent do
  # Agent decides WHICH pipeline to run
  def decide_pipeline(code) do
    case classify(code) do
      :backend ->
        BackendPipeline.run(code)  # Specific pipeline

      :frontend ->
        FrontendPipeline.run(code)  # Different pipeline

      :security ->
        SecurityPipeline.run(code)  # Security pipeline
    end
  end
end
```

Pattern 2: Pipelines Within Agent Actions

```elixir
defmodule DeepAnalysisAction do
  # This is a TOOL that contains a pipeline
  def run(code, _context) do
    # Internal pipeline
    code
    |> parse_ast()
    |> analyze_complexity()
    |> detect_patterns()
    |> score_quality()
  end
end

# Agent uses this as a tool
agent |> cmd(DeepAnalysisAction)
```

Pattern 3: Agent Network Calling Pipelines

```elixir
# Agents coordinate, pipelines execute
def review_workflow(code) do
  # Stage 1: Agent decides
  strategy = DecisionAgent.choose_strategy(code)

  # Stage 2: Pipeline executes
  analysis = AnalysisPipeline.run(code, strategy)

  # Stage 3: Multiple agents review
  reviews = [
    SecurityAgent.review(analysis),
    PerformanceAgent.review(analysis),
    StyleAgent.review(analysis)
  ]

  # Stage 4: Synthesis agent combines
  SynthesisAgent.combine(reviews)
end
```

---

**World Domination Architecture**

Here's how to actually use multi-agent with Jido:

Level 1: Specialist Agents (What You Need Next)

```elixir
# Create specialized agents with different goals
defmodule SecurityAgent do
  use Jido.Agent,
    name: "security_specialist",
    actions: [
      CheckSQLInjection,
      CheckXSS,
      CheckAuthIssues,
      CheckCrypto
    ]

  # Agent learns what to prioritize
  def decide_checks(code) do
    learned_patterns = state.learned_patterns

    code
    |> extract_features()
    |> match_patterns(learned_patterns)
    |> prioritize_checks()
  end
end
```

```elixir
defmodule PerformanceAgent do
  use Jido.Agent,
    name: "performance_specialist",
    actions: [
      CheckNPlusOne,
      CheckMemoryLeaks,
      CheckAlgorithmComplexity,
      BenchmarkHotPaths
    ]
end
```

```elixir
defmodule StyleAgent do
  use Jido.Agent,
    name: "style_specialist",
    actions: [
      CheckFormatting,
      CheckNaming,
      CheckDocumentation,
      CheckTestCoverage
    ]
end
```

Level 2: Coordinator Agent (Orchestrates Others)

```elixir
defmodule CoordinatorAgent do
  use Jido.Agent,
    name: "coordinator",
    schema: [
      active_agents: [type: {:list, :pid}, default: []],
      strategies: [type: {:map}, default: %{}]
    ]

  def evaluate(code, intent) do
    # Decide which agents to activate
    agent_team = choose_team(code, intent)

    # Spawn specialist agents
    agents = Enum.map(agent_team, &spawn_agent/1)

    # Coordinate their work (parallel or sequential)
    case intent do
      :urgent -> parallel_review(agents, code)
      :thorough -> sequential_review(agents, code)
      :learning -> collaborative_review(agents, code)
    end
  end

  defp choose_team(code, intent) do
    cond do
      security_critical?(code) ->
        [SecurityAgent, StyleAgent]

      performance_critical?(code) ->
        [PerformanceAgent, SecurityAgent]

      intent == :learning ->
        [SecurityAgent, PerformanceAgent, StyleAgent]

      true ->
        [StyleAgent]  # Fast path
    end
  end
end
```

Level 3: Learning and Adaptation

```elixir
defmodule AdaptiveAgent do
  use Jido.Agent,
    name: "adaptive_reviewer",
    schema: [
      success_patterns: [type: {:list, :map}, default: []],
      failure_patterns: [type: {:list, :map}, default: []],
      tool_effectiveness: [type: :map, default: %{}]
    ]

  def review_with_learning(code, feedback \\ nil) do
    # Learn from previous feedback
    if feedback, do: update_patterns(feedback)

    # Choose tools based on learned effectiveness
    tools = choose_best_tools(code, state.tool_effectiveness)

    # Execute review
    result = execute_tools(tools, code)

    # Track effectiveness for learning
    track_tool_performance(tools, result)

    result
  end

  def update_patterns(feedback) do
    case feedback.result do
      :successful ->
        add_success_pattern(feedback.context)

      :failed ->
        add_failure_pattern(feedback.context)
    end
  end
end
```

Level 4: Agent Negotiation

```elixir
defmodule NegotiatingAgent do
  # Agents communicate via signals
  def handle_signal(%Signal{type: "review.conflict"} = signal) do
    # Another agent disagrees with our assessment
    their_review = signal.data.review
    our_review = state.last_review

    case negotiate_consensus(our_review, their_review) do
      {:agree, consensus} ->
        # Found agreement
        emit_signal("review.consensus", consensus)

      {:disagree, reasons} ->
        # Escalate to human or higher-level agent
        emit_signal("review.escalate", %{
          conflict: {our_review, their_review},
          reasons: reasons
        })
    end
  end
end
```

---

**What You Should Build Next**

To actually make this multi-agent:

Step 1: Create Specialist Agents

```elixir
# Don't have one CriticAgent - have many specialists!
defmodule Synapse.Agents.SecuritySpecialist do
  use Jido.Agent,
    actions: [
      CheckSQLInjection,
      CheckXSS,
      CheckAuthVulnerabilities
    ]
end
```

```elixir
defmodule Synapse.Agents.PerformanceSpecialist do
  use Jido.Agent,
    actions: [
      CheckComplexity,
      CheckMemoryUsage,
      ProfileHotPaths
    ]
end
```

Step 2: Add Decision-Making

```elixir
# Agent chooses which tools to use
def on_before_run(agent) do
  context = agent.context

  # Decide what to check based on code type
  actions_to_run =
    case classify_code(context.code) do
      :api_endpoint -> [:check_auth, :check_sql_injection]
      :ui_component -> [:check_xss, :check_accessibility]
      :algorithm -> [:check_complexity, :check_correctness]
    end

  # Update agent's planned actions
  Jido.Agent.plan(agent, actions_to_run)
end
```

Step 3: Enable Agent Communication

```elixir
# Agents signal each other
def transform_result(%Signal{} = signal, result) do
  if result.security_risk > 0.7 do
    # Alert other agents
    alert =
      Jido.Signal.new!(%{
        type: "security.alert",
        data: result,
        source: agent.name
      })

    {:ok, result, alert}
  else
    {:ok, result}
  end
end
```

Step 4: Learn and Adapt

```elixir
# Agent learns from results
def on_after_run(agent, result, _directives) do
  # Update learned patterns
  pattern = extract_pattern(result)

  updated_patterns =
    case result.accuracy do
      acc when acc > 0.8 ->
        add_successful_pattern(agent.state.patterns, pattern)

      _ ->
        add_failed_pattern(agent.state.patterns, pattern)
    end

  Jido.Agent.set(agent, %{patterns: updated_patterns})
end
```

---

**The Ultimate Architecture**

```elixir
# This is what multi-agent ACTUALLY looks like:

# 1. User submits code
{:ok, review_request} = ReviewSystem.submit(code)

# 2. Runtime loads declarative config
{:ok, runtime} =
  Synapse.Orchestrator.Runtime.start_link(
    config_source: {:priv, "orchestrator_agents.exs"},
    include_types: :all,
    router: :synapse_router,
    registry: :synapse_registry
  )

# 3. Coordinator config classifies and spawns specialists
Synapse.SignalRouter.publish(
  runtime.router,
  :review_request,
  %{review_id: review_id, diff: diff, labels: labels}
)

# 4. Specialists are just config entries – Runtime spins up workflows per request
# 5. RunConfig executes each specialist's actions and emits :review_result signals
# 6. Coordinator orchestration aggregates and negotiates results declaratively
# 7. Summary is emitted on :review_summary and persisted via Workflow.Engine
# 8. Telemetry [:synapse, :workflow, :orchestrator, :summary] captures outcomes
# 9. Ops dashboards/alerts read from telemetry + workflow_executions
# 10. Humans step in only when summaries escalate or negotiation cannot resolve
```

---

**Key Insights**

Why Agents Beat Pipelines for Your Goal

| Aspect       | Pipeline      | Agent                             |
|--------------|---------------|-----------------------------------|
| Decisions    | None          | Yes - agents choose actions       |
| Learning     | None          | Yes - patterns improve over time  |
| Parallelism  | Sequential    | Natural - each agent is a process |
| Adaptability | Fixed         | Dynamic - agents adapt to input   |
| Scalability  | Vertical only | Horizontal - spawn more agents    |
| Coordination | Manual code   | Signals/messages                  |

Where They Work Together

1. Agent decides -> Pipeline executes -> Agent learns
2. Pipeline preprocesses -> Agent reasons -> Agent acts
3. Agent coordinates -> Multiple pipelines (different strategies)

---

**Your Next Steps**

Immediate (Make It Actually Multi-Agent)

1. Split the declarative configs in `priv/orchestrator_agents.exs` into specialists (`:security_specialist`, `:performance_specialist`, `:style_specialist`, `:docs_specialist`).
2. Extend the `:coordinator` orchestration block (classify/fast-path/spawn/aggregate/negotiate) instead of writing new GenServers.
   - Classifier decides which path to take.
   - `spawn_specialists` or custom selector picks the agent team.
3. Wire agent-to-agent communication through signals (`:review_request`, `:review_result`, custom alerts).
   - Specialists emit findings.
   - Coordinator (or another config entry) negotiates disagreements.
   - Signals trigger escalations instead of direct casts.
4. Layer learning on top of stateful configs.
   - Use `state_schema` + `RunConfig` state to track which tools work.
   - Feed negotiation outcomes back into configs (patterns, scar tissue).
   - Keep pattern libraries inside the runtime state rather than GenServers.

Medium Term (World Domination)

5. Agent marketplace.
   - Plug in new specialist agents.
   - Agents subscribe to review types.
   - Dynamic team formation.
6. Multi-level hierarchy.
   - Junior agents (fast, simple).
   - Senior agents (deep analysis).
   - Architect agents (system-wide view).
7. Learning network.
   - Agents share knowledge.
   - Distributed pattern library.
   - Collective intelligence.

Long Term (Actually Taking Over)

8. Self-improving agents.
   - Agents create better tools.
   - Agents train other agents.
   - Emergent strategies.
9. Human-agent collaboration.
   - Agents learn from humans.
   - Humans guide agent reasoning.
   - Hybrid intelligence.
10. Agent orchestration at scale.
    - Thousands of specialist agents.
    - Real-time coordination.
    - Global knowledge sharing.

---

**Where to Continue**

- `ROADMAP.md` – definitive plan for Stages 3–6, including marketplace, learning mesh, and planetary-scale work.
- `CONTINUATION_PROMPT.md` – snapshot prompt detailing required reading plus five concrete next moves (marketplace port, observability build-out, DSL tooling, performance-based pricing prototype, onboarding docs).
- Legacy market stack (all under `lib_old/`):
  - `lib_old/mabeam/economics.ex`
  - `lib_old/mabeam/coordination/market.ex`
  - `lib_old/mabeam/coordination/auction.ex`
  - `lib_old/foundation/coordination/primitives.ex`
  - `lib_old/mabeam/types.ex`

Those files provide the marketplace/dynamic-pricing reference implementation that Stage 4 will port into the declarative runtime. Read them before touching the marketplace roadmap items.

---

**Bottom Line**

What you have: A pipeline wearing an agent costume.  
What you need: Actual agents making decisions, coordinating, learning.  
The gap: Add decision-making, specialist agents, and inter-agent communication.

The enhancements we did today (Chain, Helpers, Compensation) made the infrastructure better. But to achieve multi-agent dominance, you need to:

1. ✅ Split into specialist agents.
2. ✅ Add decision logic (agents choose tools).
3. ✅ Enable agent communication (signals).
4. ✅ Implement learning (patterns evolve).
5. ✅ Spawn agents as processes (true parallelism).

Want help building the first real multi-agent feature—like having `SecurityAgent` and `PerformanceAgent` work together on the same code review?

---

This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        # reset the stream with the new messages
        |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
