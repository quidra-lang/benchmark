money <- function(cents) {
  dollars <- integer_divide(cents, 100)
  paste0(integer_text(dollars), ".", sprintf("%02d", as.integer(cents - 100 * dollars)))
}

percent <- function(part, whole) {
  vapply(part, function(value) integer_divide(200 * value + whole, 2 * whole), numeric(1L))
}

table_row <- function(label, values, width) {
  paste0(sprintf("%-10s", label), paste(sprintf(paste0("%", width, ".0f"), values), collapse = ""))
}

write_report <- function(name, lines) {
  dir.create("output", showWarnings = FALSE)
  writeLines(lines, file.path("output", name), useBytes = TRUE)
}
