# ui.R
# User interface definition

fluidPage(
  titlePanel("Age-Response Gradient Explorer"),

  sidebarLayout(
    # ==========================================================================
    # Sidebar Panel
    # ==========================================================================

    sidebarPanel(
      width = 3,

      # Study Filter
      h4("Filter by Study"),
      checkboxGroupInput(
        "studies_selected",
        label = NULL,
        choices = c("NE20", "NE22", "NE25", "NSCH21", "NSCH22", "USA24"),
        selected = c("NE20", "NE22", "NE25", "NSCH21", "NSCH22", "USA24")
      ),

      fluidRow(
        column(6, actionButton("select_all_studies", "Select All", width = "100%")),
        column(6, actionButton("deselect_all_studies", "Deselect All", width = "100%"))
      ),

      hr(),

      # Item Selection
      h4("Select Item"),
      selectizeInput(
        "item_selected",
        label = NULL,
        choices = item_choices,
        selected = NULL,
        options = list(
          placeholder = "Search for an item...",
          maxOptions = 500
        )
      ),

      hr(),

      # Display Options
      h4("Display Options"),
      checkboxInput("show_boxplots", "Show Box Plots", value = TRUE),
      checkboxInput("color_by_study", "Color by Study", value = TRUE),

      hr(),

      # Summary Statistics
      h4("Summary Statistics"),
      verbatimTextOutput("summary_stats")
    ),

    # ==========================================================================
    # Main Panel
    # ==========================================================================

    mainPanel(
      width = 9,

      # Item Description
      htmlOutput("item_description"),

      # Quality Flag Warning
      uiOutput("quality_flag_warning"),

      # Age Gradient Plot
      plotOutput("age_gradient_plot", height = "600px"),

      hr(),

      # Codebook JSON Display
      h4("Codebook Metadata"),
      verbatimTextOutput("codebook_json")
    )
  )
)
