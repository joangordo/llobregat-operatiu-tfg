# Llobregat River flow forecast (operational)

Operational 1–6 h streamflow forecasts for the Llobregat River (Catalonia, Spain) at
**Sant Joan Despí** and for the **Anoia River at Martorell**, using the LightGBM (Tweedie)
models developed in my undergraduate thesis in Statistics (University of Barcelona).

The system runs entirely on GitHub: every 30 minutes, GitHub Actions downloads real-time
data, computes the forecasts and publishes a bilingual (Catalan / English) web page on
GitHub Pages. No server or local computer is needed.

**Live forecast:** [joangordo.github.io/llobregat-operatiu-tfg](https://joangordo.github.io/llobregat-operatiu-tfg/?lang=en)

> Experimental academic project. **Not an official flood warning system.**

## How it works

```
Every 30 min (GitHub Actions)
  1. Restore state      previous run's recent data (Actions cache, not stored in the repo)
  2. Ingest             river flow and reservoir storage (ACA real-time API)
                        rainfall from 30+ rain gauges (Meteocat XEMA API)
  3. Features           lagged flows, rolling maxima, rainfall accumulations (1–72 h),
                        antecedent precipitation index — same code as in training
  4. Predict            one LightGBM Tweedie model per station and lead time (+1 … +6 h)
  5. Publish            web page, latest forecast CSV and forecast history (GitHub Pages)
```

| Component | Details |
| --- | --- |
| Models | LightGBM, Tweedie objective, flood-weighted training, 5–28 selected features per lead time |
| Data | Agència Catalana de l'Aigua (river gauges, reservoirs) and Servei Meteorològic de Catalunya (rain gauges) |
| Risk levels | Forecast above the 95th / 99th percentile of the training flow |
| Stack | R (dplyr, zoo, lightgbm), GitHub Actions, GitHub Pages |

## Lessons from moving the original script to the cloud

The original operational script ran on an office computer. Porting it to a reproducible
pipeline and checking it against the training data revealed several **training–serving
skews**, now fixed:

- **Rainfall was never updated.** Meteocat timestamps (`2026-11-13T10:00Z`) were parsed with
  `ymd_hms()`, which returns `NA` for that format; the model always received zero rainfall.
- **Rainfall lag.** Training used a one-step lag (Meteocat labels the end of the
  accumulation period); the operational script did not.
- **Missing inputs.** The Martorell model's most important input (Anoia flow at Sant Sadurní)
  was not in the operational data table, so it was always missing.
- **Frozen inputs.** Reservoir storage and ERA5 soil moisture were carried forward from the
  last training date. Reservoir storage is now downloaded in real time; ERA5 (not available in
  real time) is replaced by its monthly training mean, which reduces the error versus leaving
  it missing.

**Validation:** replaying real May 2026 data through the cloud pipeline reproduces the thesis
pipeline's forecasts exactly at Sant Joan Despí and within 4 % at Martorell (the difference
comes from ERA5 soil moisture).

## Repository layout

```
prediccio_operativa.R       main script (run by GitHub Actions)
R/funcions.R                data download, feature engineering, helpers
R/web.R                     bilingual web page
models/<station>/           LightGBM models (m7_h1…h6.txt), features, thresholds
inputs/                     data-table structure (no data) and ACA sensor IDs
preparar_inputs.R           rebuilds models/ and inputs/ from the thesis data (only if models change)
tests/                      end-to-end test with mocked APIs and models
.github/workflows/          30-minute schedule
```

## Run the tests

```bash
Rscript tests/test_pipeline.R
```

## Setup (for a fork)

1. Add a repository secret `METEOCAT_API_KEY` (Settings → Secrets and variables → Actions).
2. Settings → Pages → Source: **GitHub Actions**.
3. Actions → *Predicció operativa* → **Run workflow**.

## En català

Sistema operatiu de predicció de cabal a +1…+6 h al Llobregat (Sant Joan Despí) i a l'Anoia
(Martorell), basat en els models M7 del Treball de Final de Grau en Estadística (UB).
S'actualitza cada 30 minuts a GitHub Actions i publica una web en català i anglès:
[joangordo.github.io/llobregat-operatiu-tfg](https://joangordo.github.io/llobregat-operatiu-tfg/?lang=ca).
Projecte acadèmic experimental: no és un sistema oficial d'avís.

## Author and data

Joan Gordó Guardia — BSc thesis in Statistics, University of Barcelona.
Data: [Agència Catalana de l'Aigua](https://aca.gencat.cat) and
[Servei Meteorològic de Catalunya](https://www.meteo.cat).
