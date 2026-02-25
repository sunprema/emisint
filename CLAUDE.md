# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
mix setup              # Full setup: deps, ash.setup, assets, seeds
mix phx.server         # Start dev server at localhost:4000
mix test               # Run all tests (runs ash.setup --quiet first)
mix test path/to/test.exs            # Run a single test file
mix test path/to/test.exs:42         # Run a specific test at line
mix format             # Format all code (Styler, Spark, Tailwind, HEEx)
mix dialyzer           # Static type analysis
mix ash.setup          # Run migrations + Ash introspection
mix ash.reset          # Drop, create, migrate, seed
mix ash.codegen <name> # Use Ash Code gen for creatin migrations, replace name appropriate for the change.
mix ash.migrate        # Run Ash migration.
```

## Architecture

**Emisint** is a specialized SaaS platform designed for Michigan Charter School Management Companies (EMOs) and Authorizers. The **Academic Performance Module (APM)** serves as the core engine, providing real-time visibility into student achievement, contractual compliance (Schedule 7-1), and state-level accountability.
Its built on **Ash Framework + Phoenix LiveView + PostgreSQL + Ash Authentication + Ash Oban + Daisy UI**.

### Domain Structure (Ash Domains)

Each domain is an `Ash.Domain` containing related `Ash.Resource` modules:


### Resource Pattern

All domain entities are Ash Resources using `AshPostgres.DataLayer` with `Ash.Policy.Authorizer`. Business logic is encoded as Ash actions with custom changes (in `changes/` subdirectories) and validations. Domain modules define code interface functions via `:define`.


Here are the Ash Resources for **Emisint**, organized by Domain.

In Ash Framework (especially version 3.0+), **Domains** are the entry points that group related resources. Here are the Emisint resources organized by valid Elixir/Ash Domain names.

| Ash Domain | Resource | Description |
| :--- | :--- | :--- |
| **`Accounts`** | `Organization` | The primary tenant (EMO or Authorizer). Controls data isolation and global settings. |
| | `School` | Represents a specific Academy (PSA) including its official MDE District and Building codes. |
| | `User` | Platform users with granular roles (e.g., EMO Admin, School Leader) governed by Ash Policies. |
| **`Registry`** | `Student` | Individual student records mapped to the Michigan Unique Identification Code (UIC). |
| | `AcademicYear` | Defines the specific school year and the fall/winter/spring testing windows. |
| | `Enrollment` | Tracks which school/grade a student is assigned to for a given academic year. |
| **`Assessments`** | `AssessmentResult` | Stores raw scores, Scale Scores, and SGPs for M-STEP, PSAT, SAT, and interim tests (NWEA/i-Ready). |
| | `BenchmarkProvider` | Metadata for non-state tests defining scoring norms and proficiency thresholds. |
| | `CompetitorData` | Aggregated performance data of local traditional districts used for side-by-side comparison. |
| **`Compliance`** | `CharterContract` | Stores the legal timeframe and reauthorization terms between the Authorizer and the Board. |
| | `Schedule71Goal` | The digitized KPIs from the contract (e.g., "Outperform local district" or "Median SGP targets"). |
| | `GoalEvaluation` | A calculation-heavy resource that computes whether live performance meets `Schedule71Goal` targets. |
| **`Analytics`** | `PerformanceSnapshot` | Pre-calculated data aggregates (e.g., proficiency by grade) used to power high-speed dashboards. |
| | `DataSyncLog` | An audit trail of all background jobs (Oban) pulling data from MiDataHub or manual CSV uploads. |
| | `AuditLog` | Powered by `AshPaperTrail`; tracks every manual change to scores or goals for legal transparency. |
| | `InterventionTrigger` | Flags specific students or cohorts trending toward non-compliance with Schedule 7-1 targets. |

### Technical Note on Implementation:
In your Elixir code, these domains will correspond to modules like `Emisint.Accounts`, `Emisint.Assessments`, etc. Each resource (e.g., `Emisint.Assessments.AssessmentResult`) will be mapped inside its respective domain file to define the public API for that context.

### Web Layer

- **Router**: `lib/emisint_web/router.ex`
- **LiveViews**: `lib/emisint_web/live/` — main app pages (overview, products, orders, inventory, batches, etc.)
- **Components**: `lib/emisint_web/components/` — reusable UI (core, forms, data_vis, page, layouts)
- Auth via `on_mount` hooks using AshAuthenticationPhoenix




## Formatting & Style

- **Styler** enforces Elixir code style (AST-based linter + formatter)
- **Spark.Formatter** handles Ash DSL block ordering (section order defined in config)
- **TailwindFormatter** orders CSS classes
- **Phoenix.LiveView.HTMLFormatter** formats HEEx templates
- All four run via `mix format`

## Commit Convention

Commits follow the pattern: `type(scope): description` (e.g., `feat(batching):`, `ui(production):`, `fix(orders):`)


# Emisint: Academic Performance Module (APM)
**High-Level Requirements Document**

## 1. Project Overview
**Emisint** is a specialized SaaS platform designed for Michigan Charter School Management Companies (EMOs) and Authorizers. The **Academic Performance Module (APM)** serves as the core engine, providing real-time visibility into student achievement, contractual compliance (Schedule 7-1), and state-level accountability.

## 2. Target User Personas
*   **EMO Academic Officer:** Monitors a portfolio of schools to ensure they meet contract goals and identifies schools needing intervention.
*   **Authorizer Liaison:** Verifies that the Academy is meeting the legal academic requirements defined in the charter contract.
*   **School Principal:** Drills down into grade-level and subgroup data to adjust instructional strategies.

---

## 3. Functional Requirements

### 3.1 Schedule 7-1 Contractual Compliance Tracker
*   **Digital Goal Registry:** Capability to digitize and store unique "Schedule 7-1" goals for every school in the portfolio (e.g., CMU vs. GVSU targets).
*   **Automated Evaluation:** Use **Ash Calculations** to compare live test data against specific contract thresholds (e.g., "Median SGP $\ge$ 50th Percentile").
*   **Status Indicators:** Visual "Traffic Light" system (Exceeds, Meets, Approaching, Below) for every contractual goal.

### 3.2 State Accountability & Proficiency (M-STEP/PSAT/SAT)
*   **Proficiency Analysis:** Aggregation of Michigan state assessment results by school, grade, and subject (ELA, Math, Science, Social Studies).
*   **Subgroup Heatmaps:** Comparative views for ESSA-defined subgroups (Economically Disadvantaged, English Learners, Students with Disabilities).
*   **Longitudinal Tracking:** 3–5 year trend lines to visualize performance trajectory across cohorts.

### 3.3 Growth & Interim Benchmarking (SGP/NWEA/i-Ready)
*   **Student Growth Percentile (SGP) Monitor:** Tracking of growth metrics which are heavily weighted by Michigan authorizers.
*   **Interim-to-State Correlation:** Ingestion of benchmark data (NWEA MAP, i-Ready) to provide mid-year "Early Warnings" of potential M-STEP failure.
*   **Growth-to-Target:** Visualization of how many students are on track to meet their individual "Catch-up" or "Keep-up" growth targets.

### 3.4 Comparative Peer Benchmarking
*   **District-to-Academy Engine:** Automatic ingestion of MDE public data to compare Academy performance against the local traditional district (as required by most Schedule 7-1 contracts).
*   **Virtual Peer Grouping:** Ability to benchmark against a custom "composite district" or a selection of schools with similar demographics.

### 3.5 Automated Reporting & Exports
*   **Reauthorization Packet Generator:** One-click generation of the multi-year academic data evidence required for charter renewal hearings.
*   **Board Report Builder:** Exportable, presentation-ready charts for monthly school board meetings.

---

## 4. Data & Technical Requirements

### 4.1 Data Ingestion (The "Michigan Connector")
*   **MiDataHub Integration:** Primary automated data source for student demographics and state assessment results via the Ed-Fi API.
*   **CSV Upload Utility:** Robust fallback importer for NWEA/i-Ready exports with automated data mapping/validation.
*   **Async Processing:** Utilization of **Oban** for background data syncing to ensure the UI remains responsive during large data ingestions.

### 4.2 Multi-Tenancy & Security
*   **Strict Isolation:** Use **Ash Framework’s attribute-based multi-tenancy** to ensure EMO "A" can never see EMO "B" data.
*   **Policy-Based Access (RBAC):** Granular permissions ensuring Authorizers see "Portfolio Views" while School Leaders see "Student-Level Views."
*   **Audit Trail:** Immutable logging via **Ash Paper Trail** for every change made to a school’s performance goals or data records.

### 4.3 UI/UX Standards
*   **LiveView Dashboards:** Real-time updates to KPI gauges and charts without page refreshes.
*   **Mobile-First Drill-down:** Fully responsive design allowing EMO executives to check school performance on-the-go.

---

## 5. Success Metrics for Emisint
1.  **Time Savings:** Reduce the time spent preparing Authorizer "Annual Performance Reports" by 80%.
2.  **Accuracy:** Zero discrepancies between Emisint-calculated SGP and official MDE-reported growth.
3.  **Proactive Intervention:** Identify schools "At Risk" of non-compliance at least 4 months before state index scores are released.