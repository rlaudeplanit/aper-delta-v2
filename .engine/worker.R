# ==============================================================================
# worker.R (Backwards Compatibility Forwarding Wrapper)
# ------------------------------------------------------------------------------
# The primary execution engine has been renamed to 'engine.R'.
# This file is maintained for full backwards compatibility with existing
# automation scripts and CI/CD pipelines.
# ==============================================================================

message(">>> [INFO] '.engine/worker.R' is retained for backwards compatibility.")
message(">>> Forwarding execution to '.engine/engine.R'...")

get_wrapper_dir <- function() {
  args   <- commandArgs(trailingOnly = FALSE)
  needle <- "--file="
  match  <- grep(needle, args)
  if (length(match) > 0) {
    return(dirname(normalizePath(sub(needle, "", args[match]))))
  } else {
    return(file.path(getwd(), ".engine"))
  }
}

engine_script <- file.path(get_wrapper_dir(), "engine.R")
if (!file.exists(engine_script)) {
  # Fallback to current working directory check
  engine_script <- file.path(getwd(), ".engine", "engine.R")
}

if (!file.exists(engine_script)) {
  stop(">>> [ERROR] Could not locate '.engine/engine.R'. Please verify repository integrity.")
}

source(engine_script)
