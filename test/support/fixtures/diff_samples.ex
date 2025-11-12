defmodule Synapse.TestSupport.Fixtures.DiffSamples do
  @moduledoc """
  Sample diff fixtures for testing security and performance actions.
  Provides realistic code diff snippets for various scenarios.
  """

  @doc """
  Returns a diff containing SQL injection vulnerability.
  """
  def sql_injection_diff do
    """
    diff --git a/lib/user_repository.ex b/lib/user_repository.ex
    index abc123..def456 100644
    --- a/lib/user_repository.ex
    +++ b/lib/user_repository.ex
    @@ -10,7 +10,7 @@ defmodule UserRepository do
       def find_by_email(email) do
    -    query = "SELECT * FROM users WHERE email = ?"
    -    Repo.query(query, [email])
    +    query = "SELECT * FROM users WHERE email = '\#{email}'"
    +    Repo.query(query)
       end
     end
    """
  end

  @doc """
  Returns a diff containing XSS vulnerability.
  """
  def xss_diff do
    """
    diff --git a/lib/web/templates/user/show.html.heex b/lib/web/templates/user/show.html.heex
    index abc123..def456 100644
    --- a/lib/web/templates/user/show.html.heex
    +++ b/lib/web/templates/user/show.html.heex
    @@ -5,7 +5,7 @@
     <div class="user-profile">
    -  <h1><%= @user.name %></h1>
    -  <p><%= @user.bio %></p>
    +  <h1><%= raw(@user.name) %></h1>
    +  <p><%= raw(@user.bio) %></p>
     </div>
    """
  end

  @doc """
  Returns a diff with removed authentication guard.
  """
  def auth_issue_diff do
    """
    diff --git a/lib/web/controllers/admin_controller.ex b/lib/web/controllers/admin_controller.ex
    index abc123..def456 100644
    --- a/lib/web/controllers/admin_controller.ex
    +++ b/lib/web/controllers/admin_controller.ex
    @@ -3,8 +3,6 @@ defmodule Web.AdminController do
       alias MyApp.Users

    -  plug :require_admin
    -
       def delete_user(conn, %{"id" => id}) do
         Users.delete(id)
         json(conn, %{status: "deleted"})
    """
  end

  @doc """
  Returns a diff with high cyclomatic complexity.
  """
  def high_complexity_diff do
    """
    diff --git a/lib/processor.ex b/lib/processor.ex
    index abc123..def456 100644
    --- a/lib/processor.ex
    +++ b/lib/processor.ex
    @@ -5,10 +5,25 @@ defmodule Processor do
       def process(data) do
    -    simple_transform(data)
    +    cond do
    +      data.type == :a and data.flag -> handle_a_flagged(data)
    +      data.type == :a -> handle_a(data)
    +      data.type == :b and data.count > 10 -> handle_b_many(data)
    +      data.type == :b and data.count > 5 -> handle_b_some(data)
    +      data.type == :b -> handle_b_few(data)
    +      data.type == :c and data.nested.value -> handle_c_nested(data)
    +      data.type == :c -> handle_c(data)
    +      data.type == :d and data.critical -> handle_d_critical(data)
    +      data.type == :d -> handle_d(data)
    +      data.valid? and data.processed? -> handle_valid_processed(data)
    +      data.valid? -> handle_valid(data)
    +      true -> handle_default(data)
    +    end
       end
     end
    """
  end

  @doc """
  Returns a diff with greedy memory usage patterns.
  """
  def memory_issue_diff do
    """
    diff --git a/lib/data_loader.ex b/lib/data_loader.ex
    index abc123..def456 100644
    --- a/lib/data_loader.ex
    +++ b/lib/data_loader.ex
    @@ -8,8 +8,8 @@ defmodule DataLoader do
       def load_all_records do
    -    MyRepo.stream(Record)
    -    |> Stream.map(&transform/1)
    +    MyRepo.all(Record)
    +    |> Enum.to_list()
    +    |> Enum.map(&transform/1)
       end
     end
    """
  end

  @doc """
  Returns a clean diff with no issues.
  """
  def clean_diff do
    """
    diff --git a/lib/calculator.ex b/lib/calculator.ex
    index abc123..def456 100644
    --- a/lib/calculator.ex
    +++ b/lib/calculator.ex
    @@ -5,6 +5,10 @@ defmodule Calculator do
       def add(a, b), do: a + b
       def subtract(a, b), do: a - b
    +
    +  def multiply(a, b), do: a * b
    +
    +  def divide(_a, 0), do: {:error, :division_by_zero}
    +  def divide(a, b), do: {:ok, a / b}
     end
    """
  end

  @doc """
  Returns a small diff (fast path candidate).
  """
  def small_diff do
    """
    diff --git a/lib/utils.ex b/lib/utils.ex
    index abc123..def456 100644
    --- a/lib/utils.ex
    +++ b/lib/utils.ex
    @@ -1,3 +1,5 @@
     defmodule Utils do
       def format(str), do: String.trim(str)
    +
    +  def downcase(str), do: String.downcase(str)
     end
    """
  end

  @doc """
  Returns metadata for a typical review request.
  """
  def review_metadata(overrides \\ %{}) do
    Map.merge(
      %{
        author: "test_user",
        branch: "feature/test-branch",
        repo: "test/repo",
        timestamp: DateTime.utc_now()
      },
      overrides
    )
  end
end
