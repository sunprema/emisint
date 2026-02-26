# =============================================================================
# Emisint Development Seeds
#
# Populates the database with a realistic demo dataset for local development.
# Run with:
#   mix run priv/repo/seeds.exs
#   (or as part of: mix ash.reset)
#
# Idempotent: skips if an organization with slug "cornerstone-emo" already exists.
# =============================================================================

import Ecto.Query

alias Emisint.Accounts.{Organization, School, User}
alias Emisint.Analytics.{DataSyncLog, InterventionTrigger, PerformanceSnapshot}
alias Emisint.Assessments.AssessmentResult
alias Emisint.Compliance.{CharterContract, GoalEvaluation, Schedule71Goal}
alias Emisint.Registry.{AcademicYear, Enrollment, Student}
alias Emisint.Workers.{GoalRecalculationWorker, SnapshotRefreshWorker}

# ── Idempotency check ──────────────────────────────────────────────────────────

existing_orgs = Ash.read!(Organization, authorize?: false)

if Enum.any?(existing_orgs, &(&1.slug == "cornerstone-emo")) do
  IO.puts("Seeds already applied — skipping. Run `mix ash.reset` to start fresh.")
else
  IO.puts("Seeding Emisint demo data…")

  # ── Organization ────────────────────────────────────────────────────────────

  org =
    Ash.create!(
      Organization,
      %{
        name: "Cornerstone Education Management",
        type: :emo,
        slug: "cornerstone-emo"
      },
      authorize?: false
    )

  IO.puts("  ✓ Organization: #{org.name}")

  oid = org.id

  # ── Schools ─────────────────────────────────────────────────────────────────

  school1 =
    Ash.create!(
      School,
      %{
        name: "Great Lakes Academy",
        mde_district_code: "25010",
        mde_building_code: "25010-1001",
        city: "Flint",
        county: "Genesee",
        active: true
      },
      tenant: oid,
      authorize?: false
    )

  school2 =
    Ash.create!(
      School,
      %{
        name: "Riverside Charter Academy",
        mde_district_code: "25020",
        mde_building_code: "25020-2001",
        city: "Saginaw",
        county: "Saginaw",
        active: true
      },
      tenant: oid,
      authorize?: false
    )

  IO.puts("  ✓ Schools: #{school1.name}, #{school2.name}")

  # ── Academic Year ───────────────────────────────────────────────────────────

  year =
    Ash.create!(
      AcademicYear,
      %{
        label: "2024-2025",
        start_date: ~D[2024-09-03],
        end_date: ~D[2025-06-13],
        fall_window_start: ~D[2024-09-16],
        fall_window_end: ~D[2024-10-18],
        winter_window_start: ~D[2025-01-06],
        winter_window_end: ~D[2025-02-07],
        spring_window_start: ~D[2025-04-07],
        spring_window_end: ~D[2025-05-09],
        active: true
      },
      tenant: oid,
      authorize?: false
    )

  IO.puts("  ✓ Academic Year: #{year.label}")

  # ── Helper: create + confirm a user ─────────────────────────────────────────

  create_user = fn email, role, school_id ->
    {:ok, user} =
      Ash.create(
        User,
        %{
          email: email,
          password: "Password123!",
          password_confirmation: "Password123!"
        },
        action: :register_with_password,
        authorize?: false
      )

    Ash.update!(user, %{organization_id: oid, role: role, school_id: school_id},
      action: :assign_organization,
      authorize?: false
    )

    # Mark email confirmed so the user can sign in immediately
    user
    |> Ash.Changeset.for_update(:assign_organization, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(
      :confirmed_at,
      DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Ash.update!()

    user
  end

  _admin = create_user.("admin@cornerstone-emo.edu", :emo_admin, nil)
  _principal = create_user.("principal@greatlakes.edu", :school_leader, school1.id)
  _authorizer = create_user.("authorizer@cmu.edu", :authorizer_liaison, nil)

  IO.puts("  ✓ Users: admin, school leader, authorizer (all password: Password123!)")

  # ── Students — Great Lakes Academy (school1) ─────────────────────────────────

  school1_students =
    Enum.map(1..12, fn i ->
      uic = "GLA#{String.pad_leading(Integer.to_string(i), 4, "0")}"

      student =
        Ash.create!(
          Student,
          %{
            uic: uic,
            first_name:
              Enum.at(
                [
                  "Ava",
                  "Ben",
                  "Cara",
                  "Dev",
                  "Eva",
                  "Finn",
                  "Grace",
                  "Hiro",
                  "Iris",
                  "Jay",
                  "Kai",
                  "Lena"
                ],
                i - 1
              ),
            last_name: "Demo",
            economically_disadvantaged: i <= 5,
            english_learner: i in [3, 6, 9],
            special_education: i in [2, 7]
          },
          tenant: oid,
          authorize?: false
        )

      Ash.create!(
        Enrollment,
        %{
          grade_level:
            Enum.at([:g3, :g4, :g5, :g6, :g7, :g8, :g3, :g4, :g5, :g6, :g7, :g8], i - 1),
          enrolled_at: ~D[2024-09-03],
          student_id: student.id,
          school_id: school1.id,
          academic_year_id: year.id
        },
        tenant: oid,
        authorize?: false
      )

      student
    end)

  # School2 students (fewer — represents a smaller school)
  school2_students =
    Enum.map(1..6, fn i ->
      uic = "RCA#{String.pad_leading(Integer.to_string(i), 4, "0")}"

      student =
        Ash.create!(
          Student,
          %{
            uic: uic,
            first_name: Enum.at(["Noah", "Mia", "Liam", "Zoe", "Omar", "Pia"], i - 1),
            last_name: "Demo"
          },
          tenant: oid,
          authorize?: false
        )

      Ash.create!(
        Enrollment,
        %{
          grade_level: Enum.at([:g4, :g5, :g6, :g4, :g5, :g6], i - 1),
          enrolled_at: ~D[2024-09-03],
          student_id: student.id,
          school_id: school2.id,
          academic_year_id: year.id
        },
        tenant: oid,
        authorize?: false
      )

      student
    end)

  IO.puts(
    "  ✓ Students: #{length(school1_students)} (Great Lakes), #{length(school2_students)} (Riverside)"
  )

  # ── Assessment Results — School 1 ───────────────────────────────────────────
  # Spring M-STEP: 9 of 12 proficient (75% rate), median SGP = 54

  spring_mstep_data = [
    # {proficiency_level, sgp}
    {"4", 68},
    {"3", 55},
    {"4", 72},
    {"3", 54},
    {"2", 38},
    {"4", 61},
    {"3", 58},
    {"1", 28},
    {"4", 66},
    {"3", 52},
    {"4", 70},
    {"2", 35}
  ]

  Enum.each(Enum.zip(school1_students, spring_mstep_data), fn {student, {level, sgp}} ->
    Ash.create!(
      AssessmentResult,
      %{
        assessment_type: :m_step,
        subject: "math",
        testing_window: :spring,
        proficiency_level: level,
        sgp: sgp,
        scale_score: Decimal.new(Integer.to_string(2200 + sgp * 5)),
        test_date: ~D[2025-04-22],
        source: "MDE MiDataHub",
        student_id: student.id,
        academic_year_id: year.id
      },
      tenant: oid,
      authorize?: false
    )
  end)

  # Fall NWEA MAP results for school1
  fall_nwea_data = [
    {218, 58},
    {205, 44},
    {222, 65},
    {210, 50},
    {198, 34},
    {215, 54},
    {208, 48},
    {195, 29},
    {220, 62},
    {212, 51},
    {219, 60},
    {196, 32}
  ]

  Enum.each(Enum.zip(school1_students, fall_nwea_data), fn {student, {rit, sgp}} ->
    Ash.create!(
      AssessmentResult,
      %{
        assessment_type: :nwea_map,
        subject: "math",
        testing_window: :fall,
        scale_score: Decimal.new(rit),
        sgp: sgp,
        percentile: div(sgp, 2) + 20,
        test_date: ~D[2024-10-08],
        source: "NWEA MAP CSV",
        student_id: student.id,
        academic_year_id: year.id
      },
      tenant: oid,
      authorize?: false
    )
  end)

  # School2: spring ELA results — below target (50% proficiency, median SGP 42)
  ela_data_s2 = [
    {"3", 45},
    {"2", 38},
    {"4", 55},
    {"2", 35},
    {"1", 28},
    {"3", 47}
  ]

  Enum.each(Enum.zip(school2_students, ela_data_s2), fn {student, {level, sgp}} ->
    Ash.create!(
      AssessmentResult,
      %{
        assessment_type: :m_step,
        subject: "ela",
        testing_window: :spring,
        proficiency_level: level,
        sgp: sgp,
        test_date: ~D[2025-04-23],
        source: "MDE MiDataHub",
        student_id: student.id,
        academic_year_id: year.id
      },
      tenant: oid,
      authorize?: false
    )
  end)

  IO.puts("  ✓ Assessment results loaded (M-STEP + NWEA MAP)")

  # ── Charter Contracts ───────────────────────────────────────────────────────

  contract1 =
    Ash.create!(
      CharterContract,
      %{
        authorizer_name: "Central Michigan University",
        contract_start_date: ~D[2019-07-01],
        contract_end_date: ~D[2024-06-30],
        reauthorization_date: ~D[2024-04-01],
        status: :active,
        school_id: school1.id
      },
      tenant: oid,
      authorize?: false
    )

  contract2 =
    Ash.create!(
      CharterContract,
      %{
        authorizer_name: "Grand Valley State University",
        contract_start_date: ~D[2020-07-01],
        contract_end_date: ~D[2025-06-30],
        reauthorization_date: ~D[2025-04-01],
        status: :active,
        school_id: school2.id
      },
      tenant: oid,
      authorize?: false
    )

  IO.puts("  ✓ Charter contracts created")

  # ── Schedule 7-1 Goals ──────────────────────────────────────────────────────

  # School1 goals (expected to meet)
  _goal1_s1 =
    Ash.create!(
      Schedule71Goal,
      %{
        title: "Math Proficiency ≥ 65% (Spring M-STEP)",
        goal_type: :proficiency_threshold,
        subject: "math",
        grade_levels: ["g3", "g4", "g5", "g6", "g7", "g8"],
        testing_window: :spring,
        assessment_type: :m_step,
        target_value: Decimal.new("0.65"),
        exceeds_threshold: Decimal.new("0.80"),
        approaching_threshold: Decimal.new("0.55"),
        comparison_operator: :gte,
        school_id: school1.id,
        charter_contract_id: contract1.id
      },
      tenant: oid,
      authorize?: false
    )

  _goal2_s1 =
    Ash.create!(
      Schedule71Goal,
      %{
        title: "Median Student Growth Percentile ≥ 50th (Math, Spring M-STEP)",
        goal_type: :sgp_median,
        subject: "math",
        grade_levels: [],
        testing_window: :spring,
        assessment_type: :m_step,
        target_value: Decimal.new("50"),
        exceeds_threshold: Decimal.new("60"),
        approaching_threshold: Decimal.new("40"),
        comparison_operator: :gte,
        school_id: school1.id,
        charter_contract_id: contract1.id
      },
      tenant: oid,
      authorize?: false
    )

  # School2 goals (ELA — expected to be below/approaching)
  _goal1_s2 =
    Ash.create!(
      Schedule71Goal,
      %{
        title: "ELA Proficiency ≥ 60% (Spring M-STEP)",
        goal_type: :proficiency_threshold,
        subject: "ela",
        grade_levels: [],
        testing_window: :spring,
        assessment_type: :m_step,
        target_value: Decimal.new("0.60"),
        approaching_threshold: Decimal.new("0.45"),
        comparison_operator: :gte,
        school_id: school2.id,
        charter_contract_id: contract2.id
      },
      tenant: oid,
      authorize?: false
    )

  _goal2_s2 =
    Ash.create!(
      Schedule71Goal,
      %{
        title: "Median SGP ≥ 50th (ELA, Spring M-STEP)",
        goal_type: :sgp_median,
        subject: "ela",
        grade_levels: [],
        testing_window: :spring,
        assessment_type: :m_step,
        target_value: Decimal.new("50"),
        approaching_threshold: Decimal.new("40"),
        comparison_operator: :gte,
        school_id: school2.id,
        charter_contract_id: contract2.id
      },
      tenant: oid,
      authorize?: false
    )

  IO.puts("  ✓ Schedule 7-1 goals configured")

  # ── Run workers to populate snapshots + goal evaluations ────────────────────

  IO.puts("  Running SnapshotRefreshWorker for both schools…")

  SnapshotRefreshWorker.perform(%Oban.Job{
    args: %{
      "organization_id" => oid,
      "school_id" => school1.id,
      "academic_year_id" => year.id
    }
  })

  SnapshotRefreshWorker.perform(%Oban.Job{
    args: %{
      "organization_id" => oid,
      "school_id" => school2.id,
      "academic_year_id" => year.id
    }
  })

  IO.puts("  Running GoalRecalculationWorker for both schools…")

  GoalRecalculationWorker.perform(%Oban.Job{
    args: %{
      "organization_id" => oid,
      "school_id" => school1.id,
      "academic_year_id" => year.id
    }
  })

  GoalRecalculationWorker.perform(%Oban.Job{
    args: %{
      "organization_id" => oid,
      "school_id" => school2.id,
      "academic_year_id" => year.id
    }
  })

  # Print summary
  snapshots = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
  evals = Ash.read!(GoalEvaluation, tenant: oid, authorize?: false)
  triggers = Ash.read!(InterventionTrigger, tenant: oid, authorize?: false)

  IO.puts("""

  ═══════════════════════════════════════════════════════
  ✓ Emisint demo data seeded successfully!

  Organization : Cornerstone Education Management
  Schools      : 2 (Great Lakes Academy, Riverside Charter Academy)
  Academic Year: 2024-2025
  Students     : #{length(school1_students) + length(school2_students)}
  Snapshots    : #{length(snapshots)}
  Goal Evals   : #{length(evals)}
  Interventions: #{length(triggers)} active

  Sign in at http://localhost:4000/sign-in
    EMO Admin       admin@cornerstone-emo.edu / Password123!
    School Leader   principal@greatlakes.edu  / Password123!
    Authorizer      authorizer@cmu.edu        / Password123!
  ═══════════════════════════════════════════════════════
  """)
end
