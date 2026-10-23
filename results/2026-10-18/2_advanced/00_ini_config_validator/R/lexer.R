LITERAL_DOLLAR <- "\001"
trim_spaces <- function(text) sub(" +$", "", sub("^ +", "", text))

cut_first <- function(text, separator) {
    position <- regexpr(separator, text, fixed = TRUE)[1L]
    if (position < 0L) return(list(before = text, after = "", found = FALSE))
    list(before = substr(text, 1L, position - 1L), after = substring(text, position + nchar(separator)), found = TRUE)
}

split_keep <- function(text, separator) {
    pieces <- character()
    repeat {
        part <- cut_first(text, separator)
        pieces <- c(pieces, part$before)
        if (!part$found) return(pieces)
        text <- part$after
    }
}

logical_lines <- function(physical) {
    lines <- list(); index <- 1L
    escapes <- setNames(c("\\", '"', "\n", "\t", LITERAL_DOLLAR), c("\\", '"', "n", "t", "$"))
    while (index <= length(physical)) {
        number <- index; text <- physical[index]; index <- index + 1L
        position <- 1L; quoted <- FALSE; segments <- character(); current <- ""; error <- NULL
        while (position <= nchar(text)) {
            char <- substr(text, position, position)
            if (char == "\\" && position == nchar(text)) {
                text <- sub("^ +", "", physical[index]); index <- index + 1L; position <- 1L
            } else if (quoted && char == "\\") {
                follower <- substr(text, position + 1L, position + 1L)
                if (follower %in% names(escapes)) {
                    current <- paste0(current, escapes[[follower]])
                } else if (is.null(error)) {
                    error <- list(code = "E_ESCAPE", message = paste0("invalid escape sequence \\", follower))
                }
                position <- position + 2L
            } else if (char == '"') {
                segments <- c(segments, current); current <- ""; quoted <- !quoted; position <- position + 1L
            } else if (!quoted && char %in% c(";", "#")) {
                break
            } else {
                current <- paste0(current, char); position <- position + 1L
            }
        }
        if (quoted && is.null(error)) error <- list(code = "E_UNTERMINATED", message = "unterminated string")
        lines[[length(lines) + 1L]] <- list(number = number, segments = c(segments, current), error = error)
    }
    lines
}
