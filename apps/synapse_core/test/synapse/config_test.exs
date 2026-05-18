defmodule Synapse.ConfigTest do
  use ExUnit.Case, async: true

  alias Synapse.Config

  test "loads deterministic defaults" do
    config = Config.load()

    assert config.product_slug == "nshkr-agent"
    assert config.bootstrap_mode == :disabled
    assert config.execution_timeout_ms == 300_000
  end

  test "normalizes allowed string bootstrap modes without dynamic atoms" do
    assert %Config{bootstrap_mode: :required} = Config.load(%{"bootstrap_mode" => "required"})
    assert %Config{bootstrap_mode: :retrying} = Config.load(%{"bootstrap_mode" => "retrying"})
    assert %Config{bootstrap_mode: :disabled} = Config.load(%{"bootstrap_mode" => "disabled"})
  end

  test "rejects unknown bootstrap mode" do
    assert_raise ArgumentError, "invalid Synapse.Config bootstrap_mode \"other\"", fn ->
      Config.load(%{"bootstrap_mode" => "other"})
    end
  end
end
