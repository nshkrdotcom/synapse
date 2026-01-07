defmodule ResearchAgent.QueryTest do
  use ExUnit.Case, async: true

  alias ResearchAgent.Query

  describe "new/2" do
    test "creates a query with default options" do
      query = Query.new("Test topic")

      assert query.topic == "Test topic"
      assert query.depth == :quick
      assert query.max_sources == 10
      assert query.reliability_threshold == 0.6
      assert query.include_citations == true
      assert is_binary(query.id)
      assert %DateTime{} = query.inserted_at
    end

    test "creates a query with custom options" do
      query =
        Query.new("Custom topic",
          depth: :deep,
          max_sources: 20,
          reliability_threshold: 0.8,
          include_citations: false
        )

      assert query.topic == "Custom topic"
      assert query.depth == :deep
      assert query.max_sources == 20
      assert query.reliability_threshold == 0.8
      assert query.include_citations == false
    end

    test "generates unique IDs" do
      query1 = Query.new("Topic 1")
      query2 = Query.new("Topic 2")

      assert query1.id != query2.id
      assert String.starts_with?(query1.id, "query_")
      assert String.starts_with?(query2.id, "query_")
    end
  end

  describe "to_map/1" do
    test "converts query to map" do
      query = Query.new("Test topic", depth: :deep)
      map = Query.to_map(query)

      assert map.topic == "Test topic"
      assert map.depth == :deep
      assert map.id == query.id
      assert is_binary(map.inserted_at)
    end
  end
end
