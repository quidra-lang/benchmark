faces <- c("U", "R", "F", "D", "L", "B")
colors <- c("W", "R", "G", "Y", "O", "B")
move_letters <- strsplit("UDFBLRMESudfblrxyz", "", fixed = TRUE)[[1]]
corner_names <- c("URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB")
edge_names <- c("UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR")
no_arguments <- c("RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS")
word_commands <- c(CHECK = 1, LOAD = 1, UNDO = 1, REDO = 1, SEARCH = 1, WHERE = 1, SAVE = 1, RESTORE = 1, SCRAMBLE = 2)
sequence_commands <- c("APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL")
head_commands <- c("DEFINE", "MIRROR", "ROTATE")
identity <- seq_len(54)
solved_state <- rep(colors, each = 9)
state <- solved_state
history <- integer()
redo <- integer()
macros <- list()
saves <- list()
moves <- vector("list", 54)
emit <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) stop(structure(list(message = paste0("error: ", message), call = NULL), class = c("cube_error", "error", "condition")))
index <- function(face, row, col) (match(face, faces) - 1L) * 9L + (row - 1L) * 3L + col
move_code <- function(letter, amount = 1L) (match(letter, move_letters) - 1L) * 3L + as.integer(amount)
move_letter <- function(code) move_letters[(code - 1L) %/% 3L + 1L]
move_amount <- function(code) (code - 1L) %% 3L + 1L
compose <- function(first, second) second[first]
inverse <- function(sequence) {
    sequence <- rev(sequence)
    (sequence - 1L) %/% 3L * 3L + 3L - (sequence - 1L) %% 3L
}
permute <- function(state, permutation) {
    result <- state
    result[permutation] <- state
    result
}
effect <- function(sequence) {
    result <- identity
    for (code in sequence) result <- compose(result, moves[[code]])
    result
}
powers <- function(letter, permutation) {
    current <- identity
    for (amount in 1:3) {
        current <- compose(current, permutation)
        moves[[move_code(letter, amount)]] <<- current
    }
}
build_moves <- function() {
    for (letter in c("U", "R", "F", "D", "L", "B", "M", "E", "S")) {
        p <- identity
        if (letter %in% faces) for (i in 1:3) for (j in 1:3) p[index(letter, i, j)] <- index(letter, j, 4L - i)
        put <- function(a, i, j, b, k, l) p[index(a, i, j)] <<- index(b, k, l)
        for (i in 1:3) {
            if (letter == "U") {
                from <- c("F", "L", "B", "R")
                to <- c("L", "B", "R", "F")
                for (j in 1:4) put(from[j], 1L, i, to[j], 1L, i)
            } else if (letter == "D") {
                from <- c("F", "R", "B", "L")
                to <- c("R", "B", "L", "F")
                for (j in 1:4) put(from[j], 3L, i, to[j], 3L, i)
            } else if (letter == "R") {
                put("F", i, 3L, "U", i, 3L)
                put("U", i, 3L, "B", 4L - i, 1L)
                put("B", i, 1L, "D", 4L - i, 3L)
                put("D", i, 3L, "F", i, 3L)
            } else if (letter == "L") {
                put("U", i, 1L, "F", i, 1L)
                put("F", i, 1L, "D", i, 1L)
                put("D", i, 1L, "B", 4L - i, 3L)
                put("B", i, 3L, "U", 4L - i, 1L)
            } else if (letter == "F") {
                put("U", 3L, i, "R", i, 1L)
                put("R", i, 1L, "D", 1L, 4L - i)
                put("D", 1L, i, "L", i, 3L)
                put("L", i, 3L, "U", 3L, 4L - i)
            } else if (letter == "B") {
                put("U", 1L, i, "L", 4L - i, 1L)
                put("L", i, 1L, "D", 3L, i)
                put("D", 3L, i, "R", 4L - i, 3L)
                put("R", i, 3L, "U", 1L, i)
            } else if (letter == "M") {
                put("U", i, 2L, "F", i, 2L)
                put("F", i, 2L, "D", i, 2L)
                put("D", i, 2L, "B", 4L - i, 2L)
                put("B", i, 2L, "U", 4L - i, 2L)
            } else if (letter == "E") {
                from <- c("F", "R", "B", "L")
                to <- c("R", "B", "L", "F")
                for (j in 1:4) put(from[j], 2L, i, to[j], 2L, i)
            } else {
                put("U", 2L, i, "R", i, 2L)
                put("R", i, 2L, "D", 2L, 4L - i)
                put("D", 2L, i, "L", i, 2L)
                put("L", i, 2L, "U", 2L, 4L - i)
            }
        }
        powers(letter, p)
    }
    definitions <- list(r = c(move_code("R"), move_code("M", 3)), l = c(move_code("L"), move_code("M")),
                        u = c(move_code("U"), move_code("E", 3)), d = c(move_code("D"), move_code("E")),
                        f = c(move_code("F"), move_code("S")), b = c(move_code("B"), move_code("S", 3)),
                        x = c(move_code("R"), move_code("M", 3), move_code("L", 3)),
                        y = c(move_code("U"), move_code("E", 3), move_code("D", 3)), z = c(move_code("F"), move_code("S"), move_code("B", 3)))
    for (letter in names(definitions)) powers(letter, effect(definitions[[letter]]))
}
build_moves()
rotations <- list()
for (prefix in list(integer(), move_code("x"), move_code("x", 2), move_code("x", 3), move_code("z"), move_code("z", 3))) {
    for (suffix in list(integer(), move_code("y"), move_code("y", 2), move_code("y", 3))) rotations[[length(rotations) + 1]] <- c(prefix, suffix)
}
rotation_effects <- lapply(rotations, effect)
parse_stickers <- function(groups) lapply(strsplit(groups, ",", fixed = TRUE), function(words) {
    vapply(words, function(word) (match(substr(word, 1, 1), faces) - 1L) * 9L + as.integer(substr(word, 2, 2)), integer(1))
})
positions <- list(parse_stickers(c("U9,R1,F3", "U7,F1,L3", "U1,L1,B3", "U3,B1,R3", "D3,F9,R7", "D1,L9,F7", "D7,B9,L7", "D9,R9,B7")),
                  parse_stickers(c("U6,R2", "U8,F2", "U4,L2", "U2,B2", "D6,R8", "D2,F8", "D4,L8", "D8,B8", "F6,R4", "F4,L6", "B6,L4", "B4,R6")),
                  lapply(faces, function(face) index(face, 2L, 2L)))
