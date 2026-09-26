# ============================================================
#  UTILITIES MODULE FOR REPORT CHARTS
#  - Global theming
#  - Polychrome palette system
#  - Axis helpers
#  - Total RT helpers
#  - Plotly layout helpers
#  - Scrollable container wrapper
# ============================================================

library(Polychrome)
library(ggplot2)
library(plotly)
library(dplyr)
library(stringr)
library(htmltools)

# ============================================================
# GLOBAL Colors
# ============================================================

background      <-  "#2F3136"
card            <-  "#3A3D42"
secondaryCard   <-  "#44484F"
border          <-  "#555A61"
text            <-  "#FFFFFF"
mutedText       <-  "#D0D3D8"

planitWhite      <- "#FFFFFF"
planitLightGrey  <- "#DADADA"
planitGrey       <- "#7d7d7d"
planitDarkGrey   <- "#444444"
planitBlack      <- "#000000"

planitBlue       <- "#1414FF"
planitOrange     <- "#FF6432"
planitPurple     <- "#8A3C97"

backgroundBlack  <- "#000000"
backgroundWhite  <- "#FBFCFC"

passedGreen      <- "#16A34A"
failedRed        <- "#DC2626"

testInfoBlack    <- "#242424"


# ============================================================
#  GLOBAL GGPLOT THEME
#  - Applies a consistent monospace theme across all ggplots
# ============================================================
theme_set(
  theme_minimal() +
    theme(text = element_text(family = "monospace"))
)

# ============================================================
#  GLOBAL PLOTLY FONT
#  - Ensures Plotly charts also use monospace typography
# ============================================================
apply_global_plotly_layout <- function(plotly_obj) {
  plotly_obj %>%
    layout(font = list(family = "monospace"))
}

# ============================================================
# SMART PALETTE ENGINE
# - Uses Polychrome for <= 36 colors (high distinctness)
# - Uses colorRampPalette for > 36 colors (unlimited)
# - Always returns EXACTLY n colors
# - Always reproducible (set.seed)
# ============================================================
choose_palette <- function(n) {
  set.seed(42)  # stable, reproducible colours
  
  # 1. For small counts (1 to 10), use a dedicated clean palette
  if (n >= 1 && n <= 10) {
    # Using the color-blind friendly Okabe-Ito palette built into R
    # (Excludes the first color "black" if n is small, or takes what is needed)
    all_colors <- grDevices::palette.colors(palette = "Okabe-Ito")
    clean_colors <- unname(all_colors[all_colors != "#000000"]) # Remove black if preferred
    return(clean_colors[1:n])
  }
  
  # 2. Polychrome is excellent up to ~36 colors
  if (n <= 36) {
    return(Polychrome::palette36.colors(n))
  }
  
  # 3. For large palettes, use a smooth gradient
  big_palette <- grDevices::colorRampPalette(
    c("#4477AA", "#66CCEE", "#228833", "#CCBB44",
      "#EE6677", "#AA3377", "#BBBBBB")
  )
  
  return(big_palette(n))
}


# ============================================================
#  AXIS STRING BUILDER
#  - Truncates long scenario names
#  - Produces "Scenario | Run ID" axis labels
# ============================================================
build_axis_string <- function(executionGroup, run_id, width = 25) {
  exec_clean <- stringr::str_trunc(as.character(executionGroup), width)
  interaction(exec_clean, run_id, sep = " | ")
}

# ============================================================
#  TOTAL RESPONSE TIME CALCULATOR
#  - Computes cumulative RT per run (Avg or 90th)
#  - Works for any numeric RT column
# ============================================================
compute_total_rt <- function(df, value_col, group_cols = c("app_name", "run_id", "executionGroup_clean")) {
  df %>%
    group_by(across(all_of(group_cols))) %>%
    summarise(total_rt = sum(.data[[value_col]]), .groups = "drop")
}

# ============================================================
#  LABEL POSITION CALCULATOR
#  - Computes x-offset for right-side total labels
#  - Ensures consistent spacing across all charts
# ============================================================
compute_label_x <- function(total_values) {
  max_val <- max(total_values$total_rt, na.rm = TRUE)
  total_values %>%
    mutate(label_x = total_rt + max_val * 0.03)
}

# ============================================================
#  LABEL POSITION FOR INDIVIDUAL BARS (GROUPED CHARTS)
#  - Computes x-offset for each bar based on its own value
#  - Uses global max to ensure consistent spacing
# ============================================================
compute_label_x_single <- function(df, value_col) {
  max_val <- max(df[[value_col]], na.rm = TRUE)
  df %>%
    mutate(label_x = .data[[value_col]] + max_val * 0.03)
}

# ============================================================
#  AXIS LOCKING FOR PLOTLY
#  - Detects all subplot axes
#  - Freezes zoom/pan for consistent dashboard behavior
# ============================================================
lock_all_axes <- function(plotly_obj, layout_list) {
  axis_names <- names(plotly_obj$x$layout)
  axis_names <- axis_names[grepl("^xaxis|^yaxis", axis_names)]
  
  for (ax in axis_names) {
    layout_list[[ax]] <- list(fixedrange = TRUE)
  }
  
  layout_list
}

