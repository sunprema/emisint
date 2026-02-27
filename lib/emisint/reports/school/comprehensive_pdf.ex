defmodule Emisint.Reports.School.ComprehensivePdf do
  @template_path "priv/typst/school/comprehensive.typ"

  require Ash.Query

  @doc """
  Generates a PDF binary for the given school id.

  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  def generate_report(school_id, scope, _opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = build_data(school_id, scope)
    config = Imprintor.Config.new(template, data)
    Imprintor.compile_to_pdf(config)
  end

  # --- Data fetching ---

  defp build_data(school_id, scope) do
    school = fetch_school(school_id, scope)
    contract = fetch_contract(school_id, scope)
    academic_year = fetch_active_year(scope)
    all_snapshots = fetch_snapshots(school_id, scope)
    goals_with_evals = fetch_goals_with_evals(school_id, scope)
    triggers = fetch_triggers(school_id, scope)

    proficiency =
      all_snapshots |> Enum.filter(&(&1.snapshot_type == :school_wide)) |> serialize_snapshots()

    growth =
      all_snapshots
      |> Enum.filter(&(&1.snapshot_type == :by_grade))
      |> serialize_growth_snapshots()

    goals = serialize_goals(goals_with_evals)
    active_triggers = triggers |> Enum.filter(&(&1.status == :active)) |> serialize_triggers()

    %{
      school: %{
        name: school.name,
        city: school.city || "",
        mde_building_code: school.mde_building_code || "",
        report_date: Date.utc_today() |> Date.to_string()
      },
      contract: serialize_contract(contract),
      academic_year: (academic_year && academic_year.label) || "",
      proficiency: proficiency,
      growth: growth,
      goals: goals,
      active_triggers: active_triggers
    }
  end

  defp fetch_school(school_id, scope) do
    school =
      Emisint.Accounts.School
      |> Ash.Query.filter(id == ^school_id)
      |> Ash.read_one!(scope: scope)

    school || raise "School not found: #{school_id}"
  end

  defp fetch_contract(school_id, scope) do
    Emisint.Compliance.CharterContract
    |> Ash.Query.filter(school_id == ^school_id and status == :active)
    |> Ash.read!(scope: scope)
    |> List.first()
  end

  defp fetch_active_year(scope) do
    Emisint.Registry.AcademicYear
    |> Ash.read!(scope: scope)
    |> Enum.find(& &1.active)
  end

  defp fetch_snapshots(school_id, scope) do
    Emisint.Analytics.PerformanceSnapshot
    |> Ash.Query.filter(school_id == ^school_id)
    |> Ash.read!(scope: scope)
  end

  defp fetch_goals_with_evals(school_id, scope) do
    goals =
      Emisint.Compliance.Schedule71Goal
      |> Ash.Query.filter(school_id == ^school_id)
      |> Ash.read!(scope: scope)

    evaluations = Emisint.Compliance.GoalEvaluation |> Ash.read!(scope: scope)
    eval_by_goal = Map.new(evaluations, fn e -> {e.schedule71_goal_id, e} end)

    Enum.map(goals, fn goal -> {goal, Map.get(eval_by_goal, goal.id)} end)
  end

  defp fetch_triggers(school_id, scope) do
    Emisint.Analytics.InterventionTrigger
    |> Ash.Query.filter(school_id == ^school_id)
    |> Ash.read!(scope: scope)
  end

  # --- Serialization helpers ---

  defp serialize_contract(nil) do
    %{authorizer: "", start_date: "", end_date: "", status: ""}
  end

  defp serialize_contract(c) do
    %{
      authorizer: c.authorizer_name || "",
      start_date: format_date(c.contract_start_date),
      end_date: format_date(c.contract_end_date),
      status: to_string(c.status)
    }
  end

  defp serialize_snapshots(snapshots) do
    Enum.map(snapshots, fn s ->
      %{
        subject: s.subject || "",
        testing_window: to_string(s.testing_window),
        proficiency_rate: decimal_to_float(s.proficiency_rate),
        proficiency_pct: decimal_to_pct(s.proficiency_rate),
        student_count: s.student_count || 0
      }
    end)
  end

  defp serialize_growth_snapshots(snapshots) do
    snapshots
    |> Enum.sort_by(&{&1.grade_level, &1.subject})
    |> Enum.map(fn s ->
      %{
        grade_level: format_grade(s.grade_level),
        subject: s.subject || "",
        testing_window: to_string(s.testing_window),
        median_sgp: decimal_to_float(s.median_sgp),
        average_sgp: decimal_to_float(s.average_sgp),
        student_count: s.student_count || 0
      }
    end)
  end

  defp serialize_goals(goals_with_evals) do
    Enum.map(goals_with_evals, fn {goal, eval} ->
      %{
        title: goal.title || "",
        goal_type: goal.goal_type |> to_string() |> String.replace("_", " "),
        subject: goal.subject || "",
        status: eval_status_string(eval),
        actual_value: decimal_to_float(eval && eval.actual_value),
        target_value: decimal_to_float(goal.target_value)
      }
    end)
  end

  defp serialize_triggers(triggers) do
    triggers
    |> Enum.sort_by(&{severity_order(&1.severity), &1.triggered_at})
    |> Enum.map(fn t ->
      %{
        trigger_type: t.trigger_type |> to_string() |> String.replace("_", " "),
        severity: to_string(t.severity),
        triggered_at: format_datetime(t.triggered_at),
        notes: t.notes || ""
      }
    end)
  end

  defp eval_status_string(nil), do: "no data"
  defp eval_status_string(eval), do: to_string(eval.status)

  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(v) when is_float(v), do: v
  defp decimal_to_float(v) when is_integer(v), do: v * 1.0

  defp decimal_to_pct(nil), do: "—"

  defp decimal_to_pct(%Decimal{} = d) do
    pct = d |> Decimal.mult(100) |> Decimal.round(1) |> Decimal.to_string()
    "#{pct}%"
  end

  defp format_date(nil), do: ""
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y")

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_datetime(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y")
  defp format_datetime(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")

  defp format_grade("all"), do: "All"
  defp format_grade(g) when is_binary(g), do: String.upcase(g)
  defp format_grade(nil), do: ""

  defp severity_order(:high), do: 0
  defp severity_order(:medium), do: 1
  defp severity_order(:low), do: 2
  defp severity_order(_), do: 3
end
