POLICY_SYMBOLS <- c("^", ">", "v", "<")
integer_text <- function(value) sprintf("%.0f", value)
fixed_text <- function(value) paste0(
    ifelse(value < 0, "-", ""),
    integer_text(abs(value) %/% 10000),
    ".",
    sprintf("%04d", as.integer(abs(value) %% 10000))
)
average_text <- function(total, count) fixed_text((10000 * total) %/% count)
cell_text <- function(world, cell) paste0((cell - 1L) %/% world$cols, ",", (cell - 1L) %% world$cols)
cells_text <- function(world, cells) paste(cell_text(world, cells), collapse = " ")
grid_lines <- function(world, fields, separator) {
  lines <- character()
  for (row in seq_len(world$rows)) {
    cells <- seq.int((row - 1L) * world$cols + 1L, row * world$cols)
    parts <- world$kinds[cells]
    states <- world$state_index[cells]
    parts[states > 0L] <- fields[states[states > 0L]]
    lines <- c(lines, paste(parts, collapse = separator))
  }
  lines
}
value_grid <- function(world, values) grid_lines(world, fixed_text(values), " ")
policy_grid <- function(world, policy) grid_lines(world, POLICY_SYMBOLS[policy], "")
symbol_grid <- function(world, symbols) grid_lines(world, symbols, "")
q_table_rows <- function(world, name, q, visits) {
  lines <- character()
  for (state in seq_along(world$states)) {
    cell <- world$states[[state]]
    for (action in seq_len(4L)) {
      count <- if (is.null(visits)) "-" else integer_text(visits[state, action])
      lines <- c(lines, paste(name, (cell - 1L) %/% world$cols, (cell - 1L) %% world$cols,
                            ACTION_LETTERS[[action]], fixed_text(q[state, action]), count, sep = ","))
    }
  }
  lines
}
join_parts <- function(parts) {
  lines <- character()
  for (part in parts) {
    if (length(lines)) lines <- c(lines, "")
    lines <- c(lines, part)
  }
  lines
}
write_lines <- function(path, lines) writeLines(lines, path, useBytes = TRUE)
