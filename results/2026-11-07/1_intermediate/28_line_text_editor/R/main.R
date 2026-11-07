fail <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
}
characters <- function(text) strsplit(text, "", fixed = TRUE)[[1L]]
indices <- function(first, last) if (first <= last) seq.int(first, last) else integer()
part <- function(text, first, last = nchar(text)) substr(text, first, last)
digit <- function(ch) nchar(ch) == 1L && ch %in% as.character(0L:9L)
digits <- function(text) grepl("^[0-9]*$", text)
default <- function(value, fallback) if (is.null(value)) fallback else value
command <- function(kind, ...) list(kind = kind, ...)

digits_end <- function(text, position) {
    while (position <= nchar(text) && digit(part(text, position, position))) position <- position + 1L
    position
}

delimited <- function(text, position, delimiter) {
    start <- position
    chars <- character()
    matched <- logical()
    while (position <= nchar(text)) {
        ch <- part(text, position, position)
        escaped <- ch == "\\"
        if (escaped) {
            position <- position + 1L
            if (position > nchar(text)) fail("missing delimiter")
            ch <- part(text, position, position)
        } else if (ch == delimiter) {
            return(list(text = paste(chars, collapse = ""), raw = part(text, start, position - 1L),
                        replacement = list(characters = chars, matched = matched), end = position + 1L))
        }
        chars <- c(chars, ch)
        matched <- c(matched, !escaped && ch == "&")
        position <- position + 1L
    }
    fail("missing delimiter")
}

scan_address <- function(text) {
    tokens <- list()
    position <- 1L
    while (position <= nchar(text)) {
        ch <- part(text, position, position)
        if (digit(ch)) {
            end <- digits_end(text, position)
            token <- list(kind = "number", value = as.integer(part(text, position, end - 1L)))
            position <- end
        } else if (ch %in% c("+", "-")) {
            end <- digits_end(text, position + 1L)
            magnitude <- if (end == position + 1L) 1L else as.integer(part(text, position + 1L, end - 1L))
            token <- list(kind = "offset", value = if (ch == "+") magnitude else -magnitude)
            position <- end
        } else if (ch %in% c(".", "$", ",", ";", "%")) {
            token <- list(kind = ch)
            position <- position + 1L
        } else if (ch == "'") {
            position <- position + 1L
            token <- list(kind = "'", value = part(text, position, position))
            if (position <= nchar(text)) position <- position + 1L
        } else if (ch %in% c("/", "?")) {
            found <- delimited(text, position + 1L, ch)
            token <- list(kind = ch, value = found$text)
            position <- found$end
        } else break
        tokens[[length(tokens) + 1L]] <- token
    }
    list(tokens = tokens, tail = part(text, position))
}

valid_address <- function(tokens) {
    for (i in seq_along(tokens)) {
        kind <- tokens[[i]]$kind
        if (kind != "offset" && (i != 1L || !kind %in% c("number", ".", "$", "'", "/", "?"))) return(FALSE)
    }
    TRUE
}

address_form <- function(tokens) {
    if (!length(tokens)) return(list(count = 0L))
    if (length(tokens) == 1L && tokens[[1L]]$kind == "%") {
        return(list(count = 2L, left = list(list(kind = "number", value = 1L)),
                    right = list(list(kind = "$")), semicolon = FALSE))
    }
    separators <- which(vapply(tokens, function(token) token$kind %in% c(",", ";"), logical(1L)))
    if (length(separators) > 1L) fail("bad address")
    if (!length(separators)) {
        if (!valid_address(tokens)) fail("bad address")
        return(list(count = 1L, left = tokens))
    }
    separator <- separators[1L]
    left <- tokens[seq_len(separator - 1L)]
    right <- tokens[indices(separator + 1L, length(tokens))]
    if (!valid_address(left) || !valid_address(right)) fail("bad address")
    list(count = 2L, left = left, right = right, semicolon = tokens[[separator]]$kind == ";")
}

positive <- function(argument) {
    if (!nzchar(argument)) return(NULL)
    if (!digits(argument)) fail("invalid suffix")
    value <- as.integer(argument)
    if (value == 0L) fail("invalid suffix")
    value
}
print_suffix <- function(argument) {
    if (!argument %in% c("", "p", "n", "l")) fail("invalid suffix")
    argument
}
file_name <- function(argument) {
    if (!grepl("^ [a-z0-9]{1,8}$", argument)) fail("invalid file name")
    part(argument, 2L)
}
sort_form <- function(text) text == "sort" || startsWith(text, "sort ")

