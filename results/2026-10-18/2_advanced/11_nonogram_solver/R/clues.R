is_clue_line <- function(text) nzchar(text) && grepl("^[0-9 ]+$", text)
parse_clue <- function(text) {
  if (text == "0") return(integer())
  if (!grepl("^[1-9][0-9]?( [1-9][0-9]?)*$", text)) return(NULL)
  as.integer(strsplit(text, " ", fixed = TRUE)[[1L]])
}
run_clue <- function(cells) {
  runs <- rle(cells == FILLED)
  as.integer(runs$lengths[runs$values])
}
clue_text <- function(clue, separator = " ") if (length(clue)) paste(clue, collapse = separator) else "0"
clue_span <- function(clue) sum(clue) + length(clue) - 1L
clue_fits <- function(clue, length) clue_span(clue) <= length
