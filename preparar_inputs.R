# ==============================================================================
# preparar_inputs.R — Genera inputs/ i models/ a partir de les dades del TFG
# ------------------------------------------------------------------------------
# NOMÉS cal tornar-lo a executar si canvien els models. S'executa des de l'arrel
# del repositori, amb aquests fitxers del TFG (que NO es pugen a GitHub):
#   inputs/base_filtrada_sjd.RData, inputs/base_filtrada_martorell.RData
#   inputs/dataset_features_sjd.RData, inputs/dataset_features_martorell.RData
#   cache/models_sjd/, cache/models_martorell/   (m7_h1..6.txt i vars.rds)
# Genera (i aquests SÍ es pugen):
#   inputs/estructura_base.rds   columnes de la base (unió de les dues estacions, 0 files)
#   inputs/mapeig_sensors.csv    columna de cabal -> sensor de l'ACA
#   models/<id>/m7_h*.txt, vars.rds, llindars.rds, columnes.rds
# ==============================================================================
source("R/funcions.R")

carregar_base <- function(f, obj = NULL) {
  e <- new.env(); load(f, envir = e); get(obj %||% ls(e)[1], envir = e)
}
base_sjd <- carregar_base("inputs/base_filtrada_sjd.RData", "base_filtrada")
base_mar <- carregar_base("inputs/base_filtrada_martorell.RData", "base_filtrada")  # "SantJoan Cabal" = Martorell (truc ja aplicat)

# Columnes que veu cada model DESPRÉS del truc (les mateixes de l'entrenament)
columnes <- list(sjd = setdiff(names(base_sjd), "Martorell Cabal"),
                 martorell = names(base_mar))

# Estructura de la base crua: totes les columnes amb el seu nom real
estructura <- as.data.frame(base_sjd[0, ])
for (c in setdiff(names(base_mar), names(base_sjd))) estructura[[c]] <- numeric(0)
saveRDS(estructura, "inputs/estructura_base.rds")

# Sensors de cabal (catàleg Sentilo de l'ACA, per terme municipal i codi d'estació)
sensors <- c("SantJoan Cabal" = "CALC001261",      # LB-60 Sant Joan Despí
             "Martorell Cabal" = "CALC001836",     # LB-50 Anoia a Martorell
             "Castellbisbal Cabal" = "CALC001446", # LB-30
             "Castellbell Cabal" = "CALC001244",   # LB-25
             "Balsareny Cabal" = "CALC001230",     # LB-15
             "Berga Cabal" = "CALC001304",         # LB-05
             "Guardiola Cabal" = "CALC001228",     # LA-10
             "Castelllar Cabal" = "CALC001223",    # LA-05 Castellar de n'Hug
             "Vilada Vilada Cabal" = "CALC001627", # LA-25
             "Cardona Cabal" = "CALC001241",       # CB-10
             "Guixers Monegal Cabal" = "CALC001632", # CA-05
             "Guixers Aigua Cabal" = "CALC001532", # CA-10 riera Aigua de Valls
             "SantQuinti Cabal" = "CALC001266",    # LB-35 Sant Quintí de Mediona
             "SantSadurni Cabal" = "CALC001249")   # LB-45 Anoia a Sant Sadurní
merdancol <- grep("^Vilada Merdan", names(estructura), value = TRUE)  # LA-20 riu Merdançol
mapeig <- data.frame(estacio = c(names(sensors), merdancol),
                     sensor_id = c(unname(sensors), rep("CALC001622", length(merdancol))))
falten <- setdiff(grep(" Cabal$", names(estructura), value = TRUE), mapeig$estacio)
if (length(falten)) stop("Columnes de cabal sense sensor: ", paste(falten, collapse = ", "))
write.csv(mapeig, "inputs/mapeig_sensors.csv", row.names = FALSE, fileEncoding = "UTF-8")

for (cfg in ESTACIONS) {
  dir_m <- file.path("models", cfg$id); dir.create(dir_m, recursive = TRUE, showWarnings = FALSE)
  fitxers <- c(sprintf("m7_h%d.txt", HORITZONS), "vars.rds")
  origen <- file.path("cache", sprintf("models_%s", cfg$id))
  if (!all(file.exists(file.path(origen, fitxers)))) stop("Falten els models a ", origen)
  file.copy(file.path(origen, fitxers), dir_m, overwrite = TRUE)
  ds <- carregar_base(sprintf("inputs/dataset_features_%s.RData", cfg$id), "dataset")
  q_thr <- quantile(ds$Q_actual, c(0.95, 0.99), na.rm = TRUE); names(q_thr) <- c("q95", "q99")
  saveRDS(q_thr, file.path(dir_m, "llindars.rds"))
  saveRDS(columnes[[cfg$id]], file.path(dir_m, "columnes.rds"))
  # ERA5 no existeix en temps real: es guarda la mitjana mensual de l'entrenament per
  # fer-la servir en lloc de deixar la variable buida (redueix l'error a Martorell)
  era5 <- intersect(c("swvl1", "swvl2", "swvl3", "sde", "t2m", "pev"), unique(unlist(readRDS(file.path(dir_m, "vars.rds")))))
  mes <- as.integer(format(ds$Time, "%m", tz = "UTC"))
  clim <- lapply(setNames(era5, era5), function(v) tapply(ds[[v]], mes, mean, na.rm = TRUE))
  saveRDS(clim, file.path(dir_m, "climatologia_era5.rds"))
  vars <- unique(unlist(readRDS(file.path(dir_m, "vars.rds"))))
  cols <- columnes[[cfg$id]]
  fals <- as.data.frame(matrix(0, nrow = 200, ncol = length(cols), dimnames = list(NULL, cols)))
  fals$Time <- seq(as.POSIXct("2026-01-01", tz = "UTC"), by = PAS, length.out = 200)
  tpf <- tipus_columnes(cols)
  falten <- setdiff(vars, names(construir_features(fals, tpf$pluja, tpf$emb, tpf$era5)))
  cat(sprintf("%s: Q95/Q99 = %.1f/%.1f m3/s · %d columnes · variables del model que no es poden calcular: %s\n",
              cfg$id, q_thr[["q95"]], q_thr[["q99"]], length(columnes[[cfg$id]]),
              if (length(falten)) paste(falten, collapse = ", ") else "cap"))
}
cat("Fet: inputs/ i models/ preparats.\n")
