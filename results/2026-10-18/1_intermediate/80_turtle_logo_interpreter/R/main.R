options(scipen = 999)
emit <- function(...) cat(paste0(...), "\n", sep = "")
logo_error <- function(line, reason, calls = character()) {
    stop(structure(list(message = reason, call = NULL, line = line, calls = calls), class = c("logo_error", "error", "condition")))
}
logo_return <- function(value) {
    stop(structure(list(message = "", call = NULL, value = value), class = c("logo_return", "error", "condition")))
}
commands <- list(
    FD = c("FD", "E"), FORWARD = c("FD", "E"), BK = c("BK", "E"), BACK = c("BK", "E"),
    RT = c("RT", "E"), RIGHT = c("RT", "E"), LT = c("LT", "E"), LEFT = c("LT", "E"),
    SETH = c("SETH", "E"), SETHEADING = c("SETH", "E"),
    PU = c("PU", ""), PENUP = c("PU", ""), PD = c("PD", ""), PENDOWN = c("PD", ""),
    PE = c("PE", ""), PENERASE = c("PE", ""), SETPEN = c("SETPEN", "E"),
    SETXY = c("SETXY", "EE"), SETX = c("SETX", "E"), SETY = c("SETY", "E"),
    HOME = c("HOME", ""), CS = c("CS", ""), CLEARSCREEN = c("CS", ""),
    CLEAN = c("CLEAN", ""), FILL = c("FILL", ""), LABEL = c("LABEL", "P"), SNAPSHOT = c("SNAPSHOT", ""),
    REPEAT = c("REPEAT", "EL"), FOR = c("FOR", "QEEL"), WHILE = c("WHILE", "EL"),
    IF = c("IF", "EL"), IFELSE = c("IFELSE", "ELL"), TEST = c("TEST", "E"),
    IFTRUE = c("IFTRUE", "L"), IFT = c("IFTRUE", "L"), IFFALSE = c("IFFALSE", "L"), IFF = c("IFFALSE", "L"),
    STOP = c("STOP", ""), OUTPUT = c("OUTPUT", "E"), OP = c("OUTPUT", "E"), MAKE = c("MAKE", "QE"),
    LOCAL = c("LOCAL", "Q"), LOCALMAKE = c("LOCALMAKE", "QE"), TRACE = c("TRACE", "Q"),
    UNTRACE = c("UNTRACE", "Q"), SEED = c("SEED", "E"), PRINT = c("PRINT", "P"), PR = c("PRINT", "P")
)
functions <- c(XCOR = 0L, YCOR = 0L, HEADING = 0L, REPCOUNT = 0L, RANDOM = 1L, ABS = 1L, NOT = 1L, AND = 2L, OR = 2L, MAX = 2L, MIN = 2L)
primitive <- function(name) name %in% c(names(commands), names(functions), "TO", "END", "MOD")
new_token <- function(kind, text, line, sign = FALSE) structure(list(kind = kind, text = text, line = line, sign = sign), class = "logo_token")
lex <- function(line, number) {
    semicolon <- regexpr(";", line, fixed = TRUE)[1]
    if (semicolon > 0) line <- substr(line, 1, semicolon - 1L)
    text <- chartr("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", line)
    chars <- strsplit(text, "", fixed = TRUE)[[1]]
    result <- list()
    i <- 1L
    delimiters <- c(" ", "[", "]", "(", ")", "+", "-", "*", "/", "=", "<", ">")
    while (i <= length(chars)) {
        char <- chars[i]
        if (char == " ") {
            i <- i + 1L
        } else if (char %in% delimiters[-1]) {
            next_char <- if (i < length(chars)) chars[i + 1L] else ""
            spelling <- char
            if ((char == "<" && next_char %in% c("=", ">")) || (char == ">" && next_char == "=")) spelling <- paste0(spelling, next_char)
            sign <- char == "-" && (i == 1L || chars[i - 1L] %in% c(" ", "[", "(")) && nzchar(next_char) && next_char != " "
            result[[length(result) + 1L]] <- new_token("symbol", spelling, number, sign)
            i <- i + nchar(spelling)
        } else {
            start <- i
            while (i <= length(chars) && !(chars[i] %in% delimiters)) i <- i + 1L
            spelling <- paste(chars[seq.int(start, i - 1L)], collapse = "")
            kind <- if (grepl("\\A[0-9]+\\z", spelling, perl = TRUE)) "number" else if (grepl("\\A:[A-Z][A-Z0-9_]*\\z", spelling, perl = TRUE)) "variable" else if (grepl("\\A\"[A-Z][A-Z0-9_]*\\z", spelling, perl = TRUE)) "quote" else if (grepl("\\A[A-Z][A-Z0-9_]*\\z", spelling, perl = TRUE)) "word" else NULL
            if (is.null(kind)) logo_error(number, paste0("bad token '", spelling, "'"))
            result[[length(result) + 1L]] <- new_token(kind, spelling, number)
        }
    }
    result
}

