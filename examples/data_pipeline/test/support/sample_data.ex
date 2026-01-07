defmodule DataPipeline.SampleData do
  @moduledoc """
  Sample data generators for testing and examples.
  """

  @doc """
  Generates customer feedback data.
  """
  def customer_feedback(count \\ 10) do
    templates = [
      "Great product, very satisfied with the purchase!",
      "Terrible experience, would not recommend.",
      "Average quality, nothing special.",
      "URGENT: Product arrived damaged, need replacement ASAP!",
      "Quick question: How do I return an item?",
      "Thank you for the excellent customer service!",
      "Complaint: Shipping took way too long.",
      "Love the new features in the latest update!",
      "The app keeps crashing, please fix this bug.",
      "Just wanted to share my positive experience."
    ]

    Stream.cycle(templates)
    |> Enum.take(count)
    |> Enum.map(fn text -> %{text: text} end)
  end

  @doc """
  Generates event log data.
  """
  def event_logs(count \\ 10) do
    events = [
      "User logged in successfully",
      "Failed login attempt",
      "File uploaded",
      "Error: Database connection timeout",
      "Payment processed successfully",
      "Warning: High memory usage detected",
      "User updated profile information",
      "Critical: Security breach detected",
      "Scheduled backup completed",
      "System health check passed"
    ]

    Stream.cycle(events)
    |> Enum.take(count)
    |> Enum.with_index()
    |> Enum.map(fn {text, index} ->
      %{
        text: text,
        timestamp: DateTime.add(DateTime.utc_now(), -index * 60, :second),
        event_id: "evt_#{index}"
      }
    end)
  end

  @doc """
  Generates social media posts.
  """
  def social_posts(count \\ 10) do
    posts = [
      "Just launched our new product! Check it out!",
      "Not happy with the recent changes.",
      "Does anyone know how to fix this issue?",
      "Thanks to everyone for the support!",
      "BREAKING: Major announcement coming soon!",
      "Having a great day, hope you are too!",
      "Frustrated with the poor customer service.",
      "Quick poll: What feature would you like to see next?",
      "Celebrating our 1000th customer today!",
      "Disappointed with the quality of the service."
    ]

    Stream.cycle(posts)
    |> Enum.take(count)
    |> Enum.map(fn text ->
      %{
        text: text,
        platform: Enum.random(["twitter", "facebook", "linkedin"]),
        engagement: :rand.uniform(1000)
      }
    end)
  end
end
