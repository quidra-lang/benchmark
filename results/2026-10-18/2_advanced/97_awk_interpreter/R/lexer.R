KEYWORDS <- strsplit("BEGIN END function if else while for do break continue next exit return delete in getline print printf", " ", fixed = TRUE)[[1L]]
BUILTINS <- strsplit("length substr index split sprintf toupper tolower close int", " ", fixed = TRUE)[[1L]]
PAIRS <- strsplit("+= -= *= /= %= ^= == <= >= != ++ -- && || >>", " ", fixed = TRUE)[[1L]]
SYMBOLS <- strsplit("+-*/%^!><?:=()[]{},;$", "", fixed = TRUE)[[1L]]
ESCAPES <- c(n = "\n", t = "\t", "\\" = "\\", "\"" = "\"", "/" = "/")
letter <- function(character) character != "" && utf8ToInt(character) %in% c(65L:90L, 97L:122L)
digit <- function(character) character != "" && utf8ToInt(character) %in% 48L:57L
name_character <- function(character) letter(character) || digit(character) || character == "_"
syntax_issue <- function(position) {
    stop(structure(list(message = "syntax error", position = position), class = c("syntax_issue", "error", "condition")))
}
tokenize <- function(source) {
    characters <- strsplit(source, "", fixed = TRUE)[[1L]]
    tokens <- list()
    index <- line <- column <- 1L
    while (index <= length(characters)) {
        character <- characters[index]
        position <- c(line, column)
        if (character == " ") {
            index <- index + 1L
            column <- column + 1L
            next
        }
        if (character == "\\" && index < length(characters) && characters[index + 1L] == "\n") {
            index <- index + 2L
            line <- line + 1L
            column <- 1L
            next
        }
        if (character == "#") {
            while (index <= length(characters) && characters[index] != "\n") {
                index <- index + 1L
                column <- column + 1L
            }
            next
        }
        if (character == "\n") {
            tokens[[length(tokens) + 1L]] <- list(kind = "newline", spelling = "\n", value = NULL, position = position)
            index <- index + 1L
            line <- line + 1L
            column <- 1L
            next
        }
        finish <- index + 1L
        value <- NULL
        if (digit(character)) {
            while (finish <= length(characters) && digit(characters[finish])) finish <- finish + 1L
            kind <- "number"
            value <- as.integer(paste0(characters[seq.int(index, finish - 1L)], collapse = ""))
        } else if (letter(character) || character == "_") {
            while (finish <= length(characters) && name_character(characters[finish])) finish <- finish + 1L
            word <- paste0(characters[seq.int(index, finish - 1L)], collapse = "")
            kind <- if (word %in% KEYWORDS) "keyword" else if (word %in% BUILTINS) "builtin" else if (finish <= length(characters) && characters[finish] == "(") "function_name" else "name"
        } else if (character == "\"") {
            pieces <- character()
            while (finish <= length(characters) && characters[finish] != "\"") {
                if (characters[finish] == "\n") syntax_issue(position)
                if (characters[finish] == "\\") {
                    if (finish == length(characters) || !characters[finish + 1L] %in% names(ESCAPES)) syntax_issue(c(line, column + finish - index))
                    pieces <- c(pieces, ESCAPES[[characters[finish + 1L]]])
                    finish <- finish + 2L
                } else {
                    pieces <- c(pieces, characters[finish])
                    finish <- finish + 1L
                }
            }
            if (finish > length(characters)) syntax_issue(position)
            finish <- finish + 1L
            kind <- "string"
            value <- paste0(pieces, collapse = "")
        } else if (finish <= length(characters) && paste0(character, characters[finish]) %in% PAIRS) {
            finish <- finish + 1L
            kind <- "symbol"
        } else if (character %in% SYMBOLS) kind <- "symbol" else syntax_issue(position)
        spelling <- paste0(characters[seq.int(index, finish - 1L)], collapse = "")
        tokens[[length(tokens) + 1L]] <- list(kind = kind, spelling = spelling, value = value, position = position)
        column <- column + finish - index
        index <- finish
    }
    tokens[[length(tokens) + 1L]] <- list(kind = "end", spelling = "", value = NULL, position = c(sum(characters == "\n") + 1L, 1L))
    tokens
}