parse <- function(tokens, procedures, top) {
    index <- 1L
    peek <- function() if (index <= length(tokens)) tokens[[index]] else NULL
    read <- function() {
        token <- tokens[[index]]
        index <<- index + 1L
        token
    }
    error <- function(token, reason) logo_error(token$line, reason)
    unknown <- function(token) token$kind == "word" && !primitive(token$text) && is.null(procedures[[token$text]])
    need <- function(owner) {
        token <- peek()
        if (is.null(token) || token$text %in% c("]", ")")) error(owner, paste0("not enough inputs to ", owner$text))
        if (unknown(token)) error(token, paste0("I don't know how to ", token$text))
        token
    }
    read_input <- function(kind, owner) {
        token <- need(owner)
        if (kind == "L") {
            if (token$text != "[") error(token, paste0(owner$text, " doesn't like ", token$text, " as input"))
            opening <- read()
            result <- list()
            repeat {
                if (is.null(peek())) error(opening, "missing ]")
                if (peek()$text == "]") break
                result[[length(result) + 1L]] <- command()
            }
            read()
            return(result)
        }
        if (kind == "Q") {
            if (token$kind != "quote") error(token, paste0(owner$text, " doesn't like ", token$text, " as input"))
            return(read())
        }
        if (kind == "P" && token$kind == "quote") return(list(kind = "quote", value = substring(read()$text, 2)))
        expression(owner)
    }
    expressions <- function(count, owner) lapply(seq_len(count), function(i) expression(owner))
    command <- function() {
        token <- read()
        if (token$text == "]") error(token, "unexpected ]")
        if (token$text == "(" && !is.null(peek()) && peek()$text %in% c("PRINT", "PR")) {
            owner <- read()
            args <- list()
            repeat {
                if (is.null(peek()) || peek()$text == "]") error(token, "missing )")
                if (peek()$text == ")") break
                args[[length(args) + 1L]] <- read_input("P", owner)
            }
            read()
            return(list(name = "MULTIPRINT", token = owner, args = args))
        }
        if (token$kind == "word" && token$text %in% c("TO", "END")) error(token, paste0("misplaced ", token$text))
        if (token$kind == "word" && token$text %in% names(commands)) {
            name <- commands[[token$text]][1]
            if (top && token$text %in% c("STOP", "OUTPUT", "OP", "LOCAL", "LOCALMAKE")) error(token, paste0("can only use ", token$text, " inside a procedure"))
            kinds <- strsplit(commands[[token$text]][2], "", fixed = TRUE)[[1]]
            args <- lapply(kinds, function(kind) read_input(kind, token))
            if (name %in% c("TRACE", "UNTRACE") && is.null(procedures[[substring(args[[1]]$text, 2)]])) error(args[[1]], paste0("I don't know how to ", substring(args[[1]]$text, 2)))
            return(list(name = name, token = token, args = args))
        }
        if (token$kind == "word" && !is.null(procedures[[token$text]])) return(list(name = "call", token = token, args = expressions(length(procedures[[token$text]]$parameters), token)))
        if (unknown(token)) error(token, paste0("I don't know how to ", token$text))
        error(token, paste0("you don't say what to do with ", token$text))
    }
    binary <- function(owner, lower, operators) {
        left <- lower(owner)
        repeat {
            next_token <- peek()
            if (is.null(next_token) || !(next_token$text %in% operators) || (next_token$text == "-" && next_token$sign)) break
            operator <- read()
            right <- lower(operator)
            left <- list(kind = "binary", token = operator, left = left, right = right)
        }
        left
    }
    expression <- function(owner) binary(owner, parse_sum, c("=", "<>", "<", ">", "<=", ">="))
    parse_sum <- function(owner) binary(owner, product, c("+", "-"))
    product <- function(owner) binary(owner, term, c("*", "/", "MOD"))
    term <- function(owner) {
        token <- need(owner)
        read()
        if (token$kind == "number") return(list(kind = "number", value = as.numeric(token$text)))
        if (token$kind == "variable") return(list(kind = "variable", token = token))
        if (token$text == "-") return(list(kind = "unary", value = term(token)))
        if (token$text == "(") {
            value <- expression(token)
            if (is.null(peek()) || peek()$text != ")") error(token, "missing )")
            read()
            return(value)
        }
        if (token$kind == "word" && token$text %in% names(functions)) return(list(kind = "function", token = token, args = expressions(functions[[token$text]], token)))
        if (token$kind == "word" && !is.null(procedures[[token$text]])) return(list(kind = "call", token = token, args = expressions(length(procedures[[token$text]]$parameters), token)))
        error(token, paste0(owner$text, " doesn't like ", token$text, " as input"))
    }
    result <- list()
    while (!is.null(peek())) result[[length(result) + 1L]] <- command()
    result
}

