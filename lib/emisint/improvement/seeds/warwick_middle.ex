defmodule Emisint.Improvement.Seeds.WarwickMiddle do
  @moduledoc """
  Warwick Middle School (Warwick Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Warwick`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (pp.28-29); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.28-29"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Warwick

  def school do
    %{
      name: "Warwick Middle School",
      short_name: "Warwick Middle",
      slug: "warwick-middle-school",
      state: "ND",
      state_entity_id: "0302992192",
      district_name: "Warwick Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.28-29 (Warwick Middle School). No workbook goals, seasonal ratings or payment terms: those belong to Warwick Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.28-29)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (pp.28-29)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.12", "0.08"},
        {"2026-2027", "0.17", "0.13"},
        {"2027-2028", "0.22", "0.18"},
        {"2028-2029", "0.27", "0.24"},
        {"2029-2030", "0.33", "0.29"},
        {"2030-2031", "0.38", "0.35"}
      ],
      "North Dakota - ND First Schools.pdf pp.28-29 (Warwick Middle School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
    )
  end

  def comparison do
    Participant.building_comparison(%{
      participant: participant(),
      pdf_ref: @pdf_ref,
      annual_years: %{
        status: :confirmed,
        confirmation:
          "Confirmed by the user (recorded in PLAN_nd_first.md, November 8, 2026): the six targets map to 2025–2026 through 2030–2031, in order.",
        location: "North Dakota - ND First Schools.pdf p.28",
        excerpt: "“Using the assumed 2025–2026 through 2030–2031 sequence:”"
      },
      annual_note:
        "The plan (pp.28-29) lists annual targets “using the assumed 2025–2026 through 2030–2031 sequence”. Each target is compared only with this building's result for the same year (year mapping confirmed by the user); there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Warwick Middle School (North Dakota - ND First Schools.pdf pp.28-29) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Warwick Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf pp.28-29 lists Warwick Middle School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment)."
      ]
    })
  end
end
