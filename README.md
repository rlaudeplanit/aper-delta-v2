# APER Delta — Complete Usage Guide

APER Delta standardises on **Apache JMeter as its single canonical data schema and calculation engine**. It transforms raw performance test results from **JMeter**, **NeoLoad**, or other load testing tools into a unified DuckDB vault and generates a self-contained interactive HTML executive report comparing **two test runs (Current vs Base)** or evaluating a single run standalone. The report provides an executive narrative summary, 2x2 KPI metrics, dynamic workload phase profiling (ramp-up, steady state, ramp-down), multi-application baseline comparisons, SLA evaluation, failure drilldown tables, and zero-lag interactive modals.

You do not need to know R. Everything is driven by an interactive menu
(`launch.ps1` on Windows, `launch.sh` on Linux/macOS; legacy `frontdoor.ps1`/`frontdoor.sh` supported) which calls the R engine
(`.engine/engine.R`, legacy `.engine/worker.R` wrapper supported) for you.

---

## Table of contents

1. [How the tool works](#1-how-the-tool-works)
2. [Prerequisites — installing R 4.6.0](#2-prerequisites--installing-r-460)
3. [Prerequisites — installing Pandoc](#3-prerequisites--installing-pandoc)
4. [Getting the project & first run](#4-getting-the-project--first-run)
5. [Project layout](#5-project-layout)
6. [Configuration — `config.yaml`](#6-configuration--configyaml)
7. [CSV naming convention (mandatory)](#7-csv-naming-convention-mandatory)
8. [Registering results into the vault](#8-registering-results-into-the-vault)
9. [Generating a report](#9-generating-a-report)
10. [Command-line (non-interactive) usage](#10-command-line-non-interactive-usage)
11. [Reading the report](#11-reading-the-report)
12. [SLA configuration](#12-sla-configuration)
13. [Chart visibility](#13-chart-visibility)
14. [AI summary & hybrid architecture](#14-ai-summary--hybrid-architecture)
15. [Observations (editable notes in the report)](#15-observations-editable-notes-in-the-report)
16. [Maintaining the vault](#16-maintaining-the-vault)
17. [Troubleshooting](#17-troubleshooting)
18. [Quick reference](#18-quick-reference)

---

## 1. How the tool works

```
launch.ps1 / launch.sh            interactive menu — locates Rscript, asks questions (frontdoor alias)
        │
        ▼
.engine/engine.R                  CLI dispatcher (--opMode = menu | register | report; worker.R alias)
        │                         bootstraps R packages into ./RLibs
        │                         resolves the vault & output paths (local, absolute or UNC)
        │                         auto-detects Quarto CLI / Pandoc
        │
        ├── register ──► <database_path>                (DuckDB "vault": performance_history)
        │                Normalises columns into canonical JMeter schema
        │
        └── report   ──► .engine/dashboard.qmd / .Rmd   (Unified JMeter calculation engine)
                              ├── .engine/Dashboard/*.Rmd   High-density executive dashboard
                              ├── .engine/Tables/*.Rmd      Aggregates & failure tables
                              ├── .engine/Charts/*.Rmd      Responsive SVG & Plotly charts
                              ├── .engine/Utilities/*.R     Metrics, SLA, & hybrid AI helpers
                              └── .engine/Styles/*          CSS (light/dark themes, modals)
                                        │
                                        ▼
                              <output_dir>/Performance_Report_<runs>_<timestamp>.html
```

The vault and the report folder can both live on a **shared network drive**, so a whole team
can register into and report from one central vault — see §6.

Two distinct phases:

| Phase | What it does | Repeatable? |
|---|---|---|
| **Register** | Reads every CSV in a folder, normalises columns into the canonical JMeter layout, and appends rows to the unified `performance_history` table under one **Run ID** | Once per Run ID (duplicates are rejected) |
| **Report** | Reads 1–2 registered runs back out of the vault (Current and optional Base) through a single unified calculation engine and renders the HTML dashboard | As often as you like |

Data is **only** read from the vault at report time — the original CSVs are not needed again
once registered.

---

## 2. Prerequisites — installing R 4.6.0

The tool is built and validated against **R 4.6.0**. Newer 4.6.x point releases normally work,
but pin 4.6.0 if you want an environment identical to the reference one.

> On Windows the launcher auto-detects the **latest** R version found under
> `C:\Program Files\R\...\x64\Rscript.exe`. If you keep several versions installed, the newest
> one wins — uninstall newer versions (or put the R 4.6.0 `bin\x64` folder first on `PATH` and
> remove `C:\Program Files\R`) if you must force 4.6.0.

### Windows (primary supported platform)

1. Download the installer:
   <https://cran.r-project.org/bin/windows/base/old/4.6.0/R-4.6.0-win.exe>
   (the “old” folder is normal — it simply means a newer point release exists).
2. Run it as a user who can write to `C:\Program Files`.
3. Accept the defaults, in particular:
   - install destination `C:\Program Files\R\R-4.6.0`
   - **64-bit user installation** (the `x64` files are required — the launcher only looks for
     `Rscript.exe` under an `x64` folder)
   - leave “Save version number in registry” ticked
4. Verify from a **new** PowerShell window:

   ```powershell
   & "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" -e "R.version.string"
   # [1] "R version 4.6.0 ..."
   ```

   Adding R to `PATH` is optional — `frontdoor.ps1` finds it either way — but convenient:

   ```powershell
   [Environment]::SetEnvironmentVariable(
     "Path", $env:Path + ";C:\Program Files\R\R-4.6.0\bin\x64", "User")
   ```

**Rtools is not required.** `engine.R` installs packages with `type = "binary"` from
`cran.rstudio.com`, so nothing is compiled from source on Windows.

### macOS

```bash
# Apple silicon
curl -LO https://cran.r-project.org/bin/macosx/sonoma-arm64/base/R-4.6.0-arm64.pkg
sudo installer -pkg R-4.6.0-arm64.pkg -target /
# Intel: use https://cran.r-project.org/bin/macosx/big-sur-x86_64/base/R-4.6.0-x86_64.pkg
Rscript -e "R.version.string"
```

### Linux (Ubuntu/Debian, via the CRAN apt repo)

```bash
sudo apt-get update && sudo apt-get install -y --no-install-recommends \
     software-properties-common dirmngr gnupg curl
curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
  | sudo tee /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
sudo add-apt-repository \
  "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"
sudo apt-get update && sudo apt-get install -y r-base r-base-dev
Rscript -e "R.version.string"
```

The apt repo tracks the newest release. To pin exactly 4.6.0, either use
[`rig`](https://github.com/r-lib/rig) (`rig add 4.6.0`) or build from source:
<https://cran.r-project.org/src/base/R-4/R-4.6.0.tar.gz>.

On Linux, R packages are compiled from source, so install the usual build headers first:

```bash
sudo apt-get install -y build-essential libcurl4-openssl-dev libssl-dev libxml2-dev \
     libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
     libpng-dev libtiff5-dev libjpeg-dev
```

---

## 3. Prerequisites — installing Pandoc

`rmarkdown` shells out to **Pandoc** to build the HTML report. Without it, rendering fails with
`pandoc version 1.12.3 or higher is required and was not found`. Install the **latest** release
(3.10.2 at the time of writing) system-wide — do not rely on the copy bundled with RStudio,
because the engine runs through `Rscript`, not RStudio.

### Windows

Installer: <https://github.com/jgm/pandoc/releases/latest> → `pandoc-<version>-windows-x86_64.msi`

```powershell
winget install --id JohnMacFarlane.Pandoc -e      # or run the .msi manually
```

Close and reopen PowerShell, then verify:

```powershell
pandoc --version      # pandoc 3.10.2
```

### macOS

```bash
brew install pandoc && pandoc --version
```

### Linux

```bash
# Latest .deb straight from GitHub (apt's version is often too old)
curl -LO https://github.com/jgm/pandoc/releases/download/3.10.2/pandoc-3.10.2-1-amd64.deb
sudo dpkg -i pandoc-3.10.2-1-amd64.deb
pandoc --version
```

### Confirming R can see Pandoc

```bash
Rscript -e "rmarkdown::pandoc_available(); rmarkdown::pandoc_version()"
```

If `pandoc --version` works in the shell but R cannot find it, point R at the folder
(the directory, not the executable):

```powershell
setx RSTUDIO_PANDOC "C:\Program Files\Pandoc"
```

`engine.R` also honours a **portable copy** at `RLibs/tools/pandoc/` — drop the extracted
pandoc binaries there and the engine uses them automatically without touching system `PATH`.
This is the recommended trick on locked-down machines where you cannot install software.

---

## 4. Getting the project & first run

```bash
git clone https://github.com/rlaudeplanit/aper-delta.git
cd aper-delta
```

Then open `config.yaml` and set `database_path` and `output_dir` — the shipped values are
UNC placeholders (`//<host>/shared/Performance-JMeter/...`). Use your real file server, or the
local defaults `Data/Performance_Vault.db` and `Reports` (see §6).

**Windows:** right-click `launch.ps1` → *Run with PowerShell*, or from a PowerShell prompt
opened in the project root:

```powershell
cd C:\Tools\aper-delta
powershell -ExecutionPolicy Bypass -File .\launch.ps1
```
*(Note: `frontdoor.ps1` is retained as a backwards-compatible alias.)*

**Linux/macOS:**

```bash
chmod +x launch.sh      # first time only
./launch.sh
```
*(Note: `frontdoor.sh` is retained as a backwards-compatible alias.)*

> ⚠️ **Always launch from the project root.** `engine.R` reads `config.yaml` from the *current
> working directory*, so running `Rscript .engine/engine.R` from elsewhere fails with
> `cannot open file 'config.yaml'`.

### First-run package bootstrap

On first launch the engine creates `RLibs/` and installs any missing packages into it
(the global R library is left untouched). Expect **5–15 minutes** the first time; later runs
start in seconds. Packages installed:

```
yaml tidyverse DBI duckdb lubridate readr knitr here rmarkdown flexdashboard
extrafont gridExtra DT ff png ggthemes plotly shinydashboard rlang purrr tidyr
pacman scales dplyr vroom tools patchwork crosstalk Polychrome htmltools ggpubr jsonlite httr
```

Behind a corporate proxy, set `http_proxy` / `https_proxy` before the first run, or copy a
pre-populated `RLibs/` folder from a machine that already worked.

---

## 5. Project layout

```
aper-delta/
├── launch.ps1                    # Primary Windows interactive launcher (frontdoor.ps1 alias)
├── launch.sh                     # Primary Linux/macOS interactive launcher (frontdoor.sh alias)
├── config.yaml                   # Main configuration (version, paths, SLA, exclusions, AI)
├── secrets.yaml                  # (you create this) Amplify API token — git-ignored
├── aper-delta.Rproj              # RStudio project; also the `here::here()` root anchor
├── Evidence/                     # (optional) Drop-zone for manual infra screenshots (<run_id>/*.png)
├── .engine/
│   ├── engine.R                  # Primary CLI dispatcher, Quarto/Rmd orchestrator (worker.R alias)
│   ├── dashboard.Rmd             # Master Flexdashboard / Quarto template (storyteller.Rmd alias)
│   ├── dashboard.qmd             # Master Quarto engine template (storyteller.qmd alias)
│   ├── Dashboard/
│   │   └── dash-executive-summary.Rmd # High-density single-viewport dashboard & interactive modals
│   ├── Tables/                   # DT tables (aggregates, slowest, errors)
│   ├── Charts/                   # High-density SVG & Plotly chart templates
│   ├── Utilities/                # utils.R, dashboard.R, metrics & SLA calculation helpers
│   └── Styles/                   # styles.css (viewport layout, light/dark themes, modal styling)
├── SLA/performance-sla.yaml      # SLA thresholds & response time targets
├── RLibs/                        # Local isolated R package cache (git-ignored)
├── Data/Performance_Vault.db     # Default local DuckDB vault (git-ignored; may point elsewhere)
├── RawResults/                   # Suggested drop-zone for input CSVs (git-ignored)
├── Reports/                      # Default local HTML output (git-ignored; may point elsewhere)
└── check_db_head.R, check_rows.R, delete_by_runid.R   # vault maintenance helpers
```

`here::here()` resolves the project root from the `.Rproj` file (or a `.here` anchor file if
you add one). Keep the folder structure intact — child `.Rmd` files are referenced by relative
path from the root.

---

## 6. Configuration — `config.yaml`

| Key | Purpose | Notes |
|---|---|---|
| `params.project` | Report title project name | Leave `""` to auto-detect from the CSV filename / vault |
| `params.version` | Report version displayed in navbar | e.g. `"v2.0"`, `"1.0.1"` |
| `rmd_template` | Path to the master template | **Do not change** (`.engine/storyteller.Rmd`) |
| `output_dir` | Where HTML reports go | Relative, absolute or UNC — see “Shared / network locations” below |
| `database_path` | DuckDB vault file | Relative, absolute or UNC — see “Shared / network locations” below |
| `sla_file_path` | SLA definitions | Default `"SLA/performance-sla.yaml"`. Missing ⇒ SLA evaluation skipped |
| `evidence_dir` | Manual CPU/Memory screenshot directory | Optional folder (e.g. `Evidence/100002/*.png`) surfaced in Infrastructure modal |
| `ai_summary_enabled` | `"true"` / `"false"` | Toggles Amplify AI generation (with automatic deterministic fallback) |
| `ai_url`, `ai_model_id` | Amplify completion endpoint & model | Change only if your team uses a custom model/endpoint |
| `label_exclusions` | List of labels excluded globally | Pacing samplers, think time, or debug samplers excluded before analysis |
| `tool_type` | Canonical engine | Always `"jmeter"` (canonical schema & calculation engine) |
| `tool_mappings.jmeter` / `.neoload` | Source-CSV column → canonical JMeter mapping | Maps external tool CSV headers to canonical JMeter columns at ingestion |
| `workload_profile.ramp_up` / `.steady_state` / `.ramp_down` | Workload phase overrides | Optional manual overrides; leave `""` to calculate dynamically from telemetry |
| `bin_size` | Time-bucket size in seconds for per-minute charts | Default `60` |
| `user_action_filter` | Regex of transactions to include | Default `.*` (all) |

> ⚠️ **The shipped `config.yaml` contains UNC placeholders** for `output_dir` and
> `database_path` (`//<host>/shared/Performance-JMeter/...`). Replace `<host>` with your real
> file server, or set them back to the local defaults `Reports` and
> `Data/Performance_Vault.db`, before first use — otherwise the first run fails trying to
> create a folder on a host that doesn't exist.

### Shared / network locations

`database_path` and `output_dir` are each resolved the same way:

| Value looks like | Example | Resolved to |
|---|---|---|
| UNC path | `//fileserver/shared/Performance-JMeter/database/Performance_Vault.db` | Used as-is (normalised to forward slashes) |
| Absolute Windows path | `D:/PerfData/Performance_Vault.db` | Used as-is |
| Absolute Linux/macOS path | `/mnt/perf/Performance_Vault.db` | Used as-is |
| Anything else (relative) | `Data/Performance_Vault.db` | Relative to the **project root** |

Both resolved paths are echoed at startup so you can confirm what was picked up:

```
>>> [DB] Vault path resolved to: //fileserver/shared/Performance-JMeter/database/Performance_Vault.db
>>> [REPORT] Output directory resolved to: //fileserver/shared/Performance-JMeter/reports
```

Pointing `database_path` at a share gives the whole team one central vault — sequence numbers,
duplicate-Run-ID protection and run history are then shared. Caveats:

- DuckDB takes an **exclusive write lock** during registration, so only one person can register
  at a time; reports (read-only) are unaffected.
- The account running the tool needs read/write on the share, and the share must be reachable
  by that exact UNC name (a mapped drive letter also works: `Z:/Performance-JMeter/...`).
- Registering over a slow VPN link is much slower than registering locally and copying the
  vault afterwards.

Report output precedence is `--outputFolder` → `output_dir` in `config.yaml` → `Reports/`.

### Column mappings — canonical JMeter schema normalization

APER Delta standardises on **Apache JMeter as the single canonical schema** across the entire pipeline. The registration step selects the source columns declared under the tool's mapping in `config.yaml` and normalises them into standard JMeter columns before writing to the unified `performance_history` table:

| Canonical JMeter Field | JMeter Source Header | NeoLoad Source Header | Normalization Behavior |
|---|---|---|---|
| `timestamp` | `timeStamp` (epoch ms) | `Time` / `Date` | Auto-detects epoch ms, epoch seconds, or ISO-8601 text (`YYYY-MM-DDTHH:MM:SS`) and stores as UTC `TIMESTAMP` |
| `elapsed` | `elapsed` | `Response time` / `Duration` | Numeric response duration in milliseconds |
| `label` | `label` | `Element` / `User Path Element` | Transaction or sampler name |
| `success` | `success` | `Success` | Normalised to boolean (`TRUE` / `FALSE`) |
| `responseCode` | `responseCode` | *(synthesised)* | Numeric HTTP code (`200` on success, `500` or error code on failure) |
| `responseMessage` | `responseMessage` | *(synthesised)* | Text status message (`OK` on success, failure description on error) |
| `thread_group` | *(derived)* | `User Path` | JMeter thread group name (extracted from `threadName`) or NeoLoad `User Path` |
| `threadName` | `threadName` | `Virtual User ID` | Standardised format: `<ThreadGroup> <VirtualUserID>` |
| `user_index` | *(derived)* | *(derived)* | Integer index of the virtual user for concurrency calculation |
| `allThreads` / `grpThreads` | `allThreads` / `grpThreads` | *(synthesised)* | Instantaneous thread count; used alongside distinct thread calculations |
| `dataType`, `bytes`, `sentBytes`, `Latency`, `Connect`, `IdleTime` | Native columns | *(defaults/elapsed)* | Populated with standard defaults if omitted by external tools |

Because all tools are transformed into the canonical JMeter layout at registration, downstream reporting, SQL queries, SLA evaluations, and executive charts operate on one single unified data model without tool-specific conditional branches.

---

## 7. CSV naming convention (mandatory)

Every CSV in the folder you register **must** be named:

```
<ProjectName>_<TestType>_<AppName>_<BuildId>_<Timestamp>.csv
```

Example:

```
ProjectXYZ_Sanity_DemoApp_123456_20260809-1027.csv
```

| Segment | Becomes | Notes |
|---|---|---|
| `ProjectName` | `project_name` | Overridden by `params.project` in `config.yaml` if set |
| `TestType` | `test_name` | e.g. `Sanity`, `Load`, `Soak` |
| `AppName` | `app_name` | **Per file** — several apps can share one run |
| `BuildId` | `run_id` | Must be **unique across the vault** and **identical for every CSV in the folder** |
| `Timestamp` | metadata | Free-form, e.g. `20260809-1027` |

Rules enforced by the engine:

- fewer than 5 underscore-separated segments ⇒ hard error naming the offending file;
- mixed `BuildId`s within one folder ⇒ hard error (register them as separate runs);
- a `BuildId` already in the vault ⇒ registration aborts (no silent duplicates).

Avoid underscores *inside* a segment — `My_Project_Sanity_App_123_ts.csv` parses as
project `My`, test `Project`, app `Sanity`.

> ℹ️ Older documentation described a `<Project>\<Test>\<Build>\` **folder** structure. That is
> obsolete: the current engine derives everything from the **filename**, and the folder path
> itself is irrelevant.

---

## 8. Registering results into the vault

1. Put all CSVs for one build in a single folder (e.g. `RawResults\ClientX\build-042\`).
2. Launch the front door → choose **2. Register Data**.
3. Choose the tool type — **1. JMeter** (default) or **2. NeoLoad**.
4. Paste the **full path** to the folder containing the CSVs.

The engine stitches the CSVs with `vroom`, renames the columns per the mapping, adds
`run_id`, `project_name`, `test_name`, `app_name`, `csv_filename`, `upload_time`, a derived
`thread_group` / `user_index`, and an auto-incrementing **`sequence_num`** (1, 2, 3 …) so you
can later refer to a run by a short number instead of the full Run ID.

Rows land in the unified **`performance_history`** table in DuckDB. Because all incoming test data is normalized into the canonical JMeter schema at ingestion, any registered runs across the vault can be reported on or compared directly against one another.

Successful output looks like:

```
>>> [REGISTER] project=ProjectXYZ | test=Sanity | unique apps=2 | run_id=123456
>>> [REGISTER] sequence_num=3
>>> [SUCCESS] Registered as Run ID '123456' (Sequence #3) in performance_history
```

---

## 9. Generating a report

1. Launch the launcher (`launch.ps1` or `launch.sh`) → choose **1. Generate Report** (or just press Enter).
2. The engine prints the 10 most recent runs across the vault from `performance_history`:

   ```
   --------------- Recent Runs in Vault --------------
   [#4] Run ID: 1338-MarinaSands | Project: MSD | Test: Sociability | Registered: 2026-10-20 01:12:10
   [#3] Run ID: 750-Tarawera     | Project: MSD | Test: Sociability | Registered: 2026-10-20 01:11:33
   [#2] Run ID: 10003            | Project: ECAN | Test: PeakLoad   | Registered: 2026-10-28 19:45:09
   [#1] Run ID: 10001            | Project: ECAN | Test: PeakLoad   | Registered: 2026-10-28 19:43:19
   -----------------------------------------------------------
   ```

3. Enter the two run inputs — either the **Run ID** (e.g. `10003`) or the **Sequence #** (e.g. `2`):
   - **1. Current Run ID / Sequence # (Required):** The active performance test run under evaluation.
   - **2. Baseline Run ID / Sequence # (Optional):** The reference benchmark run to compare against. Press Enter to generate a standalone single-run report.
4. Optionally enter a **transaction label filter** — one or more comma-separated keywords.
   Each keyword is a *contains* match (case-sensitive, not a regex) and the keywords are
   OR-ed together, so `Login, Checkout` keeps every transaction whose label contains either
   word (`User_Login_Flow`, `Guest_Checkout`, …). Leave blank for all.

   The filter is pushed down into DuckDB as `label LIKE '%keyword%' OR …`, so it is applied
   before the data leaves the vault — a narrow filter makes big runs render much faster.
   If **nothing** matches, the render stops with an explicit error (see §17) instead of
   producing an empty report.

Output (in `output_dir`, `Reports/` by default):

```
Performance_Report_10001_vs_10003_20261029_1710.html
```

Single-run reports are named `Performance_Report_<runId>_<timestamp>.html`. The file is
fully self-contained — email it, archive it, open it in any browser, no server required.

---

## 10. Command-line (non-interactive) usage

Handy for CI/CD pipelines. Run these **from the project root**.

```bash
# List recent runs across the vault
Rscript .engine/engine.R --opMode=menu

# Register a folder of CSVs (specify active_tool to select column mapping from config.yaml)
Rscript .engine/engine.R --opMode=register \
        --rawResultsFolder="/full/path/to/build-042" --active_tool=jmeter

# Register NeoLoad CSVs (automatically normalises into canonical JMeter schema)
Rscript .engine/engine.R --opMode=register \
        --rawResultsFolder="/full/path/to/neoload-build" --active_tool=neoload

# Compare Current run vs Baseline run (tool-agnostic execution)
Rscript .engine/engine.R --opMode=report \
        --current=2 --base=1 --labelFilterParam="TRX"

# Standalone single-run report into a custom output folder
Rscript .engine/engine.R --opMode=report --current=123456 \
        --outputFolder="/mnt/share/perf-reports"
```

| Flag | Default | Meaning |
|---|---|---|
| `--opMode` | `report` | `menu`, `register` or `report` |
| `--rawResultsFolder` | `NONE` | Folder of CSVs (register mode) |
| `--current` | `NONE` | Current candidate Run ID or sequence number (Required for report mode) |
| `--base` (or `--baseline`) | `NONE` | Baseline benchmark Run ID or sequence number (Optional for standalone) |
| `--comp1` / `--comp2` | `NONE` | Legacy aliases: `--comp1` (base) and `--comp2` (current) |
| `--active_tool` | `jmeter` | In `register` mode, selects the mapping block in `config.yaml` (`jmeter` / `neoload`). Optional for `report` mode. |
| `--outputFolder` | `NONE` → `output_dir` from `config.yaml` → `Reports/` | Output directory; local, absolute or UNC, created if missing |
| `--labelFilterParam` | `NONE` | Comma-separated contains-match keywords, OR-ed together |

Windows equivalents use the same flags (`engine.R` or `worker.R` wrapper):

```powershell
& "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" --vanilla .engine\engine.R `
  "--opMode=report" "--current=2" "--base=1" "--labelFilterParam=NONE"
```

Exit codes: `0` on success, `1` when registration is rejected (no CSVs found, duplicate Run ID).
Fatal validation problems (bad filename, missing folder, unknown run) raise an R error.

---

---

## 11. Reading the report

APER Delta v2.0 renders a **single-viewport (100vh) High-Density Executive Performance Dashboard** designed for executive briefings, engineering triage, and release sign-off. Everything is visible at a glance without page scrolling, backed by instant zero-lag modal drilldowns.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ ⚡ Report Title Navbar (Project, Scenario, v2.0 Badge, Date, Theme Toggle: ☀️/🌙)      │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. Consolidated Status Bar: [✅ PASS / ❌ FAIL] | Run #100002 vs #100001 | Meta Info   │
├────────────────────────────────────────┬───────────────────────────────────────────────┤
│ ⚡ Executive Summary & Assessment       │ 2x2 Metric KPI Strip                          │
│ ├── Narrative (2 Paragraphs)           │ ├── Max Virtual Users  ├── Apps Passed TPS    │
│ └── 📋 Next Steps (3 Action Items)     │ ├── Scenarios Met RT   ├── Passed Error SLA   │
├────────────────────────────────────────┴───────────────────────────────────────────────┤
│ 2. 🏥 Application Health & Baseline Matrix (Requests, TPS, RT, Error %, SLA vs Base)   │
├────────────────────────────────────────┬───────────────────────────────────────────────┤
│ 3. 🧭 Scenario Breakdown (App Filter)  │ 4. 🔥 Top Response Time Breaches (Micro-bars) │
├────────────────────────────────────────┼───────────────────────────────────────────────┤
│ 5. ⚠️ Top Error Contributors (Pareto)  │ 6. ⚖️ Current vs Baseline Comparison Scorecard │
└────────────────────────────────────────┴───────────────────────────────────────────────┘
```

### Zone 1: Executive Assessment & 2x2 KPI Strip
- **Consolidated Top Status Bar** — Overall PASS/FAIL release gate verdict, Run IDs, start/end timestamps, test duration, peak concurrency, and optional `🖥 Infrastructure 🔍` button.
- **Executive Summary Callout (2-Column)**:
  - **Left (Narrative Synthesis)**: Paragraph 1 covers workload profile (duration, dynamically calculated ramp-up and steady state, max concurrent users, throughput, error rate, and baseline P95 latency improvement/regression). Workload phases are calculated dynamically from test telemetry and active thread boundaries across all application workloads. Paragraph 2 details SLA release criteria compliance, breach counts, worst-performing transaction vs SLA threshold, and impacted flow clusters.
  - **Right (📋 Next Steps)**: Dedicated action plan box with 3 targeted performance engineering recommendations (steady-state scoping validation, APM/server log triage for top bottlenecks, and re-test verification).
- **2x2 KPI Strip**:
  - `Max Virtual Users`: achieved concurrency vs target threshold.
  - `Apps Passed TPS SLA`: application count passing throughput gate with aggregate TPS.
  - `Scenarios Met RT SLA`: scenario count passing transaction-level response time criteria with current P95 ms.
  - `Scenarios Passed Error SLA`: scenarios compliant with error rate criteria.

### Zone 2: Application Health & Baseline Matrix
- Comprehensive multi-app scorecard comparing Current vs Baseline for Total Requests, Average Throughput, P95/P90 Response Time, Error Rate %, and Scenarios Met RT SLA.
- Inline delta badges (`▲` / `▼`) highlight performance trends; clicking `SLA Status 🔍` or `Scenarios Met RT SLA 🔍` opens instant modal deep-dives.

### Zone 3: Failure Analysis Grids
- **Scenario Breakdown**:
  - Per-scenario health table with interactive **App Filter Pills** (`All`, `App1`, `App2`) for multi-application runs.
  - Shows requests, throughput, scenario P95, transaction SLA compliance (`X of Y`), and error rate.
  - *Note:* In accordance with performance testing standards, SLA pass/fail status is rigorously evaluated against transaction-level thresholds, decoupling aggregate scenario P95 values from false SLA failures.
- **Top Response Time Breaches**:
  - Ranked list of the worst-performing transactions vs threshold with inline severity micro-bars, actual response time, SLA threshold, and % breach. Clicking any row opens the transaction drilldown modal.

### Zone 4: Error Pareto & Baseline Scorecard
- **Top Error Contributors**: Lists the highest error-producing transactions with error counts and proportional share micro-bars.
- **Current vs Baseline Comparison**: Metric-by-metric scorecard comparing Max Users, Aggregate Throughput, Error Rate %, P95 Response Time, TPS Pass Rate, Error SLA Pass Rate, and RT SLA Pass Rate.

### Interactive Zero-Lag Modals
Clicking any search icon (`🔍`) or navigation badge opens a responsive dialog without page reload:
1. **Executive Charts Modal (`📈 Executive Charts 🔍` / `📈 Compare vs Base` / `⭐ Apdex Experience`)**: Lightweight pure-SVG multi-view performance visualizer with application filter pills:
   - **Executive 2x2 Grid**: 4 key performance cards (Response Time Timeline, Throughput Profile with VU Backdrop, Apdex User Experience & Performance Index, and Error Spike Timeline & Top 5 Pareto Share).
   - **Latency & Load Timelines**: Minute-by-minute response time and throughput vs baseline.
   - **Apdex User Experience & Performance Index**: Industry-standard Apdex rating (0.00 to 1.00) measuring user satisfaction evaluated against per-transaction target thresholds ($T$). Features horizontal stacked experience zones (🟢 Satisfied $\le T$, 🟡 Tolerating $T-4T$, 🔴 Frustrated $>4T$ or Error), Apdex score badge with standard rating (`Excellent`, `Good`, `Fair`, `Poor`, `Unacceptable`), run-over-run comparison, and an educational explainer box directly on the card with instant links to the Glossary modal. File uploads/downloads and custom endpoints are evaluated against their own specific SLA targets without false penalties.
   - **Scenario vs Baseline**: Transaction-stacked horizontal duration bars with drill-down to individual transactions.
   - **Error Timeline & Pareto**: Errors/min spikes and cumulative Pareto share distribution.
2. **SLA Evaluation Modal**: Detailed rule-by-rule audit for all run-level and application thresholds.
3. **Scenario Health Details Modal**: Deep breakdown per scenario and transaction flow.
4. **Transaction RT Breakdown Modal**: Complete transaction-level table with search, sorting, and delta vs baseline.
5. **HTTP Error Breakdown Modal**: Response code distribution and error payload messages.
6. **Infrastructure Evidence Modal**: Displays manual CPU, memory, and disk screenshots placed in `Evidence/<run_id>/`.
7. **Glossary & Methodology Modal**: Clear definitions of percentile calculations, formulas, and evaluation rules.

---

## 12. SLA configuration

Default file: `SLA/performance-sla.yaml` (path set by `sla_file_path`). Missing or blank ⇒ all
SLA logic is skipped and the report still renders.

### Run-level rules

```yaml
sla_rules:
  - metric: total_users          # total_users | error_rate | throughput
    label: "Virtual Users"
    operator: ">="               # <=  >=  <  >  ==
    threshold: 100
    description: "Optional free text"

  - metric: error_rate
    label: "Error Rate"
    operator: "<="
    threshold: 1.0
    unit: "%"

  - metric: throughput
    label: "Throughput"
    operator: ">="
    threshold: 10.0
    unit: "req/s"
```

Each rule is evaluated **per run**; a run passes overall only when every rule passes.

### Per-transaction response time SLA

```yaml
response_time_sla:
  metric: p95                  # p90 or p95
  unit: "ms"
  default_threshold: 3000      # applied to any transaction not overridden
  tolerance_pct: 5             # actual may exceed threshold by 5% and still pass
  overrides:
    - label: "Login"           # exact label match
      threshold: 1500
    - label: "Checkout"
      threshold: 5000
```

A transaction fails when `actual > threshold × (1 + tolerance_pct/100)`. Breaches are ranked by
`breach_pct` and surfaced in the Top Breaches card. Only list exceptions —
everything else inherits `default_threshold`.

---

## 13. Chart visibility

```yaml
charts:
  tpmVerticalStack: true
  rawScatterWebGL: false     # hides heavy charts if needed
```

Any key omitted from the block defaults to **shown**. Turning off heavy scatter charts is the quickest way to cut render time and HTML size on very large datasets.

---

## 14. AI Summary & Hybrid Architecture

APER Delta v2.0 features a **Hybrid Executive Summary Architecture** combining generative AI with a 100% reliable deterministic fallback engine:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Hybrid Generation Flow                          │
├────────────────────────────────────────────────────────────────────────┤
│ 1. Check config.yaml (ai_summary_enabled) & secrets.yaml (token)       │
│                                                                        │
│ ┌───────────────────────────┐         ┌──────────────────────────────┐ │
│ │  Amplify AI LLM Engine    │         │  Deterministic Rule Engine   │ │
│ │  (REST API Completion)    │         │  (Native R Script in-memory) │ │
│ ├───────────────────────────┤         ├──────────────────────────────┤ │
│ │ • Context-rich prompt     │─(Fail)─>│ • 100% offline & instant     │ │
│ │ • Few-shot style guide    │         │ • Zero token / API dependency│ │
│ │ • Dynamic Next Steps      │         │ • Exact same metrics & logic │ │
│ └─────────────┬─────────────┘         └──────────────┬───────────────┘ │
│               └───────────────────────┬──────────────┘                 │
│                                       ▼                                │
│                Rich Executive Narrative + Next Steps                   │
│                                       │                                │
│                   Rendered in Executive Dashboard                      │
└────────────────────────────────────────────────────────────────────────┘
```

### Setup & Activation
1. Create `secrets.yaml` in the project root (git-ignored, never commit it):

   ```yaml
   amplify_token: "your-amplify-token-here"
   ```

2. Set `ai_summary_enabled: "true"` in `config.yaml`.
3. The engine sends aggregated run metrics (users, throughput, error rate, baseline delta %, SLA breaches, top failing endpoints) to the completion endpoint (`ai_url` / `ai_model_id`).

### Automatic Deterministic Fallback
If any of the following occur:
- `secrets.yaml` is missing or the token has expired/unauthorized
- The machine is offline or behind a firewall blocking the API endpoint
- `ai_summary_enabled` is set to `"false"`
- The API call times out or returns an error

**The engine immediately and seamlessly falls back to the internal deterministic generator.**
- It computes and synthesizes the identical structured two-paragraph executive narrative and three tailored Next Steps directly from DuckDB metrics in memory.
- **Guarantee:** Reports **never break, never hang, and never display empty or missing summary boxes**.

---

## 15. Observations (editable notes in the report)

Every chart and the AI panel carry an **Observation** box that you can type into directly in the
rendered HTML.

- Supported syntax: `**bold**`, `_italic_`, `__underline__`, `==highlight==`, plus the special
  `==OVERALL PASSED==` / `==OVERALL FAILED==` badges.
- Toggle ✏️ Edit / 👁️ Preview per box. Drafts auto-save to browser `localStorage`.
- **💾 Save Observations File** writes `<report-name>_observations.js` — keep that file in the
  **same folder as the HTML** and the notes reload for anyone who opens the report (the HTML
  alone does not carry them).

---

## 16. Maintaining the vault

Run from the project root:

| Script | Purpose |
|---|---|
| `Rscript check_db_head.R` | Lists tables, row counts, column types and a sample row; also runs `VACUUM` |
| `Rscript check_rows.R` | Lists the distinct `csv_filename` / `app_name` pairs registered per table |
| `Rscript delete_by_runid.R` | Deletes one run and vacuums — **edit `target_run` and the table name inside the script first** |

Notes:

- DuckDB takes an exclusive lock: close RStudio/other R sessions before registering, otherwise
  you get `Could not set lock on file`.
- To start clean, simply delete the vault file pointed at by `database_path` — the next
  registration recreates it (sequence numbers restart at 1).
- The helper scripts read `database_path` from `config.yaml`, so they follow the vault to a
  shared drive automatically — except `delete_by_runid.R`, which has the path hard-coded to
  `Data/Performance_Vault.db`; edit it before running against a shared vault.
- The vault is git-ignored; back it up yourself if run history matters.

---

## 17. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Rscript.exe not found` | R not installed, or installed without the 64-bit (`x64`) files. See §2 |
| `pandoc version 1.12.3 or higher is required and was not found` | Pandoc missing from `PATH`. Install it (§3), reopen the terminal, or set `RSTUDIO_PANDOC` / drop a portable copy in `RLibs/tools/pandoc` |
| `cannot open file 'config.yaml'` | You launched from the wrong directory — run from the project root |
| `Filename 'X.csv' does not match expected format` | Rename to `<Project>_<TestType>_<App>_<BuildId>_<Timestamp>.csv` (§7) |
| `CSV files in the folder have different BuildIds` | Split them into one folder per build and register separately |
| `Run ID 'X' already exists` | That build is already registered — report on it, or remove it with `delete_by_runid.R` |
| `[ERROR] No CSV files found in: …` | Wrong path, or the files are in a sub-folder (the scan is not recursive) |
| `Run(s) not found (checked both run_id and sequence_num)` | Typo in Run ID/sequence number, or the run has not been registered yet |
| `Table 'performance_history' does not exist` | No test data has been registered into the vault yet |
| `column not found` during registration | Your export headers differ from `tool_mappings` — update `config.yaml` (§6) |
| `No transactions matched query criteria` | The label filter excluded everything (matching is case-sensitive). Re-run with fewer keywords or an empty filter |
| `cannot create dir '//<host>/shared/...'` / vault not found on a share | `config.yaml` still has the `//<host>/...` placeholders, or the share is unreachable / not permitted. Check the `[DB]` and `[REPORT]` path lines printed at startup (§6) |
| AI summary shows a warning | `secrets.yaml` missing or token blank (§14) |
| Response Time SLA shows `N/A` | No `response_time_sla` block, or no SLA file configured |
| First run hangs for many minutes | Package bootstrap into `RLibs/` — normal once; check proxy settings if it never finishes |
| `Could not set lock on file … Performance_Vault.db` | Another R session/RStudio holds the vault open — close it and retry |
| PowerShell refuses to run the script | `powershell -ExecutionPolicy Bypass -File .\launch.ps1` |

---

## 18. Quick reference

| Task | How |
|---|---|
| Install prerequisites | R 4.6.0 (§2) + latest Pandoc (§3) / Quarto CLI |
| Start the tool | `launch.ps1` (Windows) / `./launch.sh` (Linux/macOS), from the project root |
| Register results | Menu → **2** → tool type → full folder path |
| `Generate a report` | Menu → **1** (or Enter) → Current Run ID & Baseline Run ID → optional filter |
| Compare runs | Pass `--current=<run>` and `--base=<run>` (or enter both at interactive prompt) |
| Filter transactions | Type one or more comma-separated substrings at the filter prompt (`Login, Checkout`) |
| Filter by application | Click application pill buttons (`All`, `App1`, `App2`) in Scenario Breakdown or Charts Modal |
| Add infrastructure screenshots | Drop `.png` files into `Evidence/<run_id>/` (opens via `🖥 Infrastructure 🔍`) |
| Switch report theme | Click the ☀️ / 🌙 theme toggle in the top-right navbar |
| Set report version | Update `params.version` in `config.yaml` (e.g. `v2.0`) |
| Set SLA thresholds | `SLA/performance-sla.yaml` |
| Exclude labels globally | Add label names under `label_exclusions` in `config.yaml` |
| AI Executive Summary | `ai_summary_enabled: "true"` + `secrets.yaml` (automatically falls back if offline/expired) |
| Find the output | `<output_dir>/Performance_Report_<runs>_<timestamp>.html` (`Reports/` by default) |
| Use a shared vault / report folder | Point `database_path` and `output_dir` at a UNC or absolute path (§6) |
| Inspect the vault | `Rscript check_db_head.R` |
| Delete a run | Edit and run `delete_by_runid.R` |
| Reset everything | Delete `Data/Performance_Vault.db` |
