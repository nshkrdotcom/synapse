defmodule TestWriter.GeneratedTest do
  @moduledoc """
  Represents a generated test with metadata about compilation and validation status.
  """

  @enforce_keys [:id, :target_id, :code]
  defstruct [
    :id,
    :target_id,
    :code,
    :status,
    :compile_errors,
    :test_results,
    :coverage,
    :metadata,
    :generated_at,
    :validated_at
  ]

  @type status :: :generated | :compiled | :validated | :failed

  @type compile_error :: %{
          file: String.t(),
          line: non_neg_integer() | nil,
          message: String.t()
        }

  @type test_result :: %{
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          skipped: non_neg_integer(),
          failures: [String.t()]
        }

  @type coverage_info :: %{
          functions_tested: non_neg_integer(),
          functions_total: non_neg_integer(),
          percentage: float()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          target_id: String.t(),
          code: String.t(),
          status: status() | nil,
          compile_errors: [compile_error()] | nil,
          test_results: test_result() | nil,
          coverage: coverage_info() | nil,
          metadata: map() | nil,
          generated_at: DateTime.t() | nil,
          validated_at: DateTime.t() | nil
        }

  @doc """
  Create a new generated test.
  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(target_id, code, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      target_id: target_id,
      code: code,
      status: opts[:status] || :generated,
      compile_errors: opts[:compile_errors],
      test_results: opts[:test_results],
      coverage: opts[:coverage],
      metadata: opts[:metadata] || %{},
      generated_at: DateTime.utc_now(),
      validated_at: opts[:validated_at]
    }
  end

  @doc """
  Generate a unique test ID.
  """
  @spec generate_id() :: String.t()
  def generate_id do
    "test_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  @doc """
  Mark test as compiled successfully.
  """
  @spec mark_compiled(t()) :: t()
  def mark_compiled(%__MODULE__{} = test) do
    %{test | status: :compiled, compile_errors: nil}
  end

  @doc """
  Mark test as failed to compile.
  """
  @spec mark_compile_failed(t(), [compile_error()]) :: t()
  def mark_compile_failed(%__MODULE__{} = test, errors) do
    %{test | status: :failed, compile_errors: errors}
  end

  @doc """
  Mark test as validated with results.
  """
  @spec mark_validated(t(), test_result(), coverage_info() | nil) :: t()
  def mark_validated(%__MODULE__{} = test, results, coverage \\ nil) do
    %{
      test
      | status: :validated,
        test_results: results,
        coverage: coverage,
        validated_at: DateTime.utc_now()
    }
  end

  @doc """
  Check if test compiled successfully.
  """
  @spec compiled?(t()) :: boolean()
  def compiled?(%__MODULE__{status: status}) when status in [:compiled, :validated], do: true
  def compiled?(_), do: false

  @doc """
  Check if test passed validation.
  """
  @spec validated?(t()) :: boolean()
  def validated?(%__MODULE__{status: :validated}), do: true
  def validated?(_), do: false

  @doc """
  Convert generated test to a map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = test) do
    %{
      id: test.id,
      target_id: test.target_id,
      code: test.code,
      status: test.status,
      compile_errors: test.compile_errors,
      test_results: test.test_results,
      coverage: test.coverage,
      metadata: test.metadata,
      generated_at: test.generated_at && DateTime.to_iso8601(test.generated_at),
      validated_at: test.validated_at && DateTime.to_iso8601(test.validated_at)
    }
  end
end
