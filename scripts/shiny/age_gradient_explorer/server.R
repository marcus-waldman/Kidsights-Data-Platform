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
  # Regression Coefficient Table
  # ============================================================================

  output$coefficient_table <- DT::renderDataTable({
    req(input$coef_table_mode)

    # Select appropriate coefficient table based on toggle
    if (input$coef_table_mode == "full") {
      coef_data <- coef_table_full
    } else {
      coef_data <- coef_table_no_influence
    }

    # Determine number of columns (Item + Pooled + studies)
    n_cols <- ncol(coef_data)

    DT::datatable(
      coef_data,
      options = list(
        pageLength = 25,
        scrollX = TRUE
      ),
      rownames = FALSE
    ) %>%
      DT::formatRound(columns = 2:n_cols, digits = 4) %>%
      DT::formatStyle(
        columns = 2:n_cols,
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
    data <- calibration_data %>%
      dplyr::filter(study %in% input$studies_selected) %>%
      dplyr::select(study, id, years, response = !!sym(input$item_selected)) %>%
      dplyr::filter(!is.na(response))

    # Exclude influence points if toggle is checked
    if (input$exclude_influence_points) {
      req(input$influence_threshold)  # Require threshold selection

      # Get influence point IDs from precomputed models
      item_models <- precomputed_models[[input$item_selected]]

      if (!is.null(item_models)) {
        # Collect influential observation IDs from all selected studies
        influential_ids <- c()

        # Determine which influence_data field to use based on threshold
        influence_field <- paste0("influence_data_", input$influence_threshold, "pct")

        for (study_name in input$studies_selected) {
          study_models <- item_models$study_specific[[study_name]]
          if (!is.null(study_models) && !is.null(study_models$full[[influence_field]])) {
            study_influential <- study_models$full[[influence_field]]
            if (nrow(study_influential) > 0 && "id" %in% names(calibration_data)) {
              # Get IDs from original calibration data that match influential observations
              study_cal_data <- calibration_data %>%
                dplyr::filter(study == study_name) %>%
                dplyr::select(id, years, response_item = !!sym(input$item_selected)) %>%
                dplyr::filter(!is.na(response_item))

              # Match influential observations by study + years + response
              for (i in seq_len(nrow(study_influential))) {
                matching_rows <- study_cal_data %>%
                  dplyr::filter(
                    abs(years - study_influential$years[i]) < 0.01,
                    response_item == study_influential$response[i]
                  )
                if (nrow(matching_rows) > 0) {
                  influential_ids <- c(influential_ids, matching_rows$id)
                }
              }
            }
          }
        }

        # Remove influential IDs from filtered data
        if (length(influential_ids) > 0) {
          data <- data %>% dplyr::filter(!(id %in% influential_ids))
        }
      }
    }

    # Remove id column before returning
    data %>% dplyr::select(-id)
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

    # Use if statements instead of %||% (not in base R)
    desc <- if (!is.null(item$content$description)) item$content$description else "No description available"
    instr <- if (!is.null(item$instruments)) item$instruments else NULL
    exp_cat <- if (!is.null(item$psychometric$expected_categories)) item$psychometric$expected_categories else NULL

    list(
      description = desc,
      instruments = instr,
      expected_categories = exp_cat,
      full_entry = item
    )
  })

  # ============================================================================
  # Item Quality Flags
  # ============================================================================

  item_flags <- reactive({
    req(input$item_selected)

    quality_flags %>%
      dplyr::filter(item_id == input$item_selected)
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
      dplyr::filter(study %in% input$studies_selected)

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
  # Age Gradient Plot (Logistic/Ordered Logit Smoothing - Using Precomputed Models)
  # ============================================================================

  output$age_gradient_plot <- renderPlot({
    req(input$item_selected)
    req(length(input$studies_selected) > 0)

    # Retrieve precomputed model results for this item
    item_models <- precomputed_models[[input$item_selected]]

    if (is.null(item_models)) {
      # No precomputed model (insufficient data)
      p <- ggplot() +
        xlim(0, 6) +
        ylim(0, 1) +
        annotate(
          "text",
          x = 3, y = 0.5,
          label = "Insufficient data to fit model",
          color = "gray50",
          size = 6
        ) +
        labs(
          title = paste0("Age-Response Gradient: ", input$item_selected),
          x = "Age (years)",
          y = "Predicted Probability"
        ) +
        theme_minimal(base_size = 14)

      return(p)
    }

    # Extract item characteristics
    is_binary <- item_models$is_binary
    n_categories <- item_models$n_categories

    # ========================================================================
    # Retrieve Precomputed Predictions and Influence Data
    # ========================================================================

    if (input$display_mode == "pooled") {
      # ------------------------------------------------------------------
      # POOLED MODE: Use precomputed pooled model
      # ------------------------------------------------------------------

      # Select model based on exclude_influence_points toggle
      if (input$exclude_influence_points) {
        req(input$influence_threshold)
        # Use reduced model at selected threshold
        threshold_field <- paste0("reduced_", input$influence_threshold, "pct")
        pooled_results <- item_models[[threshold_field]]
        # Influence data comes from full model at selected threshold
        influence_field <- paste0("influence_data_", input$influence_threshold, "pct")
        influence_data <- item_models$pooled[[influence_field]]
      } else {
        pooled_results <- item_models$pooled
        # Show influence data at selected threshold
        req(input$influence_threshold)
        influence_field <- paste0("influence_data_", input$influence_threshold, "pct")
        influence_data <- pooled_results[[influence_field]]
      }

      if (!pooled_results$model_converged || nrow(pooled_results$predictions) == 0) {
        # Model failed to converge
        p <- ggplot() +
          xlim(0, 6) +
          ylim(0, 1) +
          annotate(
            "text",
            x = 3, y = 0.5,
            label = "Model fitting failed (convergence issue)",
            color = "gray50",
            size = 6
          ) +
          labs(
            title = paste0("Age-Response Gradient: ", input$item_selected),
            x = "Age (years)",
            y = "Predicted Probability"
          ) +
          theme_minimal(base_size = 14)

        return(p)
      }

      pred_data <- pooled_results$predictions
      pred_data$study <- "Pooled"

    } else {
      # ------------------------------------------------------------------
      # STUDY-SPECIFIC MODE: Use precomputed study-specific models
      # ------------------------------------------------------------------

      pred_data_list <- list()
      influence_data_list <- list()

      for (study_name in input$studies_selected) {
        study_models <- item_models$study_specific[[study_name]]

        if (!is.null(study_models)) {
          req(input$influence_threshold)
          influence_field <- paste0("influence_data_", input$influence_threshold, "pct")

          # Select model based on exclude_influence_points toggle
          if (input$exclude_influence_points) {
            # Use reduced model at selected threshold
            threshold_field <- paste0("reduced_", input$influence_threshold, "pct")
            study_results <- study_models[[threshold_field]]
            # Influence data comes from full model at selected threshold
            study_influence <- study_models$full[[influence_field]]
          } else {
            study_results <- study_models$full
            study_influence <- study_results[[influence_field]]
          }

          if (study_results$model_converged && nrow(study_results$predictions) > 0) {
            pred_data_list[[study_name]] <- study_results$predictions
            influence_data_list[[study_name]] <- study_influence
          }
        }
      }

      if (length(pred_data_list) == 0) {
        # No models converged for selected studies
        p <- ggplot() +
          xlim(0, 6) +
          ylim(0, 1) +
          annotate(
            "text",
            x = 3, y = 0.5,
            label = "Insufficient data for selected studies",
            color = "gray50",
            size = 6
          ) +
          labs(
            title = paste0("Age-Response Gradient: ", input$item_selected),
            x = "Age (years)",
            y = "Predicted Probability"
          ) +
          theme_minimal(base_size = 14)

        return(p)
      }

      pred_data <- do.call(rbind, pred_data_list)
      influence_data <- do.call(rbind, influence_data_list)
    }

    # ========================================================================
    # Create Plot
    # ========================================================================

    # Base plot: Age on X-axis
    # Determine y-axis limits and label based on item type
    if (is_binary) {
      y_limits <- c(0, 1)
      y_label <- "Predicted Probability"
    } else {
      # For ordinal items, use response range
      response_range <- range(filtered_data()$response, na.rm = TRUE)
      y_limits <- c(min(0, response_range[1]), max(response_range[2], response_range[1] + 1))
      y_label <- "Predicted Response"
    }

    p <- ggplot() +
      xlim(0, 6) +
      ylim(y_limits[1], y_limits[2]) +
      labs(
        title = paste0("Age-Response Gradient: ", input$item_selected),
        subtitle = item_metadata()$description,
        x = "Age (years)",
        y = y_label
      ) +
      theme_minimal(base_size = 14) +
      theme(
        plot.title = element_text(face = "bold", size = 16),
        plot.subtitle = element_text(size = 12, color = "gray40"),
        legend.position = "right"
      )

    # Add smoothing curves
    if (input$display_mode == "pooled") {
      # Pooled mode: single black line for both binary and ordinal
      p <- p +
        geom_line(
          data = pred_data,
          aes(x = years, y = prob),
          color = "black",
          size = 1.5
        )
    } else {
      # Study-specific mode: colored by study
      p <- p +
        geom_line(
          data = pred_data,
          aes(x = years, y = prob, color = study),
          size = 1.5
        ) +
        scale_color_manual(values = study_colors, name = "Study")
    }

    # Add influence points if requested
    if (input$show_influence_points && nrow(influence_data) > 0) {
      # Use original response scale (no scaling needed)
      influence_data$prob_scaled <- influence_data$response

      p <- p +
        geom_point(
          data = influence_data,
          aes(x = years, y = prob_scaled, color = study),
          shape = 124,  # Vertical dash
          size = 3,
          alpha = 0.7
        )
    }

    # Show message if no data
    if (nrow(pred_data) == 0) {
      p <- p +
        annotate(
          "text",
          x = 3, y = 0.5,
          label = "Insufficient data to fit model",
          color = "gray50",
          size = 6
        )
    }

    # ========================================================================
    # Add Horizontal Boxplots Below (Age Distribution by Study)
    # ========================================================================

    data_for_boxplot <- filtered_data()

    p_boxplot <- ggplot(data_for_boxplot, aes(x = years, y = study, fill = study)) +
      geom_boxplot(alpha = 0.7) +
      scale_fill_manual(values = study_colors) +
      xlim(0, 6) +
      labs(
        x = NULL,  # Remove x-axis label (shared with main plot)
        y = "Study"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        legend.position = "none",  # Hide legend (redundant with main plot)
        axis.title.y = element_text(size = 10),
        panel.grid.major.y = element_blank()
      )

    # Combine plots vertically (main plot on top, boxplot on bottom)
    # Heights: 3 parts for main plot, 1 part for boxplot
    combined_plot <- p / p_boxplot + patchwork::plot_layout(heights = c(3, 1))

    combined_plot
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

  # ============================================================================
  # Database Connection Management
  # ============================================================================

  # Test database connection
  observeEvent(input$test_db_connection, {
    result <- test_db_connection()

    if (result$success) {
      showNotification(result$message, type = "message", duration = 3)
    } else {
      showNotification(result$message, type = "error", duration = 5)
    }
  })

  # Close all database connections
  observeEvent(input$close_all_connections, {
    result <- close_all_db_connections()

    if (result$success) {
      showNotification(result$message, type = "message", duration = 3)
    } else {
      showNotification(result$message, type = "warning", duration = 5)
    }
  })

  # Database status display
  output$db_status <- renderText({
    # Trigger re-render when buttons are clicked
    input$test_db_connection
    input$close_all_connections

    result <- test_db_connection()

    if (result$success) {
      paste0("Status: ", result$message)
    } else {
      paste0("Status: Disconnected")
    }
  })

  # ============================================================================
  # Review Notes System
  # ============================================================================

  # Load note when item changes
  observeEvent(input$item_selected, {
    req(input$item_selected)

    item_note_data <- get_item_note(input$item_selected, notes_path)

    # Update text area with current note
    updateTextAreaInput(
      session,
      "item_note",
      value = item_note_data$current$note
    )

    # Reset history visibility to hidden
    updateCheckboxInput(session, "show_history", value = FALSE)
  })

  # Save note when button clicked
  observeEvent(input$save_note, {
    req(input$item_selected)

    success <- save_item_note(
      item_id = input$item_selected,
      note_text = input$item_note,
      reviewer = Sys.info()["user"],
      notes_path = notes_path
    )

    if (success) {
      showNotification(
        "Note saved successfully!",
        type = "message",
        duration = 2
      )
    } else {
      showNotification(
        "Failed to save note (empty note?)",
        type = "warning",
        duration = 3
      )
    }
  })

  # Display last saved timestamp
  output$last_saved_text <- renderText({
    req(input$item_selected)

    # Trigger re-render when save button is clicked
    input$save_note

    item_note_data <- get_item_note(input$item_selected, notes_path)

    if (!is.null(item_note_data$current) &&
        nchar(item_note_data$current$timestamp) > 0) {
      sprintf("Last saved: %s", substr(item_note_data$current$timestamp, 1, 16))
    } else {
      "No notes saved yet"
    }
  })

  # Check if item has history (for conditional panel)
  output$has_history <- reactive({
    req(input$item_selected)

    # Trigger re-render when save button is clicked
    input$save_note

    item_note_data <- get_item_note(input$item_selected, notes_path)
    length(item_note_data$history) > 1  # More than just current
  })
  outputOptions(output, "has_history", suspendWhenHidden = FALSE)

  # Display note history
  output$note_history <- renderUI({
    req(input$item_selected)

    # Trigger re-render when save button is clicked
    input$save_note

    history_df <- get_history_summary(input$item_selected, notes_path, max_entries = 5)

    if (nrow(history_df) <= 1) {
      # Only current note exists, no previous versions
      return(NULL)
    }

    # Skip the most recent entry (that's the current note)
    history_df <- history_df[-1, , drop = FALSE]

    if (nrow(history_df) == 0) {
      return(NULL)
    }

    # Create UI elements for each history entry
    history_items <- lapply(seq_len(nrow(history_df)), function(i) {
      row <- history_df[i, ]

      # Truncate note text for display
      preview <- row$note_text
      if (nchar(preview) > 50) {
        preview <- paste0(substr(preview, 1, 47), "...")
      }

      div(
        style = "margin-bottom: 8px; padding: 5px; background-color: #f5f5f5; border-radius: 3px;",
        div(
          style = "font-size: 11px; color: #666;",
          HTML(sprintf("<b>📝 %s</b>", row$display))
        ),
        div(
          style = "font-size: 10px; color: #999; font-style: italic; margin-top: 2px;",
          sprintf('"%s"', preview)
        ),
        actionButton(
          paste0("load_history_", row$index),
          "Load ↑",
          style = "font-size: 10px; padding: 2px 8px; margin-top: 3px;",
          onclick = sprintf("Shiny.setInputValue('load_note_version', %d, {priority: 'event'})", row$index)
        )
      )
    })

    do.call(tagList, history_items)
  })

  # Load previous version into editor
  observeEvent(input$load_note_version, {
    req(input$item_selected)
    req(input$load_note_version)

    item_note_data <- get_item_note(input$item_selected, notes_path)

    if (input$load_note_version <= length(item_note_data$history)) {
      old_note <- item_note_data$history[[input$load_note_version]]

      updateTextAreaInput(
        session,
        "item_note",
        value = old_note$note
      )

      showNotification(
        "Previous version loaded. Click 'Save Note' to create a new version.",
        type = "message",
        duration = 4
      )
    }
  })
}
