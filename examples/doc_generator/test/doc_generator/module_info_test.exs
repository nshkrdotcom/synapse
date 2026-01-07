defmodule DocGenerator.ModuleInfoTest do
  use ExUnit.Case, async: true

  alias DocGenerator.ModuleInfo

  describe "new/2" do
    test "creates a new ModuleInfo struct" do
      info = ModuleInfo.new(MyModule)

      assert info.module == MyModule
      assert info.functions == []
      assert info.types == []
      assert info.callbacks == []
      assert info.behaviours == []
    end

    test "creates ModuleInfo with options" do
      info =
        ModuleInfo.new(MyModule,
          moduledoc: "Test doc",
          functions: [%{name: :test, arity: 0}],
          types: [%{name: :my_type, type: :type}]
        )

      assert info.moduledoc == "Test doc"
      assert length(info.functions) == 1
      assert length(info.types) == 1
    end
  end

  describe "to_map/1" do
    test "converts ModuleInfo to map" do
      info =
        ModuleInfo.new(MyModule,
          moduledoc: "Test",
          functions: [%{name: :test, arity: 0}]
        )

      map = ModuleInfo.to_map(info)

      assert is_map(map)
      assert map.module == "MyModule"
      assert map.moduledoc == "Test"
      assert is_list(map.functions)
    end
  end
end
