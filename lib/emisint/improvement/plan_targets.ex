defmodule Emisint.Improvement.PlanTargets do
  @moduledoc """
  Continuous-improvement-plan targets (`North Dakota - ND First Schools.pdf`)
  that are not annual Proficient-or-Advanced targets: graduation, English
  Learner, attendance, writing, readiness and engagement goals, and targets
  without a stated completion year.

  They are definitions kept in each school's seed module (`plan_targets/0`),
  read-only like the other definitions, and shown as written: values stay
  source text, never mapped to numbers. None is compared with a result:

    * `:stated` — targets and years as stated in the source;
    * `:confirmed` — the source assumed the years; the user confirmed them
      (2025–2026 through 2030–2031, recorded November 8, 2026);
    * `:year_unconfirmed` — the source assumes the year of each target;
    * `:unresolved` — the source leaves the date or definition open;
    * `:no_numeric_target` — the source names measures but no target.

  Each target also says why no result is shown (`results_note`), e.g. the
  measure isn't in the imported ND Insights datasets.
  """

  alias Emisint.Improvement.Seeds

  @years ~w(2025–2026 2026–2027 2027–2028 2028–2029 2029–2030 2030–2031)

  @doc "The plan targets of a school record (`[]` when none are recorded)."
  def for_school(%{state_entity_id: id}) do
    module = Seeds.module_for(id)

    if module && function_exported?(module, :plan_targets, 0),
      do: module.plan_targets(),
      else: []
  end

  def for_school(_school), do: []

  @doc "Six annual values as written, labeled 2025–2026 through 2030–2031 (as in the source)."
  def six_years(values) when length(values) == 6, do: Enum.zip(@years, values)

  @doc "Short status label."
  def status_label(:stated), do: "Targets as stated in the source"
  def status_label(:confirmed), do: "Years confirmed by the user"
  def status_label(:year_unconfirmed), do: "Year mapping unconfirmed"
  def status_label(:unresolved), do: "Unresolved"
  def status_label(:no_numeric_target), do: "No numeric target in the source"
end