new_environment <- function(variables = list()) {
    environment <- new.env(parent = emptyenv())
    environment$variables <- variables
    environment$test <- NULL
    environment
}
make_turtle <- function(procedures) {
    state <- new.env(parent = emptyenv())
    state$x <- state$y <- state$heading <- 0
    state$pen <- "DOWN"
    state$character <- "*"
    state$canvas <- new.env(hash = TRUE, parent = emptyenv())
    state$environments <- list(new_environment())
    state$calls <- character()
    state$repetitions <- numeric()
    state$traced <- character()
    state$random <- 1
    directions <- list(c(0, 1), c(1, 1), c(1, 0), c(1, -1), c(0, -1), c(-1, -1), c(-1, 0), c(-1, 1))
    error <- function(token, reason) logo_error(token$line, reason, state$calls)
    value <- function(node) {
        kind <- node$kind
        if (kind %in% c("number", "quote")) return(node$value)
        if (kind == "variable") {
            name <- substring(node$token$text, 2)
            for (i in rev(seq_along(state$environments))) {
                result <- state$environments[[i]]$variables[[name]]
                if (!is.null(result)) return(result)
            }
            error(node$token, paste0(name, " has no value"))
        }
        if (kind == "unary") return(-value(node$value))
        if (kind == "binary") {
            a <- value(node$left)
            b <- value(node$right)
            operator <- node$token$text
            if (operator %in% c("/", "MOD") && b == 0) error(node$token, paste0(operator, " doesn't like 0 as input"))
            return(switch(operator,
                "+" = a + b, "-" = a - b, "*" = a * b, "/" = trunc(a / b), MOD = a - b * trunc(a / b),
                "=" = as.numeric(a == b), "<>" = as.numeric(a != b), "<" = as.numeric(a < b),
                ">" = as.numeric(a > b), "<=" = as.numeric(a <= b), ">=" = as.numeric(a >= b)))
        }
        if (kind == "call") {
            result <- call(node$token, node$args)
            if (is.null(result)) error(node$token, paste0(node$token$text, " did not output"))
            return(result)
        }
        args <- lapply(node$args, value)
        token <- node$token
        a <- if (length(args) >= 1) args[[1]] else NULL
        b <- if (length(args) >= 2) args[[2]] else NULL
        if (token$text == "XCOR") return(state$x)
        if (token$text == "YCOR") return(state$y)
        if (token$text == "HEADING") return(state$heading)
        if (token$text == "REPCOUNT") {
            if (length(state$repetitions) == 0) error(token, "REPCOUNT outside REPEAT")
            return(tail(state$repetitions, 1))
        }
        if (token$text == "RANDOM") {
            if (a <= 0) error(token, paste0("RANDOM doesn't like ", a, " as input"))
            state$random <- 48271 * state$random %% 2147483647
            return(state$random %% a)
        }
        if (token$text == "ABS") return(abs(a))
        if (token$text == "NOT") return(as.numeric(a == 0))
        if (token$text == "AND") return(as.numeric(a != 0 && b != 0))
        if (token$text == "OR") return(as.numeric(a != 0 || b != 0))
        if (token$text == "MAX") return(max(a, b))
        if (token$text == "MIN") return(min(a, b))
    }
    call <- function(token, arguments) {
        inputs <- lapply(arguments, value)
        if (length(state$calls) == 100) error(token, "recursion too deep")
        procedure <- procedures[[token$text]]
        traced <- token$text %in% state$traced
        indent <- paste(rep("  ", length(state$calls)), collapse = "")
        if (traced) emit(indent, "( ", paste(c(token$text, unlist(inputs, use.names = FALSE)), collapse = " "), " )")
        state$calls <- c(state$calls, token$text)
        variables <- setNames(inputs, procedure$parameters)
        state$environments[[length(state$environments) + 1L]] <- new_environment(variables)
        result <- tryCatch({
            execute(procedure$body)
            NULL
        }, logo_return = function(signal) signal$value, finally = {
            state$environments <- head(state$environments, -1L)
            state$calls <- head(state$calls, -1L)
        })
        if (traced) emit(indent, token$text, if (is.null(result)) " stops" else paste0(" outputs ", result))
        result
    }
    make <- function(name, number) {
        if (length(state$environments) >= 2) {
            for (i in seq.int(length(state$environments), 2L)) {
                environment <- state$environments[[i]]
                if (!is.null(environment$variables[[name]])) {
                    environment$variables[[name]] <- number
                    return(invisible(NULL))
                }
            }
        }
        state$environments[[1]]$variables[[name]] <- number
    }
    key <- function(x, y) paste(x, y, sep = ",")
    marked <- function(x, y) exists(key(x, y), envir = state$canvas, inherits = FALSE)
    mark <- function(x, y, character) assign(key(x, y), character, envir = state$canvas)
    apply_pen <- function(x, y) {
        if (state$pen == "DOWN") {
            mark(x, y, state$character)
        } else if (state$pen == "ERASE" && marked(x, y)) {
            rm(list = key(x, y), envir = state$canvas)
        }
    }
    move <- function(number) {
        direction <- directions[[state$heading %/% 45 + 1L]]
        if (number < 0) direction <- -direction
        apply_pen(state$x, state$y)
        for (i in seq_len(abs(number))) {
            state$x <- state$x + direction[1]
            state$y <- state$y + direction[2]
            apply_pen(state$x, state$y)
        }
    }
    move_to <- function(x, y) {
        dx <- x - state$x
        dy <- y - state$y
        steps <- max(abs(dx), abs(dy))
        if (steps == 0) {
            apply_pen(state$x, state$y)
        } else {
            for (i in 0:steps) apply_pen(state$x + floor((2 * i * dx + steps) / (2 * steps)), state$y + floor((2 * i * dy + steps) / (2 * steps)))
        }
        state$x <- x
        state$y <- y
    }
    canvas_bounds <- function() {
        names <- ls(envir = state$canvas, all.names = TRUE)
        points <- do.call(rbind, lapply(names, function(name) as.numeric(strsplit(name, ",", fixed = TRUE)[[1]])))
        c(min(points[, 1]), min(points[, 2]), max(points[, 1]), max(points[, 2]))
    }
    fill <- function() {
        if (length(ls(envir = state$canvas, all.names = TRUE)) == 0 || marked(state$x, state$y)) return(invisible(NULL))
        box <- canvas_bounds()
        if (state$x < box[1] || state$x > box[3] || state$y < box[2] || state$y > box[4]) return(invisible(NULL))
        queue <- list(c(state$x, state$y))
        mark(state$x, state$y, state$character)
        head <- 1L
        while (head <= length(queue)) {
            current <- queue[[head]]
            x <- current[1]
            y <- current[2]
            head <- head + 1L
            for (point in list(c(x - 1, y), c(x + 1, y), c(x, y - 1), c(x, y + 1))) {
                a <- point[1]
                b <- point[2]
                if (a < box[1] || a > box[3] || b < box[2] || b > box[4] || marked(a, b)) next
                mark(a, b, state$character)
                queue[[length(queue) + 1L]] <- point
            }
        }
        invisible(NULL)
    }
    snapshot <- function() {
        count <- length(ls(envir = state$canvas, all.names = TRUE))
        if (count == 0) {
            emit("CANVAS 0 0 0")
            return(invisible(NULL))
        }
        box <- canvas_bounds()
        emit("CANVAS ", box[3] - box[1] + 1, " ", box[4] - box[2] + 1, " ", count)
        for (y in seq.int(box[4], box[2])) {
            row <- vapply(seq.int(box[1], box[3]), function(x) get0(key(x, y), envir = state$canvas, inherits = FALSE, ifnotfound = " "), character(1))
            emit(sub(" +\\z", "", paste(row, collapse = ""), perl = TRUE))
        }
    }
    repeat_body <- function(number, body) {
        state$repetitions <- c(state$repetitions, number)
        on.exit(state$repetitions <- head(state$repetitions, -1L))
        execute(body)
    }
    execute <- function(sequence) {
        for (command in sequence) {
            token <- command$token
            args <- command$args
            name <- command$name
            if (name == "call") {
                result <- call(token, args)
                if (!is.null(result)) error(token, paste0("you don't say what to do with ", result))
                next
            }
            if (name == "WHILE") {
                while (value(args[[1]]) != 0) execute(args[[2]])
                next
            }
            values <- lapply(args, function(arg) {
                if (inherits(arg, "logo_token")) substring(arg$text, 2) else if (is.null(arg$kind)) arg else value(arg)
            })
            a <- if (length(values) >= 1) values[[1]] else NULL
            b <- if (length(values) >= 2) values[[2]] else NULL
            c <- if (length(values) >= 3) values[[3]] else NULL
            d <- if (length(values) >= 4) values[[4]] else NULL
            if (name == "FD") move(a)
            if (name == "BK") move(-a)
            if (name %in% c("RT", "LT", "SETH")) {
                if (a %% 45 != 0) error(token, paste0(token$text, " doesn't like ", a, " as input"))
                heading <- if (name == "SETH") a else state$heading + if (name == "LT") -a else a
                state$heading <- heading %% 360
            }
            if (name == "PU") state$pen <- "UP"
            if (name == "PD") state$pen <- "DOWN"
            if (name == "PE") state$pen <- "ERASE"
            if (name == "SETPEN") {
                if (a < 33 || a > 126) error(token, paste0("SETPEN doesn't like ", a, " as input"))
                state$character <- rawToChar(as.raw(a))
            }
            if (name == "SETXY") move_to(a, b)
            if (name == "SETX") move_to(a, state$y)
            if (name == "SETY") move_to(state$x, a)
            if (name == "HOME") {
                move_to(0, 0)
                state$heading <- 0
            }
            if (name == "CS") {
                state$canvas <- new.env(hash = TRUE, parent = emptyenv())
                state$x <- state$y <- state$heading <- 0
            }
            if (name == "CLEAN") state$canvas <- new.env(hash = TRUE, parent = emptyenv())
            if (name == "FILL") fill()
            if (name == "LABEL") {
                direction <- directions[[state$heading %/% 45 + 1L]]
                chars <- strsplit(as.character(a), "", fixed = TRUE)[[1]]
                for (i in seq_along(chars)) mark(state$x + (i - 1L) * direction[1], state$y + (i - 1L) * direction[2], chars[i])
            }
            if (name == "SNAPSHOT") snapshot()
            if (name == "REPEAT" && a > 0 && length(b) > 0L) {
                i <- 1
                while (i <= a) {
                    repeat_body(i, b)
                    i <- i + 1
                }
            }
            if (name == "FOR") {
                if (length(d) == 0L) {
                    make(a, c)
                } else {
                    step <- if (b <= c) 1 else -1
                    number <- b
                    repeat {
                        make(a, number)
                        execute(d)
                        if (number == c) break
                        number <- number + step
                    }
                }
            }
            if (name == "IF" && a != 0) execute(b)
            if (name == "IFELSE") execute(if (a == 0) c else b)
            if (name == "TEST") state$environments[[length(state$environments)]]$test <- a != 0
            if (name %in% c("IFTRUE", "IFFALSE")) {
                test <- state$environments[[length(state$environments)]]$test
                if (is.null(test)) error(token, paste0(token$text, " without TEST"))
                if (test == (name == "IFTRUE")) execute(a)
            }
            if (name == "STOP") logo_return(NULL)
            if (name == "OUTPUT") logo_return(a)
            if (name == "MAKE") make(a, b)
            if (name == "LOCAL") state$environments[[length(state$environments)]]$variables[[a]] <- 0
            if (name == "LOCALMAKE") state$environments[[length(state$environments)]]$variables[[a]] <- b
            if (name == "TRACE") state$traced <- unique(c(state$traced, a))
            if (name == "UNTRACE") state$traced <- state$traced[state$traced != a]
            if (name == "SEED") {
                if (a <= 0) error(token, paste0("SEED doesn't like ", a, " as input"))
                state$random <- a
            }
            if (name == "PRINT") emit(a)
            if (name == "MULTIPRINT") emit(paste(unlist(values, use.names = FALSE), collapse = " "))
        }
        invisible(NULL)
    }
    finish <- function() {
        emit("TURTLE ", state$x, " ", state$y, " ", state$heading, " ", state$pen, " ", state$character)
        snapshot()
    }
    list(execute = execute, finish = finish)
}

