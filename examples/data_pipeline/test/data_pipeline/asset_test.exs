defmodule DataPipeline.AssetTest do
  use ExUnit.Case, async: true

  alias DataPipeline.Asset

  describe "new/2" do
    test "creates an asset with required fields" do
      asset =
        Asset.new(:test_asset,
          materializer: fn _deps -> {:ok, [1, 2, 3]} end
        )

      assert asset.name == :test_asset
      assert is_function(asset.materializer, 1)
      assert asset.deps == []
    end

    test "creates an asset with dependencies" do
      asset =
        Asset.new(:dependent_asset,
          deps: [:upstream_asset],
          materializer: fn %{upstream_asset: data} -> {:ok, data} end
        )

      assert asset.deps == [:upstream_asset]
    end

    test "raises error without materializer" do
      assert_raise ArgumentError, fn ->
        Asset.new(:invalid_asset)
      end
    end
  end

  describe "materialize/2" do
    test "executes materializer function" do
      asset =
        Asset.new(:test_asset,
          materializer: fn _deps -> {:ok, [1, 2, 3]} end
        )

      assert {:ok, [1, 2, 3]} = Asset.materialize(asset)
    end

    test "passes dependencies to materializer" do
      asset =
        Asset.new(:dependent_asset,
          deps: [:upstream],
          materializer: fn %{upstream: data} -> {:ok, Enum.map(data, &(&1 * 2))} end
        )

      assert {:ok, [2, 4, 6]} = Asset.materialize(asset, %{upstream: [1, 2, 3]})
    end
  end

  describe "validate_dependencies/1" do
    test "validates correct dependencies" do
      assets = [
        Asset.new(:a, materializer: fn _ -> {:ok, 1} end),
        Asset.new(:b, deps: [:a], materializer: fn _ -> {:ok, 2} end),
        Asset.new(:c, deps: [:a, :b], materializer: fn _ -> {:ok, 3} end)
      ]

      assert :ok = Asset.validate_dependencies(assets)
    end

    test "detects missing dependencies" do
      assets = [
        Asset.new(:a, materializer: fn _ -> {:ok, 1} end),
        Asset.new(:b, deps: [:missing], materializer: fn _ -> {:ok, 2} end)
      ]

      assert {:error, message} = Asset.validate_dependencies(assets)
      assert message =~ "unknown assets"
    end
  end

  describe "topological_sort/1" do
    test "sorts assets in dependency order" do
      assets = [
        Asset.new(:c, deps: [:a, :b], materializer: fn _ -> {:ok, 3} end),
        Asset.new(:a, materializer: fn _ -> {:ok, 1} end),
        Asset.new(:b, deps: [:a], materializer: fn _ -> {:ok, 2} end)
      ]

      assert {:ok, sorted} = Asset.topological_sort(assets)
      names = Enum.map(sorted, & &1.name)

      # :a should come before :b and :c
      # :b should come before :c
      assert Enum.find_index(names, &(&1 == :a)) < Enum.find_index(names, &(&1 == :b))
      assert Enum.find_index(names, &(&1 == :a)) < Enum.find_index(names, &(&1 == :c))
      assert Enum.find_index(names, &(&1 == :b)) < Enum.find_index(names, &(&1 == :c))
    end

    test "handles assets with no dependencies" do
      assets = [
        Asset.new(:a, materializer: fn _ -> {:ok, 1} end),
        Asset.new(:b, materializer: fn _ -> {:ok, 2} end)
      ]

      assert {:ok, _sorted} = Asset.topological_sort(assets)
    end
  end
end