parse_substitution <- function(argument) {
    search <- ""
    replacement <- NULL
    flags <- argument
    if (!grepl("^[gpnl0-9]*$", argument)) {
        delimiter <- part(argument, 1L, 1L)
        if (delimiter %in% c(" ", "\\")) fail("missing delimiter")
        found <- delimited(argument, 2L, delimiter)
        replace <- delimited(argument, found$end, delimiter)
        search <- found$text
        if (replace$raw != "%") replacement <- replace$replacement
        flags <- part(argument, replace$end)
    }
    all <- FALSE
    count <- 1L
    counted <- FALSE
    suffix <- ""
    position <- 1L
    while (position <= nchar(flags)) {
        ch <- part(flags, position, position)
        position <- position + 1L
        if (ch == "g") {
            if (all) fail("invalid suffix")
            all <- TRUE
        } else if (ch %in% c("p", "n", "l")) {
            if (nzchar(suffix)) fail("invalid suffix")
            suffix <- ch
        } else if (digit(ch)) {
            if (counted) fail("invalid suffix")
            counted <- TRUE
            start <- position - 1L
            position <- digits_end(flags, position)
            count <- as.integer(part(flags, start, position - 1L))
            if (count == 0L) fail("invalid suffix")
        } else fail("invalid suffix")
    }
    command("s", search = search, replacement = replacement, all = all, count = count, suffix = suffix)
}

parse_command <- function(text) {
    if (sort_form(text)) {
        options <- if (text == "sort") "" else part(text, 6L)
        chars <- characters(options)
        if (text != "sort" && (!length(chars) || any(!chars %in% c("r", "u", "i", "n")) ||
                              anyDuplicated(chars) || all(c("i", "n") %in% chars))) fail("invalid suffix")
        return(command("sort", options = chars))
    }
    if (!nzchar(text)) return(command(""))
    kind <- part(text, 1L, 1L)
    argument <- part(text, 2L)
    if (kind %in% c("a", "i", "c", "p", "n", "l", "=", "#", "y", "K", "h", "f")) {
        if (nzchar(argument)) fail("invalid suffix")
        return(command(kind))
    }
    if (kind %in% c("d", "x", "j", "J")) return(command(kind, suffix = print_suffix(argument)))
    if (kind %in% c("z", ">", "<", "u")) return(command(kind, amount = positive(argument)))
    if (kind == "~") {
        if (!argument %in% c("", "u", "l")) fail("invalid suffix")
        return(command(kind, option = argument))
    }
    if (kind == "r") {
        if (digits(argument)) return(command("redo", amount = positive(argument)))
        return(command("read", name = file_name(argument)))
    }
    if (kind == "w") {
        if (!nzchar(argument)) return(command("w"))
        return(command("write", name = file_name(argument)))
    }
    if (kind %in% c("W", "e")) return(command(kind, name = file_name(argument)))
    if (kind == "k") {
        if (!argument %in% letters) fail("invalid mark")
        return(command(kind, name = argument))
    }
    if (kind %in% c("m", "t")) {
        destination <- scan_address(argument)
        if (!length(destination$tokens) || !valid_address(destination$tokens)) fail("invalid destination")
        return(command(kind, destination = destination$tokens, suffix = print_suffix(destination$tail)))
    }
    if (kind == "s") return(parse_substitution(argument))
    if (kind %in% c("g", "v")) {
        delimiter <- part(argument, 1L, 1L)
        if (!nzchar(argument) || delimiter %in% c(" ", "\\")) fail("missing delimiter")
        found <- delimited(argument, 2L, delimiter)
        body <- part(argument, found$end)
        if (!nzchar(body)) body <- "p"
        if (!part(body, 1L, 1L) %in% c("p", "n", "l", "d", "m", "t", "j", "J", "s", ">", "<", "~", "a", "i", "c", "x") ||
            sort_form(body)) fail("invalid global command")
        return(command(kind, search = found$text, sub = parse_command(body)))
    }
    fail("unknown command")
}

with_text <- function(text) {
    tryCatch({
        tail <- scan_address(text)$tail
        if (tail %in% c("a", "i", "c")) return(TRUE)
        if (nchar(tail) < 2L || !part(tail, 1L, 1L) %in% c("g", "v") || part(tail, 2L, 2L) %in% c(" ", "\\")) return(FALSE)
        found <- delimited(tail, 3L, part(tail, 2L, 2L))
        part(tail, found$end) %in% c("a", "i", "c")
    }, command_error = function(error) FALSE)
}

