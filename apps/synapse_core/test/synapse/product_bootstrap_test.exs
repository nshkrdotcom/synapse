defmodule Synapse.ProductBootstrapTest do
  use ExUnit.Case, async: true

  alias AppKit.Core.InstallResult
  alias Synapse.{ProductBootstrap, ProductPack}

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
end
