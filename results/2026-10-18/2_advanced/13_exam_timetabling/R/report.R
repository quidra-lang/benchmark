fixed_width_line <- function(label, cells, label_width, cell_width) {
  paste0(sprintf(paste0("%-", label_width, "s"), label), paste(sprintf(paste0("%", cell_width, "s"), cells), collapse = ""))
}
rounded_percent <- function(part, whole) (200 * part + whole) %/% (2 * whole)

write_files <- function(directory, files) {
  dir.create(directory, showWarnings = FALSE, recursive = TRUE)
  for (name in names(files)) {
    connection <- file(file.path(directory, name), open = "wb")
    writeLines(files[[name]], connection, sep = "\n", useBytes = TRUE)
    close(connection)
  }
}
