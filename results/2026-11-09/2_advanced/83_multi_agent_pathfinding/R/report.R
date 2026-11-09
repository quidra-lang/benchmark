cell_text <- function(cell, grid) paste0(cell %% grid$width, ",", cell %/% grid$width)
agent_name <- function(number) intToUtf8(64L + number)
action_string <- function(path, grid) {
    actions <- character()
    if (length(path) > 1L) for (index in 2:length(path)) {
        source <- path[index - 1L]
        destination <- path[index]
        delta <- c(
            destination %% grid$width - source %% grid$width,
            destination %/% grid$width - source %/% grid$width
        )
        action <- which(vapply(GRID_ACTIONS, function(item) identical(item, delta), FALSE))[1L]
        actions <- c(actions, GRID_ACTION_NAMES[action])
    }
    paste0(actions, collapse = "")
}
conflict_text <- function(conflict, grid) {
    beginning <- sprintf(
        "%s t %d %s %s",
        conflict$kind,
        conflict$time,
        agent_name(conflict$a),
        agent_name(conflict$b)
    )
    if (conflict$kind == "vertex") paste(beginning, "at", cell_text(conflict$u, grid)) else paste(
        beginning,
        "from",
        cell_text(conflict$u, grid),
        "to",
        cell_text(conflict$v, grid)
    )
}
reduced_fraction <- function(numerator, denominator) {
    first <- numerator
    second <- denominator
    while (second > 0L) {
        remainder <- first %% second
        first <- second
        second <- remainder
    }
    paste0(numerator %/% first, "/", denominator %/% first)
}
csv_line <- function(values) paste(values, collapse = ",")
save_file <- function(name, lines) {
    dir.create("output", showWarnings = FALSE)
    writeLines(lines, file.path("output", name), useBytes = TRUE)
}
grid_picture <- function(grid, placements) {
    vapply(seq_len(grid$height) - 1L, function(y) {
        row <- strsplit(grid$rows[y + 1L], "", fixed = TRUE)[[1L]]
        for (x in seq_len(grid$width) - 1L) {
            value <- placements[[as.character(y * grid$width + x)]]
            if (!is.null(value)) row[x + 1L] <- value
        }
        paste0(row, collapse = "")
    }, "")
}
