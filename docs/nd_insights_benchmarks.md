# ND Insights comparison benchmarks: evidence and reproduction

How the Fort Yates dashboard and PDF color ND Insights results, and the evidence behind each benchmark. The code is `Emisint.NdInsights.StateComparison` and `Emisint.NdInsights.SurveyBenchmark`. Checked October 31, 2026.

## 1. Comparison rule (all sections)

- **Published bounds.** A range is compared through its published low and high values, never a midpoint. An exact value is compared as published.
  - Green: the whole school interval is strictly on the favorable side.
  - Red: the whole interval is strictly on the unfavorable side.
  - Yellow: the intervals overlap or share an endpoint.
  - "Matches": equal exact values.
- **What the sources say about ranges:**
  - Insights Data page (https://insights.nd.gov/Data): identifiable data is "converted to a range of values"; "Ranges are shown with low and high columns".
  - NDUS Institutional Research (https://ndus.edu/data-center/institutional-research/nddpi): "exact values are often replaced with value ranges (e.g., “60–70% proficient”)".
- **Not documented:** rounding, and whether 29% means "up to 29%" or "below 30%". A color is a comparison of published values, not the exact hidden value or an official determination. No allowance or tolerance is added.

## 2. Achievement and Growth: "State of North Dakota" rows

- **Source:** InstitutionID 99999 in the same Insights download as the school, so the publication version matches.
- **Matching:** same year, subject, grade, assessment type, student group, accommodations and measure.
- **All Grades:** compared only when both sides publish the same grades. Fort Yates 2024-25:
  - Achievement: school 6, 7, 8 against North Dakota 3–8 and 10 (science: 8 against 4, 8, 10).
  - Growth: school 7, 8 against North Dakota 4–8.
  - So All Grades is "context only".

## 3. % tested: 95% participation target

- **Source:** 20 U.S.C. 6311(c)(4)(E)(i) (https://www.law.cornell.edu/uscode/text/20/6311): "not less than 95 percent of all students, and 95 percent of all students in each subgroup", on the reading/language arts and mathematics assessments. Insights' participation charts note the same 95%.
- **Applied to:** ELA and math, Combined assessment (standard plus alternate), all students, All Grades.
- **Not applied:** science; single grades; other assessment types; student groups (Insights' groups are not verified as the statute's subgroups).
- **Rule:**
  - lower bound ≥ 95%: "Meets 95% target";
  - upper bound < 95%: "Below 95% target";
  - otherwise "Cannot determine".
- A dashboard comparison, not an official compliance finding.

## 4. Engagement: statewide middle-school (grades 6–8) benchmark

### Sources

ND Student Engagement Survey technical briefs (Cognia), on `nddpi.onlinehelp.cognia.org`:

| Year | URL | SHA-256 |
|---|---|---|
| 2021-22 (V1.0, June 30, 2022) | https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2022/07/ND-2122-SES-Technical-Brief.pdf | `99d8c3b83054ec4bf9eada48669290b0d6437a312bc675393ba4cc13d7af97b2` |
| 2022-23 (V1.0, June 30, 2023) | https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2023/06/ND-2223-SES-Technical-Brief.pdf | `733e8f9f4f970af14e3c35e51c2e711de99338dff71b4881358b51d9d00178c7` |
| 2023-24 (V1.0, April 1, 2024) | https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2024/04/ND-2324-SES-Technical-Brief.pdf | `3a4abc4c083b7293825b51c42c1eb9be2da4b55f8e7b76c23496303e9123987b` |
| 2024-25 (V1.0, April 3, 2025) | https://nddpi.onlinehelp.cognia.org/wp-content/uploads/sites/20/2025/04/ND-2425-SES-Technical-Brief.pdf | `f8c1e3538a26ea166e5f7e0436a907f5fd0e987924ed2cd51eb4a9eb8a2bd3e9` |

What each part of a brief is used for:

- **§2:** versions for elementary (3–5), middle (6–8) and high (9–12). A student is classified by the most frequent engagement type in each domain.
- **§6:** percentages are respondents of each type divided by all respondents who completed the survey.
- **Table 2:** respondents by version.
- **Figures 4–6** (pages 8–9): respondent counts for Committed, Compliant and Disengaged by span and domain. Only the counts are in the images, not the PDF text.
- **Appendix C:** each school's respondents by survey version, with % Committed per domain.

### Counts used (Figure 5, middle school)

| Year | Respondents | Behavioral C / Cp / D | Cognitive C / Cp / D | Emotional C / Cp / D |
|---|---|---|---|---|
| 2021-22 | 23,638 | 10,960 / 10,144 / 2,534 | 8,104 / 12,501 / 3,033 | 7,355 / 10,576 / 5,707 |
| 2024-25 | 24,900 | 12,136 / 10,222 / 2,542 | 8,817 / 12,973 / 3,110 | 8,382 / 10,545 / 5,973 |

The elementary and high counts used for the reconciliation are in `test/emisint/nd_insights/survey_benchmark_evidence_test.exs`.

### Check 1: the Insights state row is the grades 3–12 total

Summing all three spans' counts and dividing by all respondents reproduces every Insights "State of North Dakota" Committed and Disengaged value to two decimals, for Behavioral, Cognitive and Emotional, in 2021-22 and 2024-25.

- Example: 2024-25 Behavioral Committed (16,556 + 12,136 + 12,165) / 80,214 = 0.509; Insights shows 0.51.

This confirms the definitions and aggregation match. It also confirms the Insights state row is not a middle-school figure.

### Check 2: the school figure's population (Fort Yates, 4300429212)

| Year | Appendix C versions (respondents; % Committed B/C/E) | Insights Committed ranges B/C/E | Decision |
|---|---|---|---|
| 2021-22 | Middle 52; 19/27/25 | 15–19 / 25–29 / 25–29 | Middle only, inside every range: **compared** |
| 2022-23 | Elementary 13; Middle 42 (38/38/19) | 35–39 / 40–44 / 25–29 | Mixed; middle-only Cognitive 38 is outside 40–44: **not compared** |
| 2023-24 | Elementary 7; Middle 46 (41/35/30) | 45–49 / 35–39 / 30–34 | Mixed; middle-only Behavioral 41 is outside 45–49: **not compared** |
| 2024-25 | Middle 98; 34/31/31 | 30–34 / 30–34 / 30–34 | Middle only, inside every range: **compared** |
| 2017-18 to 2020-21 | not recorded | — | No verified brief: **not compared** |

For a mixed year, a matching benchmark would need the statewide figure for the same mix of versions, and that isn't published. The grades 3–12 row is never substituted.

### Use

- Same-year middle-school proportions only.
- Committed (higher is favorable) and Disengaged (lower is favorable) are rated.
- Compliant is not rated. Overall has no grade-span figure.

### Known data issue

In the Insights Behavioral, Cognitive and Emotional downloads, the state "Compliant" value equals "Committed" every year. Compliant is not rated, so no color depends on it.

## 5. Reproducing

1. Download the four briefs above and check their SHA-256 with `shasum -a 256 <file>`.
2. Read Table 2, Figures 4–6 (pages 8–9) and Appendix C (Fort Yates rows) in each.
3. Run `mix test test/emisint/nd_insights/survey_benchmark_evidence_test.exs`. It checks:
   - each span's counts sum to its Table 2 total;
   - the recorded middle-school counts equal the brief's;
   - all spans together reproduce the Insights state values;
   - Fort Yates' Appendix C figures sit inside its published Insights ranges in the middle-only years.
4. For the Behavioral and Cognitive state values and the other Fort Yates ranges, use the Insights downloads `Insights-Engagement-{Behavioral,Cognitive,Emotional}-All-CSV-v20251202.csv` from https://insights.nd.gov/Data.
