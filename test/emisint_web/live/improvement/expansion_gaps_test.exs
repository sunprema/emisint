defmodule EmisintWeb.Improvement.ExpansionGapsTest do
  @moduledoc """
  Expansion gaps (November 8, 2026):

    * documented plan targets without an imported results dataset are kept and
      shown as written, with "Actual results unavailable" and no verdict;
    * Warwick's workbook scope is labeled provisional wherever it appears and
      nothing scope-dependent is calculated from it;
    * annual targets whose years the source only assumes keep their values but
      get no year-specific comparison.

  Fixtures in `expansion/` are official 2024-25 rows (see
  `ExpansionSchoolsTest`).
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.{PlanTargets, ResultGoals, Seeds}
  alias Emisint.Improvement.Seeds.Participant
  alias Emisint.NdInsights.SchoolResults
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @fixtures Path.expand("../../../fixtures/nd_insights/expansion", __DIR__)

  setup do
    org =
      seeded_organization!(
        name: "ND First gaps",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    import_insights!(Path.wildcard(Path.join(@fixtures, "*.csv")),
      institution_ids: ["34019", "3401919281", "3401919283", "1800189752"],
      tenant: org.id
    )

    %{org: org, admin: user!(org, :emo_admin)}
  end

  defp page(conn, admin, slug), do: live(log_in(conn, admin), "/school-goals/#{slug}")

  describe "plan targets without results" do
    test "the audited targets are recorded per school, as written" do
      ids = fn module -> module.school() |> PlanTargets.for_school() |> Enum.map(& &1.id) end

      assert ids.(Seeds.ValleyMiddle) ==
               ~w(measure-1-ela measure-1-math english-learner chronic-absenteeism)

      assert ids.(Seeds.DraytonElementary) == ~w(engagement-survey)

      assert ids.(Seeds.DraytonHigh) ==
               ~w(graduation-four-year graduation-six-year engagement-survey)

      assert ids.(Seeds.DunseithElementary) == ~w(writing)

      assert ids.(Seeds.DunseithHigh) ==
               ~w(graduation-four-year graduation-five-year graduation-six-year english-learner ccmr)

      assert ids.(Seeds.MandareeElementary) == ~w(kindergarten-readiness)

      assert ids.(Seeds.MandareeHigh) ==
               ~w(graduation-four-year graduation-five-year graduation-six-year)

      assert ids.(Seeds.WarwickHigh) ==
               ~w(graduation-four-year graduation-five-year graduation-six-year)

      for module <- [Seeds.FortYates, Seeds.Oberon, Seeds.Drayton, Seeds.WarwickMiddle] do
        assert ids.(module) == [], inspect(module)
      end

      # Values stay source text; nothing is mapped to a number.
      [el | _] =
        Seeds.ValleyMiddle.school()
        |> PlanTargets.for_school()
        |> Enum.filter(&(&1.id == "english-learner"))

      assert hd(el.targets) == {"2025–2026", "20%"}
      assert List.last(el.targets) == {"2030–2031", "71%"}
      assert el.status == :confirmed

      [six | _] =
        Seeds.WarwickHigh.school()
        |> PlanTargets.for_school()
        |> Enum.filter(&(&1.id == "graduation-six-year"))

      assert Enum.map(six.targets, &elem(&1, 1)) == ~w(92% 92% 92% 93% 93% 93%)
    end

    test "Valley shows its restored goals with no verdict", %{conn: conn, admin: admin} do
      {:ok, view, _html} = page(conn, admin, "valley-middle-school")

      assert has_element?(view, "#plan-target-measure-1-ela", "79%")
      assert has_element?(view, "#plan-target-measure-1-ela", "38% in 2023–2024")
      assert has_element?(view, ~s(#plan-target-measure-1-ela [data-plan-status="unresolved"]))

      assert has_element?(
               view,
               "#plan-target-measure-1-ela",
               "a separate target completion date is not specified"
             )

      assert has_element?(view, "#plan-target-english-learner", "Actual results unavailable")
      assert has_element?(view, "#plan-target-english-learner", "2030–2031:")

      assert has_element?(
               view,
               ~s(#plan-target-english-learner [data-plan-status="confirmed"])
             )

      assert has_element?(view, "#plan-target-chronic-absenteeism", "33%")
      assert has_element?(view, "#plan-target-chronic-absenteeism", "Actual results unavailable")

      # No comparison verdict anywhere in the section.
      refute has_element?(view, "#plan-targets [data-goal]")
      refute has_element?(view, "#plan-targets", "Meets target")
      refute has_element?(view, "#plan-targets", "Below target")
    end

    test "graduation and other restored targets on the buildings", %{conn: conn, admin: admin} do
      {:ok, mandaree, _} = page(conn, admin, "mandaree-high-school")

      assert has_element?(
               mandaree,
               ~s(#plan-target-graduation-four-year [data-plan-status="stated"])
             )

      assert has_element?(mandaree, "#plan-target-graduation-four-year", "71%")

      assert has_element?(
               mandaree,
               "#plan-target-graduation-four-year",
               "Actual results unavailable"
             )

      {:ok, dunseith, _} = page(conn, admin, "dunseith-high-school")

      assert has_element?(
               dunseith,
               ~s(#plan-target-english-learner [data-plan-status="unresolved"])
             )

      assert has_element?(
               dunseith,
               "#plan-target-english-learner",
               "confirm whether the graph measures"
             )

      assert has_element?(dunseith, ~s(#plan-target-ccmr [data-plan-status="no_numeric_target"]))

      {:ok, drayton, _} = page(conn, admin, "drayton-elementary")

      assert has_element?(
               drayton,
               ~s(#plan-target-engagement-survey [data-plan-status="unresolved"])
             )

      assert has_element?(drayton, "#plan-target-engagement-survey", "75%")

      {:ok, fort_yates, _} = page(conn, admin, "fort-yates-ms")
      refute has_element?(fort_yates, "#plan-targets")
    end
  end

  describe "Warwick's provisional workbook scope" do
    test "is labeled on the district and buildings, and nothing depends on it", %{
      conn: conn,
      admin: admin
    } do
      assert Participant.provisional_scope?(Participant.scope(Seeds.Warwick.school()))
      assert Participant.provisional_scope?(Participant.scope(Seeds.WarwickHigh.school()))
      refute Participant.provisional_scope?(Participant.scope(Seeds.Drayton.school()))

      {:ok, view, _} = page(conn, admin, "warwick-public-school-district")
      assert has_element?(view, "#workbook-scope-provisional", "Workbook scope provisional")
      assert has_element?(view, "#workbook-scope-provisional", "Warwick School")

      assert has_element?(
               view,
               "#participant-scope",
               "recorded on Warwick Public School District provisionally"
             )

      refute has_element?(view, "#participant-scope", "are written for")
      assert has_element?(view, "#workbook-scope-evidence", "fit no single scope")

      # No scope-dependent comparison or payment.
      assert ResultGoals.config(Seeds.Warwick.school()).workbook == []
      refute has_element?(view, "[data-goal][data-kind=workbook]")
      assert has_element?(view, "#payment-card", "not configured")

      {:ok, building, _} = page(conn, admin, "warwick-middle-school")
      assert has_element?(building, "#building-scope", "recorded provisionally on")
      assert has_element?(building, "#building-scope-provisional")

      {:ok, drayton, _} = page(conn, admin, "drayton-public-school-district")
      refute has_element?(drayton, "#workbook-scope-provisional")
      assert has_element?(drayton, "#participant-scope", "are written for")
    end

    test "is labeled in the PDF", %{org: org, admin: admin} do
      scope = %Emisint.Scope{current_user: admin, current_tenant: org.id}

      {:ok, district, _} = NdFirstSchoolPdf.build(scope, "warwick-public-school-district")
      assert district.scope.note =~ "recorded on Warwick Public School District provisionally"
      assert district.scope.provisional =~ "Workbook scope provisional"
      assert district.payment.combined == "Not configured"

      {:ok, building, _} = NdFirstSchoolPdf.build(scope, "warwick-high-school")
      assert building.scope.note =~ "recorded provisionally on Warwick Public School District"

      {:ok, drayton, _} = NdFirstSchoolPdf.build(scope, "drayton-public-school-district")
      assert drayton.scope.provisional == ""
    end
  end

  describe "uncertain annual target years" do
    # A same-year target for Valley's real 2024-25 Reading result: Proficient
    # 30% + Advanced 3% (both exact) = 33% derived.
    defp goal(year),
      do: %{
        school_year: year,
        subject: :ela,
        target_value: Decimal.new("0.30"),
        measure: :proficient_or_advanced,
        includes_alternate: true
      }

    test "an assumed year mapping keeps the target but makes no comparison", %{admin: admin} do
      rows = SchoolResults.load(admin, "1800189752").rows
      stated = %{annual_years: %{status: :stated, location: "p.x", excerpt: "x"}}
      assumed = %{annual_years: %{status: :assumed, location: "p.25", excerpt: "x"}}

      assert %{status: :meets, value: "33%"} = ResultGoals.annual(goal("2024-2025"), rows, stated)

      assert %{status: :year_unconfirmed, value: nil, tone: :muted, missing: missing} =
               ResultGoals.annual(goal("2024-2025"), rows, assumed)

      assert missing =~ "year mapping unconfirmed (p.25)"

      # The state table uses the school's own config: Valley's mapping is user-confirmed,
      # so its same-year cell is compared.
      plan = %{
        school: Seeds.ValleyMiddle.school(),
        metrics: [],
        annual_goals: [goal("2024-2025")]
      }

      filters = %{year: "2024-2025", type: "Comp", subgroup: "All"}
      cell = ResultGoals.for_filters(rows, filters, plan).achievement[{"Reading", "All Grades"}]
      assert cell[:proficient_or_advanced].status == :meets
    end

    test "each school's year mapping is recorded with its source" do
      status = fn module -> ResultGoals.config(module.school()).annual_years.status end

      for module <- [
            Seeds.FortYates,
            Seeds.Oberon,
            Seeds.DraytonElementary,
            Seeds.MandareeElementary,
            Seeds.MandareeHigh
          ] do
        assert status.(module) == :stated, inspect(module)
      end

      for module <- [
            Seeds.ValleyMiddle,
            Seeds.DraytonHigh,
            Seeds.DunseithElementary,
            Seeds.DunseithHigh,
            Seeds.WarwickElementary,
            Seeds.WarwickMiddle,
            Seeds.WarwickHigh
          ] do
        # Assumed in the source, confirmed by the user (2025–2026 through 2030–2031).
        assert %{status: :confirmed, confirmation: confirmation} =
                 ResultGoals.config(module.school()).annual_years,
               inspect(module)

        assert confirmation =~ "2025–2026 through 2030–2031"
      end

      # The source wording is kept beside the confirmation.
      assert ResultGoals.config(Seeds.ValleyMiddle.school()).annual_years.excerpt =~
               "Using the assumed 2025–2026 through 2030–2031 sequence"
    end

    test "a confirmed mapping compares only same-year results", %{admin: admin} do
      rows = SchoolResults.load(admin, "1800189752").rows
      config = ResultGoals.config(Seeds.ValleyMiddle.school())

      # Valley's real 2024-25 Reading result (33%, exact) against a same-year target.
      assert %{status: :meets} = ResultGoals.annual(goal("2024-2025"), rows, config)

      # A 2025-26 target is never compared with the 2024-25 result.
      assert %{
               status: :not_published,
               value: nil,
               missing: "No matching results in the imported data"
             } =
               ResultGoals.annual(goal("2025-2026"), rows, config)
    end

    test "dashboards label the mapping; stated schools are unchanged", %{conn: conn, admin: admin} do
      {:ok, valley, _} = page(conn, admin, "valley-middle-school")
      assert has_element?(valley, ~s(#annual-year-mapping[data-year-mapping="confirmed"]))
      assert has_element?(valley, "#annual-year-mapping", "confirmed by the user")
      assert has_element?(valley, "#annual-2025-2026", "37%")

      assert has_element?(
               valley,
               "#annual-2025-2026-ela",
               "No matching results in the imported data"
             )

      refute has_element?(valley, ~s([data-status="year_unconfirmed"]))

      {:ok, elementary, _} = page(conn, admin, "drayton-elementary")
      assert has_element?(elementary, ~s(#annual-year-mapping[data-year-mapping="stated"]))

      assert has_element?(
               elementary,
               "#annual-2025-2026-ela",
               "No matching results in the imported data"
             )

      {:ok, oberon, _} = page(conn, admin, "oberon-elementary")
      assert has_element?(oberon, ~s(#annual-year-mapping[data-year-mapping="stated"]))
      refute has_element?(oberon, ~s([data-status="year_unconfirmed"]))
    end

    test "the PDF shows the mapping, the targets and the restored goals", %{
      org: org,
      admin: admin
    } do
      scope = %Emisint.Scope{current_user: admin, current_tenant: org.id}

      {:ok, valley, _} = NdFirstSchoolPdf.build(scope, "valley-middle-school")
      assert valley.annual_year_mapping =~ "Year mapping confirmed by the user"
      assert hd(valley.annual).ela_goal == "37%"
      assert hd(valley.annual).ela_published == "No matching results in the imported data"
      assert hd(valley.annual).ela_tone == "neutral"
      assert Enum.map(valley.plan_targets, & &1.title) |> hd() =~ "Measure 1"
      assert Enum.all?(valley.plan_targets, &(&1.results_note != ""))

      {:ok, fort_yates, _} = NdFirstSchoolPdf.build(scope, "fort-yates-ms")
      assert fort_yates.annual_year_mapping =~ "as stated in the source"
      assert fort_yates.plan_targets == []

      for slug <- ~w(valley-middle-school warwick-public-school-district dunseith-high-school) do
        assert {:ok, "%PDF" <> _, _} = NdFirstSchoolPdf.generate(scope, slug)
      end
    end
  end
end
