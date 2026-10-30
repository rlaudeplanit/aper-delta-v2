###############################################################################
###                                                                         ###
###    #### ####  #### ##### ####   #####    #### ##### ##### #   # ####    ###
###   #     #   # #       #   #   #   #     #     #       #   #   # #   #   ###
###    ###  ####  #       #   ####    #      ###  ####    #   #   # ####    ###
###       # # #   #       #   #       #         # #       #   #   # #       ###
###    ####  #  #  #### ##### #       #     ####  #####   #    ###  #       ###
###                                                                         ###
###############################################################################

### Commands:
################### Rscript .engine\worker.R --opMode=register --rawResultsFolder="C:\Full\Path\ToFolder" --active_tool=jmeter
################### Rscript .engine\worker.R --opMode=register --rawResultsFolder="C:\Full\Path\ToFolder" --active_tool=neoload
############ Report Mode (1 or 2 runs — comp1=baseline, comp2=current):
################### Rscript .engine\worker.R --opMode=report --comp1=<baseline> --comp2=<current> --active_tool=jmeter --labelFilterParam=Demo
################### Rscript .engine\worker.R --opMode=report --comp1=<baseline> --comp2=<current> --active_tool=neoload --labelFilterParam=Demo

rm(list = ls())
gc()

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

current_dir <- dirname(get_active_script_dir())

lib_dir <- file.path(current_dir, "RLibs")
if (!dir.exists(lib_dir)) dir.create(lib_dir, recursive = TRUE)
r_base_lib <- file.path(R.home(), "library")
.libPaths(c(lib_dir, r_base_lib))

### Define list of core packages (trimmed for fast high-density executive report generation) ###
packages <- c(
  "yaml", "DBI", "duckdb", "lubridate", "readr", "knitr", "here",
  "rmarkdown", "flexdashboard", "rlang", "purrr", "tidyr", "scales",
  "dplyr", "vroom", "tools", "stringr", "htmltools", "jsonlite", "httr"
)

### Auto-bootstrap missing packages ###
for (pkg in packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, type = "binary", repos = "https://cran.rstudio.com/", lib = lib_dir)
  }
  suppressMessages(library(pkg, character.only = TRUE))
}

# --- [Inputs & Config] ---
raw_args <- commandArgs(trailingOnly = TRUE)

args_map <- list(
  opMode           = "report",
  rawResultsFolder = "NONE",
  comp1            = "NONE",
  comp2            = "NONE",
  current          = "NONE",
  base             = "NONE",
  baseline         = "NONE",
  active_tool      = "jmeter",
  outputFolder     = "NONE",
  labelFilterParam = "NONE"
)

if (length(raw_args) > 0) {
  for (arg in raw_args) {
    if (grepl("^--", arg)) {
      split_arg <- strsplit(sub("^--", "", arg), "=")[[1]]
      key <- split_arg[1]
      val <- if (length(split_arg) > 1) split_arg[2] else TRUE
      if (key %in% names(args_map)) args_map[[key]] <- val
    }
  }
}

opMode           <- args_map$opMode
rawResultsFolder <- args_map$rawResultsFolder
active_tool      <- args_map$active_tool
outputFolder     <- args_map$outputFolder
labelFilterParam <- args_map$labelFilterParam

# Support both explicit (--current / --base) and legacy (--comp1 / --comp2)
raw_current <- if (args_map$current != "NONE") {
  args_map$current
} else if (args_map$comp2 != "NONE") {
  args_map$comp2
} else if (args_map$comp1 != "NONE") {
  args_map$comp1
} else {
  "NONE"
}

raw_base <- if (args_map$base != "NONE") {
  args_map$base
} else if (args_map$baseline != "NONE") {
  args_map$baseline
} else if (args_map$comp2 != "NONE" && args_map$comp1 != "NONE") {
  args_map$comp1
} else {
  "NONE"
}

params_cfg <- yaml::read_yaml("config.yaml")

excluded_labels <- params_cfg$label_exclusions %||% character(0)

if (labelFilterParam != "NONE") {
  excluded_labels <- c(
    excluded_labels,
    trimws(unlist(strsplit(labelFilterParam, ",")))
  )

  excluded_labels <- unique(excluded_labels)
}

default_local_db <- file.path(current_dir, "Data", "Performance_Vault.duckdb")

