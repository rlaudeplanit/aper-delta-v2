library(DBI)
library(duckdb)

# 1. Connect
con <- dbConnect(duckdb::duckdb(), dbdir = "Data/Performance_Vault.db", read_only = FALSE)

# 2. Delete the specific run
target_run <- "run_001"
dbExecute(con, sprintf("DELETE FROM performance_history_neoload WHERE run_id = '%s'", target_run))
message(">>> [DELETED] ", target_run)

# 3. Cleanup Disk Space (The Vacuum)
dbExecute(con, "VACUUM")
message(">>> [CLEANED] Disk space defragmented.")

# 4. Disconnect
dbDisconnect(con, shutdown = TRUE)
duckdb::duckdb_shutdown(duckdb::duckdb())
gc() # Clear memory hooks

message(">>> Connection dropped safely. File lock released.")