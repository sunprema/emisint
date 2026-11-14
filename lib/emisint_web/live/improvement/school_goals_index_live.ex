defmodule EmisintWeb.Improvement.SchoolGoalsIndexLive do
  @moduledoc """
  ND First landing page: the portfolio summary (`Emisint.Improvement.Portfolio`,
  the workbook's "Goals Dashboard" and "Performance-Based Payment" sheets),
  then the pilot schools (`Emisint.Improvement.Pilot`) with goal plans that
  the signed-in user can read in their organization. Users without a school
  membership see an empty state.
  """
  use EmisintWeb, :live_view

  import EmisintWeb.Improvement.Components, only: [school_tabs: 1]
  import EmisintWeb.Improvement.PortfolioComponents, only: [portfolio: 1]

  alias Emisint.Improvement.{Dashboard, PaymentPreview, Pilot, Portfolio}

  @impl true
  def mount(_params, _session, socket) do
    schools =
      Dashboard.list_schools(socket.assigns.scope, institution_ids: Pilot.institution_ids())

    readable = MapSet.new(schools, & &1.slug)
    tabs = Pilot.tabs(readable)

    {:ok,
     assign(socket,
       page_title: "ND First",
       tabs: tabs,
       schools: schools,
       groups: groups(tabs, schools, readable),
       summary: Portfolio.summary(socket.assigns.scope)
     )}
  end

  # Query params, kept together so no change loses another:
  #   * `open` — the expanded detail sections (comma-separated: "progress",
  #     "payment"); all closed by default. Every filter change keeps it.
  #   * `pay` "preview" (default) or "formal"; `pay_period` the seasonal
  #     period code (default: the latest with any recorded rating);
  #     `pay_ref` "18m" (default) or "36m". The preview is computed from the
  #     already loaded summary and writes nothing.
  @sections ~w(progress payment)
  @query_keys ~w(open pay pay_period pay_ref)

  @impl true
  def handle_params(params, _uri, socket) do
    summary = socket.assigns.summary
    view = if params["pay"] == "formal", do: :formal, else: :preview
    period = params["pay_period"] || PaymentPreview.default_period(summary)
    checkpoint = PaymentPreview.checkpoint(params["pay_ref"])
    query = Map.take(params, @query_keys)

    {:noreply,
     assign(socket,
       query: query,
       open: open_sections(params["open"]),
       payment: %{
         view: view,
         preview: PaymentPreview.build(summary, period, checkpoint),
         path: fn changes -> path(Map.merge(query, changes)) end
       }
     )}
  end

  @impl true
  def handle_event("preview", params, socket) do
    period = params["pay_period"] || preview_period(socket)

    {:noreply,
     patch(socket, %{"pay" => "preview", "pay_ref" => params["pay_ref"], "pay_period" => period})}
  end

  def handle_event("toggle_section", %{"section" => section}, socket) when section in @sections do
    open = socket.assigns.open

    open =
      if MapSet.member?(open, section),
        do: MapSet.delete(open, section),
        else: MapSet.put(open, section)

    {:noreply, patch(socket, %{"open" => open_param(open)}, replace: true)}
  end

  def handle_event("sections", %{"to" => "expand"}, socket),
    do: {:noreply, patch(socket, %{"open" => open_param(MapSet.new(@sections))}, replace: true)}

  def handle_event("sections", %{"to" => "collapse"}, socket),
    do: {:noreply, patch(socket, %{"open" => nil}, replace: true)}

  defp preview_period(socket) do
    case socket.assigns.payment.preview.period do
      nil -> nil
      p -> p.code
    end
  end

  defp patch(socket, changes, opts \\ []),
    do: push_patch(socket, [to: path(Map.merge(socket.assigns.query, changes))] ++ opts)

  defp open_sections(nil), do: MapSet.new()

  defp open_sections(param),
    do: param |> String.split(",") |> Enum.filter(&(&1 in @sections)) |> MapSet.new()

  # In section order, so the URL is stable.
  defp open_param(open) do
    case Enum.filter(@sections, &MapSet.member?(open, &1)) do
      [] -> nil
      list -> Enum.join(list, ",")
    end
  end

  defp path(query) do
    query = query |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    ~p"/school-goals?#{query}"
  end

  # One card per participant, in tab order, linking to its main record.
  # Buildings are not listed here (November 13, 2026): they appear only as
  # subtabs inside the participant's pages. A member who can read only a
  # building gets a card linking to that building (the tab's own `href`).
  defp groups(tabs, schools, readable) do
    by_slug = Map.new(schools, &{&1.slug, &1})

    for %{enabled?: true} = tab <- tabs do
      nav =
        Pilot.participant_nav(%{slug: tab.slug, state_entity_id: tab.institution_id}, readable)

      %{
        name: tab.name,
        slug: tab.slug,
        href: tab.href,
        main: by_slug[tab.slug],
        provisional?: nav != nil and nav.provisional?
      }
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-4 md:p-6 max-w-6xl mx-auto space-y-6">
        <.school_tabs tabs={@tabs} />
        <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold">ND First</h1>
            <div class="text-sm text-base-content/70 mt-2 space-y-2 max-w-2xl" id="nd-first-intro">
              <p>
                ND First schools are listed on the North Dakota Department of Public Instruction's <a
                  href="https://www.nd.gov/dpi/districtsschools/essa/accountability-support-improvement/nd-first"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary"
                >
                  accountability, support and improvement pages
                </a>.
              </p>
              <p>
                For each school, this page tracks its MOU goals and their seasonal 0–3 implementation
                ratings, its 18- and 36-month targets, its annual Proficient-or-Advanced targets from
                its continuous improvement plan, and the state's published results from ND Insights.
              </p>
            </div>
          </div>
        </div>

        <div
          :if={@schools == []}
          class="bg-base-100 border border-base-200 rounded-xl text-center py-12 text-base-content/50"
          id="no-schools"
        >
          No schools are available to you. Ask your organization admin for access.
        </div>

        <.portfolio
          :if={@summary.rows != []}
          summary={@summary}
          payment={@payment}
          open={@open}
        />

        <h2 :if={@groups != []} class="text-lg font-semibold" id="participants-heading">
          Participants and schools
        </h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div
            :for={g <- @groups}
            class="bg-base-100 border border-base-200 rounded-xl p-4 space-y-2"
            id={"participant-#{g.slug}"}
          >
            <.link
              :if={g.main}
              navigate={~p"/school-goals/#{g.main.slug}"}
              class="block hover:text-primary transition-colors"
              id={"school-#{g.main.slug}"}
            >
              <div class="font-semibold">{g.main.name}</div>
              <div class="text-sm text-base-content/60">{g.main.district_name}</div>
              <div class="text-xs text-base-content/50 mt-1 font-mono">
                {g.main.state} {g.main.state_entity_id}<span :if={g.main.grade_span}> · Grades {g.main.grade_span}</span>
              </div>
            </.link>
            <.link
              :if={!g.main}
              navigate={~p"/school-goals/#{g.href}"}
              class="block hover:text-primary transition-colors"
              id={"participant-link-#{g.slug}"}
            >
              <div class="font-semibold">{g.name}</div>
              <div class="text-sm text-base-content/60">Open the pages you can view</div>
            </.link>
            <span
              :if={g.provisional?}
              class="badge badge-warning badge-soft badge-sm"
              id={"participant-#{g.slug}-provisional"}
            >
              Workbook scope provisional
            </span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
