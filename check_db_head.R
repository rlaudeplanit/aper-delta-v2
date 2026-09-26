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

# --- [LIST AND INSPECT TABLES] ---
all_tables <- dbListTables(con)

if (length(all_tables) > 0) {
  message(">>> SUCCESS: Found ", length(all_tables), " table(s) in the Vault.")
  
  for (tbl_name in all_tables) {
    total_rows <- dbGetQuery(con, paste0("SELECT COUNT(*) as total FROM ", tbl_name))$total
    
    message("\n=============================================")
    message("  TABLE: ", tbl_name)
    message("  Total Cumulative Rows: ", total_rows)
    message("=============================================")
    message("  Column Headers with Sample Values:")
    
    col_headers <- dbGetQuery(con, paste0("PRAGMA table_info(", tbl_name, ");"))
    
    sample_row <- NULL
    if (total_rows > 0) {
      sample_row <- dbGetQuery(con, paste0("SELECT * FROM ", tbl_name, " LIMIT 1"))
    }
    
    max_name_len <- max(nchar(col_headers$name))
    max_type_len <- max(nchar(col_headers$type))
    
    for (i in seq_len(nrow(col_headers))) {
      name  <- col_headers$name[i]
      type  <- col_headers$type[i]
      value <- if (!is.null(sample_row)) as.character(sample_row[[name]]) else "(no data)"
      
      name_pad <- paste(rep(" ", max_name_len - nchar(name)), collapse = "")
      type_pad <- paste(rep(" ", max_type_len - nchar(type)), collapse = "")
      
      message("    ", name, name_pad, "   ", type, type_pad, "   ", value)
    }
  }
} else {
  message(">>> [ERROR] No tables found. The database file at this path is empty.")
}

# --- [CLEAN DISCONNECT] ---
dbDisconnect(con)
invisible(gc())

message(">>> Connection dropped safely. File lock released.")