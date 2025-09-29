# Quick fix for dictionary conversion issue
source("pipelines/orchestration/ne25_pipeline.R")

# Add helper function
convert_dictionary_to_df <- function(dict_list) {
  if (length(dict_list) == 0) return(data.frame())

  # Convert list to data frame
  dict_rows <- list()
  for (field_name in names(dict_list)) {
    field_info <- dict_list[[field_name]]
    dict_rows[[field_name]] <- data.frame(
      field_name = field_info$field_name %||% field_name,
      form_name = field_info$form_name %||% "",
      section_header = field_info$section_header %||% "",
      field_type = field_info$field_type %||% "",
      field_label = field_info$field_label %||% "",
      select_choices_or_calculations = field_info$select_choices_or_calculations %||% "",
      field_note = field_info$field_note %||% "",
      text_validation_type_or_show_slider_number = field_info$text_validation_type_or_show_slider_number %||% "",
      text_validation_min = field_info$text_validation_min %||% "",
      text_validation_max = field_info$text_validation_max %||% "",
      identifier = field_info$identifier %||% "",
      branching_logic = field_info$branching_logic %||% "",
      required_field = field_info$required_field %||% "",
      custom_alignment = field_info$custom_alignment %||% "",
      question_number = field_info$question_number %||% "",
      matrix_group_name = field_info$matrix_group_name %||% "",
      matrix_ranking = field_info$matrix_ranking %||% "",
      field_annotation = field_info$field_annotation %||% "",
      stringsAsFactors = FALSE
    )
  }
  return(do.call(rbind, dict_rows))
}

# Run the pipeline with fixed dictionary conversion
result <- run_ne25_pipeline(overwrite_existing = TRUE)
print(result)