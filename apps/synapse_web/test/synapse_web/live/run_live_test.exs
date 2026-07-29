defmodule SynapseWeb.RunLiveTest do
  use SynapseWeb.ConnCase, async: true

  test "lists durable AppKit run projections", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/runs")

    assert has_element?(view, "#run-index-list")
    assert has_element?(view, "#run-index-stream", "Durable run test-run")
    assert has_element?(view, "#run-index-stream", "running")
    refute has_element?(view, "#run-index-unavailable")
  end

  test "renders an accepted durable run", %{conn: conn} do
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

    assert has_element?(view, "#run-start-accepted")
    assert has_element?(view, "#run-start-run-ref", "run://durable/")
    assert has_element?(view, "#run-start-workflow-ref", "workflow://durable/")
    assert has_element?(view, "#run-start-command-ref", "command://durable/start/")
  end

  test "renders a typed idempotency conflict", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/runs/new")

    view
    |> form("#run-start-form",
      run: %{
        title: "Conflict",
        goal_summary: "Reuse a conflicting key",
        team_template_ref: "standard_implementation"
      }
    )
    |> render_submit()

    assert has_element?(view, "#run-start-conflict", "request identity conflicts")
    refute has_element?(view, "#run-start-accepted")
  end

  test "renders durable-owner unavailability without fixture success", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/runs/new")

    view
    |> form("#run-start-form",
      run: %{
        title: "Unavailable",
        goal_summary: "Owner outage",
        team_template_ref: "standard_implementation"
      }
    )
    |> render_submit()

    assert has_element?(view, "#run-start-unavailable", "durable owner is unavailable")
    refute has_element?(view, "#run-start-accepted")
  end

  test "shows durable snapshot and cursor state, then resumes refresh", %{conn: conn} do
    path = "/runs/" <> URI.encode_www_form("run://durable/test-run")
    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, "#run-durable-snapshot")
    assert has_element?(view, "#run-show-state", "accepted")
    assert has_element?(view, "#run-show-persistence", "durable")
    assert has_element?(view, "#run-turn-count", "1 durable turn")
    assert has_element?(view, "#run-control-state", "running")
    assert has_element?(view, "#run-control-version", "3")
    assert has_element?(view, "#run-pause-button:not([disabled])")
    assert has_element?(view, "#run-cancel-button:not([disabled])")
    assert has_element?(view, "#run-supersede-button[disabled]")
    assert has_element?(view, "#run-cursor-ledger", "run://durable/test-run")
    assert has_element?(view, "#run-cursor-sequence", "1")
    assert has_element?(view, "#run-event-1", "Run and initial turn accepted durably")

    view |> element("#run-refresh-button") |> render_click()
    assert has_element?(view, "#run-cursor-ref", "cursor://test/test-run/1")
    assert has_element?(view, "#run-cursor-sequence", "1")

    view |> element("#run-pause-button") |> render_click()
    assert has_element?(view, "#run-control-accepted", "Accepted by durable test backend")
  end

  test "shows ambiguous and degraded recovery without replay", %{conn: conn} do
    {:ok, ambiguous, _html} = live(conn, ~p"/runs/ambiguous")
    assert has_element?(ambiguous, "#run-control-ambiguous", "No effect will be replayed")
    assert has_element?(ambiguous, "#run-control-degraded", "provider_outcome_unknown")
    refute has_element?(ambiguous, "#run-control-actions button")

    {:ok, operator_required, _html} = live(recycle(conn), ~p"/runs/operator-required")

    assert has_element?(
             operator_required,
             "#run-control-degraded",
             "external_operation_not_found"
           )

    assert has_element?(operator_required, "#run-retry-button[disabled]")
    assert has_element?(operator_required, "#run-cancel-button:not([disabled])")
  end

  test "shows explicit unavailable and conflict readback states", %{conn: conn} do
    {:ok, unavailable, _html} = live(conn, ~p"/runs/unavailable")
    assert has_element?(unavailable, "#run-show-unavailable", "durable owner is unavailable")

    {:ok, conflict, _html} = live(recycle(conn), ~p"/runs/conflict")
    assert has_element?(conflict, "#run-show-conflict", "run cursor conflicts")
  end
end
