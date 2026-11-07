source("lexer.R")
source("parser.R")
source("values_fields.R")
source("builtins.R")
source("streams.R")

SPECIAL_NAMES <- c("FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP")
new_table <- function() new.env(hash = TRUE, parent = emptyenv())
static_issue <- function(position, message) {
    stop(structure(list(message = message, position = position), class = c("static_issue", "error", "condition")))
}
transfer <- function(kind, value = UNINITIALIZED) {
    stop(structure(list(message = kind, kind = kind, value = value), class = c("awk_transfer", "error", "condition")))
}
new_analysis <- function(items) {
    analysis <- record(items = items, functions = Filter(function(item) item$kind == "function", items),
        rules = Filter(function(item) item$kind == "rule", items), function_table = new_table(),
        global_names = new_table(), bindings = new_table(), array_names = new_table(), statement_lines = new_table(),
        nodes = list(), errors = list())
    for (name in SPECIAL_NAMES) {
        analysis$global_names[[name]] <- TRUE
        analysis$bindings[[paste0("0:", name)]] <- list(scope = 0L, name = name, key = paste0("0:", name))
    }
    analysis
}
static_error <- function(analysis, position, priority, message) {
    analysis$errors[[length(analysis$errors) + 1L]] <- list(position = position, priority = priority, message = message)
}
resolve_name <- function(analysis, node, function_node) {
    local_name <- !is.null(function_node) && node$name %in% function_node$parameter_names
    scope <- if (local_name) function_node$function_id else 0L
    key <- paste0(scope, ":", node$name)
    node$binding <- list(scope = scope, name = node$name, key = key)
    analysis$bindings[[key]] <- node$binding
    if (!local_name) analysis$global_names[[node$name]] <- TRUE
    if (exists(node$name, analysis$function_table, inherits = FALSE)) {
        static_error(analysis, node$position, 3L, paste("function", node$name, "used as variable"))
    }
}
prepare <- function(analysis) {
    for (identifier in seq_along(analysis$functions)) {
        function_node <- analysis$functions[[identifier]]
        function_node$function_id <- identifier
        if (exists(function_node$name, analysis$function_table, inherits = FALSE)) {
            static_error(analysis, function_node$name_position, 1L, paste("function", function_node$name, "redefined"))
        } else analysis$function_table[[function_node$name]] <- function_node
        names <- character()
        for (parameter in function_node$parameters) {
            if (parameter$name %in% names) static_error(analysis, parameter$position, 2L, paste("duplicate parameter", parameter$name))
            names <- union(names, parameter$name)
        }
        function_node$parameter_names <- names
    }
    for (item in analysis$items) {
        function_node <- if (item$kind == "function") item else NULL
        pending <- list(item)
        while (length(pending)) {
            node <- pending[[length(pending)]]
            pending[[length(pending)]] <- NULL
            analysis$nodes[[length(analysis$nodes) + 1L]] <- node
            if (node$kind %in% STATEMENTS) analysis$statement_lines[[as.character(node$position[1L])]] <- TRUE
            if (node$kind %in% c("name", "array", "parameter")) {
                resolve_name(analysis, node, function_node)
            } else if (node$kind == "call") {
                target <- analysis$function_table[[node$name]]
                if (is.null(target)) static_error(analysis, node$position, 4L, paste("undefined function", node$name)) else {
                    node$target_function <- target
                    if (length(node$arguments) > length(target$parameters)) {
                        static_error(analysis, node$position, 5L, paste("too many arguments to", node$name))
                    }
                }
            }
            pending <- c(pending, rev(node$children))
        }
    }
    if (length(analysis$errors)) {
        order <- order(vapply(analysis$errors, function(error) error$position[1L], integer(1L)),
            vapply(analysis$errors, function(error) error$position[2L], integer(1L)),
            vapply(analysis$errors, function(error) error$priority, integer(1L)))
        error <- analysis$errors[[order[1L]]]
        static_issue(error$position, error$message)
    }
    links <- list()
    for (node in analysis$nodes) {
        if (node$kind == "array") analysis$array_names[[node$binding$key]] <- TRUE else if (node$kind %in% c("membership", "delete", "for_in")) {
            analysis$array_names[[node$array$binding$key]] <- TRUE
        } else if (node$kind == "builtin" && node$name == "split") {
            analysis$array_names[[node$arguments[[2L]]$binding$key]] <- TRUE
        } else if (node$kind == "call") {
            for (index in seq_len(min(length(node$arguments), length(node$target_function$parameters)))) {
                argument <- node$arguments[[index]]
                if (argument$kind == "name") links[[length(links) + 1L]] <- c(argument$binding$key, node$target_function$parameters[[index]]$binding$key)
            }
        }
    }
    repeat {
        previous <- length(analysis$array_names)
        for (link in links) {
            if (exists(link[1L], analysis$array_names, inherits = FALSE) || exists(link[2L], analysis$array_names, inherits = FALSE)) {
                analysis$array_names[[link[1L]]] <- TRUE
                analysis$array_names[[link[2L]]] <- TRUE
            }
        }
        if (length(analysis$array_names) == previous) break
    }
    analysis
}
arithmetic <- function(operator, first, second, position) {
    a <- to_number(first)
    b <- to_number(second)
    if (operator %in% c("/", "%")) {
        if (b == 0L) runtime_issue(position, "division by zero")
        quotient <- abs(a) %/% abs(b)
        if ((a < 0L) != (b < 0L)) quotient <- -quotient
        result <- if (operator == "/") quotient else a - quotient * b
    } else if (operator == "^") {
        if (b < 0L) runtime_issue(position, "negative exponent")
        result <- 1L
        base <- a
        while (b > 0L) {
            if (b %% 2L == 1L) result <- result * base
            b <- b %/% 2L
            if (b > 0L) base <- base * base
        }
    } else if (operator == "+") result <- a + b else if (operator == "-") result <- a - b else result <- a * b
    number(result)
}
new_engine <- function(analysis, options, operands) {
    globals <- new_table()
    global_names <- new_table()
    for (name in ls(analysis$global_names, all.names = TRUE)) {
        globals[[name]] <- if (exists(paste0("0:", name), analysis$array_names, inherits = FALSE)) new_array() else UNINITIALIZED
        global_names[[name]] <- TRUE
    }
    initial <- list(FILENAME = string_value(""), FNR = number(0L), FS = string_value(" "), NF = number(0L),
        NR = number(0L), OFS = string_value(" "), ORS = string_value("\n"), SUBSEP = string_value(intToUtf8(28L)))
    for (name in names(initial)) globals[[name]] <- initial[[name]]
    lines <- new_table()
    for (line in ls(analysis$statement_lines)) lines[[line]] <- 0L
    for (rule in analysis$rules) {
        rule$count <- 0L
        rule$inside <- FALSE
    }
    for (function_node in analysis$functions) {
        function_node$call_count <- function_node$active_calls <- function_node$max_depth <- 0L
    }
    record(analysis = analysis, options = options, operands = operands, globals = globals, global_names = global_names,
        local_frames = list(), record = new_record(function(name) globals[[name]]), streams = new_streams(), lines = lines,
        phase = "BEGIN", exit_status = 0L, error = NULL, operand_position = 1L, current_operand = NULL,
        input_lines = character(), input_position = 1L)
}
variable <- function(engine, binding) {
    if (binding$scope != 0L) return(engine$local_frames[[length(engine$local_frames)]][[binding$name]])
    if (binding$name == "NF") number(length(engine$record$fields)) else engine$globals[[binding$name]]
}
global_value <- function(engine, name) variable(engine, list(scope = 0L, name = name))
assign_global_input <- function(engine, name, text) {
    engine$global_names[[name]] <- TRUE
    engine$globals[[name]] <- input_value(text)
}
subscript <- function(engine, expressions) {
    values <- vapply(expressions, function(expression) to_string(evaluate(engine, expression)), character(1L))
    paste0(values, collapse = to_string(global_value(engine, "SUBSEP")))
}
location <- function(engine, node) {
    if (node$kind == "name") return(list(kind = "variable", binding = node$binding))
    if (node$kind == "array") {
        key <- subscript(engine, node$indexes)
        return(list(kind = "array", array = variable(engine, node$binding), key = key))
    }
    index <- to_number(evaluate(engine, node$index))
    if (index < 0L) runtime_issue(node$position, "negative field index")
    list(kind = "field", index = index)
}
read_location <- function(engine, place) {
    if (place$kind == "variable") return(variable(engine, place$binding))
    if (place$kind == "field") return(read_field(engine$record, place$index))
    map_get(place$array, place$key, create = TRUE)
}
store <- function(engine, place, value, position) {
    force(value)
    if (place$kind == "field") write_field(engine$record, place$index, value) else if (place$kind == "array") {
        map_set(place$array, place$key, value)
    } else if (place$binding$scope != 0L) {
        engine$local_frames[[length(engine$local_frames)]][[place$binding$name]] <- value
    } else if (place$binding$name == "NF") {
        size <- to_number(value)
        if (size < 0L) runtime_issue(position, "negative NF")
        resize_fields(engine$record, size)
    } else engine$globals[[place$binding$name]] <- value
}
evaluate <- function(engine, node) {
    kind <- node$kind
    if (kind == "number") return(number(node$value))
    if (kind == "string") return(string_value(node$value))
    if (kind %in% LVALUE_KINDS) return(read_location(engine, location(engine, node)))
    if (kind == "paren") return(evaluate(engine, node$expression))
    if (kind == "assignment") {
        place <- location(engine, node$location)
        value <- evaluate(engine, node$value)
        if (node$operator != "=") value <- arithmetic(substr(node$operator, 1L, nchar(node$operator) - 1L), read_location(engine, place), value, node$position)
        store(engine, place, value, node$position)
        return(read_location(engine, place))
    }
    if (kind == "increment") {
        place <- location(engine, node$location)
        old <- to_number(read_location(engine, place))
        value <- old + node$delta
        store(engine, place, number(value), node$position)
        return(number(if (node$prefix) value else old))
    }
    if (kind == "conditional") return(evaluate(engine, if (truth(evaluate(engine, node$condition))) node$first else node$second))
    if (kind == "unary") {
        value <- evaluate(engine, node$operand)
        if (node$operator == "!") return(number(!truth(value)))
        integer <- to_number(value)
        return(number(if (node$operator == "-") -integer else integer))
    }
    if (kind == "membership") {
        key <- subscript(engine, node$indexes)
        return(number(map_has(variable(engine, node$array$binding), key)))
    }
    if (kind == "binary") {
        first <- evaluate(engine, node$left)
        operator <- node$operator
        if (operator == "||" && truth(first)) return(number(1L))
        if (operator == "&&" && !truth(first)) return(number(0L))
        second <- evaluate(engine, node$right)
        if (operator %in% c("&&", "||")) return(number(truth(second)))
        if (operator == "concat") return(string_value(paste0(to_string(first), to_string(second))))
        if (operator %in% COMPARISONS) {
            order <- compare_values(first, second)
            result <- switch(operator, "<" = order < 0L, "<=" = order <= 0L, "==" = order == 0L,
                "!=" = order != 0L, ">=" = order >= 0L, ">" = order > 0L)
            return(number(result))
        }
        return(arithmetic(operator, first, second, node$position))
    }
    if (kind == "call") return(call_function(engine, node))
    if (kind == "builtin") return(evaluate_builtin(engine, node))
    evaluate_getline(engine, node)
}
call_function <- function(engine, node) {
    function_node <- node$target_function
    frame <- new_table()
    for (index in seq_along(function_node$parameters)) {
        parameter <- function_node$parameters[[index]]
        is_array <- exists(parameter$binding$key, engine$analysis$array_names, inherits = FALSE)
        if (index <= length(node$arguments)) {
            argument <- node$arguments[[index]]
            value <- if (is_array) variable(engine, argument$binding) else evaluate(engine, argument)
        } else value <- if (is_array) new_array() else UNINITIALIZED
        frame[[parameter$name]] <- value
    }
    function_node$call_count <- function_node$call_count + 1L
    function_node$active_calls <- function_node$active_calls + 1L
    function_node$max_depth <- max(function_node$max_depth, function_node$active_calls)
    engine$local_frames[[length(engine$local_frames) + 1L]] <- frame
    on.exit({
        engine$local_frames[[length(engine$local_frames)]] <- NULL
        function_node$active_calls <- function_node$active_calls - 1L
    })
    tryCatch({
        execute_statement(engine, function_node$body)
        UNINITIALIZED
    }, awk_transfer = function(transfer) {
        if (transfer$kind == "return") transfer$value else stop(transfer)
    })
}
evaluate_builtin <- function(engine, node) {
    name <- node$name
    arguments <- node$arguments
    if (name == "length") {
        if (!length(arguments)) return(number(nchar(to_string(engine$record$zero))))
        argument <- arguments[[1L]]
        if (argument$kind == "name" && exists(argument$binding$key, engine$analysis$array_names, inherits = FALSE)) {
            return(number(variable(engine, argument$binding)$size))
        }
        return(number(nchar(to_string(evaluate(engine, argument)))))
    }
    if (name == "split") {
        text <- to_string(evaluate(engine, arguments[[1L]]))
        separator <- if (length(arguments) == 3L) to_string(evaluate(engine, arguments[[3L]])) else to_string(global_value(engine, "FS"))
        array <- variable(engine, arguments[[2L]]$binding)
        map_clear(array)
        pieces <- split_pieces(text, separator)
        for (index in seq_along(pieces)) map_set(array, as.character(index), input_value(pieces[index]))
        return(number(length(pieces)))
    }
    if (name == "close") {
        filename <- to_string(evaluate(engine, arguments[[1L]]))
        return(number(close_streams(engine$streams, filename)))
    }
    values <- lapply(arguments, function(argument) evaluate(engine, argument))
    invoke_builtin(name, values, node$position)
}
evaluate_getline <- function(engine, node) {
    if (!is.null(node$filename)) {
        filename <- to_string(evaluate(engine, node$filename))
        found <- getline_input(engine$streams, filename)
        status <- found$status
        line <- found$line
    } else if (engine$phase == "END") return(number(0L)) else {
        line <- next_record(engine)
        status <- if (is.null(line)) 0L else 1L
    }
    if (status == 1L) {
        if (is.null(node$target)) set_record(engine$record, line) else {
            place <- location(engine, node$target)
            store(engine, place, input_value(line), node$position)
        }
    }
    number(status)
}
execute_output <- function(engine, node) {
    arguments <- lapply(node$arguments, function(argument) evaluate(engine, argument))
    if (node$kind == "print") {
        if (!length(arguments)) arguments <- list(engine$record$zero)
        values <- vapply(arguments, to_string, character(1L))
        text <- paste0(paste0(values, collapse = to_string(global_value(engine, "OFS"))), to_string(global_value(engine, "ORS")))
    } else text <- format_output(arguments, node$position)
    filename <- if (is.null(node$filename)) NULL else to_string(evaluate(engine, node$filename))
    write_output(engine$streams, text, filename, node$redirect, node$redirect_position)
}
execute_loop_body <- function(engine, body) {
    tryCatch({
        execute_statement(engine, body)
        TRUE
    }, awk_transfer = function(transfer) {
        if (transfer$kind == "break") FALSE else if (transfer$kind == "continue") TRUE else stop(transfer)
    })
}
execute_statement <- function(engine, node) {
    kind <- node$kind
    if (kind == "block") {
        for (child in node$statements) execute_statement(engine, child)
        return(invisible(NULL))
    }
    if (kind == "empty") return(invisible(NULL))
    line <- as.character(node$position[1L])
    engine$lines[[line]] <- engine$lines[[line]] + 1L
    if (kind == "expression_statement") evaluate(engine, node$expression) else if (kind %in% c("print", "printf")) {
        execute_output(engine, node)
    } else if (kind == "if") {
        branch <- if (truth(evaluate(engine, node$condition))) node$first else node$second
        if (!is.null(branch)) execute_statement(engine, branch)
    } else if (kind == "while") {
        while (truth(evaluate(engine, node$condition))) if (!execute_loop_body(engine, node$body)) break
    } else if (kind == "do") {
        repeat {
            if (!execute_loop_body(engine, node$body)) break
            if (!truth(evaluate(engine, node$condition))) break
        }
    } else if (kind == "for") {
        if (!is.null(node$initial)) evaluate(engine, node$initial)
        while (is.null(node$condition) || truth(evaluate(engine, node$condition))) {
            if (!execute_loop_body(engine, node$body)) break
            if (!is.null(node$update)) evaluate(engine, node$update)
        }
    } else if (kind == "for_in") {
        keys <- ordered_subscripts(map_keys(variable(engine, node$array$binding)))
        for (key in keys) {
            store(engine, list(kind = "variable", binding = node$variable$binding), input_value(key), node$variable$position)
            if (!execute_loop_body(engine, node$body)) break
        }
    } else if (kind == "delete") {
        array <- variable(engine, node$array$binding)
        if (is.null(node$indexes)) map_clear(array) else {
            key <- subscript(engine, node$indexes)
            map_remove(array, key)
        }
    } else if (kind == "next") {
        if (engine$phase %in% c("BEGIN", "END")) runtime_issue(node$position, "next used in BEGIN or END")
        transfer("next")
    } else if (kind == "exit") {
        if (!is.null(node$value)) engine$exit_status <- to_number(evaluate(engine, node$value))
        transfer("exit")
    } else if (kind == "return") {
        value <- if (is.null(node$value)) UNINITIALIZED else evaluate(engine, node$value)
        transfer("return", value)
    } else transfer(kind)
    invisible(NULL)
}
next_record <- function(engine) {
    repeat {
        if (engine$input_position <= length(engine$input_lines)) {
            line <- engine$input_lines[engine$input_position]
            engine$input_position <- engine$input_position + 1L
            engine$current_operand$records <- engine$current_operand$records + 1L
            engine$globals[["NR"]] <- number(to_number(global_value(engine, "NR")) + 1L)
            engine$globals[["FNR"]] <- number(to_number(global_value(engine, "FNR")) + 1L)
            return(line)
        }
        if (engine$operand_position > length(engine$operands)) return(NULL)
        operand <- engine$operands[[engine$operand_position]]
        engine$operand_position <- engine$operand_position + 1L
        if (operand$kind == "assignment") assign_global_input(engine, operand$name, operand$value) else {
            engine$current_operand <- operand
            engine$input_lines <- read_records(operand$name)
            engine$input_position <- 1L
            engine$globals[["FILENAME"]] <- string_value(operand$name)
            engine$globals[["FNR"]] <- number(0L)
        }
    }
}
run_actions <- function(engine, phase) {
    engine$phase <- phase
    for (rule in engine$analysis$rules) {
        if (rule$flavor == phase) {
            rule$count <- rule$count + 1L
            execute_statement(engine, rule$action)
        }
    }
}
rule_matches <- function(engine, rule) {
    if (rule$flavor == "all") return(TRUE)
    if (rule$flavor == "pattern") return(truth(evaluate(engine, rule$patterns[[1L]])))
    if (!rule$inside && truth(evaluate(engine, rule$patterns[[1L]]))) rule$inside <- TRUE
    if (!rule$inside) return(FALSE)
    if (truth(evaluate(engine, rule$patterns[[2L]]))) rule$inside <- FALSE
    TRUE
}
run_records <- function(engine) {
    if (!any(vapply(engine$analysis$rules, function(rule) rule$flavor != "BEGIN", logical(1L)))) return(invisible(NULL))
    engine$phase <- "records"
    rules <- Filter(function(rule) !rule$flavor %in% c("BEGIN", "END"), engine$analysis$rules)
    repeat {
        line <- next_record(engine)
        if (is.null(line)) return(invisible(NULL))
        set_record(engine$record, line)
        tryCatch({
            for (rule in rules) {
                if (rule_matches(engine, rule)) {
                    rule$count <- rule$count + 1L
                    if (is.null(rule$action)) {
                        write_output(engine$streams, paste0(to_string(engine$record$zero), to_string(global_value(engine, "ORS"))))
                    } else execute_statement(engine, rule$action)
                }
            }
        }, awk_transfer = function(transfer) {
            if (transfer$kind != "next") stop(transfer)
        })
    }
}
execute <- function(engine) {
    tryCatch({
        for (option in engine$options) assign_global_input(engine, option$name, option$value)
        tryCatch({
            run_actions(engine, "BEGIN")
            run_records(engine)
        }, awk_transfer = function(transfer) {
            if (transfer$kind != "exit") stop(transfer)
        })
        tryCatch(run_actions(engine, "END"), awk_transfer = function(transfer) {
            if (transfer$kind != "exit") stop(transfer)
        })
    }, runtime_issue = function(error) engine$error <- error)
}
statistics <- function(engine) {
    status <- if (is.null(engine$error)) paste("status: exit", engine$exit_status) else {
        paste0("status: runtime error at ", engine$error$position[1L], ":", engine$error$position[2L], ": ", engine$error$message)
    }
    lines <- c(status, "[inputs]")
    for (operand in engine$operands) if (operand$kind == "file") lines <- c(lines, paste0(operand$name, " records=", operand$records))
    lines <- c(lines, "[getline]")
    for (name in engine$streams$input_order) {
        source <- map_get(engine$streams$inputs, name)
        lines <- c(lines, paste(name, if (source$ever_opened) paste0("reads=", source$reads) else "missing"))
    }
    lines <- c(lines, "[rules]")
    for (rule in engine$analysis$rules) lines <- c(lines, paste0(rule$position[1L], ":", rule$position[2L], " ", rule$flavor, " count=", rule$count))
    lines <- c(lines, "[functions]")
    for (function_node in engine$analysis$functions) lines <- c(lines, paste0(function_node$name, " calls=", function_node$call_count, " depth=", function_node$max_depth))
    lines <- c(lines, "[outputs]", paste0("stdout.txt writes=", engine$streams$stdout$writes, " bytes=", engine$streams$stdout$bytes))
    for (name in engine$streams$output_order) {
        output <- map_get(engine$streams$outputs, name)
        lines <- c(lines, paste0(name, " writes=", output$writes, " bytes=", output$bytes))
    }
    lines <- c(lines, "[lines]")
    for (line in sort(as.integer(ls(engine$lines)))) lines <- c(lines, paste0(line, " count=", engine$lines[[as.character(line)]]))
    lines <- c(lines, "[globals]")
    for (name in sort(ls(engine$global_names, all.names = TRUE), method = "radix")) {
        value <- global_value(engine, name)
        text <- if (exists(paste0("0:", name), engine$analysis$array_names, inherits = FALSE)) paste0("array (", value$size, ")") else describe_value(value)
        lines <- c(lines, paste(name, "=", text))
    }
    lines
}
main <- function() {
    options(expressions = 100000L)
    arguments <- parse_arguments(readLines("input/args.txt", warn = FALSE))
    source_lines <- readLines("input/program.awk", warn = FALSE)
    source <- if (length(source_lines)) paste0(paste0(source_lines, collapse = "\n"), "\n") else ""
    result <- tryCatch({
        items <- parse_program(new_parser(tokenize(source)))
        analysis <- prepare(new_analysis(items))
        engine <- new_engine(analysis, arguments$options, arguments$operands)
        execute(engine)
        list(lines = statistics(engine), streams = engine$streams)
    }, syntax_issue = function(error) {
        list(lines = paste0("status: syntax error at ", error$position[1L], ":", error$position[2L]), streams = new_streams())
    }, static_issue = function(error) {
        list(lines = paste0("status: error at ", error$position[1L], ":", error$position[2L], ": ", error$message), streams = new_streams())
    })
    save_streams(result$streams)
    writeLines(result$lines, "output/stats.txt", useBytes = TRUE)
}
main()
