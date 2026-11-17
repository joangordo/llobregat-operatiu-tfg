# ==============================================================================
# prediccio_operativa.R — Predicció operativa a +1..+6 h (SJD i Martorell)
# Joan Gordó Guardia — Grau d'Estadística (UB)
# ------------------------------------------------------------------------------
# Versió per executar-se a GitHub Actions (vegeu README.md). A cada execució:
#   1. Recupera l'estat (cache/estat.rds) de l'execució anterior; si no n'hi ha,
#      el reconstrueix amb els últims DIES_LLAVOR dies de les APIs.
#   2. Descarrega les dades noves de l'ACA (cabals i embassaments) i del Meteocat.
#   3. Per a cada estació, construeix les variables i aplica els models M7.
#   4. Escriu la web (web/index.html) i els CSV de predicció a web/.
# ==============================================================================

source("R/funcions.R")
if (nzchar(Sys.getenv("LLOBREGAT_TEST"))) source("tests/mocks.R")  # només als tests
if (!exists("carregar_model")) {
  suppressPackageStartupMessages(library(lightgbm))
  carregar_model <- function(ruta) lgb.load(ruta)
  predir_model   <- function(mod, x) as.numeric(predict(mod, x))
}

DIES_MAX_API <- 90   # l'API de l'ACA no deixa anar més enrere
DIES_LLAVOR  <- 25   # història mínima per a les variables (1000 files ≈ 21 dies)
DIES_ESTAT   <- 45   # història que es conserva a l'estat
DIES_HISTORIC_PRED <- 60
FILES_MARGE  <- 1000

DIR_IN     <- "inputs"
DIR_MODELS <- "models"
DIR_CACHE  <- Sys.getenv("DIR_CACHE", "cache")
DIR_WEB    <- Sys.getenv("DIR_WEB", "web")
for (d in c(DIR_CACHE, DIR_WEB)) if (!dir.exists(d)) dir.create(d, recursive = TRUE)
RUTA_ESTAT <- file.path(DIR_CACHE, "estat.rds")

API_KEY_METEOCAT <- Sys.getenv("METEOCAT_API_KEY")
ARA <- if (exists("ARA_FIXAT")) ARA_FIXAT else Sys.time()

# ------------------------------------------------------------------------------
# 1. Estat i estructura de columnes
# ------------------------------------------------------------------------------
estructura <- readRDS(file.path(DIR_IN, "estructura_base.rds"))
tipus <- tipus_columnes(names(estructura))
mapeig_cabal <- read.csv(file.path(DIR_IN, "mapeig_sensors.csv"), stringsAsFactors = FALSE,
                         colClasses = "character", fileEncoding = "UTF-8") %>%
  filter(estacio %in% tipus$cabal) %>% distinct(estacio, .keep_all = TRUE)

estat <- if (file.exists(RUTA_ESTAT)) readRDS(RUTA_ESTAT) else list(df_crua = NULL, historic = NULL)
t_ara <- floor_date(with_tz(ARA, "UTC"), PAS)

if (is.null(estat$df_crua) || nrow(estat$df_crua) == 0) {
  t_ultim <- t_ara - days(DIES_LLAVOR)
  cat(sprintf("Sense estat previ: es reconstrueixen els últims %d dies.\n", DIES_LLAVOR))
} else {
  te_cabal <- rowSums(!is.na(estat$df_crua[, mapeig_cabal$estacio, drop = FALSE])) > 0
  t_ultim <- max(estat$df_crua$Time[te_cabal])
  cat(sprintf("Estat previ fins a %s UTC.\n", format(t_ultim, "%Y-%m-%d %H:%M")))
}
data_i <- max(t_ultim - hours(6), t_ara - days(DIES_MAX_API))
nou <- graella_buida(estructura, data_i, t_ara)

# ------------------------------------------------------------------------------
# 2. Descàrregues
# ------------------------------------------------------------------------------
n_ok <- 0
for (i in seq_len(nrow(mapeig_cabal))) {
  d <- a_30min(baixar_per_blocs("AFORAMENT-EST", mapeig_cabal$sensor_id[i], data_i, t_ara))
  if (is.null(d) || nrow(d) == 0) next
  idx <- match(d$Time, nou$Time); ok <- !is.na(idx)
  nou[[mapeig_cabal$estacio[i]]][idx[ok]] <- d$valor[ok]
  n_ok <- n_ok + 1
}
cat(sprintf("  Cabal: %d de %d estacions amb dades noves.\n", n_ok, nrow(mapeig_cabal)))

for (col in intersect(names(SENSORS_EMB), tipus$emb)) {
  d <- baixar_per_blocs("EMBASSAMENT-EST", SENSORS_EMB[[col]], data_i, t_ara)
  if (is.null(d) || nrow(d) == 0) next
  diari <- d %>% mutate(Data = as.Date(Time, tz = "UTC")) %>%
    group_by(Data) %>% summarise(v = mean(valor, na.rm = TRUE), .groups = "drop")
  nou[[col]] <- diari$v[match(as.Date(nou$Time, tz = "UTC"), diari$Data)]
}

