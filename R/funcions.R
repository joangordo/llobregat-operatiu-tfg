# ==============================================================================
# funcions.R — Funcions compartides del sistema operatiu (versió núvol)
# Joan Gordó Guardia — Grau d'Estadística (UB)
# ------------------------------------------------------------------------------
# Mateixa lògica que Script_operatiu_doble.R, amb aquests canvis:
#   1. La clau del Meteocat es llegeix de la variable d'entorn METEOCAT_API_KEY.
#   2. Pluja: una sola petició per dia per a TOTES les estacions (abans, una per
#      estació i dia) i lectura correcta de les dates "AAAA-MM-DDTHH:MMZ". Amb
#      ymd_hms() aquestes dates donaven NA, de manera que la pluja recent mai
#      s'actualitzava i el model rebia pluja 0.
#   3. Pluja retardada 1 pas abans de construir les variables (Convenció A), com a
#      l'entrenament (script 03). L'operatiu original no ho feia.
#   4. Volum dels embassaments actualitzat amb l'API de l'ACA (mitjana diària, com
#      a l'entrenament). L'operatiu original arrossegava l'últim valor de la base.
#   5. Els models M7 ja entrenats es carreguen de models/ (no cal la base completa).
# Els paràmetres de les variables i la funció construir_features() són IDÈNTICS
# als dels scripts 07 i operatiu.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(lubridate); library(zoo)
  library(httr); library(jsonlite)
})

PAS              <- "30 min"
PASSOS_PER_HORA  <- 2
h2p <- function(h) as.integer(round(h * PASSOS_PER_HORA))
HORITZONS <- 1:6

ESTACIONS <- list(
  sjd = list(id = "sjd", nom_real = "SantJoan Cabal", sensor_id = "CALC001261",
             eliminar = "Martorell Cabal", nom = "Llobregat a Sant Joan Despí"),
  martorell = list(id = "martorell", nom_real = "Martorell Cabal", sensor_id = "CALC001836",
                   eliminar = "SantJoan Cabal", nom = "Anoia a Martorell")
)
NOM_OBJECTIU_INTERN <- "SantJoan Cabal"

# Paràmetres de construcció de variables (mateixos que el pas 07)
LAGS_Q_SJD      <- c(0, 1, 2, 3, 6, 12)
ROLLMAX_SJD     <- c(3, 6)
DIFF_SJD        <- c(1, 3, 6)
LAGS_CABALS     <- c(1, 2, 3, 6, 12)
FINESTRES_PLUJA <- c(1, 2, 3, 6, 12, 24, 48, 72)
API_ALPHA_SLOW  <- 0.99
API_ALPHA_FAST  <- 0.90

# Pesos i llindars (mateixos que el pas 18); només s'usen per entrenar
W_Q75 <- 3; W_Q90 <- 5; W_Q95 <- 15; W_Q99 <- 40; W_SURGE <- 100
LLINDAR_MIN_Q <- 5
TEST_INI <- as.POSIXct("2026-06-01 00:00:00", tz = "UTC")
VARS_EXCLOURE <- c("swvl4")

# Imputació (com a l'entrenament: forats de com a màxim 3 h)
GAP_CABAL <- h2p(3)

# Volum dels embassaments (sensors del catàleg de l'ACA)
SENSORS_EMB <- c(emb_baells_volum_hm3   = "CALC000697",
                 emb_llosa_volum_hm3    = "CALC000698",
                 emb_santponc_volum_hm3 = "CALC000699")

URL_ACA         <- "https://aplicacions.aca.gencat.cat/sdim2/apirest/data"
URL_METEO_DADES <- "https://api.meteo.cat/xema/v1/variables/mesurades"
CODI_VAR_PLUJA  <- "35"

`%||%` <- function(a, b) if (is.null(a)) b else a

