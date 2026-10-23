# A/B Test Analysis & Product Metrics: Does Showing Ads Beat a PSA?

> **Data disclosure:** retrospective analysis of a **public Kaggle dataset** ("Marketing A/B Testing", 588,101 users). It is real experiment data, **not simulated**, but I did not design or run the original experiment.

## Decision at a glance

| | |
|---|---|
| **Recommendation** | **SHIP, with caveats** |
| **Absolute lift** | **+0.769 pp** (95% CI [0.587, 0.936]) |
| **Relative lift** | **+43.1%** (95% CI [30.6%, 57.9%]) |
| **Conversion** | 2.55% with ad vs 1.79% with PSA |
| **Dashboard** | Data Studio (formerly Looker Studio): [View the dashboard](https://datastudio.google.com/reporting/0009e4a9-4c61-49c1-a951-cb0d7a355bdb) |

**Question:** does showing an ad increase the share of users who convert, versus showing a neutral public service announcement (PSA), and is the lift big enough to act on?

**Why it matters:** ad spend only pays off if it causes conversions that would not have happened anyway. The PSA group is that baseline, and a confidence interval (not just a p-value) says how large the effect could be.

**Stack:** BigQuery Standard SQL, Python (pandas, SciPy, statsmodels) in Google Colab, Data Studio.

## Method

The design was written down in [`01_preregistration.md`](01_preregistration.md) before any hypothesis test was run.

| Design choice | Value |
|---|---|
| Hypothesis | Conversion differs between ad (treatment) and PSA (control); two-sided |
| Primary metric | User-level conversion rate |
| Alpha / power | 0.05 / 0.80 |
| MDE | +0.3 percentage points absolute (about +17% relative) |
| Baseline (control) | 1.785% (420 / 23,524) |
| Required control users | 17,216 (24:1 allocation); 23,524 available, so the test is powered |
| Primary test | Two-proportion z-test; 95% CI by Newcombe (absolute), bootstrap (relative, 10,000 resamples, seed 42) |
| Decision rule | Ship if validity passes and the CI for absolute lift is entirely above 0; don't ship if entirely at or below 0; otherwise keep running |

**Amendment 1** (dated, in the pre-registration) defined validity thresholds and a sensitivity analysis. It was written after the validity checks but before any lift was computed.

## Results

| Metric | Value |
|---|---|
| Treatment (ad) | 14,423 / 564,577 = 2.5547% |
| Control (PSA) | 420 / 23,524 = 1.7854% |
| z-test | z = 7.37, p = 1.7e-13 |
| **Absolute lift** | **+0.769 pp, 95% CI [0.587, 0.936]** |
| **Relative lift** | **+43.1%, 95% CI [30.6%, 57.9%]** |
| Robustness: drop top 1% of `total_ads` (<= 202) | +0.792 pp, 95% CI [0.616, 0.952] |
| Sensitivity: adjusted for day and hour (logistic) | +0.769 pp, 95% CI [0.590, 0.935]; odds ratio 1.442 |

The whole CI sits above 0 and its lower bound (+0.587 pp) is above the +0.3 pp MDE. The robustness and adjusted estimates agree with the primary result, so the small day/hour imbalance below is not driving the conclusion.

### Validity checks

| Check | Result | Verdict |
|---|---|---|
| Duplicates / nulls | None in 588,101 rows | Pass |
| Split | 564,577 ad (96.0%) / 23,524 PSA (4.0%) | Intended split undocumented |
| Allocation vs day of week | chi2 = 235.61, p ~ 5e-48, **Cramer's V = 0.020** | Pass (V < 0.05) |
| Allocation vs hour | chi2 = 192.29, p ~ 1e-28, **Cramer's V = 0.018** | Pass (V < 0.05) |
| `total_ads` balance | mean 24.82 vs 24.76, median 13 vs 12, **SMD = 0.0014** | Pass (SMD < 0.1) |

The p-values are tiny only because n is very large; the effect sizes are negligible. Randomization is treated as **plausible, not proven**. `total_ads` is heavily right-skewed (skew 7.4, 99th percentile = 202), so a robustness check excludes the top 1%.

## Caveats

- **Retrospective, public data.** Randomization is plausible but unproven, and the intended split is undocumented. The control group is only 4% of users, so its estimate is noisier (reflected in the CI).
- **No guardrail metric.** The data has no revenue, opt-out or bounce fields, so hidden costs of showing ads were not checked.
- **No cost or revenue data.** A conversion lift is not profit; ads cost money.
- **No timestamps** (only day and hour), so novelty effects could not be checked.
- **Post-exposure variables.** `most_ads_day`, `most_ads_hour` and `total_ads` are measured after exposure begins, so balance checks are diagnostics, not proof.
- **Baseline from the same data.** The 1.785% baseline used for power planning comes from the control group here, and raw group sizes and rates were viewed before pre-registration (no test statistic, CI or p-value had been computed).
- **Segment cuts are exploratory** (exposure bucket, day, hour) and did not drive the decision. Conversion rises steeply with `total_ads`, but exposure is post-treatment and engagement-driven, so this does not show that more ads cause more conversions.

## Repository

| File | What it is |
|---|---|
| `README.md` | This summary and decision |
| `01_preregistration.md` | Hypothesis, metrics, MDE, power analysis, validity checks, decision rule, Amendment 1 |
| `notebook.ipynb` | Full analysis: power, validity, lift with CI, robustness, sensitivity |
| `sql/01_load_and_metric_definitions.sql` | BigQuery Standard SQL: sanity checks, metric definitions, dashboard views |

## How to reproduce

1. **Get the data.** Download the Kaggle dataset "Marketing A/B Testing" and unzip it to get `marketing_AB.csv`. The raw data is not included in this repo.
2. **Clean it.** Run once to drop the index column, use snake_case names, and make `converted` 0/1 (no values change):
   ```python
   import pandas as pd
   d = pd.read_csv("marketing_AB.csv").drop(columns=["Unnamed: 0"])
   d.columns = [c.replace(" ", "_") for c in d.columns]
   d["converted"] = d["converted"].astype(int)
   d.to_csv("marketing_ab_clean.csv", index=False)
   ```
3. **Run the notebook.** Open `notebook.ipynb` in Google Colab, upload `marketing_ab_clean.csv` when the first cell prompts, then choose **Runtime > Run all**. It needs `pandas`, `numpy`, `scipy`, `statsmodels` (preinstalled in Colab). The random seed is fixed at 42.
4. **Build the BigQuery views (for the dashboard).** Create a dataset `ab_project`, upload `marketing_ab_clean.csv` as table `marketing_ab`, then run `sql/01_load_and_metric_definitions.sql` after replacing `YOUR_PROJECT` with your project ID.
5. **Check your numbers.** You should get 14,423 / 564,577 treatment conversions, 420 / 23,524 control conversions, and a lift of +0.769 pp (95% CI [0.587, 0.936]). `SELECT * FROM ab_project.vw_primary_metric` should show the same counts.
6. **Dashboard.** Connect the `vw_...` views to Data Studio (formerly Looker Studio).