raw_db_path <- if (!is.null(params_cfg$database_path) && nzchar(trimws(params_cfg$database_path))) {
  params_cfg$database_path
} else {
  "Data/Performance_Vault.duckdb"
}

target_db_path <- if (
  # UNC path (\\host\share or //host/share)
  grepl("^//", raw_db_path) || grepl("^\\\\\\\\", raw_db_path) ||
  # Absolute Windows path (C:/ or C:\)
  grepl("^[A-Za-z]:[/\\\\]", raw_db_path) ||
  # Absolute Linux path (/home/... or /mnt/...)
  grepl("^/[^/]", raw_db_path)
) {
  normalizePath(raw_db_path, winslash = "/", mustWork = FALSE)
} else {
  file.path(current_dir, raw_db_path)
}

# Verify target directory accessibility; fall back to local project Data/ folder if unreachable
target_db_dir <- dirname(target_db_path)

db_path <- tryCatch({
  if (!dir.exists(target_db_dir)) {
    dir.create(target_db_dir, recursive = TRUE)
  }
  target_db_path
}, error = function(e) {
  warning(">>> [WARN] Configured DB path unreachable (", target_db_dir, "). Falling back to local Data/ directory.")
  if (!dir.exists(dirname(default_local_db))) {
    dir.create(dirname(default_local_db), recursive = TRUE)
  }
  default_local_db
})

message(">>> [DB] Vault path resolved to: ", db_path)

# ============================================================
# FILENAME PARSER
# Expected format: <ProjectName>_<TestType>_<AppName>_<BuildId>_<Timestamp>.csv
# Example: ProjectXYZ_Sanity_DemoApp_123456_20260809-1027.csv
# Returns: list(project_name, test_name, app_name, run_id, timestamp)
# ============================================================
parse_csv_filename <- function(filename) {
  base <- tools::file_path_sans_ext(basename(filename))
  parts <- strsplit(base, "_")[[1]]

  if (length(parts) < 5) {
    stop(paste0(
      "ERROR: Filename '", basename(filename), "' does not match expected format:\n",
      "  <ProjectName>_<TestType>_<AppName>_<BuildId>_<Timestamp>.csv\n",
      "  Example: ProjectXYZ_Sanity_DemoApp_123456_20260809-1027.csv"
    ))
  }

  list(
    project_name = parts[1],
    test_name    = parts[2],
    app_name     = parts[3],
    run_id       = parts[4],
    timestamp    = parts[5]
  )
}