address_kind <- function(kind) {
    if (kind %in% c("u", "redo", "h", "K", "f", "e")) 0L
    else if (kind %in% c("a", "i", "x", "=", "read", "k", "z")) 1L
    else 2L
}
modifying <- function(cmd) {
    if (cmd$kind %in% c("g", "v")) return(modifying(cmd$sub))
    cmd$kind %in% c("a", "i", "c", "d", "x", "j", "J", "m", "t", "s", ">", "<", "~", "sort", "read", "e")
}

new_editor <- function() {
    editor <- new.env(parent = emptyenv())
    editor$state <- list(lines = character(), ids = integer(), current = 0L, marks = setNames(integer(26L), letters),
                         cut = character(), pattern = NULL, replacement = NULL, display = 5L,
                         undo = list(), redo = list(), files = list(), next_id = 1L)
    editor$output <- character()
    editor
}
snapshot <- function(state, source) list(source = source, lines = state$lines, ids = state$ids, current = state$current)
locate <- function(state, identity) match(identity, state$ids, nomatch = 0L)
choose_pattern <- function(editor, search) {
    if (nzchar(search)) editor$state$pattern <- search
    if (is.null(editor$state$pattern)) fail("no previous pattern")
    editor$state$pattern
}

address_value <- function(editor, tokens) {
    value <- editor$state$current
    for (token in tokens) {
        kind <- token$kind
        if (kind == "offset") value <- value + token$value
        else if (kind == "number") value <- token$value
        else if (kind == ".") value <- editor$state$current
        else if (kind == "$") value <- length(editor$state$lines)
        else if (kind == "'") {
            if (!token$value %in% letters) fail("invalid mark")
            value <- locate(editor$state, editor$state$marks[[token$value]])
            if (value == 0L) fail("mark not set")
        } else {
            pattern <- choose_pattern(editor, token$value)
            size <- length(editor$state$lines)
            current <- editor$state$current
            pivot <- if (kind == "?" && current == 0L) size + 1L else current
            positions <- if (kind == "/") (pivot + seq_len(size) - 1L) %% size + 1L else (pivot - seq_len(size) - 1L) %% size + 1L
            matches <- positions[grepl(pattern, editor$state$lines[positions], fixed = TRUE)]
            if (!length(matches)) fail("no match")
            value <- matches[1L]
        }
    }
    value
}

address_values <- function(editor, form) {
    if (form$count == 0L) return(integer())
    left <- if (length(form$left)) address_value(editor, form$left) else if (form$semicolon) editor$state$current else 1L
    if (form$count == 1L) return(left)
    if (form$semicolon) {
        if (left < 0L || left > length(editor$state$lines)) fail("address out of range")
        editor$state$current <- left
    }
    right <- if (length(form$right)) address_value(editor, form$right) else length(editor$state$lines)
    c(left, right)
}

checked_range <- function(state, kind, values) {
    arity <- address_kind(kind)
    size <- length(state$lines)
    if (arity == 0L) return(c(0L, 0L))
    if (arity == 1L) {
        first <- if (length(values)) values[1L] else if (kind %in% c("=", "read")) size else state$current + as.integer(kind == "z")
        minimum <- as.integer(kind %in% c("k", "z"))
        if (first < minimum || first > size) fail("address out of range")
        return(c(first, first))
    }
    if (length(values)) {
        first <- values[1L]
        last <- if (length(values) == 1L) first else values[2L]
    } else if (kind %in% c("w", "write", "W", "#")) return(c(1L, size))
    else if (kind %in% c("g", "v", "sort")) { first <- 1L; last <- size }
    else { first <- state$current; last <- first + as.integer(kind %in% c("j", "J")) }
    if (first < 1L || first > size || last < 1L || last > size) fail("address out of range")
    if (first > last || first == last && kind %in% c("j", "J")) fail("invalid range")
    c(first, last)
}

