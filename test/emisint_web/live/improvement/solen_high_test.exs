defmodule EmisintWeb.Improvement.SolenHighTest do
  @moduledoc """
  Solen High School as Cannon Ball's building subtab (user decision of
  November 12, 2026), and Cannon Ball's grade-group references.

  Fixtures in `cannon_ball/` are official rows copied unchanged: Solen High
  School (4300380363) publishes Grade 10 and All Grades in 2023-24 and no
  growth rows; Cannon Ball Elementary (4300312781) publishes grades 3–8.
  """
  # Never concurrent with other ND Insights imports (see Emisint.NdInsightsFixtures).
  use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  import Emisint.ImprovementFixtures
  import Emisint.NdInsightsFixtures
  import Phoenix.LiveViewTest

  require Ash.Query

  alias Emisint.Improvement.{ImplementationRating, Pilot, Seeds}
  alias Emisint.NdInsights.{Parser, StateResult}
  alias Emisint.Reports.School.NdFirstSchoolPdf

  @fixtures Path.expand("../../../fixtures/nd_insights/cannon_ball", __DIR__)
  @cannon_ball "/school-goals/cannon-ball-elementary"
  @solen "/school-goals/solen-high-school"

  setup %{conn: conn} do
    org =
      seeded_organization!(
        name: "ND First Solen High",
        schools: [Seeds.FortYates, Seeds.CannonBall, Seeds.SolenHigh],
        workbook_ratings?: true
      )

    sysadmin = user!(nil, :system_admin)

    %{
      org: org,
      admin: user!(org, :emo_admin),
      admin_conn: log_in(conn, sysadmin, %{"admin_org_id" => org.id})
    }
  end

  defp files, do: Path.wildcard(Path.join(@fixtures, "*.csv"))

  defp import!(org, id), do: import_insights!(files(), institution_ids: [id], tenant: org.id)

  defp rows(org, id) do
    StateResult
    |> Ash.Query.filter(institution_id == ^id)
    |> Ash.read!(tenant: org.id, authorize?: false)
    |> Enum.map(&Map.take(&1, [:id, :natural_key, :value_state, :value, :range_low, :range_high]))
    |> Enum.sort_by(& &1.id)
  end

  defp published(id) do
    files()
    |> Enum.map(fn path ->
      {:ok, parsed} =
        Parser.parse_file(path, institution_ids: [id], file_name: Path.basename(path))

      length(parsed.observations)
    end)
    |> Enum.sum()
  end

  defp scope(user, org), do: %Emisint.Scope{current_user: user, current_tenant: org.id}

  describe "record and navigation" do
    test "Solen High School is a building subtab of Cannon Ball, not a ninth participant", %{
      admin: admin,
      conn: conn
    } do
      assert Seeds.module_for("4300380363") == Seeds.SolenHigh
      assert "4300380363" in Pilot.institution_ids()
      assert length(Pilot.roster()) == 8

      {:ok, cb, _} = live(log_in(conn, admin), @cannon_ball)
      assert has_element?(cb, "#participant-nav", "Cannon Ball Elementary School")

      assert has_element?(
               cb,
               ~s(#participant-nav-cannon-ball-elementary[aria-current="page"]),
               "Cannon Ball Elementary School"
             )

      assert has_element?(cb, "#participant-nav-solen-high-school", "Solen High School")
      refute has_element?(cb, "#participant-nav", "District overview")
      assert has_element?(cb, "#participant-scope", "School participant with a separate building")
      refute has_element?(cb, "#participant-scope", "District participant")

      {:ok, solen, _} = live(log_in(conn, admin), @solen)
      # The Cannon Ball tab stays current; Solen High School is the current subtab.
      assert has_element?(solen, ~s(#nd-tab-cannon-ball-elementary[aria-current="page"]))
      refute has_element?(solen, "#nd-tab-solen-high-school")
      assert has_element?(solen, ~s(#participant-nav-solen-high-school[aria-current="page"]))
      assert has_element?(solen, "#building-scope", "Building of an ND First participant")
      assert has_element?(solen, "#building-scope-participant-goals", "labeled by grade")
      # No workbook goal tables, ratings or payment on the building.
      refute has_element?(solen, "#payment-card")
    end
  end

  describe "imports keep Cannon Ball's and Solen High School's data separate" do
    test "each import stores only its own InstitutionID, and neither changes the other", %{
      org: org
    } do
      import!(org, "4300312781")
      cannon_ball = rows(org, "4300312781")
      assert length(cannon_ball) == published("4300312781")
      assert rows(org, "4300380363") == []

      import!(org, "4300380363")
      assert length(rows(org, "4300380363")) == published("4300380363")
      # Cannon Ball's rows are byte-for-byte unchanged; the district is never stored.
      assert rows(org, "4300312781") == cannon_ball
      assert rows(org, "43003") == []

      # A repeated import creates nothing.
      reports = import!(org, "4300380363")
      assert Enum.sum(Enum.map(reports, & &1.created)) == 0
    end

    test "only system admins get the import button and page", %{
      org: org,
      admin: admin,
      admin_conn: sys,
      conn: conn
    } do
      {:ok, view, _} = live(sys, @solen)

      assert has_element?(
               view,
               ~s(#nd-import-link[href="/school-goals/solen-high-school/import"])
             )

      {:ok, page, _} = live(sys, "#{@solen}/import")
      assert has_element?(page, "#nd-locked-school-name", "Solen High School")
      assert has_element?(page, "#nd-locked-school-kind", "Building")
      assert has_element?(page, "#nd-locked-school-id", "4300380363")

      viewer = user!(org, :school_leader)
      membership!(viewer, school!(org, "solen-high-school"), :viewer, org)

      for user <- [admin, viewer] do
        {:ok, dashboard, _} = live(log_in(conn, user), @solen)
        refute has_element?(dashboard, "#nd-import-link")

        assert {:error, {:live_redirect, %{to: "/school-goals"}}} =
                 live(log_in(conn, user), "#{@solen}/import")
      end
    end
  end

  describe "colors and target explanations" do
    setup %{org: org} do
      import!(org, "4300312781")
      import!(org, "4300380363")
      :ok
    end

    test "Solen High School: Grade 10 against the grade-10 goals", %{admin: admin, conn: conn} do
      {:ok, view, _} = live(log_in(conn, admin), "#{@solen}?state_year=2023-2024&goal_ref=18m")

      grade10 = "#achievement-reading-10"
      # G1-M3: Proficient or Advanced 0%–40% vs 20%: overlaps.
      assert has_element?(
               view,
               ~s(#{grade10} [data-goal="G1-M3"][data-kind="workbook"][data-status="overlaps"]),
               "G1-M3 Grade 10 Reading Proficient or Advanced"
             )

      # G1-M6: Reading Novice 70%–79% vs 15%: above target.
      assert has_element?(
               view,
               ~s(#{grade10} [data-goal="G1-M6"][data-status="misses"]),
               "Above target"
             )

      assert has_element?(
               view,
               ~s(#achievement-math-10 [data-goal="G2-M6"][data-status="misses"])
             )

      # The All Grades row (the same students) carries no workbook goal.
      refute has_element?(view, ~s(#achievement-reading-all-grades [data-goal]))
      assert has_element?(view, "#goal-reference-note")
      assert has_element?(view, "#achievement-matching-note", "only Grade 10 is published")
      assert has_element?(view, "#growth-matching-note", "no growth rows")

      # The Standard view: no workbook verdict, and the confirmed basis is named.
      {:ok, reg, _} =
        live(log_in(conn, admin), "#{@solen}?state_year=2023-2024&state_type=Reg")

      refute has_element?(reg, ~s([data-goal="G1-M3"]))
      assert has_element?(reg, "#achievement-type-note", "(confirmed)")
    end

    test "a Solen High School-only viewer sees why no goal is compared", %{org: org, conn: conn} do
      viewer = user!(org, :school_leader)
      membership!(viewer, school!(org, "solen-high-school"), :viewer, org)

      {:ok, view, _} = live(log_in(conn, viewer), "#{@solen}?state_year=2023-2024")
      refute has_element?(view, "[data-goal]")

      assert has_element?(
               view,
               "#participant-goals-unavailable",
               "recorded on Cannon Ball Elementary School"
             )
    end

    test "Cannon Ball: grade-group references, labeled, and the All Grades row only annual", %{
      admin: admin,
      conn: conn
    } do
      {:ok, view, _} =
        live(log_in(conn, admin), "#{@cannon_ball}?state_year=2023-2024&goal_ref=18m")

      # Grade 4 Reading Novice 40%–49% vs G1-M4 (grades 3–5) 39%.
      assert has_element?(
               view,
               ~s(#achievement-reading-4 [data-goal="G1-M4"][data-kind="grade_group_reference"][data-status="misses"]),
               "Above grades 3–5 target"
             )

      assert has_element?(
               view,
               ~s(#achievement-reading-4 [data-goal="G1-M4"]),
               "Grades 3–5 target: 39%"
             )

      # Grade 7 uses the grades 6–8 target (G1-M5).
      assert has_element?(
               view,
               ~s(#achievement-reading-7 [data-goal="G1-M5"][data-kind="grade_group_reference"])
             )

      refute has_element?(view, ~s(#achievement-reading-all-grades [data-kind="workbook"]))

      refute has_element?(
               view,
               ~s(#achievement-reading-all-grades [data-kind="grade_group_reference"])
             )

      assert has_element?(view, "#achievement-goal-notes", "never averaged into one")

      # 2024-25 math growth: Meets or Exceeds, provisional.
      {:ok, growth, _} =
        live(log_in(conn, admin), "#{@cannon_ball}?state_year=2024-2025&goal_ref=18m")

      assert has_element?(
               growth,
               ~s(#growth-math-4 [data-goal="G2-M1"][data-kind="grade_group_reference"]),
               "provisional"
             )

      assert has_element?(
               growth,
               ~s(#growth-math-6 [data-goal="G2-M2"][data-status="meets"])
             )

      refute has_element?(growth, ~s(#growth-ela-4 [data-goal]))
    end

    test "PDFs carry the same comparisons and scope notes", %{org: org, admin: admin} do
      params = %{"state_year" => "2023-2024", "state_type" => "Comp", "goal_ref" => "18m"}

      {:ok, solen, _} = NdFirstSchoolPdf.build(scope(admin, org), "solen-high-school", params)
      assert solen.scope.kind == "building"
      assert solen.scope.note =~ "compared in the state results below"
      assert solen.report.goal_reference_text =~ "18-month target"
      assert solen.goals == []
      assert solen.annual == []

      [row] =
        Enum.filter(
          solen.state.achievement,
          &(&1.subject == "ELA (Reading)" and &1.grade == "10")
        )

      assert row.derived.line =~ "G1-M3 Grade 10 Reading Proficient or Advanced"
      assert row.derived.tone == "warning"
      assert row.novice.label == "Above target"

      [all] =
        Enum.filter(
          solen.state.achievement,
          &(&1.subject == "ELA (Reading)" and &1.grade == "All Grades")
        )

      assert all.novice.line == ""

      {:ok, cb, _} = NdFirstSchoolPdf.build(scope(admin, org), "cannon-ball-elementary", params)
      assert cb.scope.note =~ "School participant with a separate building"
      assert cb.scope.note =~ "Solen High School"

      [g4] =
        Enum.filter(cb.state.achievement, &(&1.subject == "ELA (Reading)" and &1.grade == "4"))

      assert g4.novice.label == "Above grades 3–5 target"
      assert g4.novice.line =~ "Grade-group reference"

      for slug <- ~w(solen-high-school cannon-ball-elementary) do
        assert {:ok, "%PDF" <> _, _} = NdFirstSchoolPdf.generate(scope(admin, org), slug, params)
      end
    end

    test "reference comparisons record nothing: ratings and payment are unchanged", %{
      org: org,
      admin: admin,
      conn: conn
    } do
      count = fn -> length(Ash.read!(ImplementationRating, tenant: org.id, authorize?: false)) end
      before = count.()

      for path <- [@cannon_ball, @solen], ref <- ~w(18m 36m) do
        {:ok, _view, _} =
          live(log_in(conn, admin), "#{path}?state_year=2023-2024&goal_ref=#{ref}")
      end

      assert count.() == before

      {:ok, view, _} = live(log_in(conn, admin), @cannon_ball)

      assert has_element?(
               view,
               "#payment-summary",
               "36-month review payment allocation needs confirmation"
             )
    end
  end
end
