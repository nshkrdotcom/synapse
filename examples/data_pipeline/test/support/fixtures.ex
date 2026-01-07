defmodule DataPipeline.Fixtures do
  @moduledoc """
  Test fixtures for data pipeline.
  """

  @doc """
  Sample data for testing pipelines.
  """
  def sample_data do
    [
      %{text: "URGENT: Server is down, customers cannot access the system!"},
      %{text: "Scheduled maintenance will occur next Tuesday at 2 AM."},
      %{text: "Question: How do I reset my password?"},
      %{text: "Thank you for the quick response, issue is resolved."},
      %{text: "CRITICAL: Database backup failed, need immediate attention!"},
      %{text: "Feature request: Add dark mode to the dashboard."},
      %{text: "Complaint: The new interface is confusing and hard to navigate."},
      %{text: "Just wanted to say I love the new features!"},
      %{text: "ERROR: Payment processing is failing for all transactions."},
      %{text: "Reminder: Team meeting tomorrow at 10 AM."}
    ]
  end

  @doc """
  High priority sample data.
  """
  def high_priority_data do
    [
      %{text: "URGENT: Critical bug in production"},
      %{text: "EMERGENCY: System outage affecting all users"},
      %{text: "CRITICAL: Security vulnerability detected"}
    ]
  end

  @doc """
  Low priority sample data.
  """
  def low_priority_data do
    [
      %{text: "Feature request: Add new color theme"},
      %{text: "Question: Where can I find the documentation?"},
      %{text: "Thank you for your help!"}
    ]
  end

  @doc """
  Creates a sample asset for testing.
  """
  def sample_asset(name \\ :test_asset, opts \\ []) do
    DataPipeline.Asset.new(
      name,
      Keyword.merge(
        [
          description: "Test asset",
          materializer: fn _deps -> {:ok, sample_data()} end
        ],
        opts
      )
    )
  end

  @doc """
  Creates sample records for testing.
  """
  def sample_records(count \\ 5) do
    sample_data()
    |> Enum.take(count)
    |> DataPipeline.Record.new_batch(source: :test)
  end
end