new_ids <- function(editor, count) {
    result <- editor$state$next_id + seq_len(count) - 1L
    editor$state$next_id <- editor$state$next_id + count
    result
}
splice <- function(values, position, count, inserted) {
    c(values[seq_len(position)], inserted, values[indices(position + count + 1L, length(values))])
}
replace_lines <- function(editor, position, count, text, ids) {
    lines <- splice(editor$state$lines, position, count, text)
    identities <- splice(editor$state$ids, position, count, ids)
    editor$state$lines <- lines
    editor$state$ids <- identities
}
insert_text <- function(editor, position, text) replace_lines(editor, position, 0L, text, new_ids(editor, length(text)))
emit <- function(editor, text) editor$output <- c(editor$output, text)
print_line <- function(editor, number, form) {
    text <- editor$state$lines[number]
    if (form == "n") emit(editor, sprintf("%3d %s", number, text))
    else if (form == "l") {
        chars <- characters(text)
        escaped <- paste0(paste(ifelse(chars == "\\", "\\\\", chars), collapse = ""), "$")
        while (nchar(escaped) > 40L) {
            emit(editor, paste0(part(escaped, 1L, 39L), "\\"))
            escaped <- part(escaped, 40L)
        }
        emit(editor, escaped)
    } else emit(editor, text)
}
suffix_line <- function(editor, suffix) {
    if (nzchar(default(suffix, "")) && editor$state$current > 0L) print_line(editor, editor$state$current, suffix)
}
byte_count <- function(text) sum(nchar(text) + 1L)
word_count <- function(text) sum(gregexpr("[^ ]+", text)[[1L]] > 0L)
leading_spaces <- function(text) nchar(text) - nchar(sub("^ +", "", text))
letter_case <- function(text, option) {
    if (option == "u") chartr(paste(letters, collapse = ""), paste(LETTERS, collapse = ""), text)
    else if (option == "l") chartr(paste(LETTERS, collapse = ""), paste(letters, collapse = ""), text)
    else chartr(paste0(paste(letters, collapse = ""), paste(LETTERS, collapse = "")),
                paste0(paste(LETTERS, collapse = ""), paste(letters, collapse = "")), text)
}
leading_integer <- function(text) {
    if (!grepl("^-?[0-9]", text)) return(0L)
    as.integer(sub("^(-?[0-9]+).*", "\\1", text))
}

substitute_lines <- function(editor, cmd, range, inside) {
    pattern <- choose_pattern(editor, cmd$search)
    replacement <- default(cmd$replacement, editor$state$replacement)
    if (is.null(replacement)) fail("no previous substitution")
    editor$state$replacement <- replacement
    expanded <- paste(ifelse(replacement$matched, pattern, replacement$characters), collapse = "")
    changed <- 0L
    for (number in indices(range[1L], range[2L])) {
        original <- editor$state$lines[number]
        position <- 1L
        occurrence <- 0L
        replaced <- FALSE
        result <- ""
        repeat {
            found <- regexpr(pattern, part(original, position), fixed = TRUE)[1L]
            if (found < 0L) break
            found <- found + position - 1L
            result <- paste0(result, part(original, position, found - 1L))
            occurrence <- occurrence + 1L
            if (occurrence == cmd$count || cmd$all && occurrence > cmd$count) {
                result <- paste0(result, expanded)
                replaced <- TRUE
            } else result <- paste0(result, pattern)
            position <- found + nchar(pattern)
        }
        if (replaced) {
            result <- paste0(result, part(original, position))
            if (nchar(result) > 80L) fail("line too long")
            if (!nzchar(result) || endsWith(result, " ")) fail("bad line")
            editor$state$lines[number] <- result
            editor$state$current <- number
            changed <- changed + 1L
        }
    }
    if (changed == 0L && !inside) fail("no match")
    if (changed > 0L) suffix_line(editor, cmd$suffix)
    changed
}

transfer_history <- function(editor, redo, amount) {
    from <- if (redo) "redo" else "undo"
    to <- if (redo) "undo" else "redo"
    source <- editor$state[[from]]
    target <- editor$state[[to]]
    if (amount > length(source)) fail(if (redo) "nothing to redo" else "nothing to undo")
    for (iteration in seq_len(amount)) {
        saved <- source[[length(source)]]
        source <- source[-length(source)]
        target[[length(target) + 1L]] <- snapshot(editor$state, saved$source)
        editor$state$lines <- saved$lines
        editor$state$ids <- saved$ids
        editor$state$current <- saved$current
    }
    editor$state[[from]] <- source
    editor$state[[to]] <- target
}

