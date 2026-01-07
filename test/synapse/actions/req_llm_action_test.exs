defmodule Synapse.Actions.ReqLLMActionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Synapse.Actions.GenerateCritique
  alias Synapse.ReqLLM

  setup context do
    Req.Test.set_req_test_to_private(context)

    original = Application.get_env(:synapse, Synapse.ReqLLM)
    original_llm_module = Application.get_env(:synapse, :req_llm_module)
    original_force_legacy = Application.get_env(:synapse, :force_legacy_req_llm)

    # Force legacy implementation for these tests (they use Req.Test stubs)
    Application.put_env(:synapse, :force_legacy_req_llm, true)
    Application.put_env(:synapse, :req_llm_module, Synapse.ReqLLM)

    test_name = Atom.to_string(context.test)
    openai_stub = String.to_atom("req_llm_action_openai_#{test_name}")
    gemini_stub = String.to_atom("req_llm_action_gemini_#{test_name}")

    Application.put_env(:synapse, Synapse.ReqLLM,
      default_profile: :openai,
      profiles: %{
        openai: [
          base_url: "https://llm.test",
          api_key: "test-key",
          model: "gpt-5-nano",
          allowed_models: ["gpt-5-nano"],
          plug: {Req.Test, openai_stub},
          plug_owner: self(),
          req_options: [receive_timeout: 1_800_000],
          retry: [
            max_attempts: 3,
            base_backoff_ms: 5,
            max_backoff_ms: 10
          ]
        ],
        gemini: [
          base_url: "https://llm.test",
          api_key: "gemini-key",
          model: "gemini-flash-lite-latest",
          allowed_models: ["gemini-flash-lite-latest"],
          plug: {Req.Test, gemini_stub},
          plug_owner: self(),
          payload_format: :google_generate_content,
          auth_header: "x-goog-api-key",
          auth_header_prefix: nil,
          req_options: [receive_timeout: 1_800_000],
          retry: [
            max_attempts: 3,
            base_backoff_ms: 5,
            max_backoff_ms: 10
          ]
        ]
      }
    )

    on_exit(fn ->
      if original do
        Application.put_env(:synapse, Synapse.ReqLLM, original)
      else
        Application.delete_env(:synapse, Synapse.ReqLLM)
      end

      if original_llm_module do
        Application.put_env(:synapse, :req_llm_module, original_llm_module)
      else
        Application.delete_env(:synapse, :req_llm_module)
      end

      if original_force_legacy do
        Application.put_env(:synapse, :force_legacy_req_llm, original_force_legacy)
      else
        Application.delete_env(:synapse, :force_legacy_req_llm)
      end
    end)

    config = Application.get_env(:synapse, Synapse.ReqLLM)
    assert config[:default_profile] == :openai

    openai_profile = config[:profiles] |> Map.fetch!(:openai)
    assert Keyword.get(openai_profile, :model) == "gpt-5-nano"

    %{openai_stub: openai_stub, gemini_stub: gemini_stub}
  end

  test "sends prompt to LLM and returns content", %{openai_stub: stub} do
    prompt = "Summarize the following text"

    Req.Test.expect(stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Jason.decode!(body)

      assert json["model"] == "gpt-5-nano"
      assert [%{"role" => "system"} | _] = json["messages"]
      assert Enum.any?(json["messages"], fn msg -> msg["content"] =~ prompt end)

      Req.Test.json(conn, %{
        choices: [
          %{
            "message" => %{
              "content" => "Here is the requested summary."
            }
          }
        ],
        usage: %{"total_tokens" => 128},
        id: "resp-123"
      })
    end)

    {:ok, result} =
      Jido.Exec.run(
        GenerateCritique,
        %{
          prompt: prompt,
          messages: [
            %{role: "user", content: "Summarize: Hello world"}
          ]
        }
      )

    assert result.content == "Here is the requested summary."
    assert result.metadata.total_tokens == 128
    assert result.metadata.provider_id == "resp-123"
  end

  test "supports switching profiles", %{gemini_stub: stub} do
    Req.Test.expect(stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Jason.decode!(body)

      assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["gemini-key"]

      assert [
               %{
                 "role" => "user",
                 "parts" => [%{"text" => "Say hello"}]
               }
             ] = json["contents"]

      assert get_in(json, ["system_instruction", "parts", Access.at(0), "text"])

      Req.Test.json(conn, %{
        "candidates" => [
          %{
            "content" => %{"parts" => [%{"text" => "Gemini says hi."}]},
            "finishReason" => "STOP"
          }
        ],
        "usageMetadata" => %{"totalTokenCount" => 42}
      })
    end)

    {:ok, result} =
      Jido.Exec.run(
        GenerateCritique,
        %{
          prompt: "Say hello",
          messages: [],
          profile: :gemini
        }
      )

    assert result.content == "Gemini says hi."
    assert result.metadata.total_tokens == 42
  end

  test "returns helpful error when configuration missing", _context do
    Application.delete_env(:synapse, Synapse.ReqLLM)

    # Capture expected error logs from this intentional config failure
    capture_log(fn ->
      assert {:error, error} =
               Jido.Exec.run(
                 GenerateCritique,
                 %{prompt: "Something", messages: []},
                 %{},
                 max_retries: 0
               )

      assert error.message =~ "configuration"
    end)
  end

  test "rejects models outside provider allow list", _context do
    assert {:error, error} =
             legacy_chat_completion(%{prompt: "hi", messages: []}, profile: :openai, model: "bad")

    assert is_exception(error)
    assert error.message =~ "not allowed"
  end

  test "validates configuration with helpful errors", _context do
    original = Application.get_env(:synapse, Synapse.ReqLLM)

    # Set invalid config (missing required base_url)
    Application.put_env(:synapse, Synapse.ReqLLM,
      profiles: [
        broken: [
          api_key: "test-key",
          model: "gpt-4"
          # missing base_url!
        ]
      ]
    )

    # Capture expected error logs
    capture_log(fn ->
      assert {:error, error} = legacy_chat_completion(%{prompt: "test", messages: []})

      assert is_exception(error)
      assert error.message =~ "required :base_url option not found"
    end)

    # Restore
    if original do
      Application.put_env(:synapse, Synapse.ReqLLM, original)
    end
  end

  test "validates retry configuration", _context do
    original = Application.get_env(:synapse, Synapse.ReqLLM)

    # Set invalid retry config
    Application.put_env(:synapse, Synapse.ReqLLM,
      profiles: [
        openai: [
          base_url: "https://llm.test",
          api_key: "test-key",
          retry: [
            # Invalid: must be positive
            max_attempts: -1
          ]
        ]
      ]
    )

    capture_log(fn ->
      assert {:error, error} = legacy_chat_completion(%{prompt: "test", messages: []})

      assert is_exception(error)
      assert error.message =~ "invalid value for :max_attempts"
    end)

    # Restore
    if original do
      Application.put_env(:synapse, Synapse.ReqLLM, original)
    end
  end

  test "retries on 500 server errors with exponential backoff", %{openai_stub: stub} do
    # Track retry attempts
    test_pid = self()

    Req.Test.expect(stub, fn conn ->
      send(test_pid, {:attempt, System.monotonic_time()})

      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{"error" => %{"message" => "Internal server error"}})
    end)

    Req.Test.expect(stub, fn conn ->
      send(test_pid, {:attempt, System.monotonic_time()})

      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{"error" => %{"message" => "Internal server error"}})
    end)

    Req.Test.expect(stub, fn conn ->
      send(test_pid, {:attempt, System.monotonic_time()})

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "Success after retries"}}],
        "usage" => %{"total_tokens" => 10}
      })
    end)

    capture_log(fn ->
      assert {:ok, result} =
               legacy_chat_completion(%{prompt: "test", messages: []}, profile: :openai)

      assert result.content == "Success after retries"

      # Verify we made 3 attempts
      assert_received {:attempt, _time1}
      assert_received {:attempt, _time2}
      assert_received {:attempt, _time3}
    end)
  end

  test "respects max_retries configuration", %{openai_stub: stub} do
    # Override retry config to allow only 2 total attempts (1 retry)
    original = Application.get_env(:synapse, Synapse.ReqLLM)

    Application.put_env(:synapse, Synapse.ReqLLM,
      default_profile: :openai,
      profiles: %{
        openai: [
          base_url: "https://llm.test",
          api_key: "test-key",
          model: "gpt-5-nano",
          retry: [max_attempts: 2, base_backoff_ms: 10],
          plug: {Req.Test, stub},
          plug_owner: self()
        ]
      }
    )

    test_pid = self()

    # Always return 500
    Req.Test.stub(stub, fn conn ->
      send(test_pid, :attempt)

      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{"error" => %{"message" => "Server error"}})
    end)

    capture_log(fn ->
      assert {:error, error} =
               legacy_chat_completion(%{prompt: "test", messages: []}, profile: :openai)

      assert error.message =~ "500"

      # Should see exactly 2 attempts (initial + 1 retry)
      assert_received :attempt
      assert_received :attempt
      refute_received :attempt
    end)

    # Restore original config
    if original do
      Application.put_env(:synapse, Synapse.ReqLLM, original)
    end
  end

  test "surfaces authentication failures from provider", %{openai_stub: stub} do
    Req.Test.expect(stub, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{
        "error" => %{"message" => "Incorrect API key provided"}
      })
    end)

    assert {:error, error} =
             legacy_chat_completion(%{prompt: "hi", messages: []}, profile: :openai)

    assert is_exception(error)
    assert error.message =~ "unauthorized"
    assert error.message =~ "Incorrect API key provided"
    assert error.details[:status] == 401
    assert error.details[:profile] == :openai
  end

  test "surfaces transport timeouts with guidance", %{openai_stub: stub} do
    Req.Test.expect(stub, &Req.Test.transport_error(&1, :timeout))

    assert {:error, error} =
             legacy_chat_completion(%{prompt: "hi", messages: []}, profile: :openai)

    assert is_exception(error)
    assert error.message =~ "timed out"
    assert error.details[:reason] == :timeout
    assert error.details[:profile] == :openai
  end

  test "maps max_tokens to max_completion_tokens for openai", %{openai_stub: stub} do
    Req.Test.expect(stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      json = Jason.decode!(body)

      assert json["max_completion_tokens"] == 256
      refute Map.has_key?(json, "max_tokens")

      Req.Test.json(conn, %{
        choices: [
          %{"message" => %{"content" => "ok"}}
        ]
      })
    end)

    {:ok, _} =
      legacy_chat_completion(
        %{prompt: "hi", messages: [], max_tokens: 256},
        profile: :openai
      )
  end

  describe "system prompt precedence" do
    test "profile-level system prompt overrides global", %{openai_stub: stub} do
      original = Application.get_env(:synapse, Synapse.ReqLLM)

      Application.put_env(:synapse, Synapse.ReqLLM,
        default_profile: :openai,
        system_prompt: "Global prompt",
        profiles: %{
          openai: [
            base_url: "https://llm.test",
            api_key: "test-key",
            system_prompt: "Profile prompt",
            plug: {Req.Test, stub},
            plug_owner: self()
          ]
        }
      )

      Req.Test.expect(stub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        # First message should be profile-level system prompt (not global)
        assert [%{"role" => "system", "content" => "Profile prompt"} | _] = payload["messages"]

        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "OK"}}]
        })
      end)

      {:ok, _} = legacy_chat_completion(%{prompt: "test"}, profile: :openai)

      if original, do: Application.put_env(:synapse, Synapse.ReqLLM, original)
    end

    test "request-level system messages preserved in OpenAI payload", %{openai_stub: stub} do
      Req.Test.expect(stub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        messages = payload["messages"]

        # Should have base system prompt first
        assert [%{"role" => "system", "content" => base_system} | rest] = messages
        assert base_system != ""

        # Should preserve request-level system message
        assert Enum.any?(rest, fn
                 %{"role" => "system", "content" => content} ->
                   content == "You are a Rust expert"

                 _ ->
                   false
               end)

        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => "OK"}}]
        })
      end)

      {:ok, _} =
        legacy_chat_completion(
          %{
            prompt: "Review code",
            messages: [
              %{role: "system", content: "You are a Rust expert"}
            ]
          },
          profile: :openai
        )
    end

    test "gemini merges system prompts into system_instruction", %{gemini_stub: stub} do
      Req.Test.expect(stub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        # Gemini should have system_instruction field
        assert %{"parts" => [%{"text" => system_text}]} = payload["system_instruction"]

        # Should contain request system message
        assert system_text =~ "You are a Python expert"

        Req.Test.json(conn, %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [%{"text" => "Response"}]
              }
            }
          ]
        })
      end)

      {:ok, _} =
        legacy_chat_completion(
          %{
            prompt: "Write code",
            messages: [
              %{role: "system", content: "You are a Python expert"}
            ]
          },
          profile: :gemini
        )
    end
  end

  defp legacy_chat_completion(params, opts \\ []) do
    ReqLLM.legacy_chat_completion(params, opts)
  end
end
