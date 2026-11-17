# Llobregat River flow forecast (operational)

Operational 1–6 h streamflow forecasts for the Llobregat River (Catalonia, Spain) at
**Sant Joan Despí** and for the **Anoia River at Martorell**, using the LightGBM (Tweedie)
models developed in my undergraduate thesis in Statistics at the University of Barcelona,
within the BIOST3 research group.

The system runs entirely on GitHub: every 30 minutes, GitHub Actions downloads real-time
data, computes the forecasts and publishes a bilingual (Catalan / English) web page on
GitHub Pages. No server or local computer is needed.

**Live forecast:** [joangordo.github.io/llobregat-operatiu-tfg](https://joangordo.github.io/llobregat-operatiu-tfg/?lang=en)

> **Experimental academic project. Not an official flood warning system.** Do not use it to
> make safety decisions. In an emergency call **112**. Official warnings:
> [Protecció Civil de Catalunya](https://interior.gencat.cat),
> [Meteocat](https://www.meteo.cat) and
> [ACA – Aigua en temps real](https://aplicacions.aca.gencat.cat/aetr/vishid/).

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
- **Frozen inputs.** Reservoir storage was carried forward from the last training date; it
  is now downloaded in real time. One Martorell input that has no real-time source (deep soil
  moisture) is replaced by a fixed monthly average from the training period¹.

**Validation:** replaying real May 2026 data through the cloud pipeline reproduces the thesis
pipeline's forecasts exactly at Sant Joan Despí and within 4 % at Martorell (the difference
comes from that soil-moisture input).

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
Projecte acadèmic experimental del grup de recerca BIOST3 (UB): **no és un sistema oficial
d'avís**. En cas d'emergència, truca al 112. Avisos oficials:
[Protecció Civil](https://interior.gencat.cat), [Meteocat](https://www.meteo.cat) i
[ACA](https://aplicacions.aca.gencat.cat/aetr/vishid/). Sistema operatiu original d'Àlex
Rodríguez Molla; direcció d'Antonio Monleón-Getino i Pere López Brosa.

## Credits

This system is part of the Llobregat flood-forecasting work of the **BIOST3** research group
(Secció d'Estadística, Departament de Genètica, Microbiologia i Estadística, Universitat de
Barcelona).

- **Joan Gordó Guardia**: statistical modelling and validation (BSc thesis), and this cloud
  version of the operational system.
- **Àlex Rodríguez Molla**: the original operational system and web platform (BSc thesis).
- **Antonio Monleón-Getino** and **Pere López Brosa**: supervision of both theses. Pere López
  Brosa also provided historical data from his doctoral thesis.
- **Javier Méndez-Viera**: methodology and supervision.

A paper on this work (Gordó Guardia, Rodríguez Molla, López Brosa, Méndez-Viera and
Monleón-Getino) is in preparation. The work is aligned with action line 8.d.9 of the
scientific consultation of Spain's National Office for Scientific Advice (ONAC, 2025), on a
national intelligent platform for climate emergencies.

## Data and licences

- **River flow and reservoir storage:** [Agència Catalana de l'Aigua](https://aca.gencat.cat)
  (ACA), real-time open data.
- **Rainfall:** © [Servei Meteorològic de Catalunya](https://www.meteo.cat) (Meteocat), XEMA
  network, through the Meteocat API.

We thank both agencies for making these data available, and the ACA for also providing the
historical record that will be used to extend this work. Data are used under their reuse
conditions: the source is cited, the time of the latest data is shown, and observations are
not altered. The web page shows only recent observations alongside the forecasts. The
historical data used to train the models are **not** redistributed here.

¹ The 12 monthly soil-moisture values in `models/martorell/` are derived from ERA5-Land.
Contains modified Copernicus Climate Change Service information (2026). Neither the European
Commission nor ECMWF is responsible for any use that may be made of the Copernicus
information or data it contains.

## Licence

Code: [MIT](LICENSE). The models in `models/` and the published forecasts are derived from the
data above and are provided as is, for research and teaching, without any warranty.