# ============================================================
#  DEFAULT PLOTLY LAYOUT
#  - Shared layout settings for all charts
#  - Legend, margins, hover behavior, stacking mode
# ============================================================
default_plotly_layout <- function(showlegend = TRUE) {
  list(
    showlegend = showlegend,
    legend = list(
      orientation = "v",
      x = 1.05,
      y = 1,
      yanchor = "top"
    ),
    margin = list(l = 100, r = 220, b = 60, t = 80),
    dragmode = FALSE,
    barmode = "stack",
    hoverlabel = list(bgcolor = "white")
  )
}

# ============================================================
#  SCROLLABLE CONTAINER WRAPPER
#  - Prevents oversized charts from breaking page layout
#  - Adds consistent padding + border styling
# ============================================================
wrap_scrollable <- function(plot_obj, height = 800) {
  htmltools::tags$div(
    style = sprintf("
      width: 100%%;
      height: %dpx;
      overflow-y: auto;
      overflow-x: hidden;
      border: 1px solid #e3e3e3;
      padding: 10px;
    ", height),
    plot_obj
  )
}

build_run_testname_subtitle <- function(df) {
  df %>%
    distinct(run_id, test_name) %>%
    mutate(pair = paste0(run_id, " - ", test_name)) %>%
    pull(pair) %>%
    paste(collapse = " | ")
}

render_observation_panel <- function(chart_id, initial_text = "") {
  
  report_id <- if (exists("params") && !is.null(params$report_id)) params$report_id else "default_report"
  
  # Palette definitions
  planitLightGrey <- "#DADADA"
  planitGrey      <- "#7d7d7d"
  planitDarkGrey  <- "#444444"
  
  htmltools::tags$div(
    style = sprintf("
      width: 100%%;
      box-sizing: border-box;
      margin-top: 10px;
      border: 1px solid %s;
      border-radius: 6px;
      padding: 12px;
      background-color: %s;
    ", planitGrey, planitDarkGrey),
    
    htmltools::tags$div(
      style = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;",
      
      htmltools::tags$h4("Observation", style = sprintf("margin: 0; color: %s;", planitLightGrey)),
      
      # Toggle Button — Defaults to 'Edit' action because Preview mode is active by default
      htmltools::tags$button(
        "✏️ Edit",
        id = paste0(chart_id, "_toggle_view"),
        style = sprintf("color: %s; background-color: #333333; border: 1px solid %s; padding: 3px 10px; font-size: 11px; border-radius: 3px; cursor: pointer;", planitLightGrey, planitGrey)
      )
    ),
    
    # Raw Text Editor (Hidden by default, placeholder contains formatting guide)
    htmltools::tags$textarea(
      id = paste0(chart_id, "_comment"),
      placeholder = "Enter observations... (Syntax: **bold** | _italic_ | __underline__ | ==highlight==)",
      style = sprintf("
        display: none;
        width: 100%%;
        box-sizing: border-box;
        min-height: 120px;
        resize: vertical;
        padding: 10px;
        font-family: Consolas, monospace;
        color: %s;
        background-color: #2b2b2b;
        border: 1px solid %s;
        border-radius: 4px;
      ", planitLightGrey, planitGrey),
      initial_text
    ),
    
    # Rendered Markdown Preview Pane (Visible by default)
    htmltools::tags$div(
      id = paste0(chart_id, "_preview"),
      style = sprintf("
        display: block;
        width: 100%%;
        box-sizing: border-box;
        min-height: 120px;
        padding: 10px;
        font-family: 'Prompt', sans-serif;
        color: %s;
        background-color: #2b2b2b;
        border: 1px solid %s;
        border-radius: 4px;
        overflow-y: auto;
        white-space: pre-wrap;
      ", planitLightGrey, planitGrey)
    ),
    
    # Controls Footer
    htmltools::tags$div(
      style = "margin-top: 8px; display: flex; justify-content: space-between; align-items: center; width: 100%; box-sizing: border-box;",
      
      htmltools::tags$span(
        id = paste0(chart_id, "_status"),
        style = sprintf("color: %s; font-weight: bold; font-size: 11px;", planitLightGrey),
        "Draft"
      ),
      
      htmltools::tags$div(
        style = "text-align: right;",
        htmltools::tags$button(
          "💾 Save Observations File",
          id = paste0(chart_id, "_save_js"),
          style = "
            background-color: #28a745;
            color: #ffffff;
            border: none;
            border-radius: 4px;
            padding: 6px 14px;
            font-weight: bold;
            cursor: pointer;
          "
        ),
        htmltools::tags$small(
          style = sprintf("display: block; margin-top: 4px; color: %s; font-size: 10px;", planitLightGrey),
          "💡 Save in the same folder as your HTML report."
        )
      )
    ),
    
    htmltools::tags$script(
      htmltools::HTML(sprintf("
(function() {

  const CHART_ID  = '%s';
  const REPORT_ID = '%s';

  const JS_FILENAME        = (REPORT_ID || 'performance_report') + '_observations.js';
  const STORAGE_KEY        = REPORT_ID + '_' + CHART_ID + '_comment';
  const STORAGE_HEIGHT_KEY = REPORT_ID + '_' + CHART_ID + '_height';

  const textarea  = document.getElementById(CHART_ID + '_comment');
  const preview   = document.getElementById(CHART_ID + '_preview');
  const toggleBtn = document.getElementById(CHART_ID + '_toggle_view');
  const status    = document.getElementById(CHART_ID + '_status');
  const saveBtn   = document.getElementById(CHART_ID + '_save_js');

  if (!textarea) return;

  let isPreview = true;

  function parseMarkdown(text) {
    if (!text) return '';
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\\*\\*(.*?)\\*\\*/g, '<strong>$1</strong>')
      .replace(/__(.*?)__/g, '<u>$1</u>')
      .replace(/_(.*?)_/g, '<em>$1</em>')
      .replace(/\\*(.*?)\\*/g, '<em>$1</em>')
      .replace(/==OVERALL PASSED==/g,
         '<mark class=\"sla-pass\">OVERALL PASSED</mark>')
      .replace(/==OVERALL FAILED==/g,
               '<mark class=\"sla-fail\">OVERALL FAILED</mark>')
      .replace(/==(.*?)==/g,
               '<mark class=\"sla-generic\">$1</mark>');

  }

  function updatePreview() {
    preview.innerHTML = parseMarkdown(textarea.value);
  }

  toggleBtn.addEventListener('click', function() {
    isPreview = !isPreview;
    if (isPreview) {
      updatePreview();
      textarea.style.display = 'none';
      preview.style.display = 'block';
      preview.style.height = textarea.style.height || '120px';
      toggleBtn.innerHTML = '✏️ Edit';
    } else {
      preview.style.display = 'none';
      textarea.style.display = 'block';
      toggleBtn.innerHTML = '👁️ Preview';
    }
  });

  const savedHeight = localStorage.getItem(STORAGE_HEIGHT_KEY);
  if (savedHeight) {
    textarea.style.height = savedHeight;
    preview.style.height = savedHeight;
  }

  function loadSidecarJS() {
    const script = document.createElement('script');
    script.src = './' + JS_FILENAME + '?v=' + new Date().getTime();

    script.onload = function() {
      if (window.REPORT_OBSERVATIONS && window.REPORT_OBSERVATIONS[CHART_ID] !== undefined) {
        textarea.value = window.REPORT_OBSERVATIONS[CHART_ID];
        localStorage.setItem(STORAGE_KEY, window.REPORT_OBSERVATIONS[CHART_ID]);
        status.innerHTML = '✓ Observations Loaded';
      } else {
        const localVal = localStorage.getItem(STORAGE_KEY);
        if (localVal !== null) textarea.value = localVal;
      }
      updatePreview();
    };

    script.onerror = function() {
      const localVal = localStorage.getItem(STORAGE_KEY);
      if (localVal !== null) textarea.value = localVal;
      updatePreview();
    };

    document.head.appendChild(script);
  }

  loadSidecarJS();

  new ResizeObserver(function() {
    localStorage.setItem(STORAGE_HEIGHT_KEY, textarea.offsetHeight + 'px');
  }).observe(textarea);

  textarea.addEventListener('input', function() {
    localStorage.setItem(STORAGE_KEY, textarea.value);
    status.innerHTML = '✓ Draft Auto-Saved';
  });

  saveBtn.addEventListener('click', async function() {
    const payload = {};
    document.querySelectorAll('textarea[id$=\"_comment\"]').forEach(function(ta) {
      const id = ta.id.replace('_comment', '');
      payload[id] = ta.value;
    });

    const fileContent = 'window.REPORT_OBSERVATIONS = ' + JSON.stringify(payload, null, 2) + ';';

    if ('showSaveFilePicker' in window) {
      try {
        const handle = await window.showSaveFilePicker({
          suggestedName: JS_FILENAME,
          id: 'report_observations_folder',
          types: [{
            description: 'JavaScript Sidecar File',
            accept: {'text/javascript': ['.js']}
          }]
        });

        const writable = await handle.createWritable();
        await writable.write(fileContent);
        await writable.close();

        status.innerHTML = '💾 Saved! Keep beside HTML file.';
      } catch (err) {
        if (err.name !== 'AbortError') {
          console.error('Save failed:', err);
          alert('Save failed: ' + err.message);
        }
      }
    } else {
      const blob = new Blob([fileContent], { type: 'text/javascript;charset=utf-8' });
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = JS_FILENAME;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      status.innerHTML = '💾 Downloaded! Keep beside HTML file.';
    }
  });

})();
", chart_id, report_id))
    )
  )
}