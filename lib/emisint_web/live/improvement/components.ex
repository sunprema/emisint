defmodule EmisintWeb.Improvement.Components do
  @moduledoc """
  Display components for school goal data.

  Missing values are always shown as "Not reported" / "Not rated", never as
  zero. Ranges and suppressed values keep their shape, and each value carries
  its own provenance.
  """
  use EmisintWeb, :html

  alias Emisint.Improvement.{Percent, Rubric}

  attr :tabs, :list, required: true, doc: "`Emisint.Improvement.Pilot.tabs/1`"
  attr :current, :string, default: nil, doc: "the selected participant's slug"

  @doc """
  The "ND FIRST School Dashboard" heading and one main tab per ND First
  participant the user can reach (`Pilot.tabs/1`). A tab opens the
  participant's dashboard (`href`); the selected participant, including while
  one of its buildings is shown, is marked with `aria-current`. Participants
  not yet implemented are labeled "Coming soon" and link nowhere.
  """
  def school_tabs(assigns) do
    ~H"""
    <div class="space-y-2" id="nd-first-school-tabs">
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
        ND FIRST School Dashboard
      </div>
      <nav aria-label="ND First schools" class="overflow-x-auto">
        <ul class="flex gap-1 border-b border-base-200 min-w-max">
          <li :for={tab <- @tabs}>
            <.link
              :if={tab.enabled?}
              navigate={~p"/school-goals/#{tab.href}"}
              id={"nd-tab-#{tab.slug}"}
              aria-current={if tab.slug == @current, do: "page"}
              class={[
                "inline-flex items-center px-3 py-2 text-sm -mb-px border-b-2 whitespace-nowrap",
                if(tab.slug == @current,
                  do: "border-primary text-primary font-semibold",
                  else: "border-transparent text-base-content/70 hover:text-base-content"
                )
              ]}
            >
              {tab.name}
            </.link>
            <span
              :if={!tab.enabled?}
              id={"nd-tab-soon-#{tab_id(tab.name)}"}
              aria-disabled="true"
              class="inline-flex items-center gap-1.5 px-3 py-2 text-sm -mb-px border-b-2 border-transparent text-base-content/40 whitespace-nowrap cursor-not-allowed"
            >
              {tab.name}
              <span class="badge badge-ghost badge-xs">Coming soon</span>
            </span>
          </li>
        </ul>
      </nav>
    </div>
    """
  end

  defp tab_id(name), do: name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

  attr :nav, :map, default: nil, doc: "`Emisint.Improvement.Pilot.participant_nav/2`"

  @doc """
  A district participant's pages: "District overview" and its Elementary,
  Middle or High School pages, shown on the district and on each building,
  with the current page marked. Only pages the user can read are listed.
  Warwick's provisional workbook scope stays labeled.
  """
  def participant_nav(%{nav: nil} = assigns), do: ~H""

  def participant_nav(assigns) do
    ~H"""
    <nav
      aria-label={"#{@nav.participant} pages"}
      id="participant-nav"
      class="flex flex-wrap items-center gap-1 rounded-lg bg-base-200/50 px-2 py-1.5"
    >
      <span class="text-xs font-semibold uppercase tracking-wide text-base-content/60 mr-1">
        {@nav.participant}
      </span>
      <.link
        :for={item <- @nav.items}
        navigate={~p"/school-goals/#{item.slug}"}
        id={"participant-nav-#{item.slug}"}
        aria-current={if item.current?, do: "page"}
        class={[
          "btn btn-xs",
          if(item.current?, do: "btn-primary", else: "btn-ghost")
        ]}
      >
        {item.label}
      </.link>
      <span
        :if={@nav.provisional?}
        class="badge badge-warning badge-soft badge-sm ml-1"
        id="participant-nav-provisional"
        title="The workbook says “Warwick School”; whether it means the district or a building is not established."
      >
        Workbook scope provisional
      </span>
    </nav>
    """
  end

  attr :scope, :map, required: true, doc: "the dashboard's participant scope"
  attr :school, :map, required: true

  @doc """
  Explains a district participant's or building's scope (`Seeds.Participant`)
  and links the related records. Nothing for a single-building participant.
  """
  def participant_scope_note(%{scope: %{kind: :participant}} = assigns) do
    assigns =
      assign(assigns,
        provisional?: Emisint.Improvement.Seeds.Participant.provisional_scope?(assigns.scope)
      )

    ~H"""
    <div class="alert alert-info alert-soft text-sm" id="participant-scope" role="note">
      <div>
        <div class="font-medium">District participant</div>
        <div>
          <span :if={!@provisional?}>
            The ND First workbook goals, seasonal ratings and payment below are written for {@school.name}.
          </span>
          <span :if={@provisional?}>
            The ND First workbook goals, seasonal ratings and payment below are recorded on {@school.name} provisionally (see below).
          </span>
          The state results below are the district's own published rows
          (InstitutionID {@school.state_entity_id}). Annual targets are set per building and
          compared on each building's dashboard: <.related_links schools={@scope.buildings} />
        </div>
      </div>
    </div>
    <.provisional_scope :if={@provisional?} scope={@scope.workbook_scope} />
    """
  end

  def participant_scope_note(%{scope: %{kind: :building}} = assigns) do
    assigns =
      assign(assigns,
        provisional?: Emisint.Improvement.Seeds.Participant.provisional_scope?(assigns.scope)
      )

    ~H"""
    <div class="alert alert-info alert-soft text-sm" id="building-scope" role="note">
      <div>
        <div class="font-medium">Building of an ND First participant</div>
        <div>
          This dashboard shows {@school.name}'s own annual targets and published results. The ND First workbook goals, seasonal ratings and payment are
          <span :if={!@provisional?}>written for</span>
          <span :if={@provisional?}>recorded provisionally on</span>
          <.related_links schools={[@scope.participant]} /> and are not repeated here.
          <span :if={@provisional?} id="building-scope-provisional">
            Whether they cover this building is not established by the sources.
          </span>
        </div>
      </div>
    </div>
    """
  end

  def participant_scope_note(assigns), do: ~H""

  attr :targets, :list, required: true, doc: "`Emisint.Improvement.PlanTargets.for_school/1`"

  @doc """
  Other continuous-improvement-plan targets (graduation, English Learner,
  attendance, writing, readiness, engagement, undated targets), shown as
  written with their status. None is compared with a result.
  """
  def plan_targets_section(assigns) do
    ~H"""
    <section
      :if={@targets != []}
      class="bg-base-100 border border-base-200 rounded-xl overflow-hidden scroll-mt-4"
      id="plan-targets"
    >
      <div class="px-4 py-3 border-b border-base-200">
        <h2 class="font-semibold">Other plan targets</h2>
        <p class="text-sm text-base-content/60 mt-1">
          Further targets from the continuous improvement plan (North Dakota - ND First Schools.pdf), shown exactly as written. None is compared with a result: each says why, and targets whose year or definition the source leaves open are marked unresolved.
        </p>
      </div>
      <div class="divide-y divide-base-200">
        <div :for={t <- @targets} class="px-4 py-3 space-y-1" id={"plan-target-#{t.id}"}>
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="font-medium">{t.title}</h3>
            <span
              class={["badge badge-sm", plan_status_badge(t.status)]}
              data-plan-status={t.status}
            >
              {Emisint.Improvement.PlanTargets.status_label(t.status)}
            </span>
          </div>
          <p class="text-sm">{t.measure}</p>
          <p :if={t.baseline} class="text-sm">Baseline: {t.baseline}</p>
          <div :if={t.targets != []} class="flex flex-wrap gap-x-4 gap-y-1 text-sm">
            <span :for={{label, value} <- t.targets}>
              <span class="text-base-content/60">{label}:</span> {value}
            </span>
          </div>
          <p :if={t.long_term} class="text-sm text-base-content/70">{t.long_term}</p>
          <p class="text-xs text-base-content/70" data-plan-note="status">{t.status_note}</p>
          <p class="text-xs font-medium text-base-content/70" data-plan-note="results">
            {t.results_note}
          </p>
          <p class="text-xs text-base-content/50">Source: {t.location}</p>
        </div>
      </div>
    </section>
    """
  end

  defp plan_status_badge(:stated), do: "badge-ghost"
  defp plan_status_badge(:confirmed), do: "badge-ghost"
  defp plan_status_badge(:no_numeric_target), do: "badge-ghost"
  defp plan_status_badge(_unresolved), do: "badge-warning badge-soft"

  attr :years, :map, default: nil, doc: "`annual_years` of the school's comparison config"

  @doc "How the plan maps its annual targets to school years, with the source excerpt."
  def annual_year_mapping(%{years: nil} = assigns), do: ~H""

  def annual_year_mapping(assigns) do
    ~H"""
    <p
      class={[
        "text-xs mt-1",
        if(@years.status == :assumed,
          do: "nd-text-warning font-medium",
          else: "text-base-content/60"
        )
      ]}
      id="annual-year-mapping"
      data-year-mapping={@years.status}
    >
      <span :if={@years.status == :stated}>Year mapping as stated in the source:</span>
      <span :if={@years.status == :confirmed}>
        Year mapping confirmed by the user: the targets are 2025–2026 through 2030–2031, in order (recorded November 8, 2026). Source wording:
      </span>
      <span :if={@years.status == :assumed}>
        Year mapping unconfirmed: the source assumes which school year each target belongs to, so year-specific comparisons are off until the years are confirmed. Source:
      </span>
      {@years.excerpt} ({@years.location})
    </p>
    """
  end

  attr :scope, :map, required: true, doc: "`Seeds.Participant.workbook_scope/1`"

  defp provisional_scope(assigns) do
    ~H"""
    <div class="alert alert-warning alert-soft text-sm" id="workbook-scope-provisional" role="note">
      <div class="space-y-1">
        <div class="font-medium">Workbook scope provisional</div>
        <div>{@scope.note}</div>
        <div class="text-xs">Source: {@scope.excerpt}</div>
        <details :if={@scope.evidence != []} class="text-xs" id="workbook-scope-evidence">
          <summary class="cursor-pointer">Evidence checked</summary>
          <ul class="list-disc ml-5 mt-1 space-y-1">
            <li :for={e <- @scope.evidence}>{e}</li>
          </ul>
        </details>
      </div>
    </div>
    """
  end

  attr :schools, :list, required: true
  attr :id_prefix, :string, default: "related", doc: "keeps DOM ids unique per use"

  @doc "Related ND First records: links where readable, names otherwise."
  def related_links(assigns) do
    ~H"""
    <span :for={{s, i} <- Enum.with_index(@schools)}>
      <span :if={i > 0}>·</span>
      <.link
        :if={s.readable?}
        navigate={~p"/school-goals/#{s.slug}"}
        class="link link-primary"
        id={"#{@id_prefix}-#{s.slug}"}
      >
        {s.name}
      </.link>
      <span :if={!s.readable?} id={"#{@id_prefix}-#{s.slug}"} data-readable="false">{s.name}</span>
    </span>
    """
  end

  attr :entry, :any, required: true
  attr :metric, :map, required: true

  def actual_value(%{entry: nil} = assigns) do
    ~H"""
    <span class="text-base-content/50 italic">Not reported</span>
    """
  end

  def actual_value(%{entry: %{value_state: :exact}} = assigns) do
    ~H"""
    <span class="font-semibold">{format_number(@metric, @entry.value)}</span>
    """
  end

  def actual_value(%{entry: %{value_state: :range}} = assigns) do
    ~H"""
    <span class="font-semibold">
      {format_number(@metric, @entry.range_low)}–{format_number(@metric, @entry.range_high)}
    </span>
    <span class="badge badge-ghost badge-xs ml-1">Range</span>
    """
  end

  def actual_value(%{entry: %{value_state: :suppressed}} = assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm" title="Suppressed by the source; not classified.">
      Suppressed
    </span>
    <div :if={@entry.suppression_reason} class="text-xs text-base-content/60 mt-0.5">
      Source: “{@entry.suppression_reason}”
    </div>
    """
  end

  def actual_value(%{entry: %{value_state: :unavailable}} = assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">Unavailable</span>
    """
  end

  attr :entry, :any, required: true

  def rating_value(%{entry: nil} = assigns) do
    ~H"""
    <span class="text-base-content/50 italic">Not rated</span>
    """
  end

  # One status badge: the score and the full rubric label, in the rubric's
  # accessible text color on a restrained tint, wrapping in narrow cells.
  def rating_value(%{entry: %{rating_state: :rated}} = assigns) do
    ~H"""
    <span class={[
      "badge h-auto min-h-6 py-0.5 px-2 font-semibold whitespace-normal text-left leading-snug border border-current/30",
      score_badge(@entry.score)
    ]}>
      {@entry.score} · {Rubric.label(@entry.score)}
    </span>
    """
  end

  def rating_value(%{entry: %{rating_state: :not_applicable}} = assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">N/A</span>
    """
  end

  def rating_value(%{entry: %{rating_state: :unavailable}} = assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm">Unavailable</span>
    """
  end

  @doc "Who recorded an entry, when, and from what source."
  attr :entry, :map, required: true
  attr :users, :map, required: true

  def provenance(%{entry: %{source: :workbook_import}} = assigns) do
    ~H"""
    <div class="text-xs text-base-content/60 space-y-0.5">
      <div>
        <span class="badge badge-soft badge-info nd-text-info badge-xs">Workbook import</span>
        <span class="ml-1">Original author unknown</span>
      </div>
      <div>
        {@entry.source_ref}
        <span :if={@entry.source_last_updated_on}>
          · workbook last updated {format_date(@entry.source_last_updated_on)}
        </span>
      </div>
      <div>
        Imported {format_datetime(@entry.recorded_at)}{recorder_suffix(@entry, @users)}
      </div>
      <.entry_details entry={@entry} />
    </div>
    """
  end

  def provenance(%{entry: %{source: :nd_insights}} = assigns) do
    ~H"""
    <div class="text-xs text-base-content/60 space-y-0.5">
      <div>
        <span :if={@entry.kind == :correction} class="badge badge-secondary badge-xs mr-1">
          Correction
        </span>
        <span class="badge badge-soft badge-info nd-text-info badge-xs">ND Insights</span>
        <span class="ml-1">{@entry.source_ref}</span>
      </div>
      <div>
        Selected by {email(@users, @entry.author_id)} · {format_datetime(@entry.recorded_at)}
      </div>
      <.entry_details entry={@entry} />
    </div>
    """
  end

  def provenance(%{entry: %{source: :unit_conversion}} = assigns) do
    ~H"""
    <div class="text-xs text-base-content/60 space-y-0.5">
      <div>
        <span class="badge badge-secondary badge-xs mr-1">Unit correction</span>
        Originally submitted by {email(@users, @entry.author_id)} · restated {format_datetime(
          @entry.recorded_at
        )}{recorder_suffix(@entry, @users)}
      </div>
      <.entry_details entry={@entry} />
    </div>
    """
  end

  def provenance(assigns) do
    ~H"""
    <div class="text-xs text-base-content/60 space-y-0.5">
      <div>
        <span :if={@entry.kind == :correction} class="badge badge-secondary badge-xs mr-1">
          Correction
        </span>
        Submitted by {email(@users, @entry.author_id)} · {format_datetime(@entry.recorded_at)}
      </div>
      <.entry_details entry={@entry} />
    </div>
    """
  end

  @doc """
  One-line provenance with an expandable "Source details" section holding the
  full `provenance/1`. Used on the dashboard; History shows the full version.
  The toggle uses `JS.toggle`, so it stays open across LiveView updates.
  """
  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :users, :map, required: true

  def compact_provenance(assigns) do
    ~H"""
    <div class="text-xs text-base-content/60 mt-0.5">
      <button
        type="button"
        class="inline-flex items-center gap-1 hover:text-base-content text-left"
        phx-click={
          JS.toggle(to: "##{@id}")
          |> JS.toggle_class("rotate-90", to: "##{@id}-chevron")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        aria-expanded="false"
        aria-controls={@id}
        id={"#{@id}-toggle"}
      >
        <span id={"#{@id}-chevron"} class="inline-flex transition-transform">
          <.icon name="hero-chevron-right-mini" class="size-3" />
        </span>
        <span>{summary_line(@entry, @users)}</span>
      </button>
      <div id={@id} class="hidden mt-1 pl-4 border-l border-base-300">
        <.provenance entry={@entry} users={@users} />
      </div>
    </div>
    """
  end

  defp summary_line(%{source: :workbook_import}, _users), do: "Workbook import · source details"

  defp summary_line(%{source: :nd_insights} = entry, _users) do
    year = Emisint.Improvement.GrowthPercentile.source_year(entry) || "unknown"
    "ND Insights · source year #{year} · source details"
  end

  defp summary_line(%{source: :unit_conversion}, _users), do: "Unit correction · source details"

  defp summary_line(entry, users) do
    prefix = if entry.kind == :correction, do: "Corrected by ", else: ""

    "#{prefix}#{email(users, entry.author_id)} · #{format_date(DateTime.to_date(entry.recorded_at))}"
  end

  attr :entry, :map, required: true

  defp entry_details(assigns) do
    ~H"""
    <div :if={@entry.measurement_date}>Measured {format_date(@entry.measurement_date)}</div>
    <div :if={@entry.correction_reason}>Reason for correction: {@entry.correction_reason}</div>
    <div :if={@entry.notes} class="whitespace-pre-line">Notes: {@entry.notes}</div>
    <div :if={@entry.evidence_links != []} class="flex flex-wrap gap-x-2">
      <span>Evidence:</span>
      <a
        :for={link <- @entry.evidence_links}
        href={link.url}
        target="_blank"
        rel="noopener noreferrer"
        class="link link-primary"
      >
        {link.label || link.url}
      </a>
    </div>
    """
  end

  @doc "A baseline or target value; unconfirmed 36-month targets are flagged with their source cell."
  attr :metric, :map, required: true
  attr :field, :atom, required: true

  # Presentation only: the metric keeps its `:target_36m_needs_confirmation`
  # flag and `target_36m` stays unset, so it remains excluded from comparisons.
  # The muted text and toggle render here; the details panel is rendered
  # separately by `target_source_details/1` so it can use the full width.
  def target(%{field: :target_36m, metric: metric} = assigns) do
    if needs_confirmation?(metric) do
      assigns = assign(assigns, id: source_details_id(metric))

      ~H"""
      <span data-target-value class="text-base-content/60 italic">Needs confirmation</span>
      <button
        type="button"
        class="inline-flex items-center gap-0.5 text-base-content/50 hover:text-base-content whitespace-nowrap"
        phx-click={
          JS.toggle(to: "##{@id}")
          |> JS.toggle_class("rotate-90", to: "##{@id}-chevron")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        aria-expanded="false"
        aria-controls={@id}
        id={"#{@id}-toggle"}
      >
        <span id={"#{@id}-chevron"} class="inline-flex transition-transform">
          <.icon name="hero-chevron-right-mini" class="size-3" />
        </span>
        Source details
      </button>
      """
    else
      plain_target(assigns)
    end
  end

  def target(assigns), do: plain_target(assigns)

  @doc "The collapsed source details for a 36-month target that needs confirmation (renders nothing otherwise)."
  attr :metric, :map, required: true
  attr :class, :string, default: nil

  def target_source_details(assigns) do
    source = assigns.metric.source_values["target_36m"] || %{}

    assigns =
      assign(assigns,
        show?: needs_confirmation?(assigns.metric),
        id: source_details_id(assigns.metric),
        cell: source["cell"],
        raw: source["raw"]
      )

    ~H"""
    <div
      :if={@show?}
      id={@id}
      class={["hidden pl-2 border-l border-base-300 text-xs text-base-content/60 space-y-0.5", @class]}
    >
      <div :if={@cell}>36-month target source: {@cell}: “{@raw}”</div>
      <div :if={@raw}>The workbook lists {@raw}; please confirm whether this means {@raw}%.</div>
      <div :if={!@raw}>The workbook value for this target needs confirmation.</div>
      <div>Not used in comparisons until confirmed.</div>
    </div>
    """
  end

  defp needs_confirmation?(%{flags: flags}) when is_list(flags),
    do: :target_36m_needs_confirmation in flags

  defp needs_confirmation?(_metric), do: false

  defp source_details_id(metric), do: "target-36m-source-#{metric.code}"

  # Same rules as the PDF (Emisint.Improvement.Display.target/2).
  defp plain_target(assigns) do
    {shape, text} = Emisint.Improvement.Display.target(assigns.metric, assigns.field)
    source = Emisint.Improvement.Display.target_source(assigns.metric, assigns.field)
    assigns = assign(assigns, shape: shape, text: text, raw: source && source.raw)

    ~H"""
    <span :if={@shape == :number} data-target-value>{@text}</span>
    <span
      :if={@shape == :text}
      data-target-value
      class="italic"
      title="Shown exactly as written in the goal workbook; not converted or classified."
    >
      {@text}
    </span>
    <span
      :if={@shape == :date}
      data-target-value
      class="italic text-base-content/60"
      title={"The workbook cell holds the date #{@raw} where a number is expected; please confirm the intended value."}
    >
      {@text}
    </span>
    <span :if={@shape == :empty} data-target-value class="text-base-content/40">{@text}</span>
    """
  end

  def format_number(%{unit: :percent}, value), do: Percent.format(value)
  def format_number(_metric, %Decimal{} = value), do: Decimal.to_string(value, :normal)
  def format_number(_metric, nil), do: nil

  def format_date(nil), do: nil
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  def format_datetime(nil), do: nil
  def format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y %H:%M UTC")

  def format_money(nil), do: nil

  def format_money(%Decimal{} = amount) do
    whole = amount |> Decimal.round(0) |> Decimal.to_integer() |> Integer.to_string()

    "$" <>
      (whole |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse())
  end

  def format_weight(nil), do: "—"
  def format_weight(%Decimal{} = weight), do: Percent.format(weight)

  def category_label(:systems), do: "Systems"
  def category_label(:student_outcome), do: "Student Outcome"

  defp email(_users, nil), do: "unknown"
  defp email(users, id), do: Map.get(users, id, "unknown user")

  defp recorder_suffix(%{recorded_by_id: nil}, _users), do: ""
  defp recorder_suffix(%{recorded_by_id: id}, users), do: " by #{email(users, id)}"

  attr :status, :map, required: true, doc: "Emisint.Improvement.GoalStatus.evaluate/3"
  attr :id, :string, required: true
  slot :inner_block, required: true

  @doc "A result with its applicable target and status; colored only for Meets / Below."
  def goal_result(assigns) do
    assigns = assign(assigns, summary: Emisint.Improvement.GoalStatus.summary(assigns.status))

    ~H"""
    <span class={goal_status_class(@status.status)}>{render_slot(@inner_block)}</span>
    <div
      :if={@summary}
      id={@id}
      class={["text-xs mt-0.5", goal_status_class(@status.status) || "text-base-content/60"]}
    >
      {@summary}
    </div>
    """
  end

  defp goal_status_class(:meets), do: "nd-text-success font-medium"
  defp goal_status_class(:below), do: "nd-text-error font-medium"
  defp goal_status_class(_), do: nil

  # Rubric tones are shared with the PDF (Display.score_tone/1). Class names
  # are literal so Tailwind keeps them.
  defp score_badge(score), do: score |> Emisint.Improvement.Display.score_tone() |> tone_badge()

  # The nd-text-* color keeps small badge text readable on the soft fill.
  defp tone_badge(:success), do: "badge-soft badge-success nd-text-success"
  defp tone_badge(:info), do: "badge-soft badge-info nd-text-info"
  defp tone_badge(:warning), do: "badge-soft badge-warning nd-text-warning"
  defp tone_badge(:error), do: "badge-soft badge-error nd-text-error"
end
