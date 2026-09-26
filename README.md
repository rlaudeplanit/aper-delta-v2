# APER Delta — Complete Usage Guide

APER Delta turns raw **JMeter** or **NeoLoad** CSV results into a single self-contained
interactive HTML report that compares up to **3 test runs** — charts, tables, SLA pass/fail
evaluation and an optional AI-written executive summary.

You do not need to know R. Everything is driven by an interactive menu
(`frontdoor.ps1` on Windows, `frontdoor.sh` on Linux/macOS) which calls the R engine
(`.engine/worker.R`) for you.

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
14. [AI summary setup](#14-ai-summary-setup)
15. [Observations (editable notes in the report)](#15-observations-editable-notes-in-the-report)
16. [Maintaining the vault](#16-maintaining-the-vault)
17. [Troubleshooting](#17-troubleshooting)
18. [Quick reference](#18-quick-reference)

---

## 1. How the tool works

```
frontdoor.ps1 / frontdoor.sh      interactive menu — locates Rscript, asks questions
        │
        ▼
.engine/worker.R                  CLI dispatcher (--opMode = menu | register | report)
        │                         also bootstraps R packages into ./RLibs
        │                         resolves the vault & output paths (local, absolute or UNC)
        ├── register ──► <database_path>                (DuckDB "vault")
        └── report   ──► .engine/storyteller.Rmd        (Flexdashboard template)
                              ├── .engine/Dashboard/*.Rmd   KPI boxes, SLA, AI summary
                              ├── .engine/Tables/*.Rmd      DT tables
                              ├── .engine/Charts/*.Rmd      Plotly charts
                              ├── .engine/Utilities/*.R     metrics + theming helpers
                              └── .engine/Styles/*          CSS, icons
                                        │
                                        ▼
                              <output_dir>/Performance_Report_<runs>_<timestamp>.html
```

The vault and the report folder can both live on a **shared network drive**, so a whole team
can register into and report from one central vault — see §6.

Two distinct phases:

| Phase | What it does | Repeatable? |
|---|---|---|
| **Register** | Reads every CSV in a folder, normalises columns per tool, appends rows to the DuckDB vault under one **Run ID** | Once per Run ID (duplicates are rejected) |
| **Report** | Reads 1–3 registered runs back out of the vault and renders the HTML dashboard | As often as you like |

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

**Rtools is not required.** `worker.R` installs packages with `type = "binary"` from
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

`worker.R` also honours a **portable copy** at `RLibs/tools/pandoc/` — drop the extracted
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

**Windows:** right-click `frontdoor.ps1` → *Run with PowerShell*, or from a PowerShell prompt
opened in the project root:

```powershell
cd C:\Tools\aper-delta
powershell -ExecutionPolicy Bypass -File .\frontdoor.ps1
```

**Linux/macOS:**

```bash
chmod +x frontdoor.sh      # first time only
./frontdoor.sh
```

> ⚠️ **Always launch from the project root.** `worker.R` reads `config.yaml` from the *current
> working directory*, so running `Rscript .engine/worker.R` from elsewhere fails with
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
├── frontdoor.ps1                 # Windows interactive launcher
├── frontdoor.sh                  # Linux/macOS interactive launcher
├── config.yaml                   # Main configuration (charts, paths, column mappings)
├── secrets.yaml                  # (you create this) Amplify API token — git-ignored
├── aper-delta.Rproj              # RStudio project; also the `here::here()` root anchor
├── .engine/
│   ├── worker.R                  # CLI dispatcher & package bootstrapper
│   ├── storyteller.Rmd           # Master Flexdashboard template (3 tabs)
│   ├── Dashboard/                # dash-testSummary, dash-metrics, dash-rt-sla, dash-aiSummary…
│   ├── Tables/                   # tab-aggregates, tab-slowest, tab-errors
│   ├── Charts/                   # one .Rmd per chart
│   ├── Utilities/                # utils.R (theme/palette/observations), dashboard.R, rtBreakdown.R…
│   └── Styles/                   # styles.css, Planit icons
├── SLA/performance-sla.yaml      # SLA thresholds
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
| `rmd_template` | Path to the master template | **Do not change** |
| `output_dir` | Where HTML reports go | Relative, absolute or UNC — see “Shared / network locations” below |
| `database_path` | DuckDB vault file | Relative, absolute or UNC — see “Shared / network locations” below |
| `sla_file_path` | SLA definitions | Blank or missing file ⇒ SLA evaluation skipped silently |
| `ai_summary_enabled` | `"true"` / `"false"` | Requires `secrets.yaml` (see §14) |
| `ai_url`, `ai_model_id` | Amplify completion endpoint & model | Change only if IT gives you a new endpoint |
| `charts.*` | Per-chart on/off switches | See §13 |
| `tool_type` | Default engine | System default — the launcher overrides it per run |
| `tool_mappings.jmeter` / `.neoload` | Source-CSV column → internal field mapping | Edit **only** if your export uses different headers |
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

### Column mappings — what your CSV must contain

The registration step selects exactly the source columns listed under the active tool's
mapping, so those headers must exist in your CSV (blank entries are ignored).

| Internal field | JMeter header | NeoLoad header |
|---|---|---|
| `timestamp` | `timeStamp` (epoch ms) | `Time` (`YYYY-MM-DDTHH:MM:SS`) |
| `elapsed` | `elapsed` | `Response time` |
| `label` | `label` | `Element` |
| `success` | `success` | `Success` |
| `threadName` | `threadName` | `Virtual User ID` |
| `responseCode` / `responseMessage` | `responseCode` / `responseMessage` | *(not available — report shows `N/A`)* |
| `userPath` / `population` | *(n/a)* | `User Path` / `Population` |
| others | `bytes`, `sentBytes`, `grpThreads`, `allThreads`, `URL`, `Latency`, `IdleTime`, `Connect`, `dataType`, `failureMessage` | — |

If your NeoLoad export names the duration column `Duration`, or the label column
`User Path Element`, update the mapping accordingly — otherwise registration fails with a
`vroom` “column not found” error.

Derived at registration time: `thread_group` (JMeter: `threadName` with the trailing
`" <n>-<n>"` stripped; NeoLoad: trimmed `User Path`) and `user_index` (the numeric suffix of
`threadName`, used for virtual-user counts).

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

Rows land in `performance_history_jmeter` or `performance_history_neoload` — the two tool types
are stored separately and **cannot be compared against each other in one report**.

Successful output looks like:

```
>>> [REGISTER] project=ProjectXYZ | test=Sanity | unique apps=2 | run_id=123456
>>> [REGISTER] sequence_num=3
>>> [SUCCESS] Registered as Run ID '123456' (Sequence #3) in performance_history_jmeter
```

---

## 9. Generating a report

1. Launch the front door → **1. Generate Report** (or just press Enter).
2. Choose the tool type — the same one the runs were registered under.
3. The engine prints the 10 most recent runs for that tool:

   ```
   --------------- Recent JMETER Runs in Vault --------------
   [#3] Run ID: 123456 | Project: ProjectXYZ | Test: Sanity | Registered: 2026-08-09 10:31:02
   [#2] Run ID: 123455 | Project: ProjectXYZ | Test: Sanity | Registered: 2026-08-02 09:12:44
   ```

4. Enter **up to 3** runs, one per line — either the **Run ID** (`123456`) or the
   **Sequence #** (`3`). Press Enter on an empty line to finish (at least one is required).
5. Optionally enter a **transaction label filter** — one or more comma-separated keywords.
   Each keyword is a *contains* match (case-sensitive, not a regex) and the keywords are
   OR-ed together, so `Login, Checkout` keeps every transaction whose label contains either
   word (`User_Login_Flow`, `Guest_Checkout`, …). Leave blank for all.

   The filter is pushed down into DuckDB as `label LIKE '%keyword%' OR …`, so it is applied
   before the data leaves the vault — a narrow filter makes big runs render much faster.
   If **nothing** matches, the render stops with an explicit error (see §17) instead of
   producing an empty report.

Output (in `output_dir`, `Reports/` by default):

```
Performance_Report_123455_vs_123456_20260809_1435.html
```

Single-run reports are named `Performance_Report_<runId>_<timestamp>.html`. The file is
fully self-contained — email it, archive it, open it in any browser, no server required.

---

## 10. Command-line (non-interactive) usage

Handy for CI pipelines. Run these **from the project root**.

```bash
# List recent runs (what the menu prints)
Rscript .engine/worker.R --opMode=menu --active_tool=jmeter

# Register a folder of CSVs
Rscript .engine/worker.R --opMode=register \
        --rawResultsFolder="/full/path/to/build-042" --active_tool=jmeter

# Compare two runs, filtering to transactions containing "TRX" or "TRN"
Rscript .engine/worker.R --opMode=report \
        --comp1=1 --comp2=2 --active_tool=jmeter --labelFilterParam="TRX, TRN"

# Single-run report into a custom output folder
Rscript .engine/worker.R --opMode=report --comp1=123456 \
        --active_tool=neoload --outputFolder="/mnt/share/perf-reports"
```

| Flag | Default | Meaning |
|---|---|---|
| `--opMode` | `report` | `menu`, `register` or `report` |
| `--rawResultsFolder` | `NONE` | Folder of CSVs (register mode) |
| `--comp1` / `--comp2` / `--comp3` | `NONE` | Run ID **or** sequence number to include |
| `--active_tool` | `jmeter` | `jmeter` or `neoload` (selects the vault table) |
| `--outputFolder` | `NONE` → `output_dir` from `config.yaml` → `Reports/` | Output directory; local, absolute or UNC, created if missing |
| `--labelFilterParam` | `NONE` | Comma-separated contains-match keywords, OR-ed together |

Windows equivalents use the same flags:

```powershell
& "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" --vanilla .engine\worker.R `
  "--opMode=report" "--comp1=1" "--comp2=2" "--active_tool=jmeter" "--labelFilterParam=NONE"
```

Exit codes: `0` on success, `1` when registration is rejected (no CSVs found, duplicate Run ID).
Fatal validation problems (bad filename, missing folder, unknown run) raise an R error.

---

## 11. Reading the report

The dashboard has three tabs.

### Dashboard
- **Test Information** — project, Run ID, start/end time and duration per run; the highest
  sequence number is flagged as the **current** run.
- **Performance Metrics** — virtual users (distinct `user_index`), total transactions,
  throughput (transactions ÷ elapsed wall-clock seconds), pass/fail counts, error rate %.
  With an SLA file present, boxes turn **green** on pass and **red** on fail.
- **Response Time SLA** — count of transactions breaching their p90/p95 threshold plus the
  top 3 worst offenders. Shows `N/A` when no `response_time_sla` block is defined.
- **AI Performance Summary** — plain-English narrative of the run(s), weighted to the most
  recent run (see §14).

> SLA evaluation covers **client-side** metrics only (response time, error rate, throughput,
> virtual users). Server-side CPU/memory are not captured.

### Tables
- **Aggregates — Side by Side** — per transaction, per run: min / avg / p90 / p95 / max ms,
  total, pass and fail counts, average received bytes.
- **Slowest Transactions** — the 1000 slowest samples per run per app.
- **Error Transactions** — every failed sample; response code for JMeter, `N/A` for NeoLoad.

All tables have per-column filters (dropdown multi-select or free-text).

### Charts
Plotly charts, each toggleable in `config.yaml`:

| Tab | Chart key |
|---|---|
| Overall Throughput (TPM) | `tpmVerticalStack` |
| Response Time Scatter | `rawScatterWebGL` |
| Virtual Users (Load) | `vUsersPerMinute` |
| Throughput by App | `tpmVerticalStackByCsvFilename` |
| Throughput vs Response Time | `throughputVsRT` |
| Response Time vs Load | `rtVsUserLoad` |
| Average Response Times | `avgRtBreakdown` |
| 90th Percentile RT | `pct90RtBreakdown` |
| Avg RT by Transaction | `groupedAvgRT` |
| 90th Percentile RT by Transaction | `groupedPercentiles` |
| Transaction Volume | `txCountBreakdown` |
| Error Rate | `errorsPerMinute` |
| RT Scatter by App | `rawScatterWebGLByCsvFilename` |

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
`breach_pct` and the worst three are surfaced on the dashboard. Only list exceptions —
everything else inherits `default_threshold`.

---

## 13. Chart visibility

```yaml
charts:
  tpmVerticalStack: true
  rawScatterWebGL: false     # hides the tab entirely
```

Any key omitted from the block defaults to **shown**. Use the keys from the table in §11.
Turning off heavy charts (`rawScatterWebGL*`, `groupedPercentiles`) is the quickest way to cut
render time and HTML size on very large datasets.

---

## 14. AI summary setup

1. Create `secrets.yaml` in the project root — it is git-ignored, never commit or share it:

   ```yaml
   amplify_token: "your-token-here"
   ```

2. Ensure `ai_summary_enabled: "true"` in `config.yaml`, and that `ai_url` / `ai_model_id`
   point at your Amplify endpoint.

Behaviour when something is missing:

| Situation | Result |
|---|---|
| `ai_summary_enabled: "false"` | Panel hidden entirely; report renders normally |
| `secrets.yaml` missing / empty token | Panel shows “⚠ AI Summary unavailable: api_key not found.” |
| Endpoint unreachable | Panel shows the error; the rest of the report is unaffected |

The prompt is built from aggregated per-run metrics only (run ID, duration, users, transaction
counts, throughput, error rate) — raw request data is never sent.

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
| `Run(s) not found (checked both run_id and sequence_num)` | Typo, or you picked the wrong tool type — JMeter and NeoLoad live in separate tables |
| `Table 'performance_history_neoload' does not exist` | Nothing registered yet for that tool type |
| `column not found` during registration | Your export headers differ from `tool_mappings` — update `config.yaml` (§6) |
| `No transactions matched query criteria` | The label filter excluded everything (matching is case-sensitive). Re-run with fewer keywords or an empty filter |
| `cannot create dir '//<host>/shared/...'` / vault not found on a share | `config.yaml` still has the `//<host>/...` placeholders, or the share is unreachable / not permitted. Check the `[DB]` and `[REPORT]` path lines printed at startup (§6) |
| AI summary shows a warning | `secrets.yaml` missing or token blank (§14) |
| Response Time SLA shows `N/A` | No `response_time_sla` block, or no SLA file configured |
| First run hangs for many minutes | Package bootstrap into `RLibs/` — normal once; check proxy settings if it never finishes |
| `Could not set lock on file … Performance_Vault.db` | Another R session/RStudio holds the vault open — close it and retry |
| PowerShell refuses to run the script | `powershell -ExecutionPolicy Bypass -File .\frontdoor.ps1` |

---

## 18. Quick reference

| Task | How |
|---|---|
| Install prerequisites | R 4.6.0 (§2) + latest Pandoc (§3) |
| Start the tool | `frontdoor.ps1` (Windows) / `./frontdoor.sh` (Linux/macOS), from the project root |
| Register results | Menu → **2** → tool type → full folder path |
| Generate a report | Menu → **1** (or Enter) → tool type → Run IDs / Sequence #s → optional filter |
| Compare runs | Enter up to 3 identifiers, one per line |
| Filter transactions | Type one or more comma-separated substrings at the filter prompt (`Login, Checkout`) |
| Find the output | `<output_dir>/Performance_Report_<runs>_<timestamp>.html` (`Reports/` by default) |
| Use a shared vault / report folder | Point `database_path` and `output_dir` at a UNC or absolute path (§6) |
| Hide a chart | `charts.<key>: false` in `config.yaml` |
| Set SLA thresholds | `SLA/performance-sla.yaml` |
| Toggle AI summary | `ai_summary_enabled` in `config.yaml` + `secrets.yaml` token |
| Inspect the vault | `Rscript check_db_head.R` |
| Delete a run | Edit and run `delete_by_runid.R` |
| Reset everything | Delete `Data/Performance_Vault.db` |
