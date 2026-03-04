defmodule Emisint.Analytics.HealthScore do
  @moduledoc """
  Computes a 0–100 composite Academic Credit Score for a school.

  This is an internal analytics tool and does not reflect official MDE ratings.

  ## Scoring Formula

  | Component     | Weight | Source               |
  |---------------|--------|----------------------|
  | Proficiency   | 40 pts | PerformanceSnapshot  |
  | SGP (Growth)  | 30 pts | PerformanceSnapshot  |
  | Compliance    | 20 pts | GoalEvaluation       |
  | Interventions | 10 pts | InterventionTrigger  |
  """

  @proficiency_weight 40
  @sgp_weight 30
  @compliance_weight 20
  @intervention_max 10

  # Preferred window order: spring > winter > fall
  @window_order ["spring", "winter", "fall"]

  @doc """
  Computes the health score for a single school.

  ## Parameters

    - `school_id` — UUID of the school (unused in computation, kept for interface clarity)
    - `snapshots` — list of `PerformanceSnapshot` records for this school
    - `goal_evals` — list of `GoalEvaluation` records for this school
    - `active_triggers` — list of active `InterventionTrigger` records for this school

  ## Returns

  A map with:
    - `:score` — Float 0–100
    - `:grade` — "A" | "B" | "C" | "D" | "F"
    - `:proficiency_pts` — Float 0–40
    - `:sgp_pts` — Float 0–30
    - `:compliance_pts` — Float 0–20
    - `:intervention_pts` — Float 0–10
  """
  def compute(_school_id, snapshots, goal_evals, active_triggers) do
    proficiency_pts = compute_proficiency(snapshots)
    sgp_pts = compute_sgp(snapshots)
    compliance_pts = compute_compliance(goal_evals)
    intervention_pts = compute_interventions(active_triggers)

    score = Float.round(proficiency_pts + sgp_pts + compliance_pts + intervention_pts, 1)

    %{
      score: score,
      grade: grade(score),
      proficiency_pts: proficiency_pts,
      sgp_pts: sgp_pts,
      compliance_pts: compliance_pts,
      intervention_pts: intervention_pts
    }
  end

  # --- Private ---

  # proficiency_rate is a Decimal in [0, 1], e.g. 0.65 means 65% proficient
  defp compute_proficiency(snapshots) do
    relevant = best_window_snapshots(snapshots, :school_wide, ["ela", "math"])

    case decimal_values(relevant, :proficiency_rate) do
      [] -> 0.0
      vals -> Float.round(avg(vals) * @proficiency_weight, 2)
    end
  end

  # median_sgp is a Decimal in [0, 100] (percentile)
  defp compute_sgp(snapshots) do
    relevant = best_window_snapshots(snapshots, :school_wide, ["ela", "math"])

    case decimal_values(relevant, :median_sgp) do
      [] -> 0.0
      vals -> Float.round(avg(vals) / 100.0 * @sgp_weight, 2)
    end
  end

  defp compute_compliance(goal_evals) do
    non_insufficient = Enum.reject(goal_evals, &(&1.status == :insufficient_data))

    case length(non_insufficient) do
      0 ->
        0.0

      total ->
        met = Enum.count(non_insufficient, &(&1.status in [:meets, :exceeds]))
        Float.round(met / total * @compliance_weight, 2)
    end
  end

  defp compute_interventions(active_triggers) do
    penalty = Enum.reduce(active_triggers, 0, fn t, acc -> acc + severity_penalty(t.severity) end)
    max(0, @intervention_max - penalty) * 1.0
  end

  # For each subject, pick the best available window snapshot
  defp best_window_snapshots(snapshots, type, subjects) do
    Enum.flat_map(subjects, fn subject ->
      matching =
        Enum.filter(snapshots, fn s ->
          s.snapshot_type == type and to_string(s.subject) == subject
        end)

      case find_best_window(matching) do
        nil -> []
        snap -> [snap]
      end
    end)
  end

  defp find_best_window(snapshots) do
    Enum.find_value(@window_order, fn window ->
      Enum.find(snapshots, &(to_string(&1.testing_window) == window))
    end)
  end

  defp decimal_values(snapshots, field) do
    snapshots
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Decimal.to_float/1)
  end

  defp avg(vals), do: Enum.sum(vals) / length(vals)

  defp severity_penalty(:high), do: 4
  defp severity_penalty(:medium), do: 2
  defp severity_penalty(:low), do: 1
  defp severity_penalty(_), do: 0

  defp grade(score) when score >= 80, do: "A"
  defp grade(score) when score >= 65, do: "B"
  defp grade(score) when score >= 50, do: "C"
  defp grade(score) when score >= 35, do: "D"
  defp grade(_), do: "F"
end
