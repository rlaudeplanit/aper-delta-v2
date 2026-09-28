# ============================================================
#  GROUPED RESPONSE TIME CHART ENGINE (UPGRADED)
#  - metric = "avg" or "p90"
#  - Always uses raw_data$elapsed
#  - Groups by csv_filename
# ============================================================
library(Polychrome)
library(ggplot2)
library(plotly)
library(dplyr)
library(htmltools)
library(purrr)

build_grouped_rt_chart <- function(
    df,
    metric = "avg",
    title  = NULL
) {
  # ============================================================
  # METRIC SETUP
  # ============================================================
  if (metric == "avg") {
    agg_fun      <- function(x) mean(x, na.rm = TRUE)
    metric_title <- "Average Response Time"
  } else if (metric == "p90") {
    agg_fun      <- function(x) quantile(x, 0.90, na.rm = TRUE)
    metric_title <- "90th Percentile Response Time"
  } else {
    stop("Unsupported metric. Use 'avg' or 'p90'.")
  }
  
  if (!is.null(title)) metric_title <- title
  
  unique_files <- sort(unique(df$app_name))
  
  # Calculate global left margin once — based on all labels across all files
  max_label_chars_global <- max(nchar(as.character(df$label)), na.rm = TRUE)
  global_left_margin     <- max(80, max_label_chars_global * 7)
  
  # Consistent color palette across all files — based on all run_ids globally
  unique_runs <- sort(unique(df$run_id))
  set.seed(42)
  run_colors <- setNames(choose_palette(length(unique_runs)), unique_runs)
  
  plots <- map(unique_files, function(f) {
    file_data <- df %>% filter(app_name == f)
    
    # ============================================================
    # COMPUTE GROUPED METRIC
    # ============================================================
    grouped_data <- file_data %>%
      group_by(run_id, label, test_name) %>%
      summarise(value = agg_fun(elapsed), .groups = "drop")
    
    if (nrow(grouped_data) == 0) {
      return(
        htmltools::tags$div(
          style = "width: 100%; margin-bottom: 40px;",
          htmltools::tags$div(
            style = "width: 100%; border: 1px solid #e3e3e3; padding: 20px; color: #999; font-family: Consolas; font-size: 12px;",
            paste0("No data available for: ", f)
          )
        )
      )
    }
    
    # ============================================================
    # SUBTITLE + LABEL OFFSETS
    # ============================================================
    subtitle_text <- build_run_testname_subtitle(grouped_data)
    grouped_data  <- compute_label_x_single(grouped_data, "value")
    
    # ============================================================
    # DYNAMIC HEIGHT
    # ============================================================
    num_bars       <- nrow(grouped_data)
    dynamic_height <- max(400, (num_bars * 10) + 150)
    
    # ============================================================
    # BUILD GGPLOT
    # ============================================================
    p <- ggplot(
      grouped_data,
      aes(
        x    = label,
        y    = value,
        fill = run_id,
        text = paste0(
          "Run: ",            run_id,
          "\nTransaction: ",  label,
          "\nApplication: ",  f,
          "\n",               metric_title, ": ", round(value, 0), " ms"
        )
      )
    ) +
      geom_bar(
        stat     = "identity",
        position = position_dodge(0.9),
        width    = 0.7,
        color    = "#222222",
        linewidth = 0.1
      ) +
      geom_text(
        aes(
          y     = label_x,
          label = paste0(round(value, 0), " ms"),
          group = run_id
        ),
        position = position_dodge(width = 0.8),
        hjust    = 0,
        size     = 2.5,
        fontface = "bold",
        color    = "black"
      ) +
      scale_fill_manual(values = run_colors) +
      labs(
        x    = "Transaction Label",
        y    = paste(metric_title, "(ms)"),
        fill = "Run ID"
      ) +
      coord_flip() +
      theme_minimal() +
      theme(
        plot.title      = element_blank(),
        legend.position = "right",
        axis.text.y     = element_text(size = 10, margin = margin(r = 10), family = "Consolas"),
        axis.text.x     = element_text(family = "Consolas", size = 10),
        axis.title.x    = element_text(family = "Consolas", size = 12, color = "#333", margin = margin(t = 10)),
        axis.title.y    = element_text(family = "Consolas", size = 12, color = "#333", margin = margin(r = 20)),
        plot.margin     = margin(10, 40, 10, 10)
      )
    
    # ============================================================
    # CONVERT TO PLOTLY
    # ============================================================
    pl <- ggplotly(p, tooltip = "text", height = dynamic_height)
    
    # ============================================================
    # LAYOUT CONFIG
    # ============================================================
    real_max <- max(grouped_data$value, na.rm = TRUE)
    
    layout_config <- list(
      showlegend = TRUE,
      margin     = list(l = global_left_margin, r = 40, b = 80, t = 80),
      dragmode   = FALSE,
      hoverlabel = list(bgcolor = "white"),
      height     = dynamic_height,
      width      = NULL,
      title      = list(
        text    = paste0(
          "<b>", metric_title, " Comparison:</b> ", tools::file_path_sans_ext(f),
          "<br><sup>", subtitle_text, "</sup>"
        ),
        x       = 0,
        xanchor = "left",
        font    = list(size = 14, family = "Consolas", color = "#333")
      ),
      xaxis = list(
        fixedrange = TRUE,
        range      = c(0, real_max * 1.10)
      ),
      yaxis = list(
        fixedrange = TRUE,
        automargin = TRUE
      )
    )
    
    for (i in 1:10) {
      x_name <- if (i == 1) "xaxis" else paste0("xaxis", i)
      y_name <- if (i == 1) "yaxis" else paste0("yaxis", i)
      
      if (i == 1) {
        layout_config[[x_name]]$fixedrange <- TRUE
        layout_config[[y_name]]$fixedrange <- TRUE
        layout_config[[y_name]]$automargin <- TRUE
      } else {
        layout_config[[x_name]] <- list(fixedrange = TRUE)
        layout_config[[y_name]] <- list(fixedrange = TRUE, automargin = TRUE)
      }
    }
    
    pl <- do.call(layout, c(list(pl), layout_config)) %>%
      plotly::config(
        responsive     = TRUE,
        displayModeBar = TRUE,
        toImageButtonOptions = list(
          format   = "png",
          filename = paste0("Grouped_", gsub(" ", "_", metric_title), "_", f, "_", Sys.Date()),
          height   = dynamic_height,
          width    = 1400
        ),
        modeBarButtonsToRemove = list(
          "zoom2d", "pan2d", "select2d", "lasso2d", "zoomIn2d", "zoomOut2d",
          "autoScale2d", "resetScale2d", "hoverClosestCartesian", "hoverCompareCartesian"
        )
      )
    
    htmltools::tags$div(
      style = "width: 100%; margin-bottom: 40px;",
      htmltools::tags$div(
        style = "width: 100%; overflow: hidden; border: 1px solid #e3e3e3; padding: 10px;",
        pl
      ),
      render_observation_panel(
        chart_id = paste0(
          "chart_groupedRT_",
          metric,
          "_",
          gsub("[^A-Za-z0-9_]", "_", f)
        )
      )
    )
  })
  
  # ============================================================
  # RETURN STACKED TAGLIST
  # ============================================================

  htmltools::tagList(
    Filter(Negate(is.null), plots)
  )

}