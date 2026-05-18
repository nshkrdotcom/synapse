defmodule SynapseWeb.RunLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "lists fixture-backed runs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/runs")

    assert has_element?(view, "#run-index-list")
    assert has_element?(view, "#run-index-stream", "Fixture governed agent run")
  end

  test "starts a fixture-backed run", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/runs/new")

    view
    |> form("#run-start-form",
      run: %{
        title: "Boundary check",
        goal_summary: "Use AppKit only",
        team_template_ref: "standard_implementation"
      }
    )
    |> render_submit()

    assert has_element?(view, "#run-start-result", "run://fixture/")
    assert has_element?(view, "#run-start-result", "AppKit.AgentIntake")
  end

  test "shows run detail and accepts fixture-backed controls", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/runs/fixture-phase-3")

    assert has_element?(view, "#run-turn-form")
    assert has_element?(view, "#run-refresh-button")
    assert has_element?(view, "#run-cancel-button")
    assert has_element?(view, "#run-context-pack")
    assert has_element?(view, "#run-memory-projection")
    assert has_element?(view, "#run-tool-grants")

    view
    |> form("#run-turn-form", turn: %{kind: "user_input", input_summary: "Continue"})
    |> render_submit()

    assert has_element?(view, "#run-command-result", "submit_turn")

    view |> element("#run-refresh-button") |> render_click()
    assert has_element?(view, "#run-command-result", "refresh")

    view |> element("#run-cancel-button") |> render_click()
    assert has_element?(view, "#run-command-result", "cancel")
  end
end
