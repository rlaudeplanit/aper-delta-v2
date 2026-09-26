# --- [PORTABLE ROOT WORKSPACE & ENVIRONMENT SETUP] ---
get_active_script_dir <- function() {
  args   <- commandArgs(trailingOnly = FALSE)
  needle <- "--file="
  match  <- grep(needle, args)
  if (length(match) > 0) {
    return(dirname(normalizePath(sub(needle, "", args[match]))))
  } else {
    return(getwd())
  }
}

# Resolve project root whether run from root or inside a subfolder (like .engine/)
script_dir  <- get_active_script_dir()
current_dir <- if (dir.exists(file.path(script_dir, "RLibs"))) {
  script_dir
} else if (dir.exists(file.path(dirname(script_dir), "RLibs"))) {
  dirname(script_dir)
} else {
  getwd()
}

lib_dir <- file.path(current_dir, "RLibs")
if (!dir.exists(lib_dir)) dir.create(lib_dir, recursive = TRUE)
r_base_lib <- file.path(R.home(), "library")
.libPaths(c(lib_dir, r_base_lib))

# --- [AUTO-BOOTSTRAP PACKAGES] ---
required_packages <- c("DBI", "duckdb", "yaml")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(
      pkg,
      type = "binary",
      repos = "https://cloud.r-project.org/",
      lib = lib_dir
    )
  }
  suppressWarnings(suppressMessages(library(pkg, character.only = TRUE)))
}

# --- [RESOLVE DATABASE PATH FROM CONFIG] ---
config_file <- file.path(current_dir, "config.yaml")

if (!file.exists(config_file)) {
  stop(paste0("ERROR: config.yaml not found at: ", config_file))
}

params_cfg  <- yaml::read_yaml(config_file)
raw_db_path <- params_cfg$database_path

db_full_path <- if (
  grepl("^//", raw_db_path) ||
  grepl("^\\\\\\\\", raw_db_path) ||
  grepl("^[A-Za-z]:[/\\\\]", raw_db_path) ||
  grepl("^/[^/]", raw_db_path)
) {
  normalizePath(raw_db_path, winslash = "/", mustWork = FALSE)
} else {
  file.path(current_dir, raw_db_path)
}

message(">>> Connecting to Vault at: ", db_full_path)

# --- [CONNECT] ---
con <- dbConnect(
  duckdb::duckdb(shared_home = FALSE),
  dbdir = db_full_path,
  read_only = TRUE
)

# ============================================================
# CHANGE THIS VALUE
# ============================================================
target_label <- "c_CMS_Pacing"

# ============================================================
# EXACT MATCH
# ============================================================
cat("\n==================================================\n")
cat("EXACT MATCH\n")
cat("==================================================\n")

query1 <- sprintf("
SELECT DISTINCT
    run_id,
    '[' || label || ']' AS label,
    LENGTH(label) AS label_length
FROM performance_history_neoload
WHERE label = '%s'
ORDER BY run_id
", target_label)

print(dbGetQuery(con, query1))

# ============================================================
# PARTIAL MATCH
# ============================================================
cat("\n==================================================\n")
cat("PARTIAL MATCH\n")
cat("==================================================\n")

query2 <- sprintf("
SELECT DISTINCT
    run_id,
    '[' || label || ']' AS label,
    LENGTH(label) AS label_length
FROM performance_history_neoload
WHERE label LIKE '%%%s%%'
ORDER BY run_id
", target_label)

print(dbGetQuery(con, query2))

# ============================================================
# ALL CMS LABELS
# ============================================================
cat("\n==================================================\n")
cat("ALL LABELS CONTAINING 'CMS'\n")
cat("==================================================\n")

query3 <- "
SELECT DISTINCT
    '[' || label || ']' AS label,
    LENGTH(label) AS label_length
FROM performance_history_neoload
WHERE label LIKE '%CMS%'
ORDER BY label
"

print(dbGetQuery(con, query3))

query4 <- "
SELECT 
    COUNT(*)
FROM performance_history_neoload
WHERE run_id IN ('750-Tarawera','1338-MarinaSands')
    AND (label LIKE '%c_CMS_Pacing%')  
"

print(dbGetQuery(con, query4))

# --- [SAFE DISCONNECT] ---
dbDisconnect(con)
invisible(gc())

message("\n>>> Connection dropped safely. File lock released.")