################################################################################
# Codebook Lexicon Coverage Audit (CREDI + GSED -> MN26)
#
# Purpose: Confirm that every item used by the CREDI or D-score scorers (which
# require both an instrument-specific lexicon AND a study lexicon) also has an
# `mn26` lexicon entry. Without an `mn26` entry, the item is silently dropped
# from MN26 scoring, even though it is scored for NE25.
#
# Usage:
#   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/mn26/audit_codebook_lexicons.R
#
# Exit codes:
#   0 -- all CREDI + GSED items with NE25 lexicon also have MN26 lexicon
#   1 -- one or more gaps detected (details printed)
#
# Run before merging the CREDI/D-score MN26 wiring (PR 1) so any gaps are
# surfaced and addressed deliberately rather than discovered as silent drops
# during MN26 scoring.
################################################################################

suppressPackageStartupMessages({
  library(jsonlite)
})

codebook_path <- "codebook/data/codebook.json"

if (!file.exists(codebook_path)) {
  stop(sprintf("[ERROR] Codebook not found at %s. Run from project root.", codebook_path))
}

cat("[INFO] Loading codebook from", codebook_path, "\n")
codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)
cat(sprintf("[INFO] Loaded %d codebook items\n\n", length(codebook$items)))

# -----------------------------------------------------------------------------
# Build the two scorer-relevant item sets, mirroring the scorer iteration logic
# -----------------------------------------------------------------------------
# CREDI: R/credi/score_credi.R lines 74-81 -- requires lexicons$credi starting
# with "LF" AND lexicons$ne25.
# D-score: R/dscore/score_dscore.R lines 69-82 -- requires lexicons$gsed AND
# lexicons$ne25.

credi_items <- list()
gsed_items  <- list()

for (item_key in names(codebook$items)) {
  item <- codebook$items[[item_key]]
  lex  <- item$lexicons
  if (is.null(lex)) next

  has_ne25 <- !is.null(lex$ne25)
  has_mn26 <- !is.null(lex$mn26)

  if (has_ne25 && !is.null(lex$credi) && startsWith(as.character(lex$credi), "LF")) {
    credi_items[[item_key]] <- list(
      credi    = lex$credi,
      ne25     = lex$ne25,
      mn26     = if (has_mn26) lex$mn26 else NA_character_,
      has_mn26 = has_mn26
    )
  }

  if (has_ne25 && !is.null(lex$gsed)) {
    gsed_items[[item_key]] <- list(
      gsed     = lex$gsed,
      ne25     = lex$ne25,
      mn26     = if (has_mn26) lex$mn26 else NA_character_,
      has_mn26 = has_mn26
    )
  }
}

# -----------------------------------------------------------------------------
# Report per scorer
# -----------------------------------------------------------------------------

report_set <- function(set_name, items) {
  n_total   <- length(items)
  n_covered <- sum(vapply(items, function(x) isTRUE(x$has_mn26), logical(1)))
  n_gap     <- n_total - n_covered

  cat(sprintf("=== %s ===\n", set_name))
  cat(sprintf("  Total items (NE25-scored):       %d\n", n_total))
  cat(sprintf("  Also have MN26 lexicon:          %d\n", n_covered))
  cat(sprintf("  Missing MN26 lexicon (GAPS):     %d\n", n_gap))

  if (n_gap > 0) {
    gaps <- items[!vapply(items, function(x) isTRUE(x$has_mn26), logical(1))]
    cat("\n  Items missing MN26 lexicon:\n")
    cat(sprintf("    %-14s %-10s %s\n", "item_key", "instr_lex", "ne25_lex"))
    cat(sprintf("    %s\n", strrep("-", 60)))
    for (k in names(gaps)) {
      g <- gaps[[k]]
      instr <- if (!is.null(g$credi)) g$credi else g$gsed
      cat(sprintf("    %-14s %-10s %s\n", k, instr, g$ne25))
    }
  }
  cat("\n")
  invisible(n_gap)
}

n_credi_gap <- report_set("CREDI items (NE25 -> MN26)", credi_items)
n_gsed_gap  <- report_set("GSED items (NE25 -> MN26)",  gsed_items)

total_gap <- n_credi_gap + n_gsed_gap

cat("=== Summary ===\n")
cat(sprintf("  Total gaps: %d\n", total_gap))

if (total_gap > 0) {
  cat("\n[ACTION] Backfill the missing lexicons$mn26 entries in",
      "codebook/data/codebook.json before MN26 scoring will pick up these items.\n")
  cat("[INFO] Items without an MN26 lexicon will be silently dropped from MN26 scoring,\n")
  cat("       even though they are scored for NE25. This audit prevents silent drift.\n")
  quit(status = 1)
} else {
  cat("\n[OK] All NE25-scored CREDI and GSED items also have MN26 lexicon coverage.\n")
  quit(status = 0)
}
