SYMBOLS <- strsplit("+-*/\\^<>=~:.?@#&$", "", fixed = TRUE)[[1L]]
INFIX <- new_table()
for (row in list(list(1200L, "xfx", ":-"), list(1100L, "xfy", ";"), list(1050L, "xfy", "->"), list(1000L, "xfy", ","),
    list(700L, "xfx", c("=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=..")),
    list(500L, "yfx", c("+", "-")), list(400L, "yfx", c("*", "/", "//", "mod", "rem")))) {
    for (name in row[[3L]]) INFIX[[name]] <- c(row[[1L]], if (row[[2L]] == "yfx") row[[1L]] else row[[1L]] - 1L, if (row[[2L]] == "xfy") row[[1L]] else row[[1L]] - 1L)
}
PREFIX <- c("\\+" = 900L, "-" = 200L)
syntax_error <- function(token, message = NULL) {
    if (is.null(message)) {
        message <- if (token$kind == "invalid") {
            token$value
        } else if (token$kind == "eof") {
            "unexpected end of file"
        } else if (token$kind == "end") {
            "unexpected end of clause"
        } else if (token$kind == "name" && exists(token$value, INFIX, inherits = FALSE)) {
            "operator priority clash"
        } else paste0("unexpected \"", token$spelling, "\"")
    }
    stop(structure(list(message = message, token = token), class = c("prolog_syntax_error", "error", "condition")))
}
lowercase_letter <- function(character) character != "" && utf8ToInt(character) %in% 97L:122L
uppercase_letter <- function(character) character != "" && utf8ToInt(character) %in% 65L:90L
digit <- function(character) character != "" && utf8ToInt(character) %in% 48L:57L
alphanumeric <- function(character) lowercase_letter(character) || uppercase_letter(character) || digit(character) || character == "_"
tokenize <- function(text, column = 1L) {
    characters <- strsplit(text, "", fixed = TRUE)[[1L]]
    tokens <- list()
    position <- line <- 1L
    space <- TRUE
    while (position <= length(characters)) {
        character <- characters[position]
        if (character %in% c(" ", "\n")) {
            if (character == "\n") {
                line <- line + 1L
                column <- 1L
            } else column <- column + 1L
            position <- position + 1L
            space <- TRUE
            next
        }
        if (character == "%") {
            while (position <= length(characters) && characters[position] != "\n") {
                position <- position + 1L
                column <- column + 1L
            }
            space <- TRUE
            next
        }
        beginning <- position
        start_column <- column
        if (digit(character)) {
            position <- position + 1L
            while (position <= length(characters) && digit(characters[position])) position <- position + 1L
            value <- gmp::as.bigz(paste0(characters[seq.int(beginning, position - 1L)], collapse = ""))
            kind <- "integer"
            if (value > gmp::as.bigz("2147483647")) {
                kind <- "invalid"
                value <- "integer too large"
            }
        } else if (lowercase_letter(character) || uppercase_letter(character) || character == "_") {
            position <- position + 1L
            while (position <= length(characters) && alphanumeric(characters[position])) position <- position + 1L
            value <- paste0(characters[seq.int(beginning, position - 1L)], collapse = "")
            kind <- if (lowercase_letter(character)) "name" else "variable"
        } else if (character %in% SYMBOLS) {
            position <- position + 1L
            while (position <= length(characters) && characters[position] %in% SYMBOLS) position <- position + 1L
            value <- paste0(characters[seq.int(beginning, position - 1L)], collapse = "")
            kind <- if (value == "." && (position > length(characters) || characters[position] %in% c(" ", "\n", "%"))) "end" else "name"
        } else if (character %in% c("!", ";")) {
            kind <- "name"
            value <- character
            position <- position + 1L
        } else if (character %in% c(",", "|", "(", ")", "[", "]")) {
            kind <- "punct"
            value <- character
            position <- position + 1L
        } else if (character == "'") {
            position <- position + 1L
            represented <- character()
            incorrect <- FALSE
            repeat {
                if (position > length(characters) || characters[position] == "\n") {
                    kind <- "invalid"
                    value <- "unterminated quoted atom"
                    break
                }
                current <- characters[position]
                if (current == "'") {
                    if (position < length(characters) && characters[position + 1L] == "'") {
                        represented <- c(represented, "'")
                        position <- position + 2L
                    } else {
                        position <- position + 1L
                        kind <- if (incorrect) "invalid" else "quoted"
                        value <- if (incorrect) "undefined escape sequence" else paste0(represented, collapse = "")
                        break
                    }
                } else if (current == "\\") {
                    position <- position + 1L
                    if (position <= length(characters) && characters[position] != "\n") {
                        escaped <- characters[position]
                        if (!escaped %in% c("n", "t", "\\", "'")) incorrect <- TRUE
                        represented <- c(represented, if (escaped == "n") "\n" else if (escaped == "t") "\t" else escaped)
                        position <- position + 1L
                    }
                } else {
                    represented <- c(represented, current)
                    position <- position + 1L
                }
            }
        } else {
            kind <- "invalid"
            value <- paste0("illegal character '", character, "'")
            position <- position + 1L
        }
        tokens[[length(tokens) + 1L]] <- list(kind = kind, value = value,
            spelling = paste0(characters[seq.int(beginning, position - 1L)], collapse = ""),
            line = line, column = start_column, space = space, index = length(tokens) + 1L)
        column <- column + position - beginning
        space <- FALSE
    }
    tokens[[length(tokens) + 1L]] <- list(kind = "eof", value = NULL, spelling = "", line = line, column = column, space = space, index = length(tokens) + 1L)
    tokens
}
new_reader <- function(text, column = 1L) record(tokens = tokenize(text, column), index = 1L, names = new_table(), name_order = character(), counts = new_table(), count_order = character())
reader_token <- function(reader) reader$tokens[[reader$index]]
take_token <- function(reader) {
    token <- reader_token(reader)
    if (token$kind != "eof") reader$index <- reader$index + 1L
    token
}
punctuation <- function(reader, spelling) reader_token(reader)$kind == "punct" && reader_token(reader)$value == spelling
expect_punctuation <- function(reader, spelling) {
    token <- take_token(reader)
    if (token$kind != "punct" || token$value != spelling) syntax_error(token)
}
read_clause <- function(reader, query = FALSE) {
    reader$names <- new_table()
    reader$name_order <- character()
    reader$counts <- new_table()
    reader$count_order <- character()
    term <- read_term(reader, 1200L)$term
    token <- take_token(reader)
    if (token$kind != "end") syntax_error(token)
    if (query && reader_token(reader)$kind != "eof") syntax_error(reader_token(reader))
    term
}
read_term <- function(reader, limit) {
    result <- read_primary(reader, limit)
    repeat {
        token <- reader_token(reader)
        operator <- (token$kind == "name" && exists(token$value, INFIX, inherits = FALSE)) || (token$kind == "punct" && token$value == ",")
        if (!operator) return(result)
        limits <- INFIX[[token$value]]
        if (limits[1L] > limit || result$priority > limits[2L]) return(result)
        take_token(reader)
        argument <- read_term(reader, limits[3L])$term
        result <- list(term = compound(token$value, result$term, argument), priority = limits[1L])
    }
}
can_start <- function(reader) {
    token <- reader_token(reader)
    token$kind %in% c("integer", "variable", "quoted") || (token$kind == "punct" && token$value %in% c("(", "[")) ||
        (token$kind == "name" && (!exists(token$value, INFIX, inherits = FALSE) || token$value %in% names(PREFIX)))
}
read_primary <- function(reader, limit) {
    token <- take_token(reader)
    if (token$kind == "integer") return(list(term = integer_term(token$value), priority = 0L))
    if (token$kind == "variable") {
        name <- token$value
        if (!exists(name, reader$counts, inherits = FALSE)) {
            reader$count_order <- c(reader$count_order, name)
            reader$counts[[name]] <- 0L
        }
        reader$counts[[name]] <- reader$counts[[name]] + 1L
        if (name == "_") return(list(term = variable_term(), priority = 0L))
        if (!exists(name, reader$names, inherits = FALSE)) {
            reader$names[[name]] <- variable_term()
            reader$name_order <- c(reader$name_order, name)
        }
        return(list(term = reader$names[[name]], priority = 0L))
    }
    if (token$kind == "punct" && token$value == "(") {
        term <- read_term(reader, 1200L)$term
        expect_punctuation(reader, ")")
        return(list(term = term, priority = 0L))
    }
    if (token$kind == "punct" && token$value == "[") {
        if (punctuation(reader, "]")) {
            take_token(reader)
            return(list(term = NIL, priority = 0L))
        }
        elements <- list(read_term(reader, 999L)$term)
        while (punctuation(reader, ",")) {
            take_token(reader)
            elements[[length(elements) + 1L]] <- read_term(reader, 999L)$term
        }
        tail <- NIL
        if (punctuation(reader, "|")) {
            take_token(reader)
            tail <- read_term(reader, 999L)$term
        }
        expect_punctuation(reader, "]")
        return(list(term = make_list(elements, tail), priority = 0L))
    }
    if (token$kind %in% c("name", "quoted")) {
        if (punctuation(reader, "(") && !reader_token(reader)$space) {
            take_token(reader)
            arguments <- list(read_term(reader, 999L)$term)
            while (punctuation(reader, ",")) {
                take_token(reader)
                arguments[[length(arguments) + 1L]] <- read_term(reader, 999L)$term
            }
            expect_punctuation(reader, ")")
            return(list(term = compound_term(token$value, arguments), priority = 0L))
        }
        if (token$kind == "name" && token$value == "-" && reader_token(reader)$kind == "integer" && !reader_token(reader)$space) {
            return(list(term = integer_term(-take_token(reader)$value), priority = 0L))
        }
        if (token$kind == "name" && token$value %in% names(PREFIX) && can_start(reader)) {
            priority <- PREFIX[[token$value]]
            if (priority > limit) syntax_error(token, "operator priority clash")
            return(list(term = compound(token$value, read_term(reader, priority)$term), priority = priority))
        }
        return(list(term = atom_term(token$value), priority = 0L))
    }
    syntax_error(token)
}