piece_names <- list(corner_names, edge_names, faces)
piece_colors <- lapply(positions, function(positions) lapply(positions, function(stickers) solved_state[stickers]))
parse_sequence <- function(text, base, line_length) {
    position <- 1
    char <- function() if (position > nchar(text)) "" else substr(text, position, position)
    syntax <- function() fail(paste0("syntax at ", min(base + position, line_length + 1)))
    spaces <- function() while (char() == " ") position <<- position + 1
    power <- function(sequence) {
        count <- 1
        if (grepl("^[1-9]$", char())) {
            count <- as.integer(char())
            position <<- position + 1
            if (grepl("^[0-9]$", char())) {
                count <- 10 * count + as.integer(char())
                position <<- position + 1
            }
        }
        sequence <- rep(sequence, count)
        if (char() == "'") {
            position <<- position + 1
            sequence <- inverse(sequence)
        }
        sequence
    }
    read <- function() {
        output <- integer()
        repeat {
            spaces()
            c <- char()
            if (c %in% move_letters) {
                position <<- position + 1
                amount <- 1L
                if (char() %in% c("2", "'")) {
                    amount <- if (char() == "2") 2L else 3L
                    position <<- position + 1
                }
                output <- c(output, move_code(c, amount))
            } else if (c == "(") {
                position <<- position + 1
                sequence <- read()
                spaces()
                if (char() != ")") syntax()
                position <<- position + 1
                output <- c(output, power(sequence))
            } else if (c == "[") {
                position <<- position + 1
                a <- read()
                spaces()
                delimiter <- char()
                if (!(delimiter %in% c(",", ":"))) syntax()
                position <<- position + 1
                b <- read()
                spaces()
                if (char() != "]") syntax()
                position <<- position + 1
                sequence <- c(a, b, inverse(a))
                if (delimiter == ",") sequence <- c(sequence, inverse(b))
                output <- c(output, power(sequence))
            } else if (c == "{") {
                position <<- position + 1
                start <- position
                while (grepl("^[a-z]$", char())) position <<- position + 1
                name <- if (position > start) substr(text, start, position - 1) else ""
                if (name == "" || char() != "}") syntax()
                if (!(name %in% names(macros))) fail(paste0("undefined ", name))
                position <<- position + 1
                output <- c(output, power(macros[[name]]))
            } else break
        }
        output
    }
    sequence <- read()
    spaces()
    if (position <= nchar(text)) syntax()
    if (length(sequence) > 500) fail("too long")
    sequence
}
move_words <- function(sequence) {
    amounts <- move_amount(sequence)
    paste(paste0(move_letter(sequence), ifelse(amounts == 1, "", ifelse(amounts == 2, "2", "'"))), collapse = " ")
}
notation <- function(sequence) paste0(length(sequence), if (length(sequence)) paste0(" ", move_words(sequence)) else "")
axis <- function(letter) if (letter %in% strsplit("RLMrlx", "", fixed = TRUE)[[1]]) "x" else if (letter %in% strsplit("UDEudy", "", fixed = TRUE)[[1]]) "y" else "z"
simplify <- function(sequence) {
    repeat {
        output <- integer()
        position <- 1
        while (position <= length(sequence)) {
            current_axis <- axis(move_letter(sequence[position]))
            names <- character()
            amounts <- numeric()
            while (position <= length(sequence) && axis(move_letter(sequence[position])) == current_axis) {
                letter <- move_letter(sequence[position])
                if (!(letter %in% names)) {
                    names <- c(names, letter)
                    amounts[letter] <- 0
                }
                amounts[letter] <- (amounts[letter] + move_amount(sequence[position])) %% 4
                position <- position + 1
            }
            for (letter in names) if (amounts[letter] != 0) output <- c(output, move_code(letter, amounts[letter]))
        }
        if (identical(output, sequence)) return(output)
        sequence <- output
    }
}
is_solved <- function(state) all(vapply(0:5, function(face) all(state[face * 9L + 1:9] == state[face * 9L + 5L]), logical(1)))
normalize <- function(state) {
    for (i in seq_along(rotation_effects)) {
        rotated <- permute(state, rotation_effects[[i]])
        if (all(rotated[seq(5, 50, 9)] == colors)) return(list(rotation = i, state = rotated))
    }
    NULL
}
identify <- function(state, kind) {
    lapply(positions[[kind]], function(stickers) {
        colors <- state[stickers]
        found <- NULL
        for (piece in seq_along(piece_colors[[kind]])) {
            target <- piece_colors[[kind]][[piece]]
            for (twist in seq.int(0L, length(target) - 1L)) {
                rotated <- if (twist == 0) colors else c(colors[seq.int(twist + 1, length(colors))], colors[seq_len(twist)])
                if (identical(rotated, target)) found <- c(piece, twist)
            }
        }
        found
    })
}
invalid <- function(state) {
    if (length(state) != 54) return(paste0("length ", length(state)))
    bad <- which(!(state %in% colors))
    if (length(bad)) return(paste0("char ", bad[1]))
    for (color in colors) if (sum(state == color) != 9) return(paste0("count ", color, " ", sum(state == color)))
    normalized <- normalize(state)
    if (is.null(normalized)) return("centers")
    original <- list(identify(state, 1), identify(state, 2))
    for (kind in 1:2) {
        bad <- which(vapply(original[[kind]], is.null, logical(1)))
        if (length(bad)) return(paste0(if (kind == 1) "corner " else "edge ", piece_names[[kind]][bad[1]]))
    }
    for (kind in 1:2) for (piece in seq_along(piece_names[[kind]])) if (!any(vapply(original[[kind]], function(item) item[1] == piece, logical(1)))) return(paste0("missing ", piece_names[[kind]][piece]))
    corners <- identify(normalized$state, 1)
    edges <- identify(normalized$state, 2)
    if (sum(vapply(corners, function(item) item[2], integer(1))) %% 3 != 0) return("twist")
    if (sum(vapply(edges, function(item) item[2], integer(1))) %% 2 != 0) return("flip")
    parity <- function(pieces) {
        permutation <- vapply(pieces, function(item) item[1], integer(1))
        total <- 0
        for (i in seq_along(permutation)) if (i < length(permutation)) total <- total + sum(permutation[i] > permutation[seq.int(i + 1, length(permutation))])
        total %% 2
    }
    if (parity(corners) != parity(edges)) "parity" else NULL
}
cycles <- function(state, kind) {
    pieces <- identify(state, kind)
    destinations <- integer(length(pieces))
    orientations <- integer(length(pieces))
    for (i in seq_along(pieces)) {
        destinations[pieces[[i]][1]] <- i
        orientations[pieces[[i]][1]] <- pieces[[i]][2]
    }
    seen <- logical(length(pieces))
    output <- character()
    for (start in seq_along(pieces)) {
        if (seen[start]) next
        cycle <- integer()
        current <- start
        repeat {
            cycle <- c(cycle, current)
            seen[current] <- TRUE
            current <- destinations[current]
            if (current == start) break
        }
        sum <- sum(orientations[cycle])
        mark <- if (kind == 1) c("", "+", "-")[sum %% 3 + 1] else if (kind == 2 && sum %% 2 == 1) "+" else ""
        if (length(cycle) >= 2 || mark != "") output <- c(output, paste0("(", paste(piece_names[[kind]][cycle], collapse = " "), ")", mark))
    }
    if (length(output)) paste(output, collapse = " ") else "none"
}
sequence_order <- function(permutation) {
    seen <- logical(54)
    result <- 1
    for (start in seq_along(permutation)) {
        if (seen[start]) next
        current <- start
        length <- 0
        repeat {
            seen[current] <- TRUE
            length <- length + 1
            current <- permutation[current]
            if (current == start) break
        }
        a <- result
        b <- length
        while (b != 0) {
            remainder <- a %% b
            a <- b
            b <- remainder
        }
        result <- result / a * length
    }
    result
}
converted <- function(code, rotation) {
    inverse_rotation <- integer(54)
    inverse_rotation[rotation] <- identity
    target <- compose(compose(rotation, moves[[code]]), inverse_rotation)
    for (i in seq_along(moves)) if (identical(moves[[i]], target)) return(i)
    stop("No matching move")
}
unrotate <- function(sequence) {
    replacements <- list(M = c(move_code("R"), move_code("L", 3), move_code("x", 3)), E = c(move_code("U"), move_code("D", 3), move_code("y", 3)),
                         S = c(move_code("F", 3), move_code("B"), move_code("z")), r = c(move_code("L"), move_code("x")), l = c(move_code("R"), move_code("x", 3)),
                         u = c(move_code("D"), move_code("y")), d = c(move_code("U"), move_code("y", 3)), f = c(move_code("B"), move_code("z")), b = c(move_code("F"), move_code("z", 3)))
    expanded <- integer()
    for (code in sequence) {
        letter <- move_letter(code)
        if (letter %in% names(replacements)) {
            original <- replacements[[letter]]
            expanded <- c(expanded, move_code(move_letter(original), move_amount(original) * move_amount(code) %% 4))
        } else expanded <- c(expanded, code)
    }
    rotation <- identity
    output <- integer()
    for (code in expanded) {
        if (move_letter(code) %in% c("x", "y", "z")) rotation <- compose(rotation, moves[[code]])
        else output <- c(output, converted(code, rotation))
    }
    for (i in seq_along(rotation_effects)) if (identical(rotation_effects[[i]], rotation)) return(c(output, rotations[[i]]))
    stop("No matching rotation")
}
search <- function(depth) {
    candidates <- unlist(lapply(faces, function(face) move_code(face, 1:3)), use.names = FALSE)
    visit <- function(state, left, previous) {
        if (is_solved(state)) return(integer())
        if (left == 0) return(NULL)
        for (code in candidates) {
            face <- move_letter(code)
            if ((!is.null(previous) && face == previous) || (!is.null(previous) && paste0(previous, face) %in% c("DU", "LR", "BF"))) next
            tail <- visit(permute(state, moves[[code]]), left - 1, face)
            if (!is.null(tail)) return(c(code, tail))
        }
        NULL
    }
    for (limit in seq.int(0, depth)) {
        found <- visit(state, limit, NULL)
        if (!is.null(found)) return(found)
    }
    NULL
}
command <- function(line) {
    at <- regexpr(" ", line, fixed = TRUE)[1]
    name <- if (at < 0) line else substr(line, 1, at - 1)
    argument <- if (at < 0) NULL else substring(line, at + 1)
    tryCatch({
        if (!(name %in% c(no_arguments, names(word_commands), sequence_commands, head_commands))) fail(paste0("unknown command ", name))
        words <- if (is.null(argument)) character() else strsplit(argument, " ", fixed = TRUE)[[1]]
        if (name %in% no_arguments && !is.null(argument)) fail("bad arguments")
        if (name %in% names(word_commands) && length(words) != word_commands[name]) fail("bad arguments")
        if (name %in% c("UNDO", "REDO", "SEARCH", "SCRAMBLE") && !all(grepl("^(0|[1-9][0-9]{0,9})$", words))) fail("bad arguments")
        if (name %in% c("SAVE", "RESTORE") && !grepl("^[a-z]{1,8}$", words[1])) fail("bad arguments")
        sequence <- integer()
        if (name %in% head_commands) {
            if (is.null(argument)) fail("bad arguments")
            at <- regexpr(" ", argument, fixed = TRUE)[1]
            head <- if (at < 0) argument else substr(argument, 1, at - 1)
            text <- if (at < 0) "" else substring(argument, at + 1)
            valid <- switch(name, DEFINE = grepl("^[a-z]{1,8}$", head), MIRROR = head %in% c("LR", "UD", "FB"), ROTATE = grepl("^[xyz](2|')?$", head))
            if (!valid) fail("bad arguments")
            sequence <- parse_sequence(text, nchar(name) + nchar(head) + 2, nchar(line))
        } else if (name %in% sequence_commands) sequence <- parse_sequence(if (is.null(argument)) "" else argument, nchar(name) + 1, nchar(line))
        if (name %in% c("UNDO", "REDO") && as.numeric(words[1]) < 1) fail("bad value")
        if (name == "SEARCH" && as.numeric(words[1]) > 4) fail("bad value")
        if (name == "SCRAMBLE" && (as.numeric(words[1]) < 1 || as.numeric(words[1]) > 50 || as.numeric(words[2]) < 1 || as.numeric(words[2]) > 2147483646)) fail("bad value")
        if (name == "WHERE" && !(words[1] %in% c(corner_names, edge_names))) fail(paste0("unknown piece ", words[1]))
        if (name == "RESET") {
            state <<- solved_state
            history <<- integer()
            redo <<- integer()
            emit("reset")
        } else if (name == "SHOW") {
            for (side in c("U", "LFRB", "D")) for (row in 1:3) {
                stickers <- unlist(lapply(strsplit(side, "", fixed = TRUE)[[1]], function(face) state[vapply(1:3, function(col) index(face, row, col), integer(1))]), use.names = FALSE)
                emit(if (nchar(side) == 1) "      " else "", paste(stickers, collapse = " "))
            }
        } else if (name == "STATE") emit("state ", paste(state, collapse = ""))
        else if (name == "ISSOLVED") {
            count <- sum(state != rep(state[seq(5, 50, 9)], each = 9))
            emit(if (count == 0) "solved" else paste0("unsolved ", count))
        } else if (name == "HISTORY") emit("history ", notation(history))
        else if (name == "SOLUTION") emit("solution ", notation(simplify(inverse(history))))
        else if (name == "ANALYZE") {
            normalized <- normalize(state)
            emit("rotation ", if (normalized$rotation == 1) "none" else move_words(rotations[[normalized$rotation]]))
            emit("corners ", cycles(normalized$state, 1))
            emit("edges ", cycles(normalized$state, 2))
        } else if (name == "STAGE") {
            normalized <- normalize(state)$state
            corners <- identify(normalized, 1)
            edges <- identify(normalized, 2)
            cross <- sum(vapply(5:8, function(i) all(edges[[i]] == c(i, 0)), logical(1)))
            slots <- sum(vapply(5:8, function(i) all(corners[[i]] == c(i, 0)) && all(edges[[i + 4]] == c(i + 4, 0)), logical(1)))
            top <- sum(normalized[1:9] == "W")
            stage <- if (is_solved(normalized)) "solved" else if (cross == 4 && slots == 4 && top == 9) "oll" else if (cross == 4 && slots == 4) "f2l" else if (cross == 4) "cross" else "none"
            emit("stage ", stage, " cross ", cross, " slots ", slots, " top ", top)
        } else if (name == "MACROS") {
            emit("macros ", length(macros))
            for (key in sort(names(macros), method = "radix")) emit("macro ", key, " ", notation(macros[[key]]))
        } else if (name %in% c("CHECK", "LOAD")) {
            new_state <- strsplit(words[1], "", fixed = TRUE)[[1]]
            reason <- invalid(new_state)
            if (name == "CHECK") emit(if (is.null(reason)) "valid" else paste0("invalid ", reason))
            else {
                if (!is.null(reason)) fail(paste0("invalid ", reason))
                state <<- new_state
                history <<- integer()
                redo <<- integer()
                emit("loaded")
            }
        } else if (name %in% c("UNDO", "REDO")) {
            source <- if (name == "UNDO") history else redo
            if (!length(source)) fail(if (name == "UNDO") "nothing to undo" else "nothing to redo")
            count <- min(as.numeric(words[1]), length(source))
            for (i in seq_len(count)) {
                if (name == "UNDO") {
                    code <- tail(history, 1)
                    history <<- head(history, -1)
                    state <<- permute(state, moves[[inverse(code)]])
                    redo <<- c(redo, code)
                } else {
                    code <- tail(redo, 1)
                    redo <<- head(redo, -1)
                    state <<- permute(state, moves[[code]])
                    history <<- c(history, code)
                }
            }
            emit(if (name == "UNDO") "undone " else "redone ", count)
        } else if (name == "SEARCH") {
            found <- search(as.numeric(words[1]))
            emit(if (is.null(found)) "not found" else paste0("found ", notation(found)))
        } else if (name == "WHERE") {
            normalized <- normalize(state)$state
            kind <- if (words[1] %in% corner_names) 1 else 2
            wanted <- match(words[1], piece_names[[kind]])
            pieces <- identify(normalized, kind)
            position <- which(vapply(pieces, function(piece) piece[1] == wanted, logical(1)))[1]
            emit(words[1], " at ", piece_names[[kind]][position], if (kind == 1) " twist " else " flip ", pieces[[position]][2])
        } else if (name == "SAVE") {
            saves[[words[1]]] <<- list(state = state, history = history)
            emit("saved ", words[1])
        } else if (name == "RESTORE") {
            if (!(words[1] %in% names(saves))) fail(paste0("no save ", words[1]))
            state <<- saves[[words[1]]]$state
            history <<- saves[[words[1]]]$history
            redo <<- integer()
            emit("restored ", words[1])
        } else if (name %in% c("SCRAMBLE", "APPLY")) {
            if (name == "SCRAMBLE") {
                sequence <- integer()
                random <- as.numeric(words[2])
                for (i in seq_len(as.numeric(words[1]))) {
                    usable <- Filter(function(face) {
                        n <- length(sequence)
                        !(n >= 1 && face == move_letter(sequence[n])) && !(n >= 2 && axis(move_letter(sequence[n])) == axis(move_letter(sequence[n - 1])) && axis(face) == axis(move_letter(sequence[n])))
                    }, faces)
                    random <- random * 48271 %% 2147483647
                    face <- usable[random %% length(usable) + 1]
                    random <- random * 48271 %% 2147483647
                    sequence <- c(sequence, move_code(face, c(1L, 3L, 2L)[random %% 3 + 1]))
                }
            }
            state <<- permute(state, effect(sequence))
            history <<- c(history, sequence)
            redo <<- integer()
            emit(if (name == "APPLY") paste0("applied ", length(sequence)) else paste0("scramble ", move_words(sequence)))
        } else if (name == "INVERT") emit("inverse ", notation(inverse(sequence)))
        else if (name == "SIMPLIFY") emit("simplified ", notation(simplify(sequence)))
        else if (name == "METRICS") {
            htm <- 0
            qtm <- 0
            stm <- 0
            for (code in sequence) {
                letter <- move_letter(code)
                if (letter %in% c("x", "y", "z")) next
                weight <- if (letter %in% c("M", "E", "S")) 2 else 1
                htm <- htm + weight
                qtm <- qtm + weight * if (move_amount(code) == 2) 2 else 1
                stm <- stm + 1
            }
            emit("metrics htm ", htm, " qtm ", qtm, " stm ", stm, " etm ", length(sequence))
        } else if (name == "ORDER") emit("order ", sprintf("%.0f", sequence_order(effect(sequence))))
        else if (name == "CYCLES") {
            generated <- permute(solved_state, effect(sequence))
            for (kind in 1:3) emit(c("corners", "edges", "centers")[kind], " ", cycles(generated, kind))
        } else if (name == "UNROTATE") emit("unrotated ", notation(unrotate(sequence)))
        else if (name == "UNTIL") {
            permutation <- effect(sequence)
            generated <- state
            found <- NULL
            for (count in seq_len(sequence_order(permutation))) {
                generated <- permute(generated, permutation)
                if (is_solved(generated)) {
                    found <- count
                    break
                }
            }
            emit("until ", if (is.null(found)) "never" else found)
        } else if (name == "DEFINE") {
            macros[head] <<- list(sequence)
            emit("defined ", head, " ", length(sequence))
        } else if (name == "MIRROR") {
            mirror_axis <- c(LR = "x", UD = "y", FB = "z")[[head]]
            transformed <- vapply(sequence, function(code) {
                letter <- move_letter(code)
                amount <- move_amount(code)
                if (axis(letter) != mirror_axis) return(move_code(letter, 4 - amount))
                if (letter %in% c("M", "E", "S", "x", "y", "z")) return(code)
                move_code(chartr("RLUDFBrludfb", "LRDUBFlrdubf", letter), 4 - amount)
            }, integer(1))
            emit("mirror ", notation(transformed))
        } else if (name == "ROTATE") {
            amount <- if (nchar(head) == 1) 1 else if (substr(head, 2, 2) == "2") 2 else 3
            rotation <- moves[[move_code(substr(head, 1, 1), amount)]]
            emit("rotated ", notation(vapply(sequence, converted, integer(1), rotation = rotation)))
        }
    }, cube_error = function(e) emit(e$message))
}
input <- readLines(file("stdin"), warn = FALSE)
for (i in seq_len(as.integer(input[1]))) command(input[i + 1])
