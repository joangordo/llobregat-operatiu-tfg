# web.R — Pàgina estàtica amb l'última predicció (GitHub Pages)

fmt_local <- function(t, f = "%d/%m %H:%M") format(with_tz(t, "Europe/Madrid"), f)

svg_estacio <- function(r, q_thr, obs) {
  W <- 640; H <- 220; ml <- 48; mr <- 12; mt <- 12; mb <- 28
  names(obs) <- c("Time", "Q")
  tt <- c(obs$Time, r$t_target); yy <- c(obs$Q, r$pred, q_thr[["q95"]])
  x0 <- min(tt); x1 <- max(tt); y1 <- max(yy, na.rm = TRUE) * 1.1; if (!is.finite(y1) || y1 <= 0) y1 <- 1
  sx <- function(t) ml + (as.numeric(t) - as.numeric(x0)) / (as.numeric(x1) - as.numeric(x0)) * (W - ml - mr)
  sy <- function(y) mt + (1 - y / y1) * (H - mt - mb)
  ob <- obs[!is.na(obs$Q), ]
  linia <- function(t, y) paste(sprintf("%.1f,%.1f", sx(t), sy(y)), collapse = " ")
  pred_t <- c(r$t0[1], r$t_target); pred_y <- c(r$cabal_t0[1], r$pred)
  ticks <- pretty(c(0, y1), 4); ticks <- ticks[ticks <= y1]
  eix <- paste(sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" class="grid"/><text x="%d" y="%.1f" class="tick" text-anchor="end">%s</text>',
                       ml, W - mr, sy(ticks), sy(ticks), ml - 6, sy(ticks) + 4, format(ticks)), collapse = "")
  hores <- seq(ceiling_date(x0, "6 hours"), x1, by = "6 hours")
  eix_x <- paste(sprintf('<text x="%.1f" y="%d" class="tick" text-anchor="middle">%s</text>',
                         sx(hores), H - 8, fmt_local(hores, "%H:%M")), collapse = "")
  sprintf(paste0('<svg viewBox="0 0 %d %d" role="img" aria-label="Cabal observat i previst">%s%s',
                 '<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" class="q95"/>',
                 '<text x="%d" y="%.1f" class="tick" text-anchor="end">Q95</text>',
                 '<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" class="ara"/>',
                 '<polyline points="%s" class="obs"/><polyline points="%s" class="pred"/>%s</svg>'),
          W, H, eix, eix_x, ml, W - mr, sy(q_thr[["q95"]]), sy(q_thr[["q95"]]),
          W - mr - 2, sy(q_thr[["q95"]]) - 4, sx(r$t0[1]), sx(r$t0[1]), mt, H - mb,
          linia(ob$Time, ob$Q), linia(pred_t, pred_y),
          paste(sprintf('<circle cx="%.1f" cy="%.1f" r="3" class="pt"/>', sx(r$t_target), sy(r$pred)), collapse = ""))
}

escriure_web <- function(resultats, ruta, ara) {
  blocs <- vapply(resultats, function(r) {
    cfg <- ESTACIONS[[r$estacio[1]]]; q_thr <- attr(r, "q_thr")
    files <- paste(sprintf('<tr><td>+%d h</td><td>%s</td><td class="num">%.2f</td><td><span class="risc %s">%s</span></td></tr>',
                           r$horitzo, fmt_local(r$t_target), r$pred, tolower(r$risc), r$risc), collapse = "")
    absents <- if (max(r$n_vars_absents) > 0)
      sprintf('<p class="nota">Variables sense dada en aquesta predicció: fins a %d de %d.</p>',
              max(r$n_vars_absents), r$n_vars[1]) else ""
    sprintf(paste0('<section><h2>%s</h2><p class="meta">Última dada: %s · %.2f m³/s · ',
                   'Q95 %.1f · Q99 %.1f m³/s</p>%s<table><thead><tr><th>Horitzó</th>',
                   '<th>Hora</th><th class="num">Cabal previst (m³/s)</th><th>Risc</th></tr></thead>',
                   '<tbody>%s</tbody></table>%s<p class="csv"><a href="ultima_prediccio_%s.csv">CSV</a></p></section>'),
            cfg$nom, fmt_local(r$t0[1], "%d/%m/%Y %H:%M"), r$cabal_t0[1], q_thr[["q95"]], q_thr[["q99"]],
            svg_estacio(r, q_thr, attr(r, "observat")), files, absents, r$estacio[1])
  }, character(1))
  html <- sprintf('<!doctype html>
<html lang="ca"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Predicció del Llobregat</title>
<style>
:root{--bg:#fafaf8;--fg:#1d1d1b;--mut:#6b6b66;--line:#dcdcd6;--obs:#1f5fa8;--pred:#c2571a;--ok:#2e7d4f;--warn:#b7791f;--crit:#b42318}
@media (prefers-color-scheme:dark){:root{--bg:#161615;--fg:#ececea;--mut:#a3a39e;--line:#353533;--obs:#6ea8ef;--pred:#f08a4b;--ok:#5cc48a;--warn:#e0b04f;--crit:#f2776b}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,sans-serif}
main{max-width:720px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:1.5rem;margin:0 0 4px}h2{font-size:1.15rem;margin:32px 0 4px}
.meta,.nota,footer{color:var(--mut);font-size:.9rem}
table{width:100%%;border-collapse:collapse;margin-top:8px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line)}
.num{text-align:right;font-variant-numeric:tabular-nums}
.risc{font-weight:600;font-size:.8rem;padding:2px 8px;border-radius:999px;border:1px solid currentColor}
.normal{color:var(--ok)}.alerta{color:var(--warn)}.critic{color:var(--crit)}
svg{width:100%%;height:auto;margin-top:8px}.grid{stroke:var(--line)}.tick{fill:var(--mut);font-size:11px}
.obs{fill:none;stroke:var(--obs);stroke-width:2}.pred{fill:none;stroke:var(--pred);stroke-width:2;stroke-dasharray:5 4}
.pt{fill:var(--pred)}.q95{stroke:var(--warn);stroke-dasharray:2 3}.ara{stroke:var(--mut);stroke-dasharray:1 3}
a{color:var(--obs)}
</style></head><body><main>
<h1>Predicció de cabal al Llobregat</h1>
<p class="meta">Actualitzat el %s (hora local) · Model M7 (LightGBM Tweedie) del TFG · Horitzons +1 a +6 h.
Blau: cabal observat; taronja: previsió.</p>
%s
<footer><p>Projecte acadèmic experimental (Grau d\'Estadística, UB). <strong>No és un sistema oficial d\'avís.</strong>
Informació oficial: <a href="https://aca.gencat.cat">Agència Catalana de l\'Aigua</a> i Protecció Civil.
Dades: ACA i Servei Meteorològic de Catalunya. <a href="historic_prediccions.csv">Històric de prediccions (CSV)</a>.</p></footer>
</main></body></html>', fmt_local(ara, "%d/%m/%Y %H:%M"), paste(blocs, collapse = "\n"))
  writeLines(html, ruta, useBytes = TRUE)
}
