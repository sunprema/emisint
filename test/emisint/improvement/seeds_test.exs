defmodule Emisint.Improvement.SeedsTest do
  # Not async: one test toggles the :allow_dev_seeds application env.
  use Emisint.DataCase, async: false

  import Emisint.ImprovementFixtures

  require Ash.Query

  alias Emisint.Accounts.{Organization, School, SchoolMembership}

  alias Emisint.Improvement.{
    AnnualAssessmentGoal,
    Goal,
    GoalPlan,
    ImplementationRating,
    Metric,
    ReportingPeriod,
    Seeds
  }

  defp read!(resource, org), do: Ash.read!(resource, tenant: org.id, authorize?: false)

  # These tests describe the Fort Yates definitions; other schools have their own tests below.
  defp run(org_id, opts \\ []),
    do: Seeds.run(org_id, Keyword.put_new(opts, :schools, [Seeds.FortYates]))

  describe "organization requirement" do
    test "refuses to run without an explicit, existing organization" do
      assert {:error, "an explicit organization ID is required"} = Seeds.run(nil)
      assert {:error, "an explicit organization ID is required"} = Seeds.run("")
      assert {:error, message} = Seeds.run(Ash.UUID.generate())
      assert message =~ "does not exist"
    end

    test "never creates an organization for a production seed" do
      before = length(Ash.read!(Organization, authorize?: false))
      Seeds.run(Ash.UUID.generate())
      assert length(Ash.read!(Organization, authorize?: false)) == before
    end
  end

  describe "Fort Yates definitions" do
    setup do
      %{org: seeded_organization!()}
    end

    test "school identity matches ND Insights", %{org: org} do
      assert [school] = read!(School, org)
      assert school.name == "Fort Yates Middle School"
      assert school.state == "ND"
      assert school.state_entity_id == "4300429212"
      assert school.district_name == "Ft Yates Public School District"
    end

    test "4 goals, 18 metrics (8 Systems, 10 Student Outcome), 11 periods, 12 annual goals", %{
      org: org
    } do
      assert length(read!(Goal, org)) == 4

      metrics = read!(Metric, org)
      assert length(metrics) == 18
      assert Enum.count(metrics, &(&1.category == :systems)) == 8
      assert Enum.count(metrics, &(&1.category == :student_outcome)) == 10

      periods = read!(ReportingPeriod, org)
      assert length(periods) == 11
      assert Enum.count(periods, &(&1.kind == :seasonal)) == 9

      assert Enum.map(Enum.reject(periods, &(&1.kind == :seasonal)), & &1.code) |> Enum.sort() ==
               ["review_18m", "review_36m"]

      assert length(read!(AnnualAssessmentGoal, org)) == 12
    end

    test "payment rule inputs are stored on the plan", %{org: org} do
      assert [plan] = read!(GoalPlan, org)
      assert Decimal.equal?(plan.systems_weight, "0.70")
      assert Decimal.equal?(plan.outcomes_weight, "0.30")
      assert Decimal.equal?(plan.payment_cap, "70000")
      assert plan.max_rating == 3
    end

    test "lower-is-better metrics are exactly the novice and disengagement metrics", %{org: org} do
      lower =
        org
        |> then(&read!(Metric, &1))
        |> Enum.filter(&(&1.direction == :lower_is_better))
        |> Enum.map(& &1.code)
        |> Enum.sort()

      assert lower == ["G2-M2", "G3-M2", "G4-M2", "G4-M3", "G4-M4"]
    end

    test "Proficient is not Proficient or Advanced", %{org: org} do
      assert metric!(org, "G2-M1").performance_measure == :proficient
      assert metric!(org, "G3-M1").performance_measure == :proficient
      assert Enum.all?(read!(AnnualAssessmentGoal, org), &(&1.measure == :proficient_or_advanced))
    end

    test "P7 and P16 keep raw values, leave target_36m unset and are flagged", %{org: org} do
      for {code, cell, raw} <- [
            {"G1-M4", "Ft Yates Goals!P7", "90"},
            {"G2-M4", "Ft Yates Goals!P16", "80"}
          ] do
        metric = metric!(org, code)
        assert metric.target_36m == nil
        assert :target_36m_needs_confirmation in metric.flags
        assert metric.source_values["target_36m"] == %{"cell" => cell, "raw" => raw}
        assert Decimal.equal?(metric.target_18m, if(code == "G1-M4", do: "0.7", else: "0.5"))
      end

      flagged =
        org
        |> then(&read!(Metric, &1))
        |> Enum.filter(&(:target_36m_needs_confirmation in &1.flags))

      assert Enum.map(flagged, & &1.code) |> Enum.sort() == ["G1-M4", "G2-M4"]
    end

    test "every normalized percentage is within 0–1", %{org: org} do
      percent_metrics = Enum.filter(read!(Metric, org), &(&1.unit == :percent))

      values =
        Enum.flat_map(percent_metrics, &[&1.baseline_value, &1.target_18m, &1.target_36m]) ++
          Enum.map(read!(AnnualAssessmentGoal, org), & &1.target_value)

      for %Decimal{} = value <- values do
        assert Decimal.compare(value, 0) != :lt and Decimal.compare(value, 1) != :gt
      end
    end

    test "spot values match the workbook and PDF", %{org: org} do
      g4m2 = metric!(org, "G4-M2")
      assert Decimal.equal?(g4m2.baseline_value, "0.429")
      assert Decimal.equal?(g4m2.target_18m, "0.329")
      assert Decimal.equal?(g4m2.target_36m, "0.229")

      ela_2031 =
        AnnualAssessmentGoal
        |> Ash.Query.filter(school_year == "2030-2031" and subject == :ela)
        |> Ash.read_one!(tenant: org.id, authorize?: false)

      assert Decimal.equal?(ela_2031.target_value, "0.47")
    end

    test "Goal 4 metrics carry the unconfirmed review column flag", %{org: org} do
      flagged =
        org
        |> then(&read!(Metric, &1))
        |> Enum.filter(&(:review_18m_column_heading_unconfirmed in &1.flags))
        |> Enum.map(& &1.code)
        |> Enum.sort()

      assert flagged == ["G4-M1", "G4-M2", "G4-M3", "G4-M4"]
    end

    test "metric definitions are read-only (no update or destroy actions)" do
      for resource <- [GoalPlan, Goal, Metric, ReportingPeriod, AnnualAssessmentGoal, School] do
        types = resource |> Ash.Resource.Info.actions() |> Enum.map(& &1.type)
        refute :destroy in types, "#{inspect(resource)} has a destroy action"

        # Metric's one update applies a recorded unit decision and GoalPlan's
        # sets the payment terms; both are system only (see
        # GrowthPercentileTest and PaymentEstimateTest for the policy checks).
        updates =
          for %{type: :update, name: name} <- Ash.Resource.Info.actions(resource), do: name

        expected =
          case resource do
            Metric -> [:apply_unit_decision]
            GoalPlan -> [:set_payment_terms]
            _ -> []
          end

        assert updates == expected, "#{inspect(resource)} has update actions #{inspect(updates)}"
      end
    end
  end

  describe "idempotence and drift" do
    test "re-running creates nothing and reports everything unchanged" do
      org = organization!()
      assert {:ok, first} = run(org.id)
      assert first.drift == []
      assert length(first.created) > 0

      assert {:ok, second} = run(org.id)
      assert second.created == []
      assert second.drift == []
      assert length(second.unchanged) == length(first.created)

      assert length(read!(Metric, org)) == 18
      assert length(read!(ImplementationRating, org)) == 36
    end

    test "a later change to a definition is reported as drift and not overwritten" do
      org = seeded_organization!()
      metric = metric!(org, "G1-M1")
      Ash.Seed.update!(metric, %{target_18m: Decimal.new("0.85")})

      assert {:ok, report} = run(org.id, workbook_ratings?: false)
      assert [%{record: record, fields: %{target_18m: {actual, expected}}}] = report.drift
      assert record =~ "G1-M1"
      assert Decimal.equal?(actual, "0.85")
      assert Decimal.equal?(expected, "0.9")

      assert Decimal.equal?(metric!(org, "G1-M1").target_18m, "0.85")
    end
  end

  describe "historical workbook ratings" do
    test "imports Spr '26 and Sum '26 with unknown author and separate dates" do
      org = organization!()
      importer = user!(org, :emo_admin)
      started_at = DateTime.utc_now()

      assert {:ok, _report} = run(org.id, actor: importer)

      ratings = read!(ImplementationRating, org)
      assert length(ratings) == 36

      for rating <- ratings do
        assert rating.source == :workbook_import
        assert rating.kind == :observation
        assert rating.author_id == nil
        assert rating.measurement_date == nil
        assert rating.source_last_updated_on == ~D[2026-08-18]
        assert rating.recorded_by_id == importer.id
        assert DateTime.compare(rating.recorded_at, started_at) != :lt
        assert rating.source_ref =~ ~r/^Ft Yates Goals![EF]\d+$/
      end
    end

    test "recorded_by is nil when no importing actor is given" do
      org = organization!()
      assert {:ok, _} = run(org.id)
      assert Enum.all?(read!(ImplementationRating, org), &is_nil(&1.recorded_by_id))
    end

    test "seasonal category averages match the workbook's Goals Dashboard" do
      org = organization!()
      assert {:ok, _} = run(org.id)

      metrics = Map.new(read!(Metric, org), &{&1.id, &1})
      periods = Map.new(read!(ReportingPeriod, org), &{&1.id, &1.code})

      averages =
        org
        |> then(&read!(ImplementationRating, &1))
        |> Enum.group_by(
          &{periods[&1.reporting_period_id], metrics[&1.metric_id].category},
          & &1.score
        )
        |> Map.new(fn {key, scores} -> {key, Enum.sum(scores) / length(scores)} end)

      # Goals Dashboard!E5:H5 cached values
      assert averages[{"spr_26", :systems}] == 1.25
      assert averages[{"spr_26", :student_outcome}] == 1.6
      assert averages[{"sum_26", :systems}] == 1.375
      assert averages[{"sum_26", :student_outcome}] == 1.6
    end

    test "re-running leaves later corrections intact" do
      org = organization!()
      assert {:ok, _} = run(org.id)
      contributor = contributor!(org)

      original =
        ImplementationRating
        |> Ash.Query.filter(
          metric_id == ^metric!(org, "G1-M1").id and
            reporting_period_id == ^period!(org, "spr_26").id
        )
        |> Ash.read_one!(tenant: org.id, authorize?: false)

      correction =
        Ash.create!(
          ImplementationRating,
          %{
            corrects_id: original.id,
            rating_state: :rated,
            score: 2,
            correction_reason: "Reviewed evidence"
          },
          action: :correct,
          tenant: org.id,
          actor: contributor
        )

      assert {:ok, report} = run(org.id)
      assert report.created == []
      assert report.drift == []

      assert length(read!(ImplementationRating, org)) == 37

      current =
        Ash.read!(ImplementationRating, action: :current, tenant: org.id, authorize?: false)

      assert correction.id in Enum.map(current, & &1.id)
      refute original.id in Enum.map(current, & &1.id)
    end
  end

  describe "development organization" do
    test "is clearly labeled, reused, and refused when dev seeds are disabled" do
      org = Seeds.ensure_dev_organization!()
      assert org.name == "ND First Pilot — Development"
      assert Seeds.ensure_dev_organization!().id == org.id

      Application.put_env(:emisint, :allow_dev_seeds, false)
      on_exit(fn -> Application.put_env(:emisint, :allow_dev_seeds, true) end)

      assert_raise RuntimeError, ~r/disabled/, fn -> Seeds.ensure_dev_organization!() end
      assert_raise RuntimeError, ~r/disabled/, fn -> Seeds.ensure_dev_users!(org) end
    end

    test "creates demo users and memberships idempotently" do
      org = Seeds.ensure_dev_organization!()
      {:ok, _} = run(org.id)

      first = Seeds.ensure_dev_users!(org)
      assert first.drift == []
      assert length(first.created) == 6

      second = Seeds.ensure_dev_users!(org)
      assert second.created == []
      assert length(second.unchanged) == 6

      roles = org |> then(&read!(SchoolMembership, &1)) |> Enum.map(& &1.role) |> Enum.sort()
      assert roles == [:contributor, :viewer]
    end

    test "renames earlier demo accounts in place, keeping id, password and memberships" do
      org = Seeds.ensure_dev_organization!()
      {:ok, _} = run(org.id)

      legacy =
        Ash.Seed.seed!(Emisint.Accounts.User, %{
          email: "nd-first-contributor@example.com",
          hashed_password: "existing-hash",
          role: :school_leader,
          organization_id: org.id
        })

      membership!(legacy, school!(org), :contributor, org)

      report = Seeds.ensure_dev_users!(org)
      assert "user nd-first-contributor@example.com → school@example.com" in report.renamed
      assert report.drift == []

      renamed = Ash.get!(Emisint.Accounts.User, legacy.id, authorize?: false)
      assert to_string(renamed.email) == "school@example.com"
      assert renamed.hashed_password == "existing-hash"
      assert renamed.organization_id == org.id
      assert renamed.role == :school_leader

      assert [%{role: :contributor}] =
               SchoolMembership
               |> Ash.Query.filter(user_id == ^legacy.id)
               |> Ash.read!(tenant: org.id, authorize?: false)

      # Re-running neither recreates the old address nor renames again.
      again = Seeds.ensure_dev_users!(org)
      assert again.renamed == [] and again.created == [] and again.drift == []

      emails =
        Emisint.Accounts.User |> Ash.read!(authorize?: false) |> Enum.map(&to_string(&1.email))

      refute "nd-first-contributor@example.com" in emails
    end

    test "never overwrites or merges an unrelated account that already uses a new address" do
      org = Seeds.ensure_dev_organization!()
      {:ok, _} = run(org.id)
      other_org = organization!("Someone else")

      unrelated =
        Ash.Seed.seed!(Emisint.Accounts.User, %{
          email: "admin@example.com",
          hashed_password: "theirs",
          role: :school_leader,
          organization_id: other_org.id
        })

      legacy =
        Ash.Seed.seed!(Emisint.Accounts.User, %{
          email: "nd-first-admin@example.com",
          hashed_password: "demo",
          role: :emo_admin,
          organization_id: org.id
        })

      report = Seeds.ensure_dev_users!(org)
      assert Enum.any?(report.drift, &(&1.record == "user admin@example.com"))
      refute Enum.any?(report.renamed, &String.contains?(&1, "admin@example.com"))

      assert %{hashed_password: "theirs", organization_id: other_id} =
               Ash.get!(Emisint.Accounts.User, unrelated.id, authorize?: false)

      assert other_id == other_org.id

      assert to_string(Ash.get!(Emisint.Accounts.User, legacy.id, authorize?: false).email) ==
               "nd-first-admin@example.com"
    end
  end

  describe "additional ND First schools (deferred for expansion)" do
    setup do
      org = organization!()
      {:ok, report} = Seeds.run(org.id, schools: Seeds.available_schools())
      %{org: org, report: report}
    end

    defp school_metrics(org, slug) do
      school = school!(org, slug)

      Metric
      |> Ash.Query.filter(school_id == ^school.id)
      |> Ash.read!(tenant: org.id, authorize?: false)
      |> Map.new(&{&1.code, &1})
    end

    test "the default seeds only the Fort Yates pilot" do
      org = organization!()
      {:ok, _report} = Seeds.run(org.id)

      assert Seeds.schools() == [Seeds.FortYates]
      assert org |> then(&read!(School, &1)) |> Enum.map(& &1.slug) == ["fort-yates-ms"]
    end

    test "seeds every verified record when asked", %{org: org, report: report} do
      assert report.drift == []

      ids = org |> then(&read!(School, &1)) |> Map.new(&{&1.slug, &1.state_entity_id})

      assert ids == %{
               "fort-yates-ms" => "4300429212",
               "oberon-elementary" => "0301662261",
               "valley-middle-school" => "1800189752",
               "drayton-public-school-district" => "34019",
               "drayton-elementary" => "3401919281",
               "drayton-high-school" => "3401919283",
               "dunseith-public-school-district" => "40001",
               "dunseith-elementary" => "4000119681",
               "dunseith-high-school" => "4000119663",
               "mandaree-public-school-district" => "27036",
               "mandaree-elementary" => "2703654591",
               "mandaree-high-school" => "2703654593",
               "warwick-public-school-district" => "03029",
               "warwick-elementary" => "0302992191",
               "warwick-middle-school" => "0302992192",
               "warwick-high-school" => "0302992193",
               "cannon-ball-elementary" => "4300312781"
             }
    end

    test "Oberon uses its own sheet: 4 goals, 21 metrics, own targets and districts", %{org: org} do
      school = school!(org, "oberon-elementary")
      assert school.district_name == "Oberon Public School District"
      # Insights offers no grade-level filter for Oberon, so the band is not guessed.
      assert school.grade_span == nil

      metrics = school_metrics(org, "oberon-elementary")
      assert map_size(metrics) == 21
      assert Decimal.equal?(metrics["G1-M1"].baseline_value, "0.16")
      assert Decimal.equal?(metrics["G1-M1"].target_36m, "0.3")
      assert metrics["G1-M1"].source_values["baseline"]["cell"] == "Oberon Goals!D4"
    end

    test "non-numeric and date cells stay verbatim and unset", %{org: org} do
      oberon = school_metrics(org, "oberon-elementary")

      # "60-64%" baseline, "50-54%" target: kept as text, never a midpoint.
      g3m2 = oberon["G3-M2"]
      assert g3m2.baseline_value == nil and g3m2.target_18m == nil
      assert g3m2.source_values["baseline"]["raw"] == "60-64%"
      assert :value_as_text in g3m2.flags

      # Excel dates where a teacher count is expected are flagged, not used.
      g4m7 = oberon["G4-M7"]
      assert g4m7.unit == :count
      assert g4m7.target_18m == nil
      assert :source_value_is_date in g4m7.flags

      valley = school_metrics(org, "valley-middle-school")
      assert valley["G1-M2"].source_values["target_18m"]["raw"] == "> 50%"
      assert valley["G7-M2"].unit == :text
      assert valley["G7-M2"].source_values["target_36m"]["raw"] == "Utilized"
    end

    test "the review-column flag follows each goal's own heading", %{org: org} do
      oberon = school_metrics(org, "oberon-elementary")

      # Oberon Goal 1 is headed "18-Month Review Rating" (I3); Goals 2-4 "Target Check".
      refute :review_18m_column_heading_unconfirmed in oberon["G1-M1"].flags
      assert :review_18m_column_heading_unconfirmed in oberon["G2-M1"].flags

      assert oberon["G2-M1"].source_values["review_18m_heading"] == %{
               "cell" => "Oberon Goals!I12",
               "raw" => "Target Check"
             }
    end

    test "N/A workbook ratings are stored as not applicable, never scored", %{org: org} do
      valley = school_metrics(org, "valley-middle-school")
      spr = period_for(org, "valley-middle-school", "spr_26")

      [rating] =
        ImplementationRating
        |> Ash.Query.filter(metric_id == ^valley["G1-M3"].id and reporting_period_id == ^spr.id)
        |> Ash.read!(tenant: org.id, authorize?: false)

      assert rating.rating_state == :not_applicable
      assert rating.score == nil
      assert rating.source_ref == "Valley Goals!E6"
      assert rating.source_last_updated_on == ~D[2026-08-28]
    end

    test "annual targets come from each school's own PDF page", %{org: org} do
      for {slug, year, ela, math} <- [
            {"oberon-elementary", "2023-2024", "0.22", "0.22"},
            {"valley-middle-school", "2030-2031", "0.55", "0.51"}
          ] do
        school = school!(org, slug)

        goals =
          AnnualAssessmentGoal
          |> Ash.Query.filter(school_id == ^school.id and school_year == ^year)
          |> Ash.read!(tenant: org.id, authorize?: false)
          |> Map.new(&{&1.subject, &1})

        assert Decimal.equal?(goals[:ela].target_value, ela)
        assert Decimal.equal?(goals[:math].target_value, math)
      end
    end

    test "implementation step counts stored as text in the workbook are kept", %{org: org} do
      school = school!(org, "valley-middle-school")

      goal =
        Goal
        |> Ash.Query.filter(school_id == ^school.id and number == 1)
        |> Ash.read_one!(tenant: org.id, authorize?: false)

      # Valley Goals!E2:G2 hold '1', '2', '2' as text.
      assert goal.implementation_steps == %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2}
    end

    test "re-running seeds every school without duplicates", %{org: org} do
      assert {:ok, again} = Seeds.run(org.id)
      assert again.created == [] and again.drift == []
    end

    defp period_for(org, slug, code) do
      school = school!(org, slug)

      ReportingPeriod
      |> Ash.Query.filter(school_id == ^school.id and code == ^code)
      |> Ash.read_one!(tenant: org.id, authorize?: false)
    end
  end
end