# --- [MENU INTERCEPTOR] ---
if (opMode == "menu") {
  if (file.exists(db_path)) {
    con              <- dbConnect(duckdb(), dbdir = db_path, read_only = TRUE)
    available_tables <- dbListTables(con)
    target_table     <- if ("performance_history" %in% available_tables) {
      "performance_history"
    } else if (paste0("performance_history_", active_tool) %in% available_tables) {
      paste0("performance_history_", active_tool)
    } else if ("performance_history_jmeter" %in% available_tables) {
      "performance_history_jmeter"
    } else {
      "performance_history"
    }

    if (target_table %in% available_tables) {
      header_title <- if (target_table == "performance_history") "Recent Runs in Vault" else sprintf("Recent %s Runs in Vault", toupper(active_tool))
      writeLines(sprintf("\n--------------- %s --------------", header_title))
      menu_query <- sprintf("
        SELECT sequence_num, run_id, project_name, MAX(test_name) as test_name, MIN(upload_time) as upload_time
        FROM %s
        GROUP BY sequence_num, run_id, project_name
        ORDER BY sequence_num DESC
        LIMIT 10", target_table)

      hist <- dbGetQuery(con, menu_query)
      if (nrow(hist) > 0) {
        formatted_time <- format(hist$upload_time, "%Y-%m-%d %H:%M:%S")
        cat(paste0(
          "[#", hist$sequence_num, "] Run ID: ", hist$run_id,
          " | Project: ", hist$project_name,
          " | Test: ", hist$test_name,
          " | Registered: ", formatted_time,
          collapse = "\n"
        ), "\n")
      }
      writeLines("-----------------------------------------------------------\n")
    } else {
      writeLines(sprintf("\n[NOTICE] No registered data found yet for table: %s\n", target_table))
    }
    dbDisconnect(con, shutdown = TRUE)
  }
  quit(save = "no")
}

################################################################################
###########            STEP 1: DUCKDB REGISTRATION                  ###########
################################################################################

if (opMode == "register") {
  message(">>> [STITCHING] Processing folder: ", rawResultsFolder)

  target_table <- "performance_history"
  tool_key     <- if (active_tool %in% names(params_cfg$tool_mappings)) active_tool else "jmeter"
  mapping      <- params_cfg$tool_mappings[[tool_key]]
  mapping      <- mapping[nzchar(as.character(mapping))]

  if (!dir.exists(dirname(db_path))) dir.create(dirname(db_path), recursive = TRUE)
  con <- dbConnect(duckdb(), dbdir = db_path, read_only = FALSE)
  available_tables <- dbListTables(con)

  # Auto-migrate if performance_history doesn't exist yet but legacy tables do
  if (!(target_table %in% available_tables)) {
    if ("performance_history_jmeter" %in% available_tables) {
      message(">>> [MIGRATE] Creating unified 'performance_history' from 'performance_history_jmeter'...")
      dbExecute(con, "
        CREATE TABLE performance_history AS 
        SELECT 
          CAST(sequence_num AS DOUBLE) AS sequence_num,
          CAST(run_id AS VARCHAR) AS run_id,
          CAST(project_name AS VARCHAR) AS project_name,
          CAST(test_name AS VARCHAR) AS test_name,
          CAST(app_name AS VARCHAR) AS app_name,
          CAST(csv_filename AS VARCHAR) AS csv_filename,
          timestamp,
          CAST(elapsed AS DOUBLE) AS elapsed,
          CAST(label AS VARCHAR) AS label,
          CAST(responseCode AS DOUBLE) AS responseCode,
          CAST(responseMessage AS VARCHAR) AS responseMessage,
          CAST(threadName AS VARCHAR) AS threadName,
          CAST(dataType AS VARCHAR) AS dataType,
          CAST(success AS BOOLEAN) AS success,
          CAST(CAST(failureMessage AS VARCHAR) AS VARCHAR) AS failureMessage,
          CAST(bytes AS DOUBLE) AS bytes,
          CAST(sentBytes AS DOUBLE) AS sentBytes,
          CAST(grpThreads AS DOUBLE) AS grpThreads,
          CAST(allThreads AS DOUBLE) AS allThreads,
          CAST(URL AS VARCHAR) AS URL,
          CAST(Latency AS DOUBLE) AS Latency,
          CAST(IdleTime AS DOUBLE) AS IdleTime,
          CAST(Connect AS DOUBLE) AS Connect,
          upload_time,
          CAST(thread_group AS VARCHAR) AS thread_group,
          CAST(user_index AS INTEGER) AS user_index
        FROM performance_history_jmeter
      ")
      available_tables <- dbListTables(con)
    }
  }

  table_exists <- if (target_table %in% dbListTables(con)) 1 else 0

  # ── Validate folder exists ──
  if (!dir.exists(rawResultsFolder)) {
    dbDisconnect(con, shutdown = TRUE)
    stop("ERROR: --rawResultsFolder must be a valid full path to a folder containing CSV files.")
  }

  raw_path  <- rawResultsFolder
  csv_files <- list.files(path = raw_path, pattern = "\\.csv$", full.names = TRUE)

  if (length(csv_files) == 0) {
    dbDisconnect(con, shutdown = TRUE)
    message(">>> [ERROR] No CSV files found in: ", raw_path)
    quit(save = "no", status = 1)
  }

  # Parse and validate each CSV filename in the folder
  parsed_list <- lapply(csv_files, function(f) {
    tryCatch(
      parse_csv_filename(f),
      error = function(e) {
        dbDisconnect(con, shutdown = TRUE)
        stop(conditionMessage(e))
      }
    )
  })

  # Validate consistency — all files in folder must share the same BuildId
  all_projects <- sapply(parsed_list, function(p) p$project_name)
  all_tests    <- sapply(parsed_list, function(p) p$test_name)
  all_run_ids  <- sapply(parsed_list, function(p) p$run_id)

  if (length(unique(all_run_ids)) > 1) {
    dbDisconnect(con, shutdown = TRUE)
    stop(paste0(
      "ERROR: CSV files in the folder have different BuildIds: ",
      paste(unique(all_run_ids), collapse = ", "), "\n",
      "All CSV files in one registration folder must share the same BuildId."
    ))
  }

  # Build per-file lookup map for app_name
  file_app_map <- setNames(
    sapply(parsed_list, function(p) p$app_name),
    sapply(csv_files, basename)
  )

  # Extract overall run metadata
  cfg_project  <- params_cfg$params$project
  project_name <- if (!is.null(cfg_project) && nzchar(trimws(cfg_project))) cfg_project else all_projects[1]
  test_name    <- all_tests[1]
  run_id       <- all_run_ids[1]

  message(">>> [REGISTER] project=", project_name, " | test=", test_name,
          " | unique apps=", length(unique(file_app_map)), " | run_id=", run_id)

  # ── Duplicate run ID check ──
  if (table_exists > 0) {
    existing_runs <- dbGetQuery(con, sprintf("SELECT DISTINCT run_id FROM %s", target_table))$run_id
    if (run_id %in% existing_runs) {
      dbDisconnect(con, shutdown = TRUE)
      message(">>> [ERROR] Run ID '", run_id, "' already exists in '", target_table, "'. Registration aborted.")
      message(">>> [HINT] Use a different build folder/filename or delete the existing record.")
      quit(save = "no", status = 1)
    }
  }

  # ── Auto-increment sequence_num ──
  if (table_exists > 0) {
    max_seq <- dbGetQuery(con, sprintf(
      "SELECT MAX(sequence_num) as max_seq FROM %s", target_table
    ))$max_seq
    sequence_num <- if (is.na(max_seq)) 1 else max_seq + 1
  } else {
    sequence_num <- 1
  }

  message(">>> [REGISTER] sequence_num=", sequence_num)

  # ── Stitch CSVs ──
  message(">>> [REGISTERING] Target: ", run_id, " | Table: ", target_table)

  sample_header <- names(vroom::vroom(csv_files[1], n_max = 0, show_col_types = FALSE))
  source_cols   <- intersect(as.character(unlist(mapping)), sample_header)

  stitched_data <- vroom::vroom(
    csv_files,
    id           = "csv_filename",
    col_select   = any_of(source_cols),
    show_col_types = FALSE,
    .name_repair = "minimal"
  )

  # Rename headers to match canonical JMeter fields
  for (field_name in names(mapping)) {
    old_name <- mapping[[field_name]]
    if (old_name %in% names(stitched_data) && old_name != field_name) {
      stitched_data <- stitched_data %>% rename(!!field_name := all_of(old_name))
    }
  }

  # 1. Timestamp Normalization (POSIXct UTC)
  ts_raw <- stitched_data$timestamp
  if (is.numeric(ts_raw) || all(grepl("^\\d+(\\.\\d+)?$", head(na.omit(as.character(ts_raw)), 100)))) {
    num_ts <- as.numeric(ts_raw)
    stitched_data$timestamp <- if (any(num_ts > 1e11, na.rm = TRUE)) {
      as.POSIXct(num_ts / 1000, origin = "1970-01-01", tz = "UTC")
    } else {
      as.POSIXct(num_ts, origin = "1970-01-01", tz = "UTC")
    }
  } else {
    stitched_data$timestamp <- lubridate::parse_date_time(
      as.character(ts_raw),
      orders = c("ymd HMS", "ymd HM", "ymd_HMS", "Y-m-d'T'H:M:S", "Y-m-d'T'H:M:OS", "Y-m-d H:M:S", "Y-m-d H:M:OS", "d/m/Y H:M:S"),
      tz = "UTC"
    )
    if (all(is.na(stitched_data$timestamp))) {
      stitched_data$timestamp <- as.POSIXct(as.character(ts_raw), tz = "UTC")
    }
  }

  # 2. Success Normalization (boolean)
  if ("success" %in% names(stitched_data)) {
    succ_str <- tolower(trimws(as.character(stitched_data$success)))
    stitched_data$success <- succ_str %in% c("true", "yes", "1", "pass", "ok")
  } else {
    stitched_data$success <- TRUE
  }

  # 3. Response Code & Message
  if (!("responseCode" %in% names(stitched_data)) || all(is.na(stitched_data$responseCode))) {
    stitched_data$responseCode <- ifelse(stitched_data$success, 200, 500)
  } else {
    stitched_data$responseCode <- as.numeric(gsub("\\.0$", "", as.character(stitched_data$responseCode)))
  }

  if (!("responseMessage" %in% names(stitched_data)) || all(is.na(stitched_data$responseMessage))) {
    stitched_data$responseMessage <- ifelse(stitched_data$success, "OK", "KO")
  } else {
    stitched_data$responseMessage <- as.character(stitched_data$responseMessage)
  }

  # 4. Thread Group & Thread Name Normalization
  has_userPath   <- "userPath" %in% names(stitched_data)
  has_tg         <- "thread_group" %in% names(stitched_data)
  has_threadName <- "threadName" %in% names(stitched_data)

  thread_group_val <- if (has_tg && any(!is.na(stitched_data$thread_group))) {
    stitched_data$thread_group
  } else if (has_threadName && any(grepl("\\s\\d+-\\d+", stitched_data$threadName))) {
    extracted <- stringr::str_extract(stitched_data$threadName, "^.*(?=\\s\\d+-\\d+)")
    ifelse(is.na(extracted), stitched_data$threadName, extracted)
  } else if (has_userPath) {
    stringr::str_trim(as.character(stitched_data$userPath))
  } else {
    "Thread Group"
  }
  stitched_data$thread_group <- thread_group_val

  if (!has_threadName || all(is.na(stitched_data$threadName))) {
    stitched_data$threadName <- paste(stitched_data$thread_group, "1-1")
  } else {
    is_bare_id <- !grepl("\\s", stitched_data$threadName)
    stitched_data$threadName <- ifelse(
      is_bare_id,
      paste0(stitched_data$thread_group, " ", stitched_data$threadName),
      stitched_data$threadName
    )
  }

  # Extract user_index
  stitched_data$user_index <- as.integer(stringr::str_extract(stitched_data$threadName, "(?<=-)\\d+$"))
  if (all(is.na(stitched_data$user_index))) {
    stitched_data$user_index <- as.integer(stringr::str_extract(stitched_data$threadName, "\\d+$"))
  }

  # 5. Fill and Cast Remaining Canonical JMeter Fields
  if (!("elapsed" %in% names(stitched_data))) stitched_data$elapsed <- 0
  stitched_data$elapsed <- as.numeric(stitched_data$elapsed)

  if (!("label" %in% names(stitched_data))) stitched_data$label <- "Unknown"
  stitched_data$label <- as.character(stitched_data$label)

  if (!("dataType" %in% names(stitched_data))) stitched_data$dataType <- "text"
  stitched_data$dataType <- as.character(stitched_data$dataType)

  if (!("failureMessage" %in% names(stitched_data))) stitched_data$failureMessage <- NA_character_
  stitched_data$failureMessage <- as.character(stitched_data$failureMessage)

  if (!("bytes" %in% names(stitched_data))) stitched_data$bytes <- 0
  stitched_data$bytes <- as.numeric(stitched_data$bytes)

  if (!("sentBytes" %in% names(stitched_data))) stitched_data$sentBytes <- 0
  stitched_data$sentBytes <- as.numeric(stitched_data$sentBytes)

  if (!("grpThreads" %in% names(stitched_data))) stitched_data$grpThreads <- NA_real_
  stitched_data$grpThreads <- as.numeric(stitched_data$grpThreads)

  if (!("allThreads" %in% names(stitched_data))) stitched_data$allThreads <- NA_real_
  stitched_data$allThreads <- as.numeric(stitched_data$allThreads)

  if (!("URL" %in% names(stitched_data))) stitched_data$URL <- NA_character_
  stitched_data$URL <- as.character(stitched_data$URL)

  if (!("Latency" %in% names(stitched_data))) stitched_data$Latency <- stitched_data$elapsed
  stitched_data$Latency <- as.numeric(stitched_data$Latency)

  if (!("IdleTime" %in% names(stitched_data))) stitched_data$IdleTime <- 0
  stitched_data$IdleTime <- as.numeric(stitched_data$IdleTime)

  if (!("Connect" %in% names(stitched_data))) stitched_data$Connect <- 0
  stitched_data$Connect <- as.numeric(stitched_data$Connect)

  # Standard Metadata Columns
  stitched_data$sequence_num <- sequence_num
  stitched_data$run_id       <- run_id
  stitched_data$project_name <- project_name
  stitched_data$test_name    <- test_name
  stitched_data$csv_filename <- basename(stitched_data$csv_filename)
  stitched_data$app_name     <- unname(file_app_map[stitched_data$csv_filename])
  stitched_data$upload_time  <- Sys.time()

  canonical_cols <- c(
    "sequence_num", "run_id", "project_name", "test_name", "app_name", "csv_filename",
    "timestamp", "elapsed", "label", "responseCode", "responseMessage", "threadName",
    "dataType", "success", "failureMessage", "bytes", "sentBytes", "grpThreads",
    "allThreads", "URL", "Latency", "IdleTime", "Connect", "upload_time",
    "thread_group", "user_index"
  )

  stitched_data <- stitched_data %>% select(all_of(canonical_cols))

  dbWriteTable(con, target_table, stitched_data, append = TRUE)
  dbExecute(con, "CHECKPOINT;")
  dbDisconnect(con, shutdown = TRUE)

  message(">>> [SUCCESS] Registered as Run ID '", run_id, "' (Sequence #", sequence_num, ") in ", target_table)
  quit(save = "no")
}

################################################################################
###########            STEP 2: GENERATE REPORT                      ###########
################################################################################

if (opMode == "report") {

  if (raw_current == "NONE") {
    stop("Error: A Current Run ID or Sequence Number is required (--current=<run>).")
  }

  con              <- dbConnect(duckdb(), dbdir = db_path, read_only = TRUE)
  available_tables <- dbListTables(con)
  target_table     <- if ("performance_history" %in% available_tables) {
    "performance_history"
  } else if (paste0("performance_history_", active_tool) %in% available_tables) {
    paste0("performance_history_", active_tool)
  } else if ("performance_history_jmeter" %in% available_tables) {
    "performance_history_jmeter"
  } else {
    "performance_history"
  }

  resolve_id <- function(identifier, id_df) {
    if (identifier == "NONE" || is.na(identifier) || !nzchar(trimws(identifier))) return("NONE")
    match_id <- id_df$run_id[id_df$run_id == identifier]
    if (length(match_id) > 0) return(match_id[1])
    match_seq <- id_df$run_id[as.character(id_df$sequence_num) == as.character(identifier)]
    if (length(match_seq) > 0) return(match_seq[1])
    return(identifier)
  }

  resolved_current <- raw_current
  resolved_base    <- raw_base

  if (target_table %in% available_tables) {
    all_identifiers <- dbGetQuery(con, sprintf(
      "SELECT DISTINCT run_id, sequence_num FROM %s", target_table
    ))
    resolved_current <- resolve_id(raw_current, all_identifiers)
    resolved_base    <- resolve_id(raw_base, all_identifiers)
  }
  dbDisconnect(con, shutdown = TRUE)

  has_baseline <- (resolved_base != "NONE" && resolved_base != resolved_current)

  if (has_baseline) {
    message(">>> [ANALYSING] Comparing: Current #", resolved_current, " vs Baseline #", resolved_base)
    run_string    <- paste0(resolved_base, "_vs_", resolved_current)
    selected_runs <- c(resolved_base, resolved_current)
  } else {
    message(">>> [ANALYSING] Extracting metrics for: Current #", resolved_current, " (Standalone)")
    run_string    <- resolved_current
    selected_runs <- c(resolved_current)
  }

  resolved_runs <- selected_runs

  resolved_project <- params_cfg$params$project

  if (is.null(resolved_project) || !nzchar(trimws(resolved_project))) {
    if (file.exists(db_path) && length(resolved_runs) > 0) {
      con <- dbConnect(duckdb(), dbdir = db_path, read_only = TRUE)
      if (target_table %in% dbListTables(con)) {
        proj_query <- sprintf(
          "SELECT DISTINCT run_id, project_name FROM %s WHERE run_id IN (%s)",
          target_table,
          paste0("'", resolved_runs, "'", collapse = ",")
        )
        db_projects     <- dbGetQuery(con, proj_query)
        unique_projects <- unique(db_projects$project_name)
        resolved_project <- if (length(unique_projects) == 1) {
          unique_projects[1]
        } else {
          paste(unique_projects, collapse = " vs ")
        }
      }
      dbDisconnect(con, shutdown = TRUE)
    }
  }

  # report_dir <- if (outputFolder != "NONE") outputFolder else file.path(current_dir, "Reports")
  # if (!dir.exists(report_dir)) dir.create(report_dir, recursive = TRUE)

  # --- [Report Output Directory Resolution] ---
  raw_report_dir <- if (outputFolder != "NONE") {
    outputFolder  # 1. CLI argument (--outputFolder=...)
  } else if (!is.null(params_cfg$output_dir) && nzchar(trimws(params_cfg$output_dir))) {
    params_cfg$output_dir  # 2. Config file fallback (matches your config.yaml)
  } else {
    "Reports"  # 3. Final default
  }

  report_dir <- if (
    # UNC path (\\host\share or //host/share)
    grepl("^//", raw_report_dir) || grepl("^\\\\\\\\", raw_report_dir) ||
    # Absolute Windows path (C:/ or C:\)
    grepl("^[A-Za-z]:[/\\\\]", raw_report_dir) ||
    # Absolute Linux path (/home/... or /mnt/...)
    grepl("^/[^/]", raw_report_dir)
  ) {
    normalizePath(raw_report_dir, winslash = "/", mustWork = FALSE)
  } else {
    file.path(current_dir, raw_report_dir)
  }

  if (!dir.exists(report_dir)) dir.create(report_dir, recursive = TRUE)

  message(">>> [REPORT] Output directory resolved to: ", report_dir)

  report_ts       <- format(Sys.time(), "%Y%m%d_%H%M")
  report_filename <- paste0("Performance_Report_", run_string, "_", report_ts, ".html")

  pandoc_dir <- file.path(lib_dir, "tools", "pandoc")
  if (dir.exists(pandoc_dir)) {
    Sys.setenv(RSTUDIO_PANDOC = pandoc_dir)
  } else {
    rmarkdown::find_pandoc()
  }

  message(">>> [STORYTELLER] Rendering HTML Report to /Reports...")

  sanitized_filter <- if (labelFilterParam == "NONE") "" else labelFilterParam

  report_params <- list(
    project         = resolved_project,
    scenario        = params_cfg$test_scenario,
    runs            = selected_runs,
    current_run     = resolved_current,
    baseline_run    = if (has_baseline) resolved_base else "NONE",
    tool            = active_tool,
    db_path         = db_path,
    label_filter    = sanitized_filter,
    excluded_labels = excluded_labels,
    report_id       = tools::file_path_sans_ext(report_filename)
  )

  # Check if Quarto CLI is available for rendering storyteller.qmd
  quarto_bin <- Sys.which("quarto")
  if (!nzchar(quarto_bin)) {
    candidate_paths <- c(
      "C:/Program Files/Quarto/bin/quarto.exe",
      file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Quarto", "bin", "quarto.exe"),
      "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe"
    )
    existing_q <- candidate_paths[file.exists(candidate_paths)]
    if (length(existing_q) > 0) quarto_bin <- existing_q[1]
  }

  cfg_template <- if (!is.null(params_cfg$rmd_template) && nzchar(trimws(params_cfg$rmd_template))) trimws(params_cfg$rmd_template) else NULL

  qmd_template <- file.path(get_active_script_dir(), "dashboard.qmd")

  rmd_candidate <- if (!is.null(cfg_template) && file.exists(cfg_template)) {
    cfg_template
  } else {
    file.path(get_active_script_dir(), "dashboard.Rmd")
  }
  rmd_template <- rmd_candidate

  if (nzchar(quarto_bin) && file.exists(qmd_template) && requireNamespace("quarto", quietly = TRUE)) {
    message(">>> [QUARTO] Detected Quarto CLI (", quarto_bin, "). Rendering ", basename(qmd_template), "...")
    Sys.setenv(
      QUARTO_PATH = quarto_bin,
      R_LIBS      = lib_dir,
      R_LIBS_USER = lib_dir,
      R_LIBS_SITE = lib_dir
    )
    quarto::quarto_render(
      input          = qmd_template,
      execute_params = report_params,
      output_file    = report_filename,
      execute_dir    = current_dir,
      quiet          = FALSE
    )
    candidate_outputs <- c(
      file.path(dirname(qmd_template), report_filename),
      file.path(current_dir, report_filename)
    )
    for (cand in candidate_outputs) {
      if (file.exists(cand) && normalizePath(cand, mustWork = FALSE) != normalizePath(file.path(report_dir, report_filename), mustWork = FALSE)) {
        file.copy(cand, file.path(report_dir, report_filename), overwrite = TRUE)
        unlink(cand)
        break
      }
    }
  } else {
    withCallingHandlers(
      render(
        rmd_template,
        params        = report_params,
        output_file   = report_filename,
        output_dir    = report_dir,
        knit_root_dir = current_dir
      ),
      warning = function(w) {
        if (grepl("You changed the working directory", conditionMessage(w))) {
          invokeRestart("muffleWarning")
        }
      }
    )
  }

  message(">>> [SUCCESS] Report saved: ", file.path(report_dir, report_filename))
  quit(save = "no")
}