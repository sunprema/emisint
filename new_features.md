# Emisint — New Feature Ideas

These features are all buildable from data already in the system.

---

## 1. Cohort Trajectory Tracker
**What:** Follow a group of students across years (e.g., the "Class of 2027" from 3rd grade through 8th), showing how their M-STEP scores and SGPs evolve longitudinally.
**Data:** `AssessmentResult` + `Enrollment` (grade_level + academic_year_id chain) + `Student`
**Why it's powerful:** Authorizers care deeply about multi-year trend lines. This makes cohort mobility visible — which kids stayed on track vs. regressed.

---

## 2. Subgroup Heatmap Dashboard
**What:** A color-coded grid showing proficiency rates across all ESSA subgroups (Econ. Disadvantaged, ELL, SPED, gender) broken down by grade and subject.
**Data:** `PerformanceSnapshot` (subgroup dimension already exists) + `MdeEnrollmentResult` (enrollment counts by subgroup/race/grade)
**Why it's powerful:** Federal ESSA accountability requires subgroup disaggregation. This view makes gaps immediately visible without any new data ingestion.

---

## 3. Early Warning System — "Will We Miss the Goal?"
**What:** For each Schedule 7-1 goal, use fall/winter interim benchmark data (NWEA/i-Ready) to project whether the school is on pace to meet the spring M-STEP target.
**Data:** `AssessmentResult` (nwea_map/i_ready fall+winter) correlated to prior-year `AssessmentResult` (m_step spring) → project spring proficiency
**Why it's powerful:** CLAUDE.md explicitly calls this out: "Identify schools At Risk of non-compliance at least 4 months before state index scores are released." This directly fulfills that requirement.

---

## 4. Student-Level Drill-Down ("Who Are the Students Behind the Numbers?")
**What:** Click a PerformanceSnapshot cell (e.g., Grade 5 Math = 42% proficient) to see the actual student roster — names, scores, growth percentiles — with ESSA flags.
**Data:** `Student` + `Enrollment` (filter by grade) + `AssessmentResult` (filter by subject/year) + subgroup flags
**Why it's powerful:** School principals need student-level visibility to drive instructional interventions. Currently all views are aggregate-only.

---

## 5. Virtual Peer Group Benchmarking
**What:** Let an EMO admin build a custom "comparison group" — pick 3–5 MDE building IDs — and compare their school's proficiency against that virtual district average.
**Data:** `MdeStateAssessmentResult` (statewide public data by building) + `CompetitorData` (already exists for this purpose)
**Why it's powerful:** Many Schedule 7-1 contracts require outperforming a *specific* local district, but EMOs also want informal peer comparisons. No new data import needed — MDE data already loaded.

---

## 6. Reauthorization Evidence Packet Generator
**What:** One-click PDF/HTML report that assembles: 3-year proficiency trends, SGP history, goal compliance summary, demographic enrollment data, and competitive benchmarks — formatted for a charter renewal hearing.
**Data:** All domains, filtered by school + date range
**Why it's powerful:** Explicitly listed as a success metric in the requirements doc. This alone could justify the product's subscription price for an EMO.

---

## 7. SGP Distribution Histogram
**What:** Show the full distribution of Student Growth Percentiles (1–99) for a school, with median highlighted. Overlay the prior-year distribution for comparison.
**Data:** `AssessmentResult.sgp` — already stored per student; just needs a histogram bucketing calculation
**Why it's powerful:** A median SGP of 52 looks fine — until you see that 40% of students are below 30. The distribution tells the real story. Authorizers specifically focus on SGP.

---

## 8. Intervention Recommendation Engine
**What:** When an `InterventionTrigger` fires (e.g., "SGP below target"), show *which specific students* are driving the trigger and suggest a tiered response (Tier 1/2/3 support).
**Data:** `InterventionTrigger` + `AssessmentResult` (lowest SGPs in the flagged school/grade) + `Student` (ESSA subgroup flags for prioritization)
**Why it's powerful:** Right now triggers are school-level flags. This makes them actionable for teachers and principals — "Here are the 12 students to focus on this quarter."

---

## 9. Goal Timeline & History View
**What:** Show the full edit history of a Schedule 7-1 goal — who changed what threshold, when, and why — alongside the goal's evaluation status at each point in time.
**Data:** `AshPaperTrail` versions already captured on `Schedule71Goal` — just need a UI to surface them
**Why it's powerful:** Legal defensibility. If a target was quietly lowered before the school "met" it, an authorizer can see that. Already collected — zero new data needed.

---

## 10. Board Meeting Dashboard (Exportable)
**What:** A presentation-ready 1-pager per school: current-year proficiency by subject, SGP gauge, goal compliance traffic lights, top 3 active interventions. Exportable to PDF.
**Data:** `PerformanceSnapshot` + `GoalEvaluation` + `InterventionTrigger` — all pre-computed
**Why it's powerful:** EMOs present monthly board reports. This eliminates hours of manual slide-building. Data is already aggregated in snapshots — it's purely a UI/export feature.

---

## 11. MDE Enrollment vs. Internal Enrollment Reconciliation
**What:** Compare MDE's official enrollment counts (from `MdeEnrollmentResult`) against internal `Enrollment` records to flag discrepancies in total headcount, grade distributions, or subgroup counts.
**Data:** `MdeEnrollmentResult` (official, by grade/subgroup) vs. `Enrollment` + `Student` (internal records)
**Why it's powerful:** Schools often discover mid-year that their MDE-reported enrollment doesn't match what's in their SIS. Catches errors before state reporting deadlines.

---

## 12. School Health Score ("Academic Credit Score")
**What:** A single composite 0–100 score per school, weighted across: proficiency rate (40%), median SGP (30%), goal compliance rate (20%), intervention severity (10%).
**Data:** `PerformanceSnapshot` + `GoalEvaluation` + `InterventionTrigger` — all already computed
**Why it's powerful:** EMO executives managing 10+ schools need a single number to triage where to focus attention. Also useful for authorizer portfolio risk ratings.

---

## Priority Recommendation

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| High | #3 Early Warning System | Medium | Very High |
| High | #4 Student-Level Drill-Down | Low | Very High |
| High | #2 Subgroup Heatmap | Low | High |
| Medium | #7 SGP Distribution Histogram | Low | High |
| Medium | #12 School Health Score | Medium | High |
| Medium | #6 Reauthorization Packet | High | Very High |
| Lower | #1 Cohort Trajectory | High | High |
| Lower | #5 Virtual Peer Group | Medium | Medium |