file_command <- function(editor, cmd, range) {
    text <- editor$state$files[[cmd$name]]
    if (cmd$kind %in% c("write", "W")) {
        selected <- editor$state$lines[indices(range[1L], range[2L])]
        text <- if (cmd$kind == "W") c(text, selected) else selected
        editor$state$files[cmd$name] <- list(text)
    } else {
        if (is.null(text)) fail("no such file")
        if (cmd$kind == "read") insert_text(editor, range[1L], text)
        else replace_lines(editor, 0L, length(editor$state$lines), text, new_ids(editor, length(text)))
        editor$state$current <- (if (cmd$kind == "read") range[1L] else 0L) + length(text)
    }
    emit(editor, sprintf("file %s lines=%d bytes=%d", cmd$name, length(text), byte_count(text)))
}

execute_command <- function(editor, cmd, range, text, inside = FALSE) {
    kind <- cmd$kind
    first <- range[1L]
    last <- range[2L]
    selected <- indices(first, last)
    if (kind == "") {
        print_line(editor, last, "p")
        editor$state$current <- last
    } else if (kind %in% c("p", "n", "l")) {
        for (number in selected) print_line(editor, number, kind)
        editor$state$current <- last
    } else if (kind == "z") {
        if (!is.null(cmd$amount)) editor$state$display <- cmd$amount
        end <- min(length(editor$state$lines), first + editor$state$display - 1L)
        for (number in indices(first, end)) print_line(editor, number, "p")
        editor$state$current <- end
    } else if (kind == "=") emit(editor, as.character(first))
    else if (kind == "#") {
        lines <- editor$state$lines[selected]
        emit(editor, sprintf("count lines=%d words=%d chars=%d", length(lines), sum(vapply(lines, word_count, integer(1L))), sum(nchar(lines))))
    } else if (kind == "w") {
        lines <- editor$state$lines[selected]
        emit(editor, lines)
        emit(editor, sprintf("lines=%d bytes=%d", length(lines), byte_count(lines)))
    } else if (kind %in% c("a", "i")) {
        position <- if (kind == "a") first else max(first, 1L) - 1L
        insert_text(editor, position, text)
        editor$state$current <- position + length(text)
    } else if (kind %in% c("c", "d")) {
        editor$state$cut <- editor$state$lines[selected]
        inserted <- if (kind == "c") text else character()
        replace_lines(editor, first - 1L, length(selected), inserted, new_ids(editor, length(inserted)))
        editor$state$current <- if (length(inserted)) first + length(inserted) - 1L else min(first, length(editor$state$lines))
    } else if (kind == "y") editor$state$cut <- editor$state$lines[selected]
    else if (kind == "x") {
        if (!length(editor$state$cut)) fail("nothing to put")
        insert_text(editor, first, editor$state$cut)
        editor$state$current <- first + length(editor$state$cut)
    } else if (kind %in% c("m", "t")) {
        destination <- address_value(editor, cmd$destination)
        if (destination < 0L || destination > length(editor$state$lines)) fail("address out of range")
        if (kind == "m" && first <= destination && destination < last) fail("invalid destination")
        lines <- editor$state$lines[selected]
        ids <- editor$state$ids[selected]
        position <- destination
        if (kind == "m") {
            replace_lines(editor, first - 1L, length(selected), character(), integer())
            if (destination >= last) position <- position - length(selected)
        } else ids <- new_ids(editor, length(selected))
        replace_lines(editor, position, 0L, lines, ids)
        editor$state$current <- position + length(lines)
    } else if (kind %in% c("j", "J")) {
        lines <- editor$state$lines[selected]
        if (kind == "J") lines[-1L] <- sub("^ +", "", lines[-1L])
        joined <- paste(lines, collapse = if (kind == "j") "" else " ")
        if (nchar(joined) > 80L) fail("line too long")
        replace_lines(editor, first - 1L, length(selected), joined, editor$state$ids[first])
        editor$state$current <- first
    } else if (kind %in% c(">", "<", "~")) {
        width <- default(cmd$amount, 4L)
        lines <- editor$state$lines[selected]
        if (kind == ">") {
            if (any(nchar(lines) + width > 80L)) fail("line too long")
            lines <- paste0(strrep(" ", width), lines)
        } else if (kind == "<") {
            removed <- pmin(width, vapply(lines, leading_spaces, integer(1L)))
            lines <- substring(lines, removed + 1L)
        } else lines <- letter_case(lines, cmd$option)
        editor$state$lines[selected] <- lines
        editor$state$current <- last
    } else if (kind == "sort") {
        lines <- editor$state$lines[selected]
        keys <- if ("n" %in% cmd$options) vapply(lines, leading_integer, integer(1L)) else if ("i" %in% cmd$options) letter_case(lines, "l") else lines
        ordered <- order(keys, decreasing = "r" %in% cmd$options, method = "radix")
        if ("u" %in% cmd$options) ordered <- ordered[!duplicated(keys[ordered])]
        ids <- editor$state$ids[selected][ordered]
        replace_lines(editor, first - 1L, length(selected), lines[ordered], ids)
        editor$state$current <- first + length(ordered) - 1L
    } else if (kind == "s") return(substitute_lines(editor, cmd, range, inside))
    else if (kind == "k") editor$state$marks[[cmd$name]] <- editor$state$ids[first]
    else if (kind == "K") {
        positions <- vapply(editor$state$marks, function(id) locate(editor$state, id), integer(1L))
        pieces <- paste0(names(positions)[positions > 0L], "=", positions[positions > 0L])
        emit(editor, if (any(positions > 0L)) paste("marks", paste(pieces, collapse = " ")) else "marks none")
    } else if (kind %in% c("u", "redo")) transfer_history(editor, kind == "redo", default(cmd$amount, 1L))
    else if (kind == "h") {
        emit(editor, sprintf("history undo=%d redo=%d", length(editor$state$undo), length(editor$state$redo)))
        for (side in c("undo", "redo")) {
            records <- rev(editor$state[[side]])
            for (i in seq_along(records)) emit(editor, sprintf("%s %d: %s", side, i, records[[i]]$source))
        }
    } else if (kind %in% c("read", "write", "W", "e")) file_command(editor, cmd, range)
    else if (kind == "f") {
        names <- sort(names(editor$state$files), method = "radix")
        pieces <- vapply(names, function(name) sprintf("%s=%d", name, length(editor$state$files[[name]])), character(1L))
        emit(editor, if (length(names)) paste("files", paste(pieces, collapse = " ")) else "files none")
    } else if (kind %in% c("g", "v")) {
        pattern <- choose_pattern(editor, cmd$search)
        matches <- grepl(pattern, editor$state$lines[selected], fixed = TRUE)
        identities <- editor$state$ids[selected][matches == (kind == "g")]
        if (!length(identities)) fail("no match")
        changed <- 0L
        for (identity in identities) {
            position <- locate(editor$state, identity)
            if (position == 0L) next
            editor$state$current <- position
            subrange <- checked_range(editor$state, cmd$sub$kind, integer())
            changed <- changed + execute_command(editor, cmd$sub, subrange, text, inside = TRUE)
        }
        if (cmd$sub$kind == "s" && changed == 0L) fail("no match")
    }
    if (kind %in% c("d", "x", "j", "J", "m", "t")) suffix_line(editor, cmd$suffix)
    0L
}

process_command <- function(editor, source, text) {
    saved <- editor$state
    before <- snapshot(saved, source)
    editor$output <- character()
    tryCatch({
        scanned <- scan_address(source)
        form <- address_form(scanned$tokens)
        cmd <- parse_command(scanned$tail)
        arity <- address_kind(cmd$kind)
        if (arity == 0L && form$count > 0L) fail("unexpected address")
        if (arity == 1L && form$count == 2L) fail("too many addresses")
        values <- address_values(editor, form)
        range <- checked_range(editor$state, cmd$kind, values)
        execute_command(editor, cmd, range, text)
        if (length(editor$state$lines) > 200L) fail("buffer full")
        if (modifying(cmd)) {
            editor$state$undo[[length(editor$state$undo) + 1L]] <- before
            editor$state$redo <- list()
        }
        editor$output
    }, command_error = function(error) {
        editor$state <- saved
        editor$output <- character()
        paste("?", conditionMessage(error))
    })
}

input <- readLines(file("stdin"), warn = FALSE)
editor <- new_editor()
position <- 1L
while (position <= length(input)) {
    source <- input[position]
    position <- position + 1L
    if (source == "Q") break
    text <- character()
    if (with_text(source)) {
        start <- position
        while (input[position] != ".") position <- position + 1L
        text <- input[indices(start, position - 1L)]
        position <- position + 1L
    }
    output <- process_command(editor, source, text)
    if (length(output)) writeLines(output)
}
