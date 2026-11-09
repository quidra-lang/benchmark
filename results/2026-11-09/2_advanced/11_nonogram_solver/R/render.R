state_char <- function(state) c("?", "#", ".")[state + 1L]
char_state <- function(character) match(character, c("?", "#", ".")) - 1L
state_string <- function(cells) paste(state_char(cells), collapse = "")
state_grid <- function(lines) matrix(unlist(lapply(lines, function(line) char_state(strsplit(line, "", fixed = TRUE)[[1L]])), use.names = FALSE), length(lines), nchar(lines[1L]), byrow = TRUE)
grid_display <- function(names, grids) c(paste("grid", paste(names, collapse = " ")), vapply(seq_len(nrow(grids[[1L]])), function(row) paste(vapply(grids, function(grid) state_string(grid[row, ]), character(1L)), collapse = " | "), character(1L)))
right_align <- function(text, width) paste0(strrep(" ", width - nchar(text)), text)
answer_sheet <- function(row_clues, column_clues, grid) {
  tokens <- lapply(column_clues, function(clue) strsplit(clue_text(clue), " ", fixed = TRUE)[[1L]])
  width <- max(nchar(unlist(tokens))) + 1L
  depth <- max(lengths(tokens))
  margin <- max(nchar(vapply(row_clues, clue_text, character(1L))))
  lines <- vapply(seq_len(depth), function(line) {
    parts <- vapply(tokens, function(column) {
      skip <- depth - length(column)
      if (line > skip) right_align(column[line - skip], width) else strrep(" ", width)
    }, character(1L))
    sub(" +$", "", paste0(strrep(" ", margin), paste(parts, collapse = "")))
  }, character(1L))
  c(lines, vapply(seq_along(row_clues), function(row) paste0(right_align(clue_text(row_clues[[row]]), margin), paste0(strrep(" ", width - 1L), state_char(grid[row, ]), collapse = "")), character(1L)))
}
