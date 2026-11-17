# Predicció operativa del Llobregat (TFG)

Sistema operatiu del TFG: prediu el cabal a **Sant Joan Despí** i a l'**Anoia a Martorell**
a +1…+6 h amb els models M7 (LightGBM Tweedie) ja entrenats. S'executa sol a GitHub
Actions cada 30 minuts i publica els resultats a GitHub Pages: no cal cap ordinador encès.

Web: `https://joangordo.github.io/llobregat-operatiu-tfg/`
CSV de l'última predicció: `.../ultima_prediccio_sjd.csv` i `.../ultima_prediccio_martorell.csv`

> Projecte acadèmic experimental. **No és un sistema oficial d'avís.**

## Com funciona

A cada execució:
1. Recupera l'estat de l'execució anterior (memòria cau d'Actions; no es guarda cap dada al repositori).
2. Descarrega les dades noves: cabals i volum d'embassaments (API de l'ACA) i pluja (API del Meteocat).
3. Construeix les variables amb el mateix codi que l'entrenament i aplica els models M7.
4. Publica la web i els CSV.

Si la memòria cau es perd, la primera execució reconstrueix els últims 25 dies (uns 10 minuts).

## Canvis respecte a `Script_operatiu_doble.R`

| Canvi | Motiu |
| --- | --- |
| La clau del Meteocat és un secret de GitHub | No pot estar escrita al codi |
| Pluja: una petició per dia per a totes les estacions | Abans, una per estació i dia (unes 30 vegades més quota) |
| Dates del Meteocat llegides amb el format `AAAA-MM-DDTHH:MMZ` | `ymd_hms()` les convertia en NA: la pluja recent no s'actualitzava i el model rebia pluja 0 |
| Pluja retardada 1 pas abans de les variables | Com a l'entrenament (script 03, Convenció A) |
| Volum dels embassaments descarregat de l'API | Abans s'arrossegava l'últim valor de la base |
| Forats de cabal: com a màxim 3 h | Com a l'entrenament (abans fins a 48 h) |
| Models i llindars precalculats a `models/` | No cal la base completa ni reentrenar |
| Cada model rep les columnes de la seva base d'entrenament | El model de Martorell fa servir el cabal de Sant Sadurní, que no era a `base_complet`: sempre quedava buit |
| ERA5 substituïda per la mitjana mensual de l'entrenament | En temps real no existeix; buida donava més error |

Les variables (`construir_features`) i els models són els mateixos del TFG.

## Contingut

| Carpeta | Què és | Al repositori? |
| --- | --- | --- |
| `models/sjd`, `models/martorell` | Models M7 (6 horitzons), variables, llindars Q95/Q99, columnes i climatologia ERA5 | Sí |
| `inputs/estructura_base.rds`, `inputs/mapeig_sensors.csv` | Columnes de la base (sense dades) i sensors de l'ACA | Sí |
| `inputs/*.RData`, `cache/` | Dades i fitxers del TFG (només per a `preparar_inputs.R`) | **No** (`.gitignore`) |

## Posada en marxa (un sol cop)

1. Puja aquesta carpeta a un repositori **públic** de GitHub (`llobregat-operatiu-tfg`).
   Comprova que a GitHub hi ha `models/` i `inputs/estructura_base.rds`, i que **no** hi ha cap `.RData`.
2. **Settings → Secrets and variables → Actions → New repository secret**:
   nom `METEOCAT_API_KEY`, valor la teva clau.
3. **Settings → Pages → Build and deployment → Source: GitHub Actions**.
4. **Actions → Predicció operativa → Run workflow**. La primera execució triga uns 10–15 minuts
   (instal·la R i reconstrueix 25 dies). Després s'executa sola cada 30 minuts.

`preparar_inputs.R` només cal si es reentrenen els models: regenera `inputs/` i `models/`
a partir de les dades del TFG (`inputs/base_filtrada_*.RData`, `inputs/dataset_features_*.RData`
i `cache/models_*`).

## Validació

Executant aquest sistema amb les dades reals de maig de 2026 (APIs simulades), les prediccions
coincideixen amb les del pipeline del TFG: idèntiques a Sant Joan Despí i amb menys d'un 4 % de
diferència a Martorell, que ve de `swvl3` (ERA5): en temps real no existeix i s'hi posa la mitjana
del mes, que dona menys error que deixar-la buida.

## Proves

```bash
Rscript tests/test_pipeline.R
```
Prova el pipeline sencer amb APIs i models simulats (no cal xarxa ni lightgbm).

## Autoria

Joan Gordó Guardia. Treball de Final de Grau en Estadística, Universitat de Barcelona.
Dades: Agència Catalana de l'Aigua i Servei Meteorològic de Catalunya.
