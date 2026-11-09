fixed <- function(value, places = 4L) {
  text <- sprintf(paste0("%.", places, "f"), value)
  zero <- paste0("0.", strrep("0", places))
  text[text == paste0("-", zero)] <- zero
  text
}

four_decimal <- function(value) as.numeric(fixed(value))
ratio_text <- function(numerator, denominator) paste(paste0(numerator, "/", denominator), fixed(numerator / denominator))
fraction_text <- function(numerator, denominator) {
  if (denominator == 0L) return("- -")
  a <- numerator
  b <- denominator
  while (b) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  paste(paste0(numerator / a, "/", denominator / a), fixed(numerator / denominator))
}

write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
