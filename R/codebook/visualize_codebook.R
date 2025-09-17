#' Visualization Functions for Codebook
#'
#' Functions for creating plots and visualizations of codebook data

library(ggplot2)
library(plotly)
library(tidyverse)

#' Plot domain distribution
#'
#' @param codebook Codebook object
#' @param hrtl_domain Whether to use HRTL domain classification (default: FALSE)
#' @return ggplot object
#' @examples
#' \dontrun{
#' plot_domain_distribution(codebook)
#' }
plot_domain_distribution <- function(codebook, hrtl_domain = FALSE) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  # Convert to data frame
  df <- items_to_dataframe(codebook, flatten_identifiers = FALSE)

  # Choose domain column
  domain_col <- if (hrtl_domain) "domain_cahmi" else "domain_kidsights"
  plot_title <- if (hrtl_domain) "Item Distribution by CAHMI Domain" else "Item Distribution by Kidsights Domain"

  # Create plot
  p <- df %>%
    filter(!is.na(.data[[domain_col]])) %>%
    count(.data[[domain_col]], name = "n_items") %>%
    ggplot(aes(x = reorder(.data[[domain_col]], n_items), y = n_items)) +
    geom_col(fill = "steelblue", alpha = 0.8) +
    coord_flip() +
    labs(
      title = plot_title,
      x = "Domain",
      y = "Number of Items"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      axis.text = element_text(size = 12)
    )

  return(p)
}

#' Plot study coverage heatmap
#'
#' @param codebook Codebook object
#' @param max_items Maximum number of items to show (default: 50)
#' @return ggplot object
#' @examples
#' \dontrun{
#' plot_study_coverage(codebook)
#' }
plot_study_coverage <- function(codebook, max_items = 50) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  # Get coverage matrix
  coverage_matrix <- get_study_coverage(codebook)

  # Limit items if needed
  if (nrow(coverage_matrix) > max_items) {
    coverage_matrix <- coverage_matrix[1:max_items, ]
    warning("Showing only first ", max_items, " items. Use max_items parameter to adjust.")
  }

  # Convert to long format for ggplot
  coverage_df <- coverage_matrix %>%
    as.data.frame() %>%
    rownames_to_column("item_id") %>%
    pivot_longer(-item_id, names_to = "study", values_to = "present") %>%
    mutate(present = as.logical(present))

  # Create heatmap
  p <- ggplot(coverage_df, aes(x = study, y = item_id, fill = present)) +
    geom_tile(color = "white", size = 0.2) +
    scale_fill_manual(
      values = c("FALSE" = "white", "TRUE" = "steelblue"),
      labels = c("FALSE" = "Absent", "TRUE" = "Present"),
      name = "Item Present"
    ) +
    labs(
      title = "Item Coverage Across Studies",
      x = "Study",
      y = "Item ID"
    ) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      axis.text.y = element_text(size = 8),
      plot.title = element_text(size = 14, face = "bold")
    )

  return(p)
}

#' Plot IRT characteristic curve for an item
#'
#' @param item Single item from codebook
#' @param theta_range Range of theta values (default: c(-4, 4))
#' @param study Study name to use for parameters (default: NULL uses first available)
#' @return plotly object
#' @examples
#' \dontrun{
#' item <- get_item(codebook, "AA102")
#' plot_item_icc(item, study = "NE25")
#' }
plot_item_icc <- function(item, theta_range = c(-4, 4), study = NULL) {

  # Check if item has IRT parameters
  if (is.null(item$psychometric$irt_parameters)) {
    stop("Item does not have IRT parameters")
  }

  irt_params <- item$psychometric$irt_parameters

  # Handle study-specific parameters
  if (is.null(study)) {
    # Use first available study with parameters
    available_studies <- names(irt_params)
    if (length(available_studies) == 0) {
      stop("No IRT parameters available for any study")
    }
    study <- available_studies[1]
    message("Using parameters from study: ", study)
  }

  if (!study %in% names(irt_params)) {
    stop("Study '", study, "' not found in IRT parameters. Available: ",
         paste(names(irt_params), collapse = ", "))
  }

  params <- irt_params[[study]]

  # Check if parameters have actual values
  if (length(params$loadings) == 0 || length(params$thresholds) == 0) {
    stop("Study '", study, "' has empty IRT parameters")
  }

  # Extract parameters (use first loading as slope for compatibility)
  slope <- params$loadings[[1]]
  thresholds <- unlist(params$thresholds)

  if (is.null(slope) || is.null(thresholds)) {
    stop("Missing loading or threshold parameters")
  }

  # Generate theta values
  theta <- seq(theta_range[1], theta_range[2], 0.1)

  # Calculate probabilities (2PL model)
  if (length(thresholds) == 1) {
    # Binary item
    prob <- 1 / (1 + exp(-(slope * (theta - thresholds[1]))))

    # Create data frame
    plot_data <- data.frame(
      theta = theta,
      probability = prob,
      category = "P(θ)"
    )

    # Create plot
    p <- plot_ly(
      data = plot_data,
      x = ~theta,
      y = ~probability,
      type = 'scatter',
      mode = 'lines',
      name = ~category,
      hovertemplate = paste(
        'θ: %{x:.2f}<br>',
        'P(θ): %{y:.3f}<br>',
        '<extra></extra>'
      )
    ) %>%
      layout(
        title = paste("Item Characteristic Curve -", item$lexicons$equate, "(", study, ")"),
        xaxis = list(title = "Ability (θ)"),
        yaxis = list(title = "Probability"),
        hovermode = 'closest'
      )

  } else {
    # Polytomous item (GRM)
    n_categories <- length(thresholds) + 1
    prob_matrix <- matrix(0, nrow = length(theta), ncol = n_categories)

    # Calculate cumulative probabilities
    cum_probs <- matrix(1, nrow = length(theta), ncol = length(thresholds) + 1)
    for (k in 1:length(thresholds)) {
      cum_probs[, k + 1] <- 1 / (1 + exp(-(slope * (theta - thresholds[k]))))
    }

    # Calculate category probabilities
    for (k in 1:n_categories) {
      if (k == 1) {
        prob_matrix[, k] <- 1 - cum_probs[, 2]
      } else if (k == n_categories) {
        prob_matrix[, k] <- cum_probs[, k]
      } else {
        prob_matrix[, k] <- cum_probs[, k] - cum_probs[, k + 1]
      }
    }

    # Create data frame
    plot_data <- data.frame(
      theta = rep(theta, n_categories),
      probability = as.vector(prob_matrix),
      category = rep(paste("Category", 1:n_categories), each = length(theta))
    )

    # Create plot
    p <- plot_ly(
      data = plot_data,
      x = ~theta,
      y = ~probability,
      color = ~category,
      type = 'scatter',
      mode = 'lines',
      hovertemplate = paste(
        'θ: %{x:.2f}<br>',
        'P(θ): %{y:.3f}<br>',
        '<extra></extra>'
      )
    ) %>%
      layout(
        title = paste("Item Characteristic Curves -", item$lexicons$equate, "(", study, ")"),
        xaxis = list(title = "Ability (θ)"),
        yaxis = list(title = "Probability"),
        hovermode = 'closest'
      )
  }

  return(p)
}

