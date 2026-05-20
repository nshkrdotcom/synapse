defmodule Synapse.ProductBootstrapTest do
  use ExUnit.Case, async: true

  alias AppKit.BackendStack
  alias AppKit.Core.InstallResult
  alias Synapse.{ProductBootstrap, ProductPack}

  defmodule AgentBackend do
    def start_agent_run(_context, _request, _opts), do: {:error, :not_used}
    def submit_agent_turn(_context, _submission, _opts), do: {:error, :not_used}
    def cancel_agent_run(_context, _run_ref, _opts), do: {:error, :not_used}
    def await_agent_outcome(_context, _run_ref, _request, _opts), do: {:error, :not_used}
  end

  defmodule EffectBackend do
    @behaviour AppKit.EffectSurface

    def propose_effect(_context, _attrs, _opts), do: {:error, :not_used}
    def get_effect(_context, _effect_ref, _opts), do: {:error, :not_used}
    def list_effects(_context, _run_ref, _opts), do: {:error, :not_used}
    def get_effect_timeline(_context, _effect_ref, _opts), do: {:error, :not_used}
  end

  test "disabled mode returns a product-safe disabled result" do
    assert {:ok, result} = ProductBootstrap.ensure_bootstrapped(bootstrap_mode: :disabled)

    assert result.status == :disabled
    assert result.installation_ref.status == :inactive
    assert result.pack.slug == ProductPack.pack_slug([])
  end

  test "required mode bootstraps through an injected AppKit installation surface" do
    assert {:ok, result} =
             ProductBootstrap.ensure_bootstrapped(
               bootstrap_mode: :required,
               installation_surface: Synapse.Fixtures.InstallationSurface,
               trace_id: "22222222222222222222222222222222"
             )

    assert result.status == :bootstrapped
    assert %InstallResult{} = result.install_result
    assert %InstallResult{} = result.authoring_result
    assert result.installation_ref.status == :active
    assert result.authoring_result.metadata.bundle.bundle_id == "nshkr-agent-default-0.1.0"
  end

  test "retrying mode schedules retry state when the live surface is unavailable" do
    assert {:ok, result} =
             ProductBootstrap.ensure_bootstrapped(
               bootstrap_mode: :retrying,
               installation_surface: NotLoaded.InstallationSurface
             )

    assert result.status == :retry_scheduled
    assert result.retry_delay_ms == 2_000
    assert result.reason == {:installation_surface_not_available, NotLoaded.InstallationSurface}
  end

  test "fixture status classifies installation as not live" do
    status = ProductBootstrap.fixture_status()

    assert status.status == :fixture_backed
    assert status.surface == "AppKit.InstallationSurface"
    assert status.live? == false
  end

  test "effect surface status detects injected staged-live capability" do
    stack =
      BackendStack.new!(
        agent_intake_backend: AgentBackend,
        effect_surface_backend: EffectBackend
      )

    status = ProductBootstrap.effect_surface_status(backend_stack: stack)

    assert status.status == :staging_live
    assert status.live? == true
    assert status.effect_surface_available? == true
    assert status.agent_intake_available? == true
  end

  test "effect surface status stays fixture-backed without both live backends" do
    status = ProductBootstrap.effect_surface_status(effect_surface_adapter: EffectBackend)

    assert status.status == :fixture_backed
    assert status.live? == false
    assert status.effect_surface_available? == true
    assert status.agent_intake_available? == false
  end
end
