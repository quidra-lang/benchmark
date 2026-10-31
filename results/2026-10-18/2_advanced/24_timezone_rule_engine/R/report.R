integer_text <- function(value) sprintf("%.0f", value)
local_text <- function(time) {
  values <- split_time(time)
  sprintf("%04.0f-%02.0f-%02.0fT%02.0f:%02.0f:%02.0f", values[1], values[2], values[3], values[4], values[5], values[6])
}
ut_text <- function(time) paste0(local_text(time), "Z")
offset_text <- function(value) {
  sign <- if (value < 0) "-" else "+"
  value <- abs(value)
  text <- sprintf("%s%02.0f:%02.0f", sign, floor_div(value, 3600), modulo(floor_div(value, 60), 60))
  if (modulo(value, 60) != 0) text <- paste0(text, sprintf(":%02.0f", modulo(value, 60)))
  text
}
duration_text <- function(value) {
  sign <- if (value < 0) "-" else ""
  value <- abs(value)
  sprintf("%s%.0f:%02.0f:%02.0f", sign, floor_div(value, 3600), modulo(floor_div(value, 60), 60), modulo(value, 60))
}
clock_text <- function(value) {
  text <- sprintf("%.0f:%02.0f", floor_div(value, 3600), modulo(floor_div(value, 60), 60))
  if (modulo(value, 60) != 0) text <- paste0(text, sprintf(":%02.0f", modulo(value, 60)))
  text
}
state_text <- function(period) {
  paste(offset_text(period$offset), if (period$dst) "DST" else "STD", period$abbreviation)
}
change_text <- function(time, before, after) paste(ut_text(time), state_text(before), "->", state_text(after))
write_lines <- function(name, lines) {
  text <- if (length(lines)) paste0(paste(lines, collapse = "\n"), "\n") else ""
  cat(text, file = file.path("output", name))
}
write_blocks <- function(name, blocks) {
  lines <- character()
  for (i in seq_along(blocks)) {
    if (i > 1) lines <- c(lines, "")
    lines <- c(lines, blocks[[i]])
  }
  write_lines(name, lines)
}
