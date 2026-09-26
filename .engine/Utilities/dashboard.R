# ============================================================
#  TOTAL USERS COMPARISON ENGINE
#  - Works for JMeter and NeoLoad
#  - Returns one row per run_id
# ============================================================
compute_total_users <- function(df) {
  
  # Detect whether user_index exists (JMeter)
  has_user_index <- "user_index" %in% names(df)
  
  if (has_user_index) {
    user_counts <- df %>%
      distinct(run_id, user_index) %>%
      group_by(run_id) %>%
      summarise(total_users = n(), .groups = "drop")
  } else {
    # NeoLoad fallback: count unique userPath
    user_counts <- df %>%
      distinct(run_id, userPath) %>%
      group_by(run_id) %>%
      summarise(total_users = n(), .groups = "drop")
  }
  
  return(user_counts)
}
