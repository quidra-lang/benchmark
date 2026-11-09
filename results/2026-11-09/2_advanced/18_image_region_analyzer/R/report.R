rational <- function(numerator, denominator = 1) {
  first <- abs(numerator)
  second <- denominator
  while (second != 0) {
    remainder <- first %% second
    first <- second
    second <- remainder
  }
  c(numerator / first, denominator / first)
}

compare_ratio <- function(first, second) {
  sign(first[1L] * second[2L] - second[1L] * first[2L])
}

integer_text <- function(value) sprintf("%.0f", value)

decimal_text <- function(value, digits) {
  scale <- 10^digits
  rounded <- (2 * scale * abs(value[1L]) + value[2L]) %/% (2 * value[2L])
  sign <- if (value[1L] < 0 && rounded > 0) "-" else ""
  fraction <- integer_text(rounded %% scale)
  paste0(sign, integer_text(rounded %/% scale), ".", strrep("0", digits - nchar(fraction)), fraction)
}

hull_area_text <- function(doubled) {
  paste0(integer_text(doubled %/% 2), ".", if (doubled %% 2 == 0) "0" else "5")
}

write_files <- function(directory, files) {
  dir.create(directory, showWarnings = FALSE, recursive = TRUE)
  for (name in names(files)) {
    writeLines(files[[name]], file.path(directory, name), useBytes = TRUE)
  }
}
