source("charset.R")
source("formatter.R")

record <- function(...) list2env(list(...), parent = emptyenv())
regex_node <- function(kind, value = NULL, child = NULL, elements = list(), lower = 0L,
                       upper = NULL, mode = "greedy", number = 0L, name = NULL,
                       column = 0L, codes = integer(), negated = FALSE, positive = TRUE) {
    record(kind = kind, value = value, child = child, elements = elements, lower = lower,
        upper = upper, mode = mode, number = number, name = name, column = column,
        codes = codes, negated = negated, positive = positive)
}
new_parser <- function(text) {
    record(text = text, index = 1L, groups = 0L, named = new.env(hash = TRUE, parent = emptyenv()), backrefs = list())
}
parser_peek <- function(parser, offset = 0L) {
    position <- parser$index + offset
    if (position <= nchar(parser$text)) substr(parser$text, position, position) else ""
}
read_character <- function(parser) {
    character <- parser_peek(parser)
    if (character != "") parser$index <- parser$index + 1L
    character
}
pattern_error <- function(parser, message, column = parser$index) {
    stop(structure(list(message = message, column = column), class = c("pattern_error", "error", "condition")))
}
read_digits <- function(parser) {
    beginning <- parser$index
    while (is_digit(parser_peek(parser))) read_character(parser)
    if (beginning == parser$index) "" else substr(parser$text, beginning, parser$index - 1L)
}
read_name <- function(parser) {
    initial <- parser_peek(parser)
    if (!(is_letter(initial) || initial == "_")) pattern_error(parser, "invalid group name")
    beginning <- parser$index
    while (is_letter(parser_peek(parser)) || is_digit(parser_peek(parser)) || parser_peek(parser) == "_") read_character(parser)
    name <- substr(parser$text, beginning, parser$index - 1L)
    if (parser_peek(parser) != ">") pattern_error(parser, "invalid group name")
    read_character(parser)
    name
}
parse_pattern <- function(parser) {
    root <- parse_alternation(parser)
    if (parser_peek(parser) != "") pattern_error(parser, "unmatched )")
    for (reference in parser$backrefs) {
        if (!is.null(reference$name)) {
            if (!exists(reference$name, parser$named, inherits = FALSE)) pattern_error(parser, "unknown group name", reference$column)
            reference$number <- parser$named[[reference$name]]
        } else if (reference$number > parser$groups) pattern_error(parser, "invalid group reference", reference$column)
    }
    root
}
parse_alternation <- function(parser) {
    elements <- list(parse_concatenation(parser))
    while (parser_peek(parser) == "|") {
        read_character(parser)
        elements[[length(elements) + 1L]] <- parse_concatenation(parser)
    }
    if (length(elements) == 1L) elements[[1L]] else regex_node("alternation", elements = elements)
}
parse_concatenation <- function(parser) {
    elements <- list()
    while (parser_peek(parser) != "" && !parser_peek(parser) %in% c("|", ")")) {
        elements[[length(elements) + 1L]] <- parse_quantified(parser)
    }
    if (length(elements) == 1L) elements[[1L]] else regex_node("concat", elements = elements)
}
is_quantifier <- function(character) character %in% c("*", "+", "?", "{")
parse_quantified <- function(parser) {
    if (is_quantifier(parser_peek(parser))) pattern_error(parser, "nothing to repeat")
    element <- parse_element(parser)
    if (!is_quantifier(parser_peek(parser))) return(element)
    if (element$kind %in% c("assert", "look")) pattern_error(parser, "nothing to repeat")
    beginning <- parser$index
    character <- read_character(parser)
    if (character == "*") {
        lower <- 0L
        upper <- NULL
    } else if (character == "+") {
        lower <- 1L
        upper <- NULL
    } else if (character == "?") {
        lower <- 0L
        upper <- 1L
    } else {
        digits <- read_digits(parser)
        if (digits == "") pattern_error(parser, "invalid quantifier", beginning)
        lower <- as.integer(digits)
        if (parser_peek(parser) == "}") {
            upper <- lower
        } else if (parser_peek(parser) == ",") {
            read_character(parser)
            if (parser_peek(parser) == "}") {
                upper <- NULL
            } else {
                digits <- read_digits(parser)
                if (digits == "") pattern_error(parser, "invalid quantifier", beginning)
                upper <- as.integer(digits)
            }
        } else pattern_error(parser, "invalid quantifier", beginning)
        if (parser_peek(parser) != "}") pattern_error(parser, "invalid quantifier", beginning)
        read_character(parser)
        if (lower > 100L || (!is.null(upper) && upper > 100L)) pattern_error(parser, "quantifier too large", beginning)
        if (!is.null(upper) && lower > upper) pattern_error(parser, "quantifier range out of order", beginning)
    }
    mode <- "greedy"
    if (parser_peek(parser) == "?") {
        read_character(parser)
        mode <- "lazy"
    } else if (parser_peek(parser) == "+") {
        read_character(parser)
        mode <- "possessive"
    }
    if (is_quantifier(parser_peek(parser))) pattern_error(parser, "nested quantifier")
    regex_node("repeat", child = element, lower = lower, upper = upper, mode = mode)
}
parse_element <- function(parser) {
    character <- parser_peek(parser)
    if (character == "(") return(parse_group(parser))
    if (character == "[") return(parse_class(parser))
    if (character == "\\") return(parse_escape(parser))
    read_character(parser)
    if (character == ".") return(regex_node("any"))
    if (character == "^") return(regex_node("assert", value = "BOL"))
    if (character == "$") return(regex_node("assert", value = "EOL"))
    regex_node("literal", value = character)
}
parse_group <- function(parser) {
    column <- parser$index
    read_character(parser)
    kind <- "capture"
    name <- NULL
    if (parser_peek(parser) == "?") {
        read_character(parser)
        special <- read_character(parser)
        if (special == ":") {
            kind <- "noncapture"
        } else if (special == "=") {
            kind <- "positive"
        } else if (special == "!") {
            kind <- "negative"
        } else if (special == "<") {
            beginning <- parser$index
            name <- read_name(parser)
            if (exists(name, parser$named, inherits = FALSE)) pattern_error(parser, "duplicate group name", beginning)
        } else pattern_error(parser, "invalid group", column)
    }
    number <- 0L
    if (kind == "capture") {
        parser$groups <- parser$groups + 1L
        number <- parser$groups
        if (!is.null(name)) parser$named[[name]] <- number
    }
    child <- parse_alternation(parser)
    if (parser_peek(parser) != ")") pattern_error(parser, "missing )", column)
    read_character(parser)
    if (kind == "noncapture") return(child)
    if (kind %in% c("positive", "negative")) return(regex_node("look", child = child, positive = kind == "positive"))
    regex_node("group", number = number, name = name, child = child)
}
read_class_item <- function(parser) {
    character <- read_character(parser)
    if (character != "\\") return(list(set = FALSE, codes = utf8ToInt(character)))
    column <- parser$index - 1L
    if (parser_peek(parser) == "") pattern_error(parser, "trailing backslash", column)
    character <- read_character(parser)
    if (character %in% c("d", "D", "w", "W", "s", "S")) return(list(set = TRUE, codes = escaped_set(character)))
    if (character == "n") return(list(set = FALSE, codes = 10L))
    if (character == "t") return(list(set = FALSE, codes = 9L))
    if (is_letter(character) || is_digit(character)) pattern_error(parser, "invalid escape", column)
    list(set = FALSE, codes = utf8ToInt(character))
}
parse_class <- function(parser) {
    column <- parser$index
    read_character(parser)
    negated <- parser_peek(parser) == "^"
    if (negated) read_character(parser)
    if (parser_peek(parser) == "]") pattern_error(parser, "empty class")
    codes <- integer()
    repeat {
        if (parser_peek(parser) == "") pattern_error(parser, "missing ]", column)
        if (parser_peek(parser) == "]") {
            read_character(parser)
            break
        }
        initial <- read_class_item(parser)
        if (parser_peek(parser) == "-" && parser_peek(parser, 1L) != "" && parser_peek(parser, 1L) != "]") {
            hyphen <- parser$index
            read_character(parser)
            if (initial$set) pattern_error(parser, "invalid range", hyphen)
            final <- read_class_item(parser)
            if (final$set || initial$codes > final$codes) pattern_error(parser, "invalid range", hyphen)
            codes <- union(codes, seq.int(initial$codes, final$codes))
        } else codes <- union(codes, initial$codes)
    }
    regex_node("class", codes = sort(codes), negated = negated)
}
parse_escape <- function(parser) {
    column <- parser$index
    read_character(parser)
    if (parser_peek(parser) == "") pattern_error(parser, "trailing backslash", column)
    character <- read_character(parser)
    if (character %in% c("d", "D", "w", "W", "s", "S")) {
        code <- utf8ToInt(character)
        lower <- intToUtf8(if (code %in% UPPER) code + 32L else code)
        return(regex_node("class", codes = STANDARD[[lower]], negated = code %in% UPPER))
    }
    if (character == "b") return(regex_node("assert", value = "WORD"))
    if (character == "B") return(regex_node("assert", value = "NOTWORD"))
    if (character == "n") return(regex_node("literal", value = "\n"))
    if (character == "t") return(regex_node("literal", value = "\t"))
    if (utf8ToInt(character) %in% 49L:57L) {
        beginning <- parser$index - 1L
        read_digits(parser)
        reference <- regex_node("backref", number = as.integer(substr(parser$text, beginning, parser$index - 1L)), column = column)
        parser$backrefs[[length(parser$backrefs) + 1L]] <- reference
        return(reference)
    }
    if (character == "k") {
        if (parser_peek(parser) != "<") pattern_error(parser, "invalid escape", column)
        read_character(parser)
        reference <- regex_node("backref", name = read_name(parser), column = column)
        parser$backrefs[[length(parser$backrefs) + 1L]] <- reference
        return(reference)
    }
    if (is_letter(character) || is_digit(character)) pattern_error(parser, "invalid escape", column)
    regex_node("literal", value = character)
}
emit <- function(compiler, op, ...) {
    address <- length(compiler$program)
    compiler$program[[address + 1L]] <- record(op = op, ...)
    address
}
compile_node <- function(compiler, node) {
    kind <- node$kind
    if (kind == "literal") {
        emit(compiler, "CHAR", character = node$value)
    } else if (kind == "any") {
        emit(compiler, "ANY")
    } else if (kind == "class") {
        emit(compiler, "CLASS", codes = node$codes, negated = node$negated)
    } else if (kind == "assert") {
        emit(compiler, "ASSERT", kind = node$value)
    } else if (kind == "backref") {
        emit(compiler, "BACKREF", group = node$number)
    } else if (kind == "group") {
        emit(compiler, "SAVE", slot = 2L * node$number)
        compile_node(compiler, node$child)
        emit(compiler, "SAVE", slot = 2L * node$number + 1L)
    } else if (kind == "look") {
        address <- emit(compiler, "LOOK", kind = if (node$positive) "AHEAD" else "NOT")
        compile_node(compiler, node$child)
        emit(compiler, "MATCH")
        compiler$program[[address + 1L]]$x <- length(compiler$program)
    } else if (kind == "concat") {
        for (child in node$elements) compile_node(compiler, child)
    } else if (kind == "alternation") {
        jumps <- integer()
        for (child in head(node$elements, -1L)) {
            address <- emit(compiler, "SPLIT")
            compiler$program[[address + 1L]]$x <- length(compiler$program)
            compile_node(compiler, child)
            jumps <- c(jumps, emit(compiler, "JMP"))
            compiler$program[[address + 1L]]$y <- length(compiler$program)
        }
        compile_node(compiler, node$elements[[length(node$elements)]])
        for (address in jumps) compiler$program[[address + 1L]]$x <- length(compiler$program)
    } else if (node$mode == "possessive") {
        address <- emit(compiler, "LOOK", kind = "ATOMIC")
        compile_repeat(compiler, node$child, node$lower, node$upper, "greedy")
        emit(compiler, "MATCH")
        compiler$program[[address + 1L]]$x <- length(compiler$program)
    } else compile_repeat(compiler, node$child, node$lower, node$upper, node$mode)
    invisible(NULL)
}
patch_split <- function(entry, continuation, finish, mode) {
    entry$x <- if (mode == "lazy") finish else continuation
    entry$y <- if (mode == "lazy") continuation else finish
}
compile_repeat <- function(compiler, child, lower, upper, mode) {
    if (is.null(upper) && lower == 0L) {
        address <- emit(compiler, "SPLIT")
        compile_node(compiler, child)
        emit(compiler, "JMP", x = address)
        patch_split(compiler$program[[address + 1L]], address + 1L, length(compiler$program), mode)
    } else if (is.null(upper)) {
        for (unused in seq_len(lower - 1L)) compile_node(compiler, child)
        beginning <- length(compiler$program)
        compile_node(compiler, child)
        address <- emit(compiler, "SPLIT")
        patch_split(compiler$program[[address + 1L]], beginning, length(compiler$program), mode)
    } else {
        for (unused in seq_len(lower)) compile_node(compiler, child)
        splits <- integer()
        for (unused in seq_len(upper - lower)) {
            splits <- c(splits, emit(compiler, "SPLIT"))
            compile_node(compiler, child)
        }
        for (address in splits) patch_split(compiler$program[[address + 1L]], address + 1L, length(compiler$program), mode)
    }
}
compile_pattern <- function(root) {
    compiler <- record(program = list())
    emit(compiler, "SAVE", slot = 0L)
    compile_node(compiler, root)
    emit(compiler, "SAVE", slot = 1L)
    emit(compiler, "MATCH")
    compiler$program
}
length_range <- function(node) {
    kind <- node$kind
    if (kind %in% c("literal", "any", "class")) return(list(minimum = 1L, maximum = 1L))
    if (kind %in% c("assert", "look")) return(list(minimum = 0L, maximum = 0L))
    if (kind == "backref") return(list(minimum = 0L, maximum = NULL))
    if (kind == "group") return(length_range(node$child))
    if (kind == "repeat") {
        child <- length_range(node$child)
        high <- if (!is.null(child$maximum) && child$maximum == 0L) {
            0L
        } else if (is.null(child$maximum) || is.null(node$upper)) {
            NULL
        } else child$maximum * node$upper
        return(list(minimum = child$minimum * node$lower, maximum = high))
    }
    ranges <- lapply(node$elements, length_range)
    lows <- vapply(ranges, function(range) range$minimum, integer(1L))
    infinite <- any(vapply(ranges, function(range) is.null(range$maximum), logical(1L)))
    highs <- if (infinite) NULL else vapply(ranges, function(range) range$maximum, integer(1L))
    list(minimum = if (kind == "concat") sum(lows) else min(lows),
        maximum = if (infinite) NULL else if (kind == "concat") sum(highs) else max(highs))
}
first_characters <- function(node, flags) {
    kind <- node$kind
    if (kind == "literal") {
        code <- utf8ToInt(node$value)
        codes <- if (has_flag(flags, "i") && is_letter(node$value)) c(code, switched_code(code)) else code
        return(list(codes = sort(unique(codes)), nullable = FALSE))
    }
    if (kind == "any") return(list(codes = if (has_flag(flags, "s")) ASCII else setdiff(ASCII, 10L), nullable = FALSE))
    if (kind == "class") return(list(codes = ASCII[vapply(ASCII, code_matches_class, logical(1L), codes = node$codes, negated = node$negated, flags = flags)], nullable = FALSE))
    if (kind %in% c("assert", "look")) return(list(codes = integer(), nullable = TRUE))
    if (kind == "backref") return(list(codes = ASCII, nullable = TRUE))
    if (kind == "group") return(first_characters(node$child, flags))
    if (kind == "repeat") {
        if (!is.null(node$upper) && node$upper == 0L) return(list(codes = integer(), nullable = TRUE))
        child <- first_characters(node$child, flags)
        return(list(codes = child$codes, nullable = child$nullable || node$lower == 0L))
    }
    codes <- integer()
    nullable <- kind == "concat"
    for (child in node$elements) {
        first <- first_characters(child, flags)
        codes <- union(codes, first$codes)
        if (kind == "concat") {
            if (!first$nullable) {
                nullable <- FALSE
                break
            }
        } else nullable <- nullable || first$nullable
    }
    list(codes = sort(codes), nullable = nullable)
}

