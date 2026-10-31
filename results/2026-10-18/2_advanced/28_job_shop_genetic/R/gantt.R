chart_scale <- function(makespan, width) {
    magnitude <- 1L
    repeat {
        for (step in c(1L, 2L, 5L)) {
            scale <- step * magnitude
            columns <- (makespan + scale - 1L) %/% scale
            if (columns <= width) return(c(scale, columns))
        }
        magnitude <- magnitude * 10L
    }
}
time_row <- function(scale, columns) {
    row <- "time"
    for (column in seq.int(0L, columns - 1L, 10L)) row <- paste0(
        row,
        strrep(" ", max(0L, 6L + column - nchar(row))),
        column * scale
    )
    row
}
rule_row <- function(columns) paste0(
    "      ",
    paste(ifelse(seq.int(0L, columns - 1L) %% 10L == 0L, "+", "-"), collapse = "")
)
framed <- function(label, marks) paste0(sprintf("%-4s", label), " |", marks, "|")
chart_row <- function(label, intervals, scale, columns) {
    intervals <- intervals[order(vapply(intervals, function(item) item$start, 0L))]
    marks <- vapply(seq.int(0L, columns - 1L), function(column) {
        mark <- "."
        widest <- 0L
        for (item in intervals) {
            overlap <- min(item$end, (column + 1L) * scale) - max(item$start, column * scale)
            if (overlap > widest) {
                mark <- item$symbol
                widest <- overlap
            }
        }
        mark
    }, "")
    framed(label, paste(marks, collapse = ""))
}
busy_row <- function(intervals, scale, columns) {
    marks <- vapply(seq.int(0L, columns - 1L), function(column) {
        time <- column * scale
        busy <- sum(vapply(
            intervals,
            function(row) any(vapply(row, function(item) item$start <= time && time < item$end, FALSE)),
            FALSE
        ))
        if (busy == 10L) "X" else as.character(busy)
    }, "")
    framed("busy", paste(marks, collapse = ""))
}