if (nzchar(API_KEY_METEOCAT)) {
  dies <- seq(as.Date(data_i, tz = "UTC"), as.Date(t_ara, tz = "UTC"), by = "day")
  parts <- lapply(dies, function(dia) baixar_meteocat_dia(dia, API_KEY_METEOCAT))
  pl <- bind_rows(parts)
  if (nrow(pl) > 0) {
    pl <- pluja_30min(pl %>% filter(estacio %in% tipus$pluja))
    for (est in unique(pl$estacio)) {
      s <- pl[pl$estacio == est, ]
      idx <- match(s$Time, nou$Time); ok <- !is.na(idx)
      nou[[est]][idx[ok]] <- s$valor[ok]
    }
  }
  cat(sprintf("  Pluja: %d peticions al Meteocat, %d estacions amb dades.\n",
              length(dies), length(unique(pl$estacio))))
} else {
  cat("  (sense METEOCAT_API_KEY: la pluja no s'actualitza)\n")
}

df_crua <- fusionar(estat$df_crua, nou) %>% filter(Time > t_ara - days(DIES_ESTAT))

# ------------------------------------------------------------------------------
# 3. Predicció per estació
# ------------------------------------------------------------------------------
base <- preparar_base(df_crua, tipus$cabal, tipus$emb, tipus$pluja)

predir_estacio <- function(cfg) {
  dir_m <- file.path(DIR_MODELS, cfg$id)
  vars_h <- readRDS(file.path(dir_m, "vars.rds"))
  q_thr  <- readRDS(file.path(dir_m, "llindars.rds"))
  cols   <- readRDS(file.path(dir_m, "columnes.rds"))  # columnes de la base d'entrenament

  # El truc del TFG i, després, exactament les columnes de l'entrenament d'aquesta
  # estació (importa per a la pluja global i l'API, que sumen totes les estacions)
  d <- aplicar_truc(base, cfg)
  for (c in setdiff(cols, names(d))) d[[c]] <- NA_real_
  d <- tail(d[, c("Time", setdiff(cols, "Time"))], FILES_MARGE)
  tp <- tipus_columnes(names(d))
  X <- construir_features(d, tp$pluja, tp$emb, tp$era5)
  valid <- !is.na(d[[NOM_OBJECTIU_INTERN]])
  if (!any(valid)) { cat(sprintf("%s: sense cabal recent, no es prediu.\n", cfg$id)); return(NULL) }
  t0 <- max(d$Time[valid]); q0 <- d[[NOM_OBJECTIU_INTERN]][d$Time == t0][1]
  fila <- X[X$Time == t0, , drop = FALSE]
  # ERA5 (humitat del sòl, etc.) no arriba en temps real: mitjana del mes a l'entrenament
  ruta_clim <- file.path(dir_m, "climatologia_era5.rds")
  if (file.exists(ruta_clim)) for (v in names(clim <- readRDS(ruta_clim)))
    if (is.null(fila[[v]]) || is.na(fila[[v]])) fila[[v]] <- unname(clim[[v]][as.character(as.integer(format(t0, "%m", tz = "UTC")))])
  max_clip <- 2.5 * max(d[[NOM_OBJECTIU_INTERN]], na.rm = TRUE)

  res <- bind_rows(lapply(HORITZONS, function(h) {
    v <- vars_h[[paste0("h", h)]]
    for (col in setdiff(v, names(fila))) fila[[col]] <- NA_real_
    x0 <- as.matrix(fila[, v, drop = FALSE]); storage.mode(x0) <- "double"
    p <- predir_model(carregar_model(file.path(dir_m, sprintf("m7_h%d.txt", h))), x0)
    p <- min(max(p, 0), max_clip)
    data.frame(estacio = cfg$id, t0 = t0, cabal_t0 = q0, horitzo = h,
               t_target = t0 + hours(h), pred = round(p, 2), model = "M7",
               risc = classificar_risc(p, q_thr), generat = with_tz(ARA, "UTC"),
               n_vars_absents = sum(is.na(x0)), n_vars = length(v))
  }))
  cat(sprintf("%s | t0 = %s UTC | Q(t0) = %.2f m3/s | Q95/Q99 = %.1f/%.1f\n",
              toupper(cfg$id), format(t0, "%Y-%m-%d %H:%M"), q0, q_thr[["q95"]], q_thr[["q99"]]))
  print(res[, c("horitzo", "t_target", "pred", "risc", "n_vars_absents")], row.names = FALSE)
  attr(res, "q_thr") <- q_thr
  attr(res, "observat") <- d[d$Time > t0 - hours(48), c("Time", NOM_OBJECTIU_INTERN)]
  res
}

resultats <- lapply(ESTACIONS, predir_estacio)
resultats <- resultats[!vapply(resultats, is.null, logical(1))]

# ------------------------------------------------------------------------------
# 4. Sortides: estat, CSV i web
# ------------------------------------------------------------------------------
noves <- bind_rows(lapply(resultats, function(r) { attributes(r)[c("q_thr", "observat")] <- NULL; r }))
historic <- bind_rows(estat$historic, noves) %>%
  filter(generat > with_tz(ARA, "UTC") - days(DIES_HISTORIC_PRED)) %>%
  distinct(estacio, t0, horitzo, .keep_all = TRUE)
saveRDS(list(df_crua = df_crua, historic = historic), RUTA_ESTAT)

for (r in resultats) write.csv(r, file.path(DIR_WEB, sprintf("ultima_prediccio_%s.csv", r$estacio[1])),
                               row.names = FALSE)
write.csv(historic, file.path(DIR_WEB, "historic_prediccions.csv"), row.names = FALSE)
source("R/web.R")
escriure_web(resultats, file.path(DIR_WEB, "index.html"), ARA)
cat("== Predicció operativa completada ==\n")