source("backtrack_vm.R")
source("pike_vm.R")

split_fields <- function(line, limit) {
    spaces <- which(strsplit(line, "", fixed = TRUE)[[1L]] == " ")
    spaces <- head(spaces, limit - 1L)
    bounds <- c(0L, spaces, nchar(line) + 1L)
    vapply(seq_len(length(bounds) - 1L), function(index) substr(line, bounds[index] + 1L, bounds[index + 1L] - 1L), character(1L))
}
read_pattern <- function(line) {
    fields <- split_fields(line, 3L)
    parser <- new_parser(fields[3L])
    root <- tryCatch(parse_pattern(parser), pattern_error = function(error) error)
    invalid <- inherits(root, "pattern_error")
    program <- if (invalid) list() else compile_pattern(root)
    list(name = fields[1L], original_flags = fields[2L], flags = if (fields[2L] == "-") "" else fields[2L],
        text = fields[3L], groups = parser$groups, named = parser$named,
        root = if (invalid) NULL else root, program = program, error = if (invalid) root else NULL,
        compatible = !invalid && all(vapply(program, function(entry) !entry$op %in% c("LOOK", "BACKREF"), logical(1L))))
}
decode_quoted <- function(encoded) {
    characters <- strsplit(encoded, "", fixed = TRUE)[[1L]]
    result <- character()
    index <- 2L
    while (index < length(characters)) {
        character <- characters[index]
        if (character == "\\") {
            index <- index + 1L
            escaped <- characters[index]
            character <- if (escaped == "n") "\n" else if (escaped == "t") "\t" else escaped
        }
        result <- c(result, character)
        index <- index + 1L
    }
    paste0(result, collapse = "")
}
subject_slice <- function(text, beginning, finish) {
    if (beginning == finish) "" else substr(text, beginning + 1L, finish)
}
parse_template <- function(template, pattern) {
    characters <- strsplit(template, "", fixed = TRUE)[[1L]]
    parts <- list()
    index <- 1L
    while (index <= length(characters)) {
        character <- characters[index]
        index <- index + 1L
        if (character != "$") {
            parts[[length(parts) + 1L]] <- character
            next
        }
        if (index > length(characters)) return(NULL)
        character <- characters[index]
        index <- index + 1L
        if (character == "$") {
            parts[[length(parts) + 1L]] <- "$"
            next
        } else if (is_digit(character)) {
            group <- as.integer(character)
        } else if (character == "{") {
            beginning <- index
            while (index <= length(characters) && characters[index] != "}") index <- index + 1L
            if (index > length(characters)) return(NULL)
            content <- if (beginning == index) "" else paste0(characters[seq.int(beginning, index - 1L)], collapse = "")
            index <- index + 1L
            if (content != "" && all(vapply(strsplit(content, "", fixed = TRUE)[[1L]], is_digit, logical(1L)))) {
                group <- as.integer(content)
            } else if (content != "" && exists(content, pattern$named, inherits = FALSE)) {
                group <- pattern$named[[content]]
            } else return(NULL)
        } else return(NULL)
        if (group > pattern$groups) return(NULL)
        parts[[length(parts) + 1L]] <- group
    }
    parts
}
group_is_set <- function(captures, group) captures[2L * group + 1L] >= 0L && captures[2L * group + 2L] >= 0L
expand_template <- function(parts, captures, text) {
    pieces <- vapply(parts, function(part) {
        if (is.character(part)) part else if (group_is_set(captures, part)) subject_slice(text, captures[2L * part + 1L], captures[2L * part + 2L]) else ""
    }, character(1L))
    paste0(pieces, collapse = "")
}
search_vm <- function(vm, start) {
    if (vm$engine == "backtrack") search_backtrack(vm, start) else search_pike(vm, start)
}
command_matches <- function(vm, kind, mode, text) {
    if (kind %in% c("MATCH", "SEARCH") || (kind == "REPLACE" && mode == "FIRST")) {
        found <- search_vm(vm, 0L)
        return(if (is.null(found)) list() else list(found))
    }
    matches <- list()
    position <- 0L
    while (position <= nchar(text)) {
        found <- search_vm(vm, position)
        if (is.null(found)) break
        matches[[length(matches) + 1L]] <- found
        position <- if (found[2L] > found[1L]) found[2L] else found[2L] + 1L
    }
    matches
}
span_text <- function(captures, group, text) {
    beginning <- captures[2L * group + 1L]
    finish <- captures[2L * group + 2L]
    paste0(beginning, "-", finish, " ", quoted(subject_slice(text, beginning, finish)))
}
match_lines <- function(captures, pattern, text) {
    lines <- paste("match", span_text(captures, 0L, text))
    for (group in seq_len(pattern$groups)) {
        lines <- c(lines, paste("group", group, if (group_is_set(captures, group)) span_text(captures, group, text) else "-"))
    }
    lines
}
result_lines <- function(kind, matches, pattern, text, parts) {
    if (kind %in% c("MATCH", "SEARCH")) return(if (!length(matches)) "no match" else match_lines(matches[[1L]], pattern, text))
    if (kind == "FINDALL") {
        lines <- paste("matches", length(matches))
        for (captures in matches) lines <- c(lines, match_lines(captures, pattern, text))
        return(lines)
    }
    position <- 0L
    if (kind == "REPLACE") {
        pieces <- character()
        for (captures in matches) {
            pieces <- c(pieces, subject_slice(text, position, captures[1L]), expand_template(parts, captures, text))
            position <- captures[2L]
        }
        pieces <- c(pieces, subject_slice(text, position, nchar(text)))
        return(c(paste("replacements", length(matches)), paste("result", quoted(paste0(pieces, collapse = "")))))
    }
    lines <- paste("pieces", length(matches) + 1L)
    for (captures in matches) {
        lines <- c(lines, paste("piece", quoted(subject_slice(text, position, captures[1L]))))
        for (group in seq_len(pattern$groups)) {
            value <- if (group_is_set(captures, group)) quoted(subject_slice(text, captures[2L * group + 1L], captures[2L * group + 2L])) else "-"
            lines <- c(lines, paste("group", group, value))
        }
        position <- captures[2L]
    }
    c(lines, paste("piece", quoted(subject_slice(text, position, nchar(text)))))
}
program_lines <- function(pattern) {
    range <- length_range(pattern$root)
    first <- first_characters(pattern$root, pattern$flags)$codes
    names <- ls(pattern$named, all.names = TRUE)
    names <- names[order(vapply(names, function(name) pattern$named[[name]], integer(1L)))]
    name_list <- if (!length(names)) "-" else paste0(vapply(names, function(name) paste0(name, ":", pattern$named[[name]]), character(1L)), collapse = ",")
    properties <- paste0("flags=", pattern$original_flags, " groups=", pattern$groups, " names=", name_list,
        " length=", range$minimum, "..", if (is.null(range$maximum)) "inf" else range$maximum,
        " first=", if (!length(first)) "-" else set_notation(first),
        " pike=", if (pattern$compatible) "yes" else "no", " size=", length(pattern$program))
    instructions <- vapply(seq_along(pattern$program), function(index) paste(index - 1L, instruction_notation(pattern$program[[index]])), character(1L))
    c(paste("===", pattern$name), properties, instructions)
}
main <- function() {
    patterns <- lapply(readLines("input/patterns.txt", warn = FALSE), read_pattern)
    by_name <- setNames(patterns, vapply(patterns, function(pattern) pattern$name, character(1L)))
    subjects <- list()
    for (line in readLines("input/subjects.txt", warn = FALSE)) {
        fields <- split_fields(line, 2L)
        subjects[[fields[1L]]] <- decode_quoted(fields[2L])
    }
    results <- programs <- errors <- character()
    steps <- "command,engine,steps"
    for (pattern in patterns) {
        if (!is.null(pattern$error)) {
            error <- pattern$error
            errors <- c(errors, paste0(pattern$name, ": ", error$message, " at column ", error$column),
                paste0("  ", pattern$text), paste0(strrep(" ", error$column + 1L), "^"))
        }
    }
    commands <- readLines("input/commands.txt", warn = FALSE)
    for (number in seq_along(commands)) {
        line <- commands[number]
        fields <- split_fields(line, 5L)
        kind <- fields[1L]
        mode <- if (kind == "REPLACE") fields[2L] else ""
        pattern <- by_name[[fields[if (kind == "REPLACE") 3L else 2L]]]
        results <- c(results, paste0("#", number, " ", line))
        if (!is.null(pattern$error)) {
            results <- c(results, "invalid pattern")
            next
        }
        if (kind == "LIST") {
            results <- c(results, paste("instructions", length(pattern$program)))
            programs <- c(programs, program_lines(pattern))
            next
        }
        parts <- if (kind == "REPLACE") parse_template(decode_quoted(fields[5L]), pattern) else NULL
        if (kind == "REPLACE" && is.null(parts)) {
            results <- c(results, "invalid template")
            next
        }
        text <- subjects[[fields[if (kind == "REPLACE") 4L else 3L]]]
        backtrack <- new_backtrack(pattern, text, kind == "MATCH")
        aborted <- FALSE
        backtrack_matches <- tryCatch(command_matches(backtrack, kind, mode, text), too_many_steps = function(error) {
            aborted <<- TRUE
            list()
        })
        steps <- c(steps, paste(number, "backtrack", backtrack$steps, sep = ","))
        matches <- backtrack_matches
        label <- "backtrack"
        if (pattern$compatible) {
            pike <- new_pike(pattern, text, kind == "MATCH")
            pike_matches <- command_matches(pike, kind, mode, text)
            steps <- c(steps, paste(number, "pike", pike$steps, sep = ","))
            if (!aborted && !identical(backtrack_matches, pike_matches)) {
                results <- c(results, "MISMATCH")
                next
            }
            matches <- pike_matches
            label <- if (aborted) "pike (backtrack: TOO_MANY_STEPS)" else "both"
        } else if (aborted) {
            results <- c(results, "TOO_MANY_STEPS")
            next
        }
        results <- c(results, paste("engine", label), result_lines(kind, matches, pattern, text, parts))
    }
    if (!length(programs)) programs <- "no programs"
    if (!length(errors)) errors <- "no errors"
    writeLines(results, "output/results.txt", useBytes = TRUE)
    writeLines(programs, "output/programs.txt", useBytes = TRUE)
    writeLines(steps, "output/steps.csv", useBytes = TRUE)
    writeLines(errors, "output/errors.txt", useBytes = TRUE)
}
main()