#' Plot domain × study crosstab
#'
#' @param codebook Codebook object
#' @param hrtl_domain Whether to use HRTL domain classification (default: FALSE)
#' @return ggplot object
#' @examples
#' \dontrun{
#' plot_domain_study_crosstab(codebook)
#' }
plot_domain_study_crosstab <- function(codebook, hrtl_domain = FALSE) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  # Get crosstab
  crosstab <- get_domain_study_crosstab(codebook, hrtl_domain = hrtl_domain)

  # Convert to long format
  domain_col <- names(crosstab)[1]
  crosstab_long <- crosstab %>%
    pivot_longer(-1, names_to = "study", values_to = "n_items") %>%
    filter(n_items > 0)  # Only show non-zero cells

  # Create plot
  p <- ggplot(crosstab_long, aes(x = study, y = .data[[domain_col]], fill = n_items)) +
    geom_tile(color = "white", size = 0.5) +
    geom_text(aes(label = n_items), color = "white", size = 4, fontface = "bold") +
    scale_fill_gradient(low = "lightblue", high = "darkblue", name = "Items") +
    labs(
      title = "Items by Domain and Study",
      x = "Study",
      y = if (hrtl_domain) "CAHMI Domain" else "Kidsights Domain"
    ) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.title = element_text(size = 14, face = "bold")
    )

  return(p)
}

#' Create summary dashboard plot
#'
#' @param codebook Codebook object
#' @return List of ggplot objects
#' @examples
#' \dontrun{
#' plots <- create_summary_plots(codebook)
#' gridExtra::grid.arrange(grobs = plots, ncol = 2)
#' }
create_summary_plots <- function(codebook) {
  if (!inherits(codebook, "codebook")) {
    stop("Input must be a codebook object")
  }

  plots <- list()

  # Domain distribution
  plots$domain_dist <- plot_domain_distribution(codebook)

  # Study coverage summary
  df <- items_to_dataframe(codebook, flatten_identifiers = FALSE)
  study_counts <- df %>%
    separate_rows(studies, sep = ";") %>%
    filter(studies != "") %>%
    count(studies, name = "n_items")

  plots$study_coverage <- ggplot(study_counts, aes(x = reorder(studies, n_items), y = n_items)) +
    geom_col(fill = "darkgreen", alpha = 0.8) +
    coord_flip() +
    labs(
      title = "Items by Study",
      x = "Study",
      y = "Number of Items"
    ) +
    theme_minimal()

  # Response options coverage
  has_responses <- df %>%
    summarise(
      `Has Response Options` = sum(has_response_opts),
      `No Response Options` = sum(!has_response_opts)
    ) %>%
    pivot_longer(everything(), names_to = "category", values_to = "count")

  plots$response_coverage <- ggplot(has_responses, aes(x = category, y = count, fill = category)) +
    geom_col(alpha = 0.8) +
    scale_fill_manual(values = c("steelblue", "lightcoral")) +
    labs(
      title = "Response Options Coverage",
      x = "",
      y = "Number of Items"
    ) +
    theme_minimal() +
    theme(legend.position = "none")

  # IRT parameters coverage
  has_irt <- df %>%
    summarise(
      `Has IRT Parameters` = sum(has_irt_params),
      `No IRT Parameters` = sum(!has_irt_params)
    ) %>%
    pivot_longer(everything(), names_to = "category", values_to = "count")

  plots$irt_coverage <- ggplot(has_irt, aes(x = category, y = count, fill = category)) +
    geom_col(alpha = 0.8) +
    scale_fill_manual(values = c("darkblue", "lightgray")) +
    labs(
      title = "IRT Parameters Coverage",
      x = "",
      y = "Number of Items"
    ) +
    theme_minimal() +
    theme(legend.position = "none")

  return(plots)
}