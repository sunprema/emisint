defmodule EmisintWeb.Mde.DistrictAnalysisLive do
  use EmisintWeb, :live_view

  require Ash.Query

  alias Emisint.Assessments.{MdeDistrict, MdeStateAssessmentResult}

  @subjects ["ELA", "Mathematics", "Science", "Social Studies"]

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    years = load_school_years()
    selected_year = List.last(years) || ""
    all_districts = load_all_districts()

    {:ok,
     socket
     |> assign(:page_title, "District Analysis")
     |> assign(:school_years, years)
     |> assign(:selected_year, selected_year)
     |> assign(:all_districts, all_districts)
     |> assign(:district_code, nil)
     |> assign(:compare_code, "")
     |> assign(:primary, nil)
     |> assign(:compare, nil)}
  end

  def handle_params(%{"district_code" => dc} = params, _uri, socket) do
    compare_code = Map.get(params, "compare", "")
    year = socket.assigns.selected_year

    primary = if year != "", do: load_district_data(dc, year), else: nil

    compare =
      if compare_code != "" && year != "",
        do: load_district_data(compare_code, year),
        else: nil

    {:noreply,
     socket
     |> assign(:district_code, dc)
     |> assign(:compare_code, compare_code)
     |> assign(:primary, primary)
     |> assign(:compare, compare)
     |> assign(:page_title, page_title(primary, compare))}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  def handle_event("select_year", %{"year" => year}, socket) do
    primary =
      if socket.assigns.district_code,
        do: load_district_data(socket.assigns.district_code, year),
        else: nil

    compare =
      if socket.assigns.compare_code != "",
        do: load_district_data(socket.assigns.compare_code, year),
        else: nil

    {:noreply,
     socket
     |> assign(:selected_year, year)
     |> assign(:primary, primary)
     |> assign(:compare, compare)}
  end

  def handle_event("select_compare", %{"compare" => ""}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/mde/districts/#{socket.assigns.district_code}")}
  end

  def handle_event("select_compare", %{"compare" => code}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/mde/districts/#{socket.assigns.district_code}?compare=#{code}"
     )}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns = assign(assigns, :subjects, @subjects)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto space-y-8">

        <%!-- Top bar: back link + year selector --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/mde"}
              class="flex items-center gap-1.5 text-sm text-base-content/50 hover:text-base-content transition-colors"
            >
              <.icon name="hero-arrow-left" class="size-4" /> MDE Overview
            </.link>
            <div class="h-4 w-px bg-base-300"></div>
            <div class="flex items-center gap-2">
              <div class="p-1.5 bg-info/10 border border-info/20">
                <.icon name="hero-chart-bar" class="size-4 text-info" />
              </div>
              <h1 class="text-lg font-bold tracking-tight">District Analysis</h1>
            </div>
          </div>

          <div :if={@school_years != []} class="flex items-center gap-2 shrink-0">
            <label class="text-sm font-medium text-base-content/60">School Year</label>
            <form>
              <select
                name="year"
                phx-change="select_year"
                class="border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-info/25 focus:border-info transition-all"
              >
                <option
                  :for={year <- @school_years}
                  value={year}
                  selected={year == @selected_year}
                >
                  {year}
                </option>
              </select>
            </form>
          </div>
        </div>

        <%!-- District headers --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <%!-- Primary district --%>
          <.district_header district={@primary} label="Primary District" color="info" />

          <%!-- Compare district --%>
          <div class="bg-base-100 border border-base-200 p-5 space-y-3">
            <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40">
              Comparison District
            </div>
            <form phx-change="select_compare">
              <select
                name="compare"
                class="w-full border border-base-300 bg-base-100 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-warning/25 focus:border-warning transition-all"
              >
                <option value="">— Select a district to compare —</option>
                <option
                  :for={d <- @all_districts}
                  value={d.district_code}
                  selected={d.district_code == @compare_code}
                >
                  {d.district_name} ({d.entity_type || "—"})
                </option>
              </select>
            </form>
            <.district_header :if={@compare} district={@compare} label={nil} color="warning" />
            <div
              :if={!@compare}
              class="text-sm text-base-content/35 text-center py-4 border border-dashed border-base-300"
            >
              Select a district above to compare side-by-side
            </div>
          </div>
        </div>

        <%!-- ── Subject Proficiency Side-by-Side ──────────────────────────────── --%>
        <div :if={@primary} class="space-y-3">
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              M-STEP Proficiency by Subject
            </h2>
            <div class="flex-1 h-px bg-base-200"></div>
          </div>

          <div class="bg-base-100 border border-base-200 p-5 space-y-5">
            <.subject_comparison
              :for={subject <- @subjects}
              subject={subject}
              primary={Map.get(@primary.all_subjects, subject)}
              primary_label={short_name(@primary.district_name)}
              compare={@compare && Map.get(@compare.all_subjects, subject)}
              compare_label={@compare && short_name(@compare.district_name)}
            />
          </div>
        </div>

        <%!-- ── Grade Breakdown ─────────────────────────────────────────────────── --%>
        <div :if={@primary && @primary.grade_breakdown != []} class="space-y-3">
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              Grade-Level Breakdown — ELA &amp; Math
            </h2>
            <div class="flex-1 h-px bg-base-200"></div>
          </div>

          <div class="bg-base-100 border border-base-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-base-200 bg-base-50">
                    <th class="text-left px-4 py-3 text-xs font-medium text-base-content/50 uppercase tracking-wide">
                      Grade
                    </th>
                    <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                      ELA — {short_name(@primary.district_name)}
                    </th>
                    <th
                      :if={@compare}
                      class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide"
                    >
                      ELA — {short_name(@compare.district_name)}
                    </th>
                    <th class="text-right px-4 py-3 text-xs font-medium text-info uppercase tracking-wide">
                      Math — {short_name(@primary.district_name)}
                    </th>
                    <th
                      :if={@compare}
                      class="text-right px-4 py-3 text-xs font-medium text-warning uppercase tracking-wide"
                    >
                      Math — {short_name(@compare.district_name)}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200">
                  <tr
                    :for={grade_row <- align_grades(@primary.grade_breakdown, @compare && @compare.grade_breakdown)}
                    class="hover:bg-base-50"
                  >
                    <td class="px-4 py-2.5 font-medium text-xs">{grade_label(grade_row.grade)}</td>
                    <td class="px-4 py-2.5 text-right">
                      <.pct_badge value={grade_row.primary_ela} color="info" />
                    </td>
                    <td :if={@compare} class="px-4 py-2.5 text-right">
                      <.pct_badge value={grade_row.compare_ela} color="warning" />
                    </td>
                    <td class="px-4 py-2.5 text-right">
                      <.pct_badge value={grade_row.primary_math} color="info" />
                    </td>
                    <td :if={@compare} class="px-4 py-2.5 text-right">
                      <.pct_badge value={grade_row.compare_math} color="warning" />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <%!-- ── Proficiency Distribution ───────────────────────────────────────── --%>
        <div :if={@primary && @primary.proficiency_dist} class="space-y-3">
          <div class="flex items-center gap-2">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              Proficiency Level Distribution — All M-STEP Subjects
            </h2>
            <div class="flex-1 h-px bg-base-200"></div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <.dist_card
              district={@primary}
              color_class="border-info/30 bg-info/5"
              label="Primary"
            />
            <.dist_card
              :if={@compare && @compare.proficiency_dist}
              district={@compare}
              color_class="border-warning/30 bg-warning/5"
              label="Comparison"
            />
            <div
              :if={!@compare}
              class="bg-base-50 border border-dashed border-base-300 flex items-center justify-center py-10 text-sm text-base-content/30"
            >
              No comparison district selected
            </div>
          </div>
        </div>

      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :district, :map, default: nil
  attr :label, :string, default: nil
  attr :color, :string, default: "info"

  def district_header(%{district: nil} = assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-200 p-5 flex items-center justify-center text-base-content/30 text-sm py-10">
      No data found for this district
    </div>
    """
  end

  def district_header(assigns) do
    ~H"""
    <div class={"bg-base-100 border border-#{@color}/30 p-5 space-y-2"}>
      <div :if={@label} class={"text-xs font-semibold uppercase tracking-wider text-#{@color}/60"}>
        {@label}
      </div>
      <div class="font-bold text-base leading-tight">{@district.district_name}</div>
      <div class="flex flex-wrap gap-x-2 gap-y-0.5 text-xs text-base-content/50">
        <span :if={@district.isd_name} class="flex items-center gap-1">
          <.icon name="hero-map-pin" class="size-3" />
          {@district.isd_name} ISD
        </span>
        <span :if={@district.isd_name}>·</span>
        <span :if={@district.entity_type}>{@district.entity_type}</span>
        <span :if={@district.entity_type}>·</span>
        <span>{@district.buildings} {if @district.buildings == 1, do: "building", else: "buildings"}</span>
        <span :if={@district.total_assessed > 0}>·</span>
        <span :if={@district.total_assessed > 0}>
          {format_number(@district.total_assessed)} students
        </span>
      </div>
    </div>
    """
  end

  attr :subject, :string, required: true
  attr :primary, :any, default: nil
  attr :primary_label, :string, default: "Primary"
  attr :compare, :any, default: nil
  attr :compare_label, :string, default: nil

  def subject_comparison(assigns) do
    primary_f = if assigns.primary, do: Decimal.to_float(assigns.primary), else: nil
    compare_f = if assigns.compare, do: Decimal.to_float(assigns.compare), else: nil

    assigns =
      assigns
      |> assign(:primary_f, primary_f)
      |> assign(:compare_f, compare_f)

    ~H"""
    <div class="space-y-1.5">
      <div class="flex items-center justify-between text-xs mb-1">
        <span class="font-semibold text-base-content/70">{@subject}</span>
        <div class="flex items-center gap-4">
          <span :if={@compare_f} class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-warning"></span>
            <span class="tabular-nums text-warning font-semibold">
              {if @compare, do: "#{@compare}%", else: "—"}
            </span>
          </span>
          <span class="flex items-center gap-1.5">
            <span class="inline-block w-2 h-2 rounded-full bg-info"></span>
            <span class="tabular-nums text-info font-semibold">
              {if @primary, do: "#{@primary}%", else: "—"}
            </span>
          </span>
        </div>
      </div>

      <%!-- Primary bar --%>
      <div class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">
          {@primary_label}
        </span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-info/70 transition-all duration-500"
            style={"width: #{if @primary_f, do: min(@primary_f, 100), else: 0}%"}
          >
          </div>
          <%!-- Comparison marker on primary bar --%>
          <div
            :if={@compare_f}
            class="absolute top-0 bottom-0 w-0.5 bg-warning"
            style={"left: #{min(@compare_f, 100)}%"}
            title={"#{@compare_label}: #{@compare_f}%"}
          >
          </div>
        </div>
      </div>

      <%!-- Compare bar (shown when compare is selected) --%>
      <div :if={@compare_label} class="flex items-center gap-2">
        <span class="text-xs text-base-content/40 w-20 truncate text-right">
          {@compare_label}
        </span>
        <div class="flex-1 bg-base-200 h-5 relative">
          <div
            class="h-5 bg-warning/70 transition-all duration-500"
            style={"width: #{if @compare_f, do: min(@compare_f, 100), else: 0}%"}
          >
          </div>
          <%!-- Primary marker on compare bar --%>
          <div
            :if={@primary_f}
            class="absolute top-0 bottom-0 w-0.5 bg-info"
            style={"left: #{min(@primary_f, 100)}%"}
            title={"#{@primary_label}: #{@primary_f}%"}
          >
          </div>
        </div>
      </div>

      <%!-- Delta badge when both are present --%>
      <div :if={@primary_f && @compare_f} class="flex justify-end">
        <% delta = Float.round(@primary_f - @compare_f, 1) %>
        <span class={[
          "text-xs font-semibold tabular-nums px-1.5 py-0.5",
          if(delta >= 0, do: "text-success bg-success/10", else: "text-error bg-error/10")
        ]}>
          {if delta >= 0, do: "+#{delta}", else: "#{delta}"} pts vs comparison
        </span>
      </div>
    </div>
    """
  end

  attr :value, :any, default: nil
  attr :color, :string, default: "info"

  def pct_badge(assigns) do
    ~H"""
    <span class={"font-semibold tabular-nums text-#{@color}"}>
      {if @value, do: "#{@value}%", else: "—"}
    </span>
    """
  end

  attr :district, :map, required: true
  attr :color_class, :string, default: "border-base-200 bg-base-50"
  attr :label, :string, default: ""

  def dist_card(assigns) do
    ~H"""
    <div class={"border p-5 space-y-3 #{@color_class}"}>
      <div class="font-semibold text-sm truncate">{@district.district_name}</div>

      <div class="flex h-6 w-full overflow-hidden">
        <div
          class="bg-success flex items-center justify-center text-xs text-white font-semibold"
          style={"width: #{@district.proficiency_dist.advanced}%"}
          title={"Advanced: #{@district.proficiency_dist.advanced}%"}
        >
          {if @district.proficiency_dist.advanced >= 8,
            do: "#{@district.proficiency_dist.advanced}%",
            else: ""}
        </div>
        <div
          class="bg-info flex items-center justify-center text-xs text-white font-semibold"
          style={"width: #{@district.proficiency_dist.proficient}%"}
          title={"Proficient: #{@district.proficiency_dist.proficient}%"}
        >
          {if @district.proficiency_dist.proficient >= 8,
            do: "#{@district.proficiency_dist.proficient}%",
            else: ""}
        </div>
        <div
          class="bg-warning flex items-center justify-center text-xs text-white font-semibold"
          style={"width: #{@district.proficiency_dist.partially}%"}
          title={"Partially: #{@district.proficiency_dist.partially}%"}
        >
          {if @district.proficiency_dist.partially >= 8,
            do: "#{@district.proficiency_dist.partially}%",
            else: ""}
        </div>
        <div
          class="bg-error flex-1 flex items-center justify-center text-xs text-white font-semibold"
          title={"Not Proficient: #{@district.proficiency_dist.not_proficient}%"}
        >
          {if @district.proficiency_dist.not_proficient >= 8,
            do: "#{@district.proficiency_dist.not_proficient}%",
            else: ""}
        </div>
      </div>

      <div class="grid grid-cols-2 gap-x-4 gap-y-1">
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-success"></span>
          Advanced {@district.proficiency_dist.advanced}%
        </span>
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-info"></span>
          Proficient {@district.proficiency_dist.proficient}%
        </span>
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-warning"></span>
          Partially {@district.proficiency_dist.partially}%
        </span>
        <span class="flex items-center gap-1.5 text-xs text-base-content/60">
          <span class="inline-block w-2 h-2 rounded-sm bg-error"></span>
          Not Prof. {@district.proficiency_dist.not_proficient}%
        </span>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  defp load_school_years do
    MdeStateAssessmentResult
    |> Ash.Query.select([:school_year])
    |> Ash.Query.sort(:school_year)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.school_year)
    |> Enum.uniq()
  end

  defp load_all_districts do
    MdeDistrict
    |> Ash.Query.sort(:district_name)
    |> Ash.read!(authorize?: false)
  end

  defp load_district_data(district_code, year) do
    results =
      MdeStateAssessmentResult
      |> Ash.Query.filter(
        school_year == ^year and
          report_category == "All Students" and
          rollup_level == :building and
          mde_building.mde_district.district_code == ^district_code
      )
      |> Ash.Query.load(mde_building: [mde_district: :mde_isd])
      |> Ash.read!(authorize?: false)

    case results do
      [] ->
        nil

      _ ->
        first = List.first(results)
        district = first.mde_building && first.mde_building.mde_district
        isd_name = district && district.mde_isd && district.mde_isd.isd_name

        ela_rows = Enum.filter(results, &(&1.subject == "ELA"))
        buildings = results |> Enum.map(& &1.mde_building_id) |> Enum.uniq() |> length()

        total_assessed =
          ela_rows
          |> Enum.filter(&(&1.grade_content_tested == "All"))
          |> Enum.map(&(&1.number_assessed || 0))
          |> Enum.sum()

        all_subjects =
          Map.new(@subjects, fn subject ->
            subj_rows = Enum.filter(results, &(&1.subject == subject))
            {subject, weighted_proficiency(subj_rows)}
          end)

        %{
          district_code: district_code,
          district_name: (district && district.district_name) || district_code,
          entity_type: district && district.entity_type,
          isd_name: isd_name,
          buildings: buildings,
          total_assessed: total_assessed,
          all_subjects: all_subjects,
          grade_breakdown: build_grade_breakdown(results),
          proficiency_dist: compute_proficiency_dist(results)
        }
    end
  end

  defp build_grade_breakdown(rows) do
    rows
    |> Enum.reject(fn r ->
      is_nil(r.grade_content_tested) or r.grade_content_tested == "All"
    end)
    |> Enum.group_by(& &1.grade_content_tested)
    |> Enum.map(fn {grade, grade_rows} ->
      ela = Enum.filter(grade_rows, &(&1.subject == "ELA"))
      math = Enum.filter(grade_rows, &(&1.subject == "Mathematics"))
      students = ela |> Enum.map(&(&1.number_assessed || 0)) |> Enum.sum()

      %{
        grade: grade,
        ela: weighted_proficiency(ela),
        math: weighted_proficiency(math),
        students: students
      }
    end)
    |> Enum.sort_by(& &1.grade)
  end

  defp compute_proficiency_dist(rows) do
    all_grade_rows = Enum.filter(rows, &(&1.grade_content_tested == "All"))

    {total_adv, total_prof, total_partly, total_not, total_n} =
      Enum.reduce(all_grade_rows, {0, 0, 0, 0, 0}, fn r, {adv, prof, partly, not_p, n} ->
        {
          adv + (r.total_advanced || 0),
          prof + (r.total_proficient || 0),
          partly + (r.total_partially_proficient || 0),
          not_p + (r.total_not_proficient || 0),
          n + (r.number_assessed || 0)
        }
      end)

    if total_n > 0 do
      %{
        advanced: Float.round(total_adv / total_n * 100, 1),
        proficient: Float.round(total_prof / total_n * 100, 1),
        partially: Float.round(total_partly / total_n * 100, 1),
        not_proficient: Float.round(total_not / total_n * 100, 1)
      }
    else
      nil
    end
  end

  defp weighted_proficiency([]), do: nil

  defp weighted_proficiency(rows) do
    {total_assessed, total_prof} =
      Enum.reduce(rows, {0, 0}, fn r, {assessed, prof} ->
        {
          assessed + (r.number_assessed || 0),
          prof + (r.total_advanced || 0) + (r.total_proficient || 0)
        }
      end)

    if total_assessed > 0 do
      total_prof
      |> Decimal.new()
      |> Decimal.div(Decimal.new(total_assessed))
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.round(1)
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Merge two grade breakdown lists into aligned rows for the comparison table
  defp align_grades(primary_grades, nil) do
    Enum.map(primary_grades, fn g ->
      %{grade: g.grade, primary_ela: g.ela, primary_math: g.math, compare_ela: nil, compare_math: nil}
    end)
  end

  defp align_grades(primary_grades, compare_grades) do
    compare_map = Map.new(compare_grades, &{&1.grade, &1})

    all_grades =
      (Enum.map(primary_grades, & &1.grade) ++ Enum.map(compare_grades, & &1.grade))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.map(all_grades, fn grade ->
      p = Enum.find(primary_grades, &(&1.grade == grade))
      c = Map.get(compare_map, grade)

      %{
        grade: grade,
        primary_ela: p && p.ela,
        primary_math: p && p.math,
        compare_ela: c && c.ela,
        compare_math: c && c.math
      }
    end)
  end

  defp grade_label("11"), do: "Grade 11"
  defp grade_label(g), do: "Grade #{g}"

  # Truncate long district names for column headers
  defp short_name(nil), do: "—"

  defp short_name(name) when byte_size(name) > 20 do
    String.slice(name, 0, 18) <> "…"
  end

  defp short_name(name), do: name

  defp page_title(nil, _), do: "District Analysis"
  defp page_title(primary, nil), do: "#{primary.district_name} — Analysis"

  defp page_title(primary, compare),
    do: "#{short_name(primary.district_name)} vs #{short_name(compare.district_name)}"

  defp format_number(nil), do: "—"
  defp format_number(0), do: "0"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end
end
