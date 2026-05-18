defmodule SynapseWeb.Layouts do
  @moduledoc """
  Application layouts for the NSHKR Agent product shell.
  """
  use SynapseWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-slate-200 bg-white">
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-3 sm:px-6 lg:px-8">
        <.link navigate={~p"/"} class="flex items-center gap-3">
          <span class="flex size-9 items-center justify-center rounded border border-slate-300 bg-slate-950 text-white">
            <.icon name="hero-command-line" class="size-5" />
          </span>
          <span>
            <span class="block text-sm font-semibold text-slate-950">NSHKR Agent</span>
            <span class="block text-xs text-slate-500">AppKit product shell</span>
          </span>
        </.link>

        <nav class="flex items-center gap-1 text-sm" aria-label="Primary">
          <.link
            navigate={~p"/"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Dashboard
          </.link>
          <.link
            navigate={~p"/runs"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Runs
          </.link>
          <.link
            navigate={~p"/reviews"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Reviews
          </.link>
          <.link
            navigate={~p"/memory"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Memory
          </.link>
          <.link
            navigate={~p"/tools"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Tools
          </.link>
          <.link
            navigate={~p"/catalog"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Catalog
          </.link>
          <.link
            navigate={~p"/teams"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Teams
          </.link>
          <.link
            navigate={~p"/evidence"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Evidence
          </.link>
          <.link
            navigate={~p"/operations"}
            class="rounded px-3 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            Ops
          </.link>
        </nav>
      </div>
    </header>

    <main class="min-h-screen bg-slate-50">
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connection lost")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Server unavailable")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
