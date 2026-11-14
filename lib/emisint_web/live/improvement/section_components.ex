defmodule EmisintWeb.Improvement.SectionComponents do
  @moduledoc """
  Collapsible detail sections shared by the ND First portfolio (`/school-goals`)
  and the school and district pages.

  The open state is server-side, kept in the page URL (`open`, a
  comma-separated list of section keys), so filter and period changes,
  reloads and shared links keep it. Each header is one full-width `<button>`
  (Enter and Space work natively) with `aria-expanded` and `aria-controls`.
  A collapsed body stays in the page as a `hidden` region, so
  `aria-controls` always resolves. Header actions (e.g. an import link) sit
  beside the button, outside it, and stay visible while collapsed.
  """
  use EmisintWeb, :html

  attr :id, :string, required: true
  attr :section, :string, required: true, doc: "the section's key in the `open` param"
  attr :open?, :boolean, required: true
  attr :title, :string, required: true
  attr :summary, :string, default: nil
  attr :event, :string, default: "toggle_section"
  attr :tag, :string, default: "div", doc: "\"section\" for a page landmark"
  attr :heading, :string, default: "h2", doc: "the header's heading level"
  attr :class, :string, default: "bg-base-100 border border-base-200 rounded-xl scroll-mt-4"
  slot :actions, doc: "controls kept visible beside the header"
  slot :inner_block, required: true

  def collapsible(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@tag} class={@class} id={@id} data-open={to_string(@open?)}>
      <div class="flex flex-wrap items-start gap-x-2">
        <.dynamic_tag tag_name={@heading} class="min-w-0 flex-1 basis-64">
          <button
            type="button"
            class="flex w-full items-start gap-3 rounded-xl p-4 text-left hover:bg-base-200/50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            phx-click={@event}
            phx-value-section={@section}
            aria-expanded={to_string(@open?)}
            aria-controls={"#{@id}-body"}
            id={"#{@id}-toggle"}
          >
            <.icon
              name="hero-chevron-right"
              class={["mt-0.5 size-5 shrink-0 transition-transform", @open? && "rotate-90"]}
            />
            <span class="min-w-0">
              <span class="block font-semibold">{@title}</span>
              <span :if={@summary} class="block text-sm text-base-content/70" id={"#{@id}-summary"}>
                {@summary}
              </span>
            </span>
          </button>
        </.dynamic_tag>
        <div :if={@actions != []} class="flex items-center gap-2 px-4 pb-3 sm:py-3">
          {render_slot(@actions)}
        </div>
      </div>
      <div
        id={"#{@id}-body"}
        role="region"
        aria-labelledby={"#{@id}-toggle"}
        hidden={!@open?}
        class="border-t border-base-200"
      >
        {render_slot(@inner_block)}
      </div>
    </.dynamic_tag>
    """
  end

  attr :id, :string, default: "section-controls"
  attr :all_open?, :boolean, required: true
  attr :none_open?, :boolean, required: true
  attr :event, :string, default: "sections"

  @doc "Expand all / Collapse all, each disabled when there is nothing to change."
  def section_controls(assigns) do
    ~H"""
    <div class="flex gap-2" id={@id}>
      <button
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={@event}
        phx-value-to="expand"
        id={"#{@id}-expand"}
        disabled={@all_open?}
      >
        <.icon name="hero-chevron-double-down" class="size-4" /> Expand all
      </button>
      <button
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={@event}
        phx-value-to="collapse"
        id={"#{@id}-collapse"}
        disabled={@none_open?}
      >
        <.icon name="hero-chevron-double-up" class="size-4" /> Collapse all
      </button>
    </div>
    """
  end

  @doc "The open sections from the `open` param, limited to `allowed`."
  def open_sections(nil, _allowed), do: MapSet.new()

  def open_sections(param, allowed) when is_binary(param),
    do: param |> String.split(",") |> Enum.filter(&(&1 in allowed)) |> MapSet.new()

  @doc "The `open` param for a set of sections, in `order` (nil when none)."
  def open_param(open, order) do
    case Enum.filter(order, &MapSet.member?(open, &1)) do
      [] -> nil
      list -> Enum.join(list, ",")
    end
  end

  @doc "Toggles one section in a set."
  def toggle(open, section) do
    if MapSet.member?(open, section),
      do: MapSet.delete(open, section),
      else: MapSet.put(open, section)
  end
end
