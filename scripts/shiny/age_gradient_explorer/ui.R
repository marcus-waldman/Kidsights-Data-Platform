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
      radioButtons(
        "display_mode",
        label = "Display Mode:",
        choices = c(
          "Pooled (combined studies)" = "pooled",
          "Study-Specific (colored curves)" = "study_specific"
        ),
        selected = "study_specific"
      ),
      sliderInput(
        "influence_threshold",
        label = "Influence Point Threshold (%):",
        min = 1,
        max = 5,
        value = 5,
        step = 1,
        ticks = TRUE
      ),
      checkboxInput("exclude_influence_points", "Exclude Influence Points from Curves", value = FALSE),
      checkboxInput("show_influence_points", "Show Influence Points (markers)", value = FALSE),

      hr(),

      # Summary Statistics
      h4("Summary Statistics"),
      verbatimTextOutput("summary_stats"),

      hr(),

      # Database Connection Management
      h4("Database"),
      actionButton("test_db_connection", "Test Connection", icon = icon("database"), width = "100%"),
      br(), br(),
      actionButton("close_all_connections", "Close All Connections", icon = icon("plug"), width = "100%"),
      br(), br(),
      textOutput("db_status")
    ),

    # ==========================================================================
    # Main Panel
    # ==========================================================================

    mainPanel(
      width = 9,

      tabsetPanel(
        id = "main_tabs",

        # ======================================================================
        # Tab 1: Regression Coefficient Table
        # ======================================================================

        tabPanel(
          "Regression Coefficients",
          br(),
          p("Regression coefficients (beta for age on logit scale) for each item across studies. Negative coefficients are highlighted in red."),
          radioButtons(
            "coef_table_mode",
            label = "Coefficient Table Mode:",
            choices = c(
              "Full Model (with influence points)" = "full",
              "Reduced Model (excluding top 5% influence points)" = "no_influence"
            ),
            selected = "full",
            inline = TRUE
          ),
          p(style = "font-size: 11px; color: #666; margin-top: -5px;",
            em("Note: Reduced model uses 5% threshold. Use slider in Display Options to adjust threshold for plots.")),
          DT::dataTableOutput("coefficient_table")
        ),

        # ======================================================================
        # Tab 2: Age Gradient Plot
        # ======================================================================

        tabPanel(
          "Age Gradient Plot",
          br(),

          # Item Description
          htmlOutput("item_description"),

          hr(),

          # Review Notes
          h4("Review Notes"),
          fluidRow(
            column(
              width = 8,
              textAreaInput(
                "item_note",
                label = NULL,
                value = "",
                placeholder = "Enter notes for this item...",
                rows = 3,
                width = "100%"
              )
            ),
            column(
              width = 4,
              actionButton("save_note", "Save Note", icon = icon("save"), width = "100%", style = "margin-top: 0px;"),
              br(), br(),
              textOutput("last_saved_text"),
              br(),
              # Version History (collapsible, hidden by default)
              conditionalPanel(
                condition = "output.has_history",
                checkboxInput("show_history", "Show previous versions", value = FALSE),
                conditionalPanel(
                  condition = "input.show_history == true",
                  uiOutput("note_history")
                )
              )
            )
          ),

          hr(),

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
  )
)
