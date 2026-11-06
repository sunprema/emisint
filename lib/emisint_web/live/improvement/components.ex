defmodule EmisintWeb.Improvement.Components do
  @moduledoc """
  Display components for school goal data.

  Missing values are always shown as "Not reported" / "Not rated", never as
  zero. Ranges and suppressed values keep their shape, and each value carries
  its own provenance.
  """
  use EmisintWeb, :html

  alias Emisint.Improvement.{Percent, Rubric}

  attr :tabs, :list, required: true, doc: "`Emisint.Improvement.Pilot.roster/0`"
  attr :current, :string, default: nil, doc: "the selected school's slug"

  @doc """
  The "ND FIRST School Dashboard" heading and one tab per ND First school.
  Enabled schools link to their own dashboard; the selected one is marked
  with `aria-current`. Schools not yet implemented are labeled "Coming soon"
  and link nowhere, so no other school's data is ever shown under them.
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
              navigate={~p"/school-goals/#{tab.slug}"}
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
