# Prova de punta a punta amb APIs i models simulats:
#   Rscript tests/test_pipeline.R
arrel <- normalizePath(".")
tmp <- Sys.getenv("TEST_DIR", file.path(tempdir(), "operatiu")); unlink(tmp, recursive = TRUE); dir.create(tmp)
invisible(file.copy(file.path(arrel, c("R", "tests", "prediccio_operativa.R")), tmp, recursive = TRUE))
setwd(tmp); dir.create("inputs"); Sys.setenv(LLOBREGAT_TEST = "1", METEOCAT_API_KEY = "fals")
suppressPackageStartupMessages({ library(dplyr); library(lubridate) })

est <- data.frame(Time = as.POSIXct(character(0), tz = "UTC"), `SantJoan Cabal` = numeric(0),
                  `Martorell Cabal` = numeric(0), `Castellbell Cabal` = numeric(0),
                  `Abrera Cabal` = numeric(0), CC = numeric(0), U4 = numeric(0),
                  emb_baells_volum_hm3 = numeric(0), swvl1 = numeric(0), check.names = FALSE)
saveRDS(est, "inputs/estructura_base.rds")
write.csv(data.frame(estacio = c("SantJoan Cabal", "Martorell Cabal", "Castellbell Cabal", "Abrera Cabal"),
                     sensor_id = c("CALC001261", "CALC001836", "CALC001244", "SENSE_DADES")),
          "inputs/mapeig_sensors.csv", row.names = FALSE)
vars <- c("QSJD_lag0h", "QSJD_diff_1h", "Q_Castellbell_lag3h", "P_CC_acum_6h", "API_slow",
          "emb_baells_volum_hm3", "swvl1", "Q_Abrera_lag1h")
for (id in c("sjd", "martorell")) {
  dir.create(file.path("models", id), recursive = TRUE)
  saveRDS(setNames(rep(list(vars), 6), paste0("h", 1:6)), file.path("models", id, "vars.rds"))
  saveRDS(c(q95 = 40, q99 = 90), file.path("models", id, "llindars.rds"))
  cols <- names(est); if (id == "sjd") cols <- setdiff(cols, "Martorell Cabal")
  if (id == "martorell") cols <- setdiff(cols, "Martorell Cabal")  # després del truc, Martorell es diu SantJoan
  saveRDS(cols, file.path("models", id, "columnes.rds"))
  saveRDS(list(swvl1 = setNames(rep(0.3, 12), 1:12)), file.path("models", id, "climatologia_era5.rds"))
}

comprova <- function(cond, msg) { if (!isTRUE(cond)) stop("FALLA: ", msg); cat("OK:", msg, "\n") }

ARA_FIXAT <- as.POSIXct("2026-11-16 10:12:00", tz = "UTC")
source("prediccio_operativa.R")
e1 <- readRDS("cache/estat.rds")
comprova(nrow(e1$df_crua) >= 25 * 48, "primera execució reconstrueix 25 dies")
comprova(CRIDES$meteo == 26, "una petició al Meteocat per dia (26 dies)")
comprova(all(c("ultima_prediccio_sjd.csv", "ultima_prediccio_martorell.csv", "index.html") %in% list.files("web")),
         "CSV i web generats")
p1 <- read.csv("web/ultima_prediccio_sjd.csv")
comprova(nrow(p1) == 6 && all(p1$horitzo == 1:6), "6 horitzons")
comprova(all(p1$n_vars_absents == 1), "Abrera (sense dades) queda NA; swvl1 s'omple amb la climatologia")
b <- preparar_base(e1$df_crua, tipus$cabal, tipus$emb, tipus$pluja)
comprova(sum(b$CC, na.rm = TRUE) > 0, "la pluja s'ha llegit i no és tota 0")
raw <- e1$df_crua$CC; i <- which(!is.na(raw) & raw > 0)[3]
comprova(b$CC[i + 1] == raw[i], "la pluja es retarda 1 pas (Convenció A)")
comprova(any(!is.na(b$emb_baells_volum_hm3)), "volum de La Baells actualitzat")
m <- read.csv("web/ultima_prediccio_martorell.csv")
comprova(m$cabal_t0[1] != p1$cabal_t0[1], "Martorell fa servir el seu propi cabal (truc)")

CRIDES$meteo <- 0; CRIDES$aca <- 0
ARA_FIXAT <- ARA_FIXAT + 30 * 60
source("prediccio_operativa.R")
e2 <- readRDS("cache/estat.rds")
comprova(CRIDES$meteo <= 2, "segona execució: 1-2 peticions al Meteocat")
comprova(max(e2$df_crua$Time) > max(e1$df_crua$Time), "l'estat avança")
comprova(nrow(e2$historic) == 24, "històric de prediccions acumulat (2 execucions x 2 estacions x 6)")
cat("\nTots els tests han passat.\n")
