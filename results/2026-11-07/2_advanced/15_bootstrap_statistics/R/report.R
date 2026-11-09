integer_text <- function(value) sprintf("%.0f", value)

real_text <- function(value) {
  text <- sprintf("%.4f", value)
  text[text == "-0.0000"] <- "0.0000"
  text
}

p_value <- function(numerator, denominator) {
  fraction <- reduced_fraction(numerator, denominator)
  paste0(integer_text(fraction[1L]), "/", integer_text(fraction[2L]), " ", real_text(fraction[1L] / fraction[2L]))
}

number_list <- function(numbers) {
  if (!length(numbers)) "none" else paste(integer_text(ordered_values(numbers)), collapse = " ")
}

bin_number <- function(value, low, high, bins) min(floor(bins * (value - low) / (high - low)), bins - 1L) + 1L
bar <- function(count, top) strrep("#", (40 * count + top - 1L) %/% top)
write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
