defmodule EmisintWeb.Reports.SchoolReportBuilderLive do
  use EmisintWeb, :live_view

  alias Emisint.Reports.School.{ReportSectionRegistry, ReportTemplateRegistry}

  @impl true
  def mount(%{"building_code" => building_code} = params, _session, socket) do
    default_key = ReportTemplateRegistry.default_key()
    selected_sections = MapSet.new(ReportSectionRegistry.default_keys())

    {:ok,
     socket
     |> assign(:page_title, "Create Custom School Report")
     |> assign(:building_code, building_code)
     |> assign(:year, Map.get(params, "year", ""))
     |> assign(:templates, ReportTemplateRegistry.list())
     |> assign(:default_key, default_key)
     |> assign(:selected_key, default_key)
     |> assign(:sections, ReportSectionRegistry.list())
     |> assign(:selected_sections, selected_sections)}
  end

  @impl true
  def handle_event("select_template", %{"template" => key}, socket) do
    case ReportTemplateRegistry.fetch(key) do
      {:ok, template} -> {:noreply, assign(socket, :selected_key, template.key)}
      {:error, :unknown_template} -> {:noreply, put_flash(socket, :error, "Unknown template")}
    end
  end

  def handle_event("toggle_section", %{"section" => key}, socket) do
    with {:ok, [section_key]} <- ReportSectionRegistry.normalize([key]) do
      selected =
        if MapSet.member?(socket.assigns.selected_sections, section_key) do
          MapSet.delete(socket.assigns.selected_sections, section_key)
        else
          MapSet.put(socket.assigns.selected_sections, section_key)
        end

      {:noreply, assign(socket, :selected_sections, selected)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Unknown report section")}
    end
  end

  defp report_url(assigns) do
    selected =
      ReportSectionRegistry.default_keys()
      |> Enum.filter(&MapSet.member?(assigns.selected_sections, &1))
      |> Enum.map_join(",", &Atom.to_string/1)

    query =
      URI.encode_query(%{
        building: assigns.building_code,
        year: assigns.year,
        template: assigns.selected_key,
        sections: selected
      })

    "/mde/reports/school.pdf?" <> query
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <main id="school-report-builder" class="mx-auto max-w-6xl space-y-8 px-4 py-8 sm:px-6">
        <header class="space-y-3">
          <.link
            navigate={~p"/mde"}
            class="inline-flex items-center gap-2 text-sm text-base-content/60 transition hover:text-primary"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Back to district analysis
          </.link>
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
              School report studio
            </p>
            <h1 class="mt-2 text-3xl font-bold tracking-tight">Build a school report</h1>
            <p class="mt-2 max-w-3xl text-base-content/65">
              Choose a format and the real-data sections to include for building {@building_code}.
              Choices apply only to this generated report.
            </p>
          </div>
        </header>

        <section id="report-template-options" class="grid gap-5 lg:grid-cols-2">
          <button
            :for={template <- @templates}
            id={"report-template-#{template.key}"}
            type="button"
            phx-click="select_template"
            phx-value-template={template.key}
            class={[
              "group relative overflow-hidden rounded-2xl border p-6 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg",
              @selected_key == template.key && "border-primary bg-primary/5 ring-2 ring-primary/20",
              @selected_key != template.key && "border-base-300 bg-base-100 hover:border-primary/40"
            ]}
          >
            <div class="flex items-start justify-between gap-4">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <h2 class="text-xl font-semibold">{template.name}</h2>
                  <span
                    :if={@default_key == template.key}
                    class="rounded-full bg-secondary/15 px-2.5 py-1 text-xs font-semibold text-secondary"
                  >
                    Default
                  </span>
                </div>
                <p class="mt-2 text-sm text-base-content/65">{template.description}</p>
              </div>
              <span class={[
                "grid size-6 shrink-0 place-items-center rounded-full border transition",
                @selected_key == template.key && "border-primary bg-primary text-primary-content",
                @selected_key != template.key && "border-base-300"
              ]}>
                <.icon :if={@selected_key == template.key} name="hero-check" class="size-4" />
              </span>
            </div>
            <div class="mt-8 rounded-xl bg-base-200/70 p-4">
              <div class={[
                "mx-auto border border-base-300 bg-base-100 shadow-sm",
                template.key == :compact_portrait && "h-44 w-32",
                template.key == :detailed_landscape && "h-32 w-52"
              ]}>
                <div class="h-3 bg-primary"></div>
                <div class="space-y-2 p-3">
                  <div class="h-2 w-3/4 rounded bg-base-300"></div>
                  <div class="grid grid-cols-3 gap-1">
                    <div :for={_ <- 1..3} class="h-8 rounded bg-primary/10"></div>
                  </div>
                  <div class="h-12 rounded bg-base-200"></div>
                  <div class="h-7 rounded bg-secondary/10"></div>
                </div>
              </div>
              <p class="mt-3 text-center text-xs font-medium text-base-content/55">
                {template.page_description}
              </p>
            </div>
          </button>
        </section>

        <section
          id="report-section-options"
          class="rounded-2xl border border-base-300 bg-base-100 p-6"
        >
          <div>
            <h2 class="text-xl font-semibold">Choose report sections</h2>
            <p class="mt-1 text-sm text-base-content/60">
              School identity and authorizer remain in the report header.
            </p>
          </div>
          <div class="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            <label
              :for={section <- @sections}
              id={"report-section-#{section.key}"}
              class={[
                "flex cursor-pointer gap-3 rounded-xl border p-4 transition",
                MapSet.member?(@selected_sections, section.key) &&
                  "border-primary bg-primary/5",
                !MapSet.member?(@selected_sections, section.key) &&
                  "border-base-300 hover:border-primary/40"
              ]}
            >
              <input
                type="checkbox"
                class="checkbox checkbox-primary mt-0.5"
                checked={MapSet.member?(@selected_sections, section.key)}
                phx-click="toggle_section"
                phx-value-section={section.key}
              />
              <span>
                <span class="flex flex-wrap items-center gap-2 font-semibold">
                  {section.name}
                  <span
                    :if={section.availability in [:partial, :unavailable]}
                    class={[
                      "rounded-full px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wide",
                      section.availability == :partial && "bg-warning/15 text-warning",
                      section.availability == :unavailable && "bg-base-200 text-base-content/50"
                    ]}
                  >
                    {if section.availability == :partial, do: "Partial data", else: "Data unavailable"}
                  </span>
                </span>
                <span class="mt-1 block text-sm text-base-content/60">{section.description}</span>
              </span>
            </label>
          </div>
        </section>

        <footer class="flex border-t border-base-300 pt-6 sm:justify-end">
          <.link
            id="generate-custom-report"
            href={report_url(assigns)}
            target="_blank"
            class="inline-flex items-center justify-center gap-2 rounded-lg bg-primary px-5 py-3 font-semibold text-primary-content shadow-sm transition hover:bg-primary/90"
          >
            <.icon name="hero-document-arrow-down" class="size-5" /> Generate report
          </.link>
        </footer>
      </main>
    </Layouts.app>
    """
  end
end
