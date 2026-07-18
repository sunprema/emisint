defmodule EmisintWeb.Components.ScatterChart do
  @moduledoc """
  A quadrant scatter chart with a linear-regression trend line, built as
  inline SVG (no JS charting dependency). Used by the ESP Portfolio
  "Regression" tab for ED% vs M-STEP/SAT performance.

  Color is never the only signal for the red/yellow/green quadrant
  classification (their CVD separation is in the "secondary encoding
  required" band per the dataviz palette validator) — every dot carries a
  native SVG `<title>` tooltip with the quadrant name in text, the legend is
  text-labeled, and a plain table below the chart repeats every point.
  """

  use Phoenix.Component

  attr :points, :list, required: true, doc: "list of %{school_name, ed_pct, value, quadrant}"
  attr :excluded, :list, default: [], doc: "resolved schools missing ED% or a performance value"
  attr :thresholds, :map, required: true, doc: "%{ed_pct:, value:} statewide averages"
  attr :regression, :any, default: nil, doc: "%{slope:, intercept:} | nil"
  attr :title, :string, required: true
  attr :y_label, :string, required: true
  attr :y_unit, :atom, required: true, values: [:percent, :score]
  attr :y_domain, :any, default: nil, doc: "{min, max} | nil (auto from data)"

  def scatter_chart(assigns) do
    geometry =
      build_geometry(
        assigns.points,
        assigns.thresholds,
        assigns.regression,
        assigns.y_domain,
        assigns.y_unit
      )

    assigns = assign(assigns, :geo, geometry)

    ~H"""
    <div class="bg-base-50/50">
      <div class="px-6 pt-4 pb-3">
        <h3 class="text-sm font-semibold">{@title}</h3>
        <p class="text-xs text-base-content/40 mt-0.5">
          X: Economically Disadvantaged % · Y: {@y_label} · dashed line: statewide averages · solid line: trend
        </p>
      </div>

      <div :if={@points == []} class="px-6 pb-4 text-xs text-base-content/30 italic">
        No schools with both ED% and {@y_label} data for this year.
      </div>

      <div :if={@points != []} class="px-6 pb-4">
        <svg viewBox="0 0 640 400" class="w-full h-auto" role="img" aria-label={@title}>
          <%!-- quadrant fills --%>
          <rect
            x={@geo.plot.x}
            y={@geo.plot.y}
            width={@geo.crosshair.px - @geo.plot.x}
            height={@geo.crosshair.py - @geo.plot.y}
            class="fill-warning/5"
          />
          <rect
            x={@geo.crosshair.px}
            y={@geo.plot.y}
            width={@geo.plot.x + @geo.plot.w - @geo.crosshair.px}
            height={@geo.crosshair.py - @geo.plot.y}
            class="fill-success/5"
          />
          <rect
            x={@geo.plot.x}
            y={@geo.crosshair.py}
            width={@geo.crosshair.px - @geo.plot.x}
            height={@geo.plot.y + @geo.plot.h - @geo.crosshair.py}
            class="fill-error/5"
          />
          <rect
            x={@geo.crosshair.px}
            y={@geo.crosshair.py}
            width={@geo.plot.x + @geo.plot.w - @geo.crosshair.px}
            height={@geo.plot.y + @geo.plot.h - @geo.crosshair.py}
            class="fill-warning/5"
          />

          <%!-- plot border --%>
          <rect
            x={@geo.plot.x}
            y={@geo.plot.y}
            width={@geo.plot.w}
            height={@geo.plot.h}
            fill="none"
            class="stroke-base-content/10"
          />

          <%!-- statewide-average crosshair --%>
          <line
            :if={@geo.crosshair.px}
            x1={@geo.crosshair.px}
            y1={@geo.plot.y}
            x2={@geo.crosshair.px}
            y2={@geo.plot.y + @geo.plot.h}
            stroke-dasharray="3,3"
            class="stroke-base-content/25"
          />
          <line
            :if={@geo.crosshair.py}
            x1={@geo.plot.x}
            y1={@geo.crosshair.py}
            x2={@geo.plot.x + @geo.plot.w}
            y2={@geo.crosshair.py}
            stroke-dasharray="3,3"
            class="stroke-base-content/25"
          />

          <%!-- regression trend line --%>
          <line
            :if={@geo.trend}
            x1={@geo.trend.x1}
            y1={@geo.trend.y1}
            x2={@geo.trend.x2}
            y2={@geo.trend.y2}
            stroke-width="2"
            class="stroke-primary/70"
          />

          <%!-- axis ticks --%>
          <text
            :for={{x_val, x_px} <- @geo.x_ticks}
            x={x_px}
            y={@geo.plot.y + @geo.plot.h + 16}
            text-anchor="middle"
            class="fill-base-content/40 text-[9px]"
          >
            {x_val}%
          </text>
          <text
            :for={{y_val, y_px} <- @geo.y_ticks}
            x={@geo.plot.x - 6}
            y={y_px + 3}
            text-anchor="end"
            class="fill-base-content/40 text-[9px]"
          >
            {y_val}
          </text>

          <%!-- data points --%>
          <circle
            :for={p <- @geo.dots}
            cx={p.cx}
            cy={p.cy}
            r="6"
            class={["stroke-base-100", quadrant_fill_class(p.quadrant)]}
            stroke-width="1.5"
            opacity="0.9"
          >
            <title>{p.tooltip}</title>
          </circle>
        </svg>

        <%!-- legend --%>
        <div class="flex flex-wrap items-center gap-4 mt-2 px-1">
          <div :for={{label, cls} <- legend_entries()} class="flex items-center gap-1.5">
            <span class={["inline-block size-2.5 rounded-full", cls]} />
            <span class="text-[10px] text-base-content/50">{label}</span>
          </div>
        </div>

        <p
          :if={is_nil(@regression) and length(@points) > 0}
          class="mt-2 text-[10px] text-base-content/30 italic"
        >
          Fewer than 3 schools with data — not enough points for a trend line.
        </p>
      </div>

      <%!-- table view (accessible fallback + always-visible detail) --%>
      <div :if={@points != [] || @excluded != []} class="px-6 pb-5">
        <div class="border border-base-200 overflow-hidden">
          <table class="w-full text-xs">
            <thead>
              <tr class="bg-base-200/40 text-[10px] text-base-content/50 uppercase tracking-wide">
                <th class="px-3 py-1.5 text-left font-medium">School</th>
                <th class="px-3 py-1.5 text-right font-medium">ED %</th>
                <th class="px-3 py-1.5 text-right font-medium">{@y_label}</th>
                <th class="px-3 py-1.5 text-left font-medium">Category</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200">
              <tr :for={p <- @points}>
                <td class="px-3 py-1.5">{p.school_name}</td>
                <td class="px-3 py-1.5 text-right font-mono">{p.ed_pct}%</td>
                <td class="px-3 py-1.5 text-right font-mono">{format_value(p.value, @y_unit)}</td>
                <td class="px-3 py-1.5">
                  <span class={["inline-flex items-center gap-1", quadrant_text_class(p.quadrant)]}>
                    <span class={[
                      "inline-block size-1.5 rounded-full",
                      quadrant_fill_class(p.quadrant)
                    ]} />
                    {quadrant_label(p.quadrant)}
                  </span>
                </td>
              </tr>
              <tr :for={p <- @excluded} class="text-base-content/30 italic">
                <td class="px-3 py-1.5">{p.school_name}</td>
                <td class="px-3 py-1.5 text-right font-mono">{p.ed_pct || "—"}</td>
                <td class="px-3 py-1.5 text-right font-mono">{p.value || "—"}</td>
                <td class="px-3 py-1.5">missing data</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Geometry (pure math — scales data into the 640x400 SVG viewBox)
  # ---------------------------------------------------------------------------

  @plot %{x: 50, y: 20, w: 570, h: 300}

  defp build_geometry(points, thresholds, regression, y_domain_override, y_unit) do
    x_min = 0.0
    x_max = 100.0

    {y_min, y_max} = y_domain_override || auto_y_domain(points, thresholds, y_unit)

    sx = fn ed -> @plot.x + safe_ratio(ed - x_min, x_max - x_min) * @plot.w end
    sy = fn v -> @plot.y + (1 - safe_ratio(v - y_min, y_max - y_min)) * @plot.h end

    dots =
      Enum.map(points, fn p ->
        %{
          cx: sx.(p.ed_pct),
          cy: sy.(clamp(p.value, y_min, y_max)),
          quadrant: p.quadrant,
          tooltip:
            "#{p.school_name}: ED #{p.ed_pct}% · #{format_value(p.value, y_unit)} (#{quadrant_label(p.quadrant)})"
        }
      end)

    crosshair = %{
      px: thresholds.ed_pct && sx.(thresholds.ed_pct),
      py: thresholds.value && sy.(clamp(thresholds.value, y_min, y_max))
    }

    trend =
      case regression do
        %{slope: slope, intercept: intercept} ->
          y1 = clamp(slope * x_min + intercept, y_min, y_max)
          y2 = clamp(slope * x_max + intercept, y_min, y_max)
          %{x1: sx.(x_min), y1: sy.(y1), x2: sx.(x_max), y2: sy.(y2)}

        nil ->
          nil
      end

    %{
      plot: @plot,
      dots: dots,
      crosshair: crosshair,
      trend: trend,
      x_ticks: Enum.map([0, 25, 50, 75, 100], fn v -> {round(v), sx.(v)} end),
      y_ticks: y_ticks(y_min, y_max, sy)
    }
  end

  defp auto_y_domain(_points, _thresholds, :percent), do: {0.0, 100.0}

  defp auto_y_domain(points, thresholds, :score) do
    values = Enum.map(points, & &1.value) ++ List.wrap(thresholds.value)

    case values do
      [] ->
        {400.0, 1600.0}

      _ ->
        min_v = Enum.min(values)
        max_v = Enum.max(values)
        pad = max((max_v - min_v) * 0.15, 20.0)
        {Float.floor(min_v - pad), Float.ceil(max_v + pad)}
    end
  end

  defp y_ticks(y_min, y_max, sy) do
    step = (y_max - y_min) / 4

    0..4
    |> Enum.map(fn i ->
      v = y_min + step * i
      {round(v), sy.(v)}
    end)
  end

  defp safe_ratio(_num, 0), do: 0.0
  defp safe_ratio(num, den), do: num / den

  defp clamp(v, min, _max) when v < min, do: min
  defp clamp(v, _min, max) when v > max, do: max
  defp clamp(v, _min, _max), do: v

  # ---------------------------------------------------------------------------
  # Presentation helpers
  # ---------------------------------------------------------------------------

  defp quadrant_fill_class(:green), do: "fill-success"
  defp quadrant_fill_class(:yellow), do: "fill-warning"
  defp quadrant_fill_class(:red), do: "fill-error"

  defp quadrant_text_class(:green), do: "text-success"
  defp quadrant_text_class(:yellow), do: "text-warning"
  defp quadrant_text_class(:red), do: "text-error"

  defp quadrant_label(:green), do: "Beating the odds"
  defp quadrant_label(:yellow), do: "As expected"
  defp quadrant_label(:red), do: "Underperforming despite advantage"

  defp legend_entries do
    [
      {"Beating the odds (high ED, high performance)", "bg-success"},
      {"As expected", "bg-warning"},
      {"Underperforming despite advantage (low ED, low performance)", "bg-error"}
    ]
  end

  defp format_value(nil, _unit), do: "—"
  defp format_value(v, :percent), do: "#{v}%"
  defp format_value(v, :score), do: "#{round(v)}"
end
