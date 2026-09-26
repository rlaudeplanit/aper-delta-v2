#!/bin/bash
###################################################
# frontdoor.sh - The Interface (Linux)
# APER Delta - Performance Data Engine
###################################################

# ── Get the directory where this script lives (project root) ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$SCRIPT_DIR/.engine"
RSCRIPT_PATH="$ENGINE_DIR/worker.R"

# ── Check engine folder exists ──
if [ ! -f "$RSCRIPT_PATH" ]; then
  echo "ERROR: Engine files not found. Expected: $RSCRIPT_PATH"
  echo "Please ensure the .engine folder is present in the project directory."
  exit 1
fi

# ── Find Rscript — check common locations ──
RSCRIPT_EXE=""

# Check if already on PATH
if command -v Rscript &>/dev/null; then
  RSCRIPT_EXE=$(command -v Rscript)
# Common Linux install locations
elif [ -f "/usr/bin/Rscript" ]; then
  RSCRIPT_EXE="/usr/bin/Rscript"
elif [ -f "/usr/local/bin/Rscript" ]; then
  RSCRIPT_EXE="/usr/local/bin/Rscript"
elif [ -f "/opt/R/bin/Rscript" ]; then
  RSCRIPT_EXE="/opt/R/bin/Rscript"
fi

if [ -z "$RSCRIPT_EXE" ]; then
  echo "ERROR: Rscript not found."
  echo "Please install R from https://cran.r-project.org/ or via your package manager:"
  echo "   Ubuntu/Debian: sudo apt-get install r-base"
  echo "   RHEL/CentOS:   sudo yum install R"
  echo "   Fedora:        sudo dnf install R"
  exit 1
fi

echo "Using R: $RSCRIPT_EXE"

###################################################
# HELPER FUNCTIONS
###################################################

select_tool_type() {
  local tool_var=$1
  echo ""
  echo "Select Tool Type:"
  echo "  1. JMeter (Default)"
  echo "  2. NeoLoad"

  while true; do
    read -r -p "Enter choice (1 or 2, or press Enter for default): " tool_choice
    tool_choice="${tool_choice// /}"
    if [ -z "$tool_choice" ] || [ "$tool_choice" = "1" ]; then
      eval "$tool_var=jmeter"
      break
    elif [ "$tool_choice" = "2" ]; then
      eval "$tool_var=neoload"
      break
    else
      echo "Invalid choice. Please enter 1, 2, or press Enter."
    fi
  done
}

###################################################
# MAIN MENU
###################################################

echo ""
echo "--- APER Delta - Performance Data Engine ---"
echo ""
echo "Operations:"
echo "  1. Generate Report (Math & HTML) [Default]"
echo "  2. Register Data (Save to DuckDB Vault)"
echo ""

CHOICE=""
while true; do
  read -r -p "Select operation [1 or 2, or press Enter for default]: " input_choice
  input_choice="${input_choice// /}"
  if [ -z "$input_choice" ]; then
    CHOICE="1"
    break
  elif [ "$input_choice" = "1" ] || [ "$input_choice" = "2" ]; then
    CHOICE="$input_choice"
    break
  else
    echo "Invalid choice! Please enter 1, 2, or just press Enter."
  fi
done

RAW_RESULTS_FOLDER="NONE"
COMP1="NONE"
COMP2="NONE"
COMP3="NONE"
TOOL_TYPE="jmeter"
LABEL_FILTER="NONE"

###################################################
# REGISTER MODE
###################################################

if [ "$CHOICE" = "2" ]; then
  OP_MODE="register"

  select_tool_type TOOL_TYPE

  # Folder input — expects CSV files following the filename naming standard
  while true; do
    echo ""
    echo "Required CSV Naming Convention in Target Folder:"
    echo "  <ProjectName>_<TestType>_<AppName>_<BuildId>_<Timestamp>.csv"
    echo "  e.g., ProjectXYZ_Sanity_DemoApp_123456_20260809-1027.csv"
    echo ""
    read -r -p "Enter FULL folder path containing CSV results: " RAW_RESULTS_FOLDER
    if [ -z "$RAW_RESULTS_FOLDER" ]; then
      echo "Full path is required!"
    else
      break
    fi
  done

###################################################
# REPORT MODE
###################################################

else
  OP_MODE="report"

  select_tool_type TOOL_TYPE

  # Display recent runs
  "$RSCRIPT_EXE" --vanilla "$RSCRIPT_PATH" \
    "--opMode=menu" \
    "--active_tool=$TOOL_TYPE"

  # Collect up to 3 Run IDs or Sequence Numbers
  RUN_IDS=()
  echo ""
  echo "Enter up to 3 Run IDs or Sequence Numbers (#) to compare."
  echo "Press ENTER on an empty line when finished."

  while [ ${#RUN_IDS[@]} -lt 3 ]; do
    current_count=$((${#RUN_IDS[@]} + 1))
    read -r -p "Enter Run ID or Sequence # $current_count: " input_run
    if [ -z "$input_run" ]; then
      if [ ${#RUN_IDS[@]} -ge 1 ]; then
        break
      else
        echo "You must enter at least one Run ID to generate a report."
      fi
    else
      RUN_IDS+=("$input_run")
    fi
  done

  COMP1="${RUN_IDS[0]:-NONE}"
  COMP2="${RUN_IDS[1]:-NONE}"
  COMP3="${RUN_IDS[2]:-NONE}"

  echo ""
  read -r -p "Enter transaction label filter (e.g. Login) or press Enter to include all: " input_filter
  if [ -n "$input_filter" ]; then
    LABEL_FILTER="$input_filter"
  fi
fi

###################################################
# EXECUTE WORKER
###################################################

echo ""
echo "Launching APER Delta Engine..."

if [ "$OP_MODE" = "register" ]; then
  "$RSCRIPT_EXE" --vanilla "$RSCRIPT_PATH" \
    "--opMode=$OP_MODE" \
    "--rawResultsFolder=$RAW_RESULTS_FOLDER" \
    "--active_tool=$TOOL_TYPE"
else
  "$RSCRIPT_EXE" --vanilla "$RSCRIPT_PATH" \
    "--opMode=$OP_MODE" \
    "--comp1=$COMP1" \
    "--comp2=$COMP2" \
    "--comp3=$COMP3" \
    "--active_tool=$TOOL_TYPE" \
    "--labelFilterParam=$LABEL_FILTER"
fi

echo ""
echo "Process complete."