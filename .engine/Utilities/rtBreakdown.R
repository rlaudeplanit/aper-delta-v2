library(plotly)
library(dplyr)
library(ggplot2)
library(stringr)

render_individual_rt_chart <- function(raw_data, active_file) {

  # 1. Filter data
  file_data <- raw_data %>%
    filter(csv_filename == active_file) %>%
    group_by(run_id, executionGroup, label) %>%
    summarise(avg_rt = mean(elapsed, na.rm = TRUE), .groups = "drop")
  
  if (nrow(file_data) == 0) {
    return(htmltools::div(
      style = "padding:20px; color:#888;",
      paste("No data available for:", active_file)
    ))
  }
  
  # 2. Basic plot (no helpers, no palettes)
  p <- ggplot(
    file_data,
    aes(
      y = interaction(executionGroup, run_id, sep = " | "),
      x = avg_rt,
      fill = label,
      text = paste0(
        "Scenario: ", executionGroup,
        "\nRun ID: ", run_id,
        "\nTransaction: ", label,
        "\nAvg RT: ", round(avg_rt, 0), "ms"
      )
    )
  ) +
    geom_col() +
    theme_minimal()
  
  # 3. Convert to plotly
  plt <- ggplotly(p, tooltip = "text")
  
  return(plt)
}

build_avg_rt_breakdown <- function(shared_data) {
  # 1. Build the base ggplot layout mapping the SharedData object
  gg <- ggplot(shared_data, aes(x = elapsed, y = axis_string, fill = label)) +
    geom_col(position = "stack", width = 0.6) +
    scale_fill_viridis_d(option = "mako", name = "Transactions") +
    labs(
      title = "Response Times Breakdown",
      x     = "Total Cumulative Average Response Time (ms)",
      y     = "Scenario | Run ID"
    ) +
    facet_grid(testName ~ ., scales = "free_y", space = "free_y") +
    theme_minimal(base_size = 11) +
    theme(
      strip.text.y    = element_text(angle = 0, hjust = 0, face = "bold"),
      legend.position = "bottom",
      panel.grid.major.y = element_blank()
    )
  
  # 2. Convert to an interactive plotly canvas element
  p <- ggplotly(gg, tooltip = c("x", "fill")) %>% 
    layout(
      legend = list(orientation = "h", x = 0, y = -0.15),
      margin = list(l = 50, r = 50, b = 100, t = 50)
    )
  
  return(p)
}