# ==============================================================================
# 1. Descàrregues
# ==============================================================================
# ACA (Sentilo). Retorna com a màxim 200 observacions per petició: blocs de 12 h.
baixar_sensor_aca <- function(proveidor, sensor_id, data_i, data_f) {
  from <- format(data_i, "%d/%m/%YT%H:%M:%S", tz = "UTC")
  to   <- format(data_f, "%d/%m/%YT%H:%M:%S", tz = "UTC")
  url  <- sprintf("%s/%s/%s?from=%s&to=%s&limit=1000", URL_ACA, proveidor, sensor_id, from, to)
  resp <- tryCatch(GET(url, timeout(30)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) return(NULL)
  parsejar_aca(content(resp, as = "text", encoding = "UTF-8"))
}

parsejar_aca <- function(txt) {
  dj <- tryCatch(fromJSON(txt), error = function(e) NULL)
  if (is.null(dj) || is.null(dj$observations) || length(dj$observations) == 0)
    return(data.frame(Time = as.POSIXct(character(0), tz = "UTC"), valor = numeric(0)))
  obs <- dj$observations
  data.frame(Time  = as.POSIXct(as.numeric(obs$time) / 1000, origin = "1970-01-01", tz = "UTC"),
             valor = suppressWarnings(as.numeric(obs$value))) %>% arrange(Time)
}

baixar_per_blocs <- function(proveidor, sensor_id, data_i, data_f, hores_bloc = 12,
                             baixar = baixar_sensor_aca) {
  if (data_i >= data_f) return(NULL)
  talls <- seq(data_i, data_f, by = sprintf("%d hours", hores_bloc))
  if (max(talls) < data_f) talls <- c(talls, data_f)
  parts <- list()
  for (i in seq_len(length(talls) - 1)) {
    d <- baixar(proveidor, sensor_id, talls[i], talls[i + 1])
    if (!is.null(d) && nrow(d) > 0) parts[[length(parts) + 1]] <- d
    Sys.sleep(PAUSA_API)
  }
  if (length(parts) == 0) return(NULL)
  bind_rows(parts) %>% distinct(Time, .keep_all = TRUE) %>% arrange(Time)
}
PAUSA_API <- 0.3

# Cabal a 30 min: mateixa regla que l'entrenament (round_date + primer valor vàlid)
a_30min <- function(d) {
  if (is.null(d) || nrow(d) == 0) return(NULL)
  d %>% mutate(Time = round_date(Time, unit = PAS)) %>%
    group_by(Time) %>% summarise(valor = first(na.omit(valor)), .groups = "drop") %>%
    filter(!is.na(valor), valor >= 0) %>% arrange(Time)
}

# Meteocat: una petició per dia per a totes les estacions
baixar_meteocat_dia <- function(dia, api_key) {
  url <- sprintf("%s/%s/%s/%s/%s", URL_METEO_DADES, CODI_VAR_PLUJA,
                 format(dia, "%Y"), format(dia, "%m"), format(dia, "%d"))
  resp <- tryCatch(GET(url, add_headers("X-Api-Key" = api_key), timeout(60)),
                   error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  if (status_code(resp) == 429) stop("Quota de l'API del Meteocat esgotada (HTTP 429)")
  if (status_code(resp) != 200) {
    message(sprintf("  Meteocat %s: HTTP %d", format(dia), status_code(resp)))
    return(NULL)
  }
  parsejar_meteocat(content(resp, as = "text", encoding = "UTF-8"))
}

parsejar_meteocat <- function(txt) {
  dj <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  buit <- data.frame(estacio = character(0), Time = as.POSIXct(character(0), tz = "UTC"),
                     valor = numeric(0))
  if (is.null(dj) || length(dj) == 0) return(buit)
  files <- list()
  for (st in dj) for (v in st$variables %||% list()) for (l in v$lectures %||% list())
    files[[length(files) + 1]] <- c(st$codi %||% NA, l$data %||% NA,
                                    as.character(l$valor %||% NA))
  if (length(files) == 0) return(buit)
  m <- do.call(rbind, files)
  data.frame(estacio = m[, 1],
             Time = parse_date_time(m[, 2], orders = c("Ymd HMS", "Ymd HM"), tz = "UTC",
                                    quiet = TRUE),
             valor = suppressWarnings(as.numeric(m[, 3]))) %>%
    filter(!is.na(Time))
}

# Pluja a 30 min: floor_date + suma (com a l'entrenament, script 01)
pluja_30min <- function(d) {
  d$valor[!is.na(d$valor) & d$valor < 0] <- NA_real_
  d %>% mutate(Time = floor_date(Time, unit = PAS)) %>%
    group_by(estacio, Time) %>%
    summarise(valor = if (all(is.na(valor))) NA_real_ else sum(valor, na.rm = TRUE),
              .groups = "drop")
}

# ==============================================================================
# 2. Estat (base crua) i fusió
# ==============================================================================
graella_buida <- function(estructura, data_i, data_f) {
  g <- data.frame(Time = seq(floor_date(data_i, PAS), floor_date(data_f, PAS), by = PAS))
  for (c in setdiff(names(estructura), "Time")) g[[c]] <- NA_real_
  g
}

# Uneix la base vella i la nova: per a cada instant preval el valor nou no NA
fusionar <- function(vell, nou) {
  if (is.null(vell) || nrow(vell) == 0) return(nou %>% arrange(Time))
  bind_rows(nou, vell) %>%
    group_by(Time) %>%
    summarise(across(everything(), ~ dplyr::first(.x[!is.na(.x)], default = NA_real_)),
              .groups = "drop") %>%
    arrange(Time)
}

# Base de treball per a les variables: graella completa, imputació i lag de la pluja
preparar_base <- function(df_crua, cols_cabal, cols_emb, cols_pluja) {
  d <- data.frame(Time = seq(min(df_crua$Time), max(df_crua$Time), by = PAS)) %>%
    left_join(df_crua, by = "Time") %>% arrange(Time)
  for (c in intersect(cols_cabal, names(d))) {
    d[[c]] <- zoo::na.approx(d[[c]], maxgap = GAP_CABAL, na.rm = FALSE)
    d[[c]] <- zoo::na.locf(d[[c]], maxgap = GAP_CABAL, na.rm = FALSE)  # latència de l'API
  }
  for (c in cols_emb) d[[c]] <- zoo::na.locf(d[[c]], na.rm = FALSE)
  for (c in cols_pluja) {
    x <- d[[c]]; x[is.na(x)] <- 0
    d[[c]] <- dplyr::lag(x, 1)  # Convenció A (script 03)
  }
  d
}

# ==============================================================================
# 3. Variables (idèntic a 07_variables.R i a l'operatiu)
# ==============================================================================
acum_enrere <- function(x, finestra_h) {
  x0 <- ifelse(is.na(x), 0, x)
  as.numeric(rollapplyr(x0, width = h2p(finestra_h), FUN = sum, fill = NA, partial = FALSE))
}
api_recursiu <- function(pluja, alpha) {
  p0 <- ifelse(is.na(pluja), 0, pluja); out <- numeric(length(p0)); acc <- 0
  for (i in seq_along(p0)) { acc <- alpha * acc + p0[i]; out[i] <- acc }; out
}
calcular_pesos <- function(y) {
  q <- quantile(y, c(0.75, 0.90, 0.95, 0.99), na.rm = TRUE); w <- rep(1, length(y))
  w[y > q[1]] <- W_Q75; w[y > q[2]] <- W_Q90; w[y > q[3]] <- W_Q95; w[y > q[4]] <- W_Q99
  w[y > LLINDAR_MIN_Q & y > q[3]] <- W_SURGE; w
}
construir_features <- function(d, cols_pluja, cols_emb, cols_era5) {
  cols_cabal_tot   <- grep(" Cabal$", names(d), value = TRUE)
  cols_cabal_amunt <- setdiff(cols_cabal_tot, NOM_OBJECTIU_INTERN)
  qsjd <- d[[NOM_OBJECTIU_INTERN]]
  B <- data.frame(Time = d$Time)
  for (L in LAGS_Q_SJD) B[[sprintf("QSJD_lag%dh", L)]] <- if (L == 0) qsjd else lag(qsjd, h2p(L))
  for (W in ROLLMAX_SJD) B[[sprintf("QSJD_rollmax_%dh", W)]] <-
    as.numeric(rollapplyr(qsjd, width = h2p(W), FUN = max, fill = NA, partial = FALSE))
  for (D in DIFF_SJD) B[[sprintf("QSJD_diff_%dh", D)]] <- qsjd - lag(qsjd, h2p(D))
  for (est in cols_cabal_amunt) {
    nom <- gsub("[^A-Za-z0-9]", "_", sub(" Cabal$", "", est))
    for (L in LAGS_CABALS) B[[sprintf("Q_%s_lag%dh", nom, L)]] <- lag(d[[est]], h2p(L))
  }
  for (est in cols_pluja)
    for (Fw in FINESTRES_PLUJA) B[[sprintf("P_%s_acum_%dh", est, Fw)]] <- acum_enrere(d[[est]], Fw)
  pluja_total <- rowSums(d[, cols_pluja, drop = FALSE], na.rm = TRUE)
  for (Fw in FINESTRES_PLUJA) B[[sprintf("P_global_acum_%dh", Fw)]] <- acum_enrere(pluja_total, Fw)
  B[["API_slow"]] <- api_recursiu(pluja_total, API_ALPHA_SLOW)
  B[["API_fast"]] <- api_recursiu(pluja_total, API_ALPHA_FAST)
  for (e in cols_emb) { B[[e]] <- d[[e]]; B[[paste0(e, "_var24h")]] <- d[[e]] - lag(d[[e]], h2p(24)) }
  for (v in cols_era5) B[[v]] <- d[[v]]
  B
}
vars_horitzo <- function(hist, h, n) {
  hh <- hist[[paste0("h", h)]]; k <- as.integer(names(hh)); hh[[as.character(k[which.min(abs(k - n))])]]
}
treure_vars <- function(hist) lapply(hist, function(ph) lapply(ph, function(v) setdiff(v, VARS_EXCLOURE)))

tipus_columnes <- function(noms) {
  era5 <- intersect(c("swvl1", "swvl2", "swvl3", "swvl4", "sde", "t2m", "pev"), noms)
  emb  <- grep("^emb_", noms, value = TRUE)
  cab  <- grep(" Cabal$", noms, value = TRUE)
  plu  <- setdiff(grep("^[A-Z][0-9A-Z]$", noms, value = TRUE), c(cab, era5, emb))
  list(era5 = era5, emb = emb, cabal = cab, pluja = plu)
}

# "Truc" del TFG: primer s'elimina el que el model no ha de veure i després es
# renombra el cabal objectiu com a "SantJoan Cabal"
aplicar_truc <- function(d, cfg) {
  for (col in cfg$eliminar) if (col %in% names(d)) d[[col]] <- NULL
  if (cfg$nom_real != NOM_OBJECTIU_INTERN) {
    d[[NOM_OBJECTIU_INTERN]] <- d[[cfg$nom_real]]
    d[[cfg$nom_real]] <- NULL
  }
  d
}

classificar_risc <- function(p, q_thr) {
  ifelse(p > q_thr[["q99"]], "CRITIC", ifelse(p > q_thr[["q95"]], "ALERTA", "NORMAL"))
}
