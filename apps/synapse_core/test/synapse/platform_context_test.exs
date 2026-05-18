defmodule Synapse.PlatformContextTest do
  use ExUnit.Case, async: true

  alias Synapse.{Config, PlatformContext, ProductPack}

  test "builds a bootstrap AppKit request context with product metadata" do
    config = Config.load(trace_id: "ignored")

    context =
      PlatformContext.bootstrap_context(config, trace_id: "11111111111111111111111111111111")

    assert context.trace_id == "11111111111111111111111111111111"
    assert context.actor_ref.id == "synapse_core"
    assert context.tenant_ref.id == config.tenant_id
    assert context.metadata.product_slug == ProductPack.pack_slug(config)
    assert context.metadata.runtime_profile.program.slug == config.product_slug
  end
end
