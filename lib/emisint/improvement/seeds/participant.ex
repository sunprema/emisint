defmodule Emisint.Improvement.Seeds.Participant do
  @moduledoc """
  ND First participants whose workbook goals are written for a district
  rather than one building (Drayton, Dunseith, Mandaree, Warwick).

  The sources split by scope, and nothing is copied between scopes:

    * **Participant (district) record:** the workbook sheet's goals, metrics,
      baselines, targets and seasonal ratings, the payment row
      ("Performance-Based Payment" lists one row per participant), and the
      district's own published ND Insights rows (5-digit InstitutionID).
    * **Building records:** the annual Proficient-or-Advanced targets that
      `North Dakota - ND First Schools.pdf` lists per building, compared only
      with that building's own published rows. A building has no workbook
      goals, seasonal ratings or payment terms.

  District goals are never duplicated across buildings, building results are
  never averaged or combined into a district value, and each published row is
  shown only on the record of its own InstitutionID.

  A participant module defines `buildings/0` (building modules, in PDF
  order). A building module defines `participant/0` (its participant module).
  """

  alias Emisint.Improvement.Seeds

  @doc """
  The goal plan of a building record: it holds only the building's annual
  targets, so no payment cap, weights or allocations are set.
  """
  def building_plan(source_note) do
    %{
      program: "nd_first_mou",
      name: "ND First annual targets (building)",
      definition_version: 1,
      progress_doc_url: nil,
      payment_cap: nil,
      systems_weight: nil,
      outcomes_weight: nil,
      max_rating: 3,
      source_note: source_note
    }
  end

  @doc """
  Annual Proficient-or-Advanced targets from `[{year, ela, math}]` (0–1
  strings), including the alternate assessment as the PDF states.
  """
  def annual_goals(rows, source_ref) do
    rows
    |> Enum.flat_map(fn {year, ela, math} -> [{year, :ela, ela}, {year, :math, math}] end)
    |> Enum.map(fn {year, subject, target} ->
      %{
        school_year: year,
        subject: subject,
        target_value: Decimal.new(target),
        measure: :proficient_or_advanced,
        includes_alternate: true,
        source_ref: source_ref
      }
    end)
  end

  @doc """
  The comparison configuration of a building record: no workbook metric is
  matched (the workbook goals belong to the participant), only the
  building's own annual targets.
  """
  def building_comparison(%{participant: participant, pdf_ref: pdf_ref} = opts) do
    name = participant.school().name

    %{
      plan_start_year: "2025-2026",
      workbook: [],
      assumptions: %{},
      grade_reference: nil,
      matching:
        "This building has no workbook goals: the ND First workbook goals are written for #{name} and appear on its dashboard. Only this building's annual Proficient-or-Advanced targets (#{pdf_ref}) are compared, each with this building's own published result for the same school year (all grades, all students, Combined assessment). District results and other buildings' results are never used.",
      assumptions_text: "No assumptions are applied.",
      assumptions_short: "No assumptions: only this building's own annual targets are compared.",
      section_notes: %{
        achievement:
          "No workbook goal applies to this building (the workbook goals are set for #{name}). Where an annual target exists for the same school year, the Proficient or Advanced cell shows that comparison.",
        growth: "No school goal applies to this building's growth results.",
        engagement: "No school goal applies to this building's Engagement Survey results."
      },
      annual_note: opts[:annual_note],
      annual_years: opts[:annual_years],
      report_notes: Map.get(opts, :report_notes, [])
    }
  end

  @doc """
  Where a school record sits among the ND First participants:

    * `%{kind: :participant, buildings: [module]}` — a district participant;
    * `%{kind: :building, participant: module}` — a building of one;
    * `%{kind: :school}` — a single-building participant (or unknown).
  """
  def scope(%{state_entity_id: id}) do
    module = Seeds.module_for(id)

    cond do
      module && function_exported?(module, :buildings, 0) ->
        %{
          kind: :participant,
          buildings: module.buildings(),
          workbook_scope: workbook_scope(module)
        }

      module && function_exported?(module, :participant, 0) ->
        participant = module.participant()
        %{kind: :building, participant: participant, workbook_scope: workbook_scope(participant)}

      true ->
        %{kind: :school}
    end
  end

  def scope(_school), do: %{kind: :school}

  @doc """
  How well the sources support recording a participant's workbook goals on
  its district record: `%{status: :source_supported | :provisional, excerpt:,
  note:, evidence:}`. `:provisional` (Warwick) must be labeled wherever the
  goals appear, and nothing scope-dependent is calculated from it.
  """
  def workbook_scope(module) do
    if function_exported?(module, :workbook_scope, 0),
      do: module.workbook_scope(),
      else: %{status: :source_supported, excerpt: nil, note: nil, evidence: []}
  end

  @doc "True when the participant's workbook scope is provisional."
  def provisional_scope?(%{workbook_scope: %{status: :provisional}}), do: true
  def provisional_scope?(_scope), do: false
end