run_program <- function(name, source) {
    emit("PROGRAM ", name)
    tryCatch({
        procedures <- list()
        top <- list()
        current <- NULL
        for (line in source) {
            number <- line$number
            tokens <- lex(line$text, number)
            if (length(tokens) == 0) next
            if (tokens[[1]]$kind == "word" && tokens[[1]]$text == "TO") {
                if (!is.null(current)) logo_error(number, paste0("TO inside definition of ", current$name))
                if (length(tokens) < 2 || tokens[[2]]$kind != "word") logo_error(number, "bad procedure header")
                procedure_name <- tokens[[2]]$text
                if (primitive(procedure_name)) logo_error(number, paste0(procedure_name, " is a primitive"))
                if (!is.null(procedures[[procedure_name]])) logo_error(number, paste0(procedure_name, " is already defined"))
                parameters <- character()
                for (token in tail(tokens, -2L)) {
                    if (token$kind != "variable") logo_error(number, "bad procedure header")
                    parameter <- substring(token$text, 2)
                    if (parameter %in% parameters) logo_error(number, paste0("duplicate input ", token$text))
                    parameters <- c(parameters, parameter)
                }
                current <- new.env(parent = emptyenv())
                current$name <- procedure_name
                current$parameters <- parameters
                current$line <- number
                current$tokens <- list()
                procedures[[procedure_name]] <- current
            } else if (length(tokens) == 1 && tokens[[1]]$kind == "word" && tokens[[1]]$text == "END") {
                if (is.null(current)) logo_error(number, "END without TO")
                current <- NULL
            } else if (is.null(current)) {
                top <- c(top, tokens)
            } else {
                current$tokens <- c(current$tokens, tokens)
            }
        }
        if (!is.null(current)) logo_error(current$line, paste0("missing END for ", current$name))
        for (procedure in procedures) procedure$body <- parse(procedure$tokens, procedures, FALSE)
        body <- parse(top, procedures, TRUE)
        turtle <- make_turtle(procedures)
        turtle$execute(body)
        turtle$finish()
    }, logo_error = function(error) {
        emit("ERROR line ", error$line, ": ", conditionMessage(error))
        calls <- rev(error$calls)
        i <- 1L
        while (i <= length(calls)) {
            procedure <- calls[i]
            count <- 0L
            while (i <= length(calls) && calls[i] == procedure) {
                count <- count + 1L
                i <- i + 1L
            }
            emit("  in ", procedure, if (count >= 2) paste0(" x", count) else "")
        }
    })
}

input <- readLines(file("stdin"), warn = FALSE)
programs <- list()
for (i in seq_along(input)) {
    line <- input[i]
    if (line == "#EOF") break
    if (startsWith(line, "#PROGRAM ")) {
        programs[[length(programs) + 1L]] <- list(name = substring(line, 10), source = list())
    } else {
        index <- length(programs)
        programs[[index]]$source[[length(programs[[index]]$source) + 1L]] <- list(text = line, number = i)
    }
}
for (program in programs) run_program(program$name, program$source)
