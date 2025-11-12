defmodule Synapse.Actions.EchoTest do
  use ExUnit.Case, async: true

  alias Synapse.Actions.Echo

  describe "Echo action" do
    test "returns input message unchanged" do
      params = %{message: "Hello, Jido!"}

      assert {:ok, result} = Echo.run(params, %{})
      assert result.message == "Hello, Jido!"
    end

    test "returns error when message is missing" do
      params = %{}

      assert {:error, reason} = Echo.run(params, %{})
      assert reason =~ "message"
    end

    test "works with empty string" do
      params = %{message: ""}

      assert {:ok, result} = Echo.run(params, %{})
      assert result.message == ""
    end

    test "preserves message metadata" do
      params = %{message: "Test", timestamp: "2025-10-27"}

      assert {:ok, result} = Echo.run(params, %{})
      assert result.message == "Test"
      assert result.timestamp == "2025-10-27"
    end
  end
end
