symbol_lines <- function(symbol) {
    vapply(seq_len(nrow(symbol)), function(y) paste0(ifelse(symbol[y, ] == 1L, "#", "."), collapse = ""), "")
}

pbm_text <- function(symbol, quiet, scale) {
    side <- nrow(symbol)
    width <- (side + 2L * quiet) * scale
    margin <- strrep("0", quiet * scale)
    empty_row <- strrep("0", width)
    lines <- c("P1", paste(width, width), rep(empty_row, quiet * scale))
    for (y in seq_len(side)) {
        pixels <- paste0(margin, paste0(strrep(as.character(symbol[y, ]), scale), collapse = ""), margin)
        lines <- c(lines, rep(pixels, scale))
    }
    paste0(paste(c(lines, rep(empty_row, quiet * scale)), collapse = "\n"), "\n")
}
