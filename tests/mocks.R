# Substituts de les APIs i de lightgbm per provar el pipeline sense xarxa.
PAUSA_API <- 0
CRIDES <- new.env(); CRIDES$aca <- 0; CRIDES$meteo <- 0

baixar_sensor_aca <- function(proveidor, sensor_id, data_i, data_f) {
  CRIDES$aca <- CRIDES$aca + 1
  t <- seq(data_i, data_f, by = "5 min")
  if (sensor_id == "SENSE_DADES") t <- t[0]
  base <- if (proveidor == "EMBASSAMENT-EST") 60 else 20
  v <- base + 5 * sin(as.numeric(t) / 20000) + (sensor_id == "CALC001836") * 3
  obs <- data.frame(value = sprintf("%.3f", v), time = as.character(round(as.numeric(t) * 1000)),
                    timestamp = format(t, "%d/%m/%YT%H:%M:%S", tz = "UTC"))
  parsejar_aca(jsonlite::toJSON(list(observations = obs), auto_unbox = TRUE))
}

baixar_meteocat_dia <- function(dia, api_key) {
  CRIDES$meteo <- CRIDES$meteo + 1
  t <- seq(as.POSIXct(paste(dia, "00:00"), tz = "UTC"), by = "30 min", length.out = 48)
  lect <- lapply(seq_along(t), function(i) list(data = format(t[i], "%Y-%m-%dT%H:%MZ", tz = "UTC"),
                                                 valor = if (i %% 10 == 0) 1.5 else 0, estat = "V"))
  est <- lapply(c("CC", "U4", "ZZ"), function(c) list(codi = c, variables = list(list(codi = 35, lectures = lect))))
  parsejar_meteocat(jsonlite::toJSON(est, auto_unbox = TRUE))
}

carregar_model <- function(ruta) ruta
predir_model <- function(mod, x) { v <- x[1, !is.na(x[1, ])]; if (length(v)) abs(mean(v)) else 0 }
