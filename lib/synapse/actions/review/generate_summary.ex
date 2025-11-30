defmodule Synapse.Actions.Review.GenerateSummary do
  @moduledoc """
  Deprecated: Use `Synapse.Domains.CodeReview.Actions.GenerateSummary` instead.

  This module is maintained for backward compatibility and will be removed
  in a future release.
  """

  @behaviour Jido.Action

  @deprecated "Use Synapse.Domains.CodeReview.Actions.GenerateSummary instead"
  alias Synapse.Domains.CodeReview.Actions.GenerateSummary, as: Impl

  defdelegate name(), to: Impl
  defdelegate description(), to: Impl
  defdelegate category(), to: Impl
  defdelegate tags(), to: Impl
  defdelegate vsn(), to: Impl
  defdelegate schema(), to: Impl
  defdelegate output_schema(), to: Impl
  defdelegate validate_params(params), to: Impl
  defdelegate validate_output(output), to: Impl
  defdelegate to_json(), to: Impl
  defdelegate to_tool(), to: Impl
  defdelegate __action_metadata__(), to: Impl

  defdelegate on_before_validate_params(params), to: Impl
  defdelegate on_after_validate_params(params), to: Impl
  defdelegate on_before_validate_output(output), to: Impl
  defdelegate on_after_validate_output(output), to: Impl
  defdelegate on_after_run(result), to: Impl
  defdelegate on_error(params, error, context, opts), to: Impl

  defdelegate run(params, context), to: Impl
end
