# server.R
# Server logic

function(input, output, session) {

  # ============================================================================
  # Study Selection Observers
  # ============================================================================

  # Select All button
  observeEvent(input$select_all_studies, {
    updateCheckboxGroupInput(
      session,
      "studies_selected",
      selected = c("NE20", "NE22", "NE25", "NSCH21", "NSCH22", "USA24")
    )
  })

  # Deselect All button
  observeEvent(input$deselect_all_studies, {
    updateCheckboxGroupInput(
      session,
      "studies_selected",
      selected = character(0)
    )
  })

  # ============================================================================
  # Correlation Table
  # ============================================================================

  output$correlation_table <- DT::renderDataTable({
    DT::datatable(
      corr_matrix,
      options = list(
        pageLength = 25,
        scrollX = TRUE
      ),
      rownames = FALSE
    ) %>%
      DT::formatRound(columns = 2:6, digits = 3) %>%
      DT::formatStyle(
        columns = 2:6,
        color = DT::styleInterval(0, c('red', 'black'))
      )
  })

  # ============================================================================
  # Reactive Data Filtering
  # ============================================================================

  filtered_data <- reactive({
    req(input$item_selected)
    req(length(input$studies_selected) > 0)

    # Extract item response data
    calibration_data %>%
      filter(study %in% input$studies_selected) %>%
      select(study, years, response = !!input$item_selected) %>%
      filter(!is.na(response))
  })

  # ============================================================================
  # Item Metadata
  # ============================================================================

  item_metadata <- reactive({
    req(input$item_selected)

    item <- item_metadata_lookup[[input$item_selected]]

    if (is.null(item)) {
      return(list(
        description = "No description available",
        instruments = NULL,
        expected_categories = NULL
      ))
    }

    list(
      description = item$content$description %||% "No description available",
      instruments = item$instruments %||% NULL,
      expected_categories = item$psychometric$expected_categories %||% NULL,
      full_entry = item
    )
  })

  # ============================================================================
  # Item Quality Flags
  # ============================================================================

  item_flags <- reactive({
    req(input$item_selected)

    quality_flags %>%
      filter(item_id == input$item_selected)
  })

  # ============================================================================
  # Available Studies (Dynamic Filtering)
  # ============================================================================

  available_studies <- reactive({
    req(input$item_selected)

    calibration_data %>%
      dplyr::select(study, !!sym(input$item_selected)) %>%
      dplyr::filter(!is.na(!!sym(input$item_selected))) %>%
      dplyr::distinct(study) %>%
      dplyr::pull(study)
  })

  # Update study checkboxes when item changes
  observeEvent(input$item_selected, {
    studies_with_data <- available_studies()

    # Update choices to only studies with data, auto-select all
    updateCheckboxGroupInput(
      session,
      "studies_selected",
      choices = studies_with_data,
      selected = studies_with_data
    )
  })

  # ============================================================================
  # Summary Statistics
  # ============================================================================

  output$summary_stats <- renderText({
    req(nrow(filtered_data()) > 0)

    data <- filtered_data()

    n_obs <- nrow(data)
    age_min <- min(data$years, na.rm = TRUE)
    age_max <- max(data$years, na.rm = TRUE)

    # Calculate % missing from full dataset
    full_data <- calibration_data %>%
      filter(study %in% input$studies_selected)

    n_total <- nrow(full_data)
    n_missing <- sum(is.na(full_data[[input$item_selected]]))
    pct_missing <- (n_missing / n_total) * 100

    paste0(
      "n observations: ", n_obs, "\n",
      "Age range: ", round(age_min, 2), " - ", round(age_max, 2), " years\n",
      "% missing: ", round(pct_missing, 1), "%"
    )
  })

  # ============================================================================
  # Item Description
  # ============================================================================

  output$item_description <- renderUI({
    req(input$item_selected)

    description <- item_metadata()$description

    HTML(paste0(
      "<h4>", input$item_selected, "</h4>",
      "<p><em>", description, "</em></p>"
    ))
  })

  # ============================================================================
  # Quality Flag Warning
  # ============================================================================

  output$quality_flag_warning <- renderUI({
    flags <- item_flags()

    if (nrow(flags) == 0) {
      return(NULL)
    }

    flag_html <- sapply(1:nrow(flags), function(i) {
      flag <- flags[i, ]

      color <- if (flag$flag_severity == "ERROR") "#d9534f" else "#f0ad4e"

      paste0(
        "<div style='background-color: ", color, "; color: white; padding: 10px; margin: 5px 0; border-radius: 5px;'>",
        "<strong>", flag$flag_type, " (", flag$study, ")</strong>: ",
        flag$description,
        "</div>"
      )
    })

    HTML(paste(flag_html, collapse = ""))
  })

  # ============================================================================
  # Age Gradient Plot
  # ============================================================================

  output$age_gradient_plot <- renderPlot({
    req(nrow(filtered_data()) > 0)

    data <- filtered_data()

    # Base plot (empty)
    # X-axis = response levels (discrete), Y-axis = age (continuous)
    p <- ggplot() +
      ylim(0, 6) +  # Age range: 0-6 years
      labs(
        title = paste0("Age-Response Distribution: ", input$item_selected),
        subtitle = item_metadata()$description,
        x = "Item Response",
        y = "Age (years)"
      ) +
      theme_minimal(base_size = 14) +
      theme(
        plot.title = element_text(face = "bold", size = 16),
        plot.subtitle = element_text(size = 12, color = "gray40")
      )

    # Add box plots if requested
    if (input$show_boxplots) {
      if (input$color_by_study && length(input$studies_selected) > 1) {
        # Color by study - use interaction for proper grouping
        p <- p +
          geom_boxplot(
            data = data,
            aes(x = factor(response), y = years,
                group = interaction(response, study),
                fill = study),
            width = 0.6,
            alpha = 0.7,
            outlier.shape = 16,
            outlier.size = 2,
            position = position_dodge(width = 0.8)
          ) +
          scale_fill_manual(values = study_colors, name = "Study")
      } else {
        # Single color
        p <- p +
          geom_boxplot(
            data = data,
            aes(x = factor(response), y = years),
            width = 0.6,
            alpha = 0.7,
            fill = "gray70",
            outlier.shape = 16,
            outlier.size = 2
          )
      }
    }

    # Show message if no studies selected
    if (length(input$studies_selected) == 0) {
      p <- p +
        annotate(
          "text",
          x = 0.5, y = 3,
          label = "Select at least one study",
          color = "gray50",
          size = 6
        )
    }

    p
  })

  # ============================================================================
  # Codebook JSON Display
  # ============================================================================

  output$codebook_json <- renderText({
    req(input$item_selected)

    item <- item_metadata()$full_entry

    if (is.null(item)) {
      return("No codebook entry found for this item.")
    }

    # Convert to pretty JSON
    jsonlite::toJSON(item, pretty = TRUE, auto_unbox = TRUE)
  })
}
