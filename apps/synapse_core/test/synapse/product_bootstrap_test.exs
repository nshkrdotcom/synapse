defmodule Synapse.ProductBootstrapTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.InstallResult
  alias Synapse.{ProductBootstrap, ProductPack}

  defmodule EffectBackend do
    @behaviour AppKit.EffectSurface

    def propose_effect(_context, _attrs, _opts), do: {:error, :not_used}
    def get_effect(_context, _effect_ref, _opts), do: {:error, :not_used}
    def list_effects(_context, _run_ref, _opts), do: {:error, :not_used}
    def get_effect_timeline(_context, _effect_ref, _opts), do: {:error, :not_used}
  end

  test "disabled installation mode returns a product-safe result" do
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
  end

  test "retrying mode schedules retry state when the installation surface is unavailable" do
    assert {:ok, result} =
             ProductBootstrap.ensure_bootstrapped(
               bootstrap_mode: :retrying,
               installation_surface: NotLoaded.InstallationSurface
             )

    assert result.status == :retry_scheduled
    assert result.retry_delay_ms == 2_000
    assert result.reason == {:installation_surface_not_available, NotLoaded.InstallationSurface}
  end

  test "resolves the configured provider into complete durable AppKit options" do
    assert {:ok, opts} = ProductBootstrap.durable_readback_options()
    assert %AppKit.BackendStack{} = opts[:app_kit_backend_stack]
    assert opts[:program_id] == "program://test/synapse"
    assert opts[:work_class_id] == "work-class://test/agent-run"
  end

  test "fails closed when owner routing is absent" do
    assert {:error, :app_kit_routing_unavailable} =
             ProductBootstrap.agent_intake_options(
               backend: Synapse.Test.AppKitBackend,
               program_id: nil,
               work_class_id: nil
             )
  end

  test "effect status is unavailable without a complete runtime stack" do
    status =
      ProductBootstrap.effect_surface_status(
        app_kit_backend_stack: nil,
        effect_surface_adapter: EffectBackend,
        program_id: "program://test/synapse",
        work_class_id: "work-class://test/agent-run"
      )

    assert status.status == :unavailable
    assert status.live? == false
    assert status.agent_intake_available? == false
  end
end
