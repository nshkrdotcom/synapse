defmodule AxonPython do
  @moduledoc """
  Documentation for `AxonPython`.
  """

  @doc """
  Returns the path to the Python source directory.
  """
  def python_src_path do
    Application.app_dir(:axon_python, "priv/python")
  end
end
