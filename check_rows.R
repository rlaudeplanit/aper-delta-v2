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
required_packages <- c("DBI", "duckdb", "here", "yaml")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(">>> Installing missing package: ", pkg)
    install.packages(pkg, type = "binary", repos = "https://cloud.r-project.org/", lib = lib_dir)
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
  grepl("^//", raw_db_path) || grepl("^\\\\\\\\", raw_db_path) ||
  grepl("^[A-Za-z]:[/\\\\]", raw_db_path) ||
  grepl("^/[^/]", raw_db_path)
) {
  normalizePath(raw_db_path, winslash = "/", mustWork = FALSE)
} else {
  file.path(current_dir, raw_db_path)
}

message(">>> Connecting to Vault at: ", db_full_path)

if (!file.exists(db_full_path)) {
  stop(paste0("Database file not found at: ", db_full_path))
}

# --- [CONNECT (READ-ONLY)] ---
con <- dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = db_full_path, read_only = TRUE)

# --- [LIST AND QUERY TABLES] ---
all_tables <- dbListTables(con)

if (length(all_tables) > 0) {
  message(">>> SUCCESS: Found ", length(all_tables), " table(s) in the Vault.")
  
  for (tbl_name in all_tables) {
    message("\n=============================================")
    message("  TABLE: ", tbl_name)
    message("=============================================")
    
    # Query distinct runs without app_name and timestamp
    query <- sprintf("
      SELECT DISTINCT
        sequence_num,
        run_id,
        project_name,
        test_name
      FROM %s
      ORDER BY sequence_num DESC
    ", tbl_name)
    
    unique_records <- tryCatch({
      dbGetQuery(con, query)
    }, error = function(e) {
      message("  [ERROR] Failed to query table: ", e$message)
      NULL
    })
    
    if (!is.null(unique_records) && nrow(unique_records) > 0) {
      message("  Distinct Runs (Ordered by sequence_num DESC):\n")
      print(unique_records, row.names = FALSE)
    } else if (!is.null(unique_records)) {
      message("  (Table contains no data)")
    }
  }
} else {
  message(">>> [ERROR] No tables found. Database file is empty.")
}

# --- [SAFE DISCONNECT] ---
dbDisconnect(con)
invisible(gc())

message("\n>>> Connection dropped safely. File lock released.")