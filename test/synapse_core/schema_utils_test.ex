# # synapse_core/test/synapse_core/schema_utils_test.exs

# defmodule SynapseCore.SchemaUtilsTest do
#   use ExUnit.Case, async: true

#   doctest SynapseCore.SchemaUtils

#   # Test cases for elixir_to_json_schema
#   # ...

#   # Test cases for json_schema_to_elixir_type
#   # ...

#   # Test cases for validate
#   # ...
# end


# synapse_core/test/synapse_core/schema_utils_test.exs

defmodule SynapseCore.SchemaUtilsTest do
  use ExUnit.Case

  describe "elixir_to_json_schema/1" do
    test "converts basic types" do
      assert SchemaUtils.elixir_to_json_schema(:string) == %{"type" => "string"}
      assert SchemaUtils.elixir_to_json_schema(:integer) == %{"type" => "integer"}
      # ... other basic types
    end

    test "converts lists" do
      assert SchemaUtils.elixir_to_json_schema([:integer]) == %{"type" => "array", "items" => %{"type" => "integer"}}
    end

    test "converts maps" do
      schema = %{
        name: :string,
        age: {:integer, :required},
        city: :string
      }
      expected_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "city" => %{"type" => "string"}
        },
        "required" => ["age"]
      }
      assert SchemaUtils.elixir_to_json_schema(schema) == expected_schema
    end
  end

  # ... more test cases for other functions ...
end
