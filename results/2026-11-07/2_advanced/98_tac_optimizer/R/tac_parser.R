record <- function(...) list2env(list(...), parent = emptyenv())
new_table <- function() new.env(hash = TRUE, parent = emptyenv())
KINDS <- c("copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print")
is_constant <- function(value) inherits(value, "bigz")
operand_text <- function(value) as.character(value)
instruction <- function(kind, destination = NULL, a = NULL, b = NULL, operation = "", name = "", count = 0L) {
    list(kind = kind, destination = destination, a = a, b = b, operation = operation, name = name, count = count)
}
replace_instruction <- function(entry, kind = entry$kind, destination = entry$destination, a = entry$a, b = entry$b,
                                operation = entry$operation, name = entry$name, count = entry$count) {
    instruction(kind, destination, a, b, operation, name, count)
}
new_function <- function(name, parameters, code = list()) {
    record(name = name, parameters = parameters, code = code, temporary_serial = 0L, preheader_serial = 0L)
}
instructions <- function(function_node) Filter(function(line) !is.character(line), function_node$code)
operand_fields <- function(entry) {
    if (entry$kind %in% c("bin", "if", "store")) return(c("a", "b"))
    if (entry$kind %in% c("copy", "load", "param", "print") || (entry$kind == "return" && !is.null(entry$a))) return("a")
    character()
}
used_variables <- function(entry) {
    values <- lapply(operand_fields(entry), function(field) entry[[field]])
    variables <- unlist(Filter(is.character, values), use.names = FALSE)
    if (is.null(variables)) character() else variables
}
expression <- function(entry) {
    if (entry$kind == "bin") {
        return(list(kind = "bin", operation = entry$operation, a = entry$a, b = entry$b,
            key = paste0(operand_text(entry$a), entry$operation, operand_text(entry$b))))
    }
    if (entry$kind == "load") {
        return(list(kind = "load", operation = entry$name, a = entry$a, b = NULL,
            key = paste0(entry$name, "[", operand_text(entry$a), "]")))
    }
    NULL
}
expression_key <- function(entry) {
    value <- expression(entry)
    if (is.null(value)) NULL else value$key
}
operand <- function(word) {
    initial <- substr(word, 1L, 1L)
    if (initial == "-" || initial %in% as.character(0L:9L)) gmp::as.bigz(word) else word
}
array_operand <- function(word) {
    opening <- which(strsplit(word, "", fixed = TRUE)[[1L]] == "[")[1L]
    list(name = substr(word, 1L, opening - 1L), index = operand(substr(word, opening + 1L, nchar(word) - 1L)))
}
parse_instruction <- function(words) {
    first <- words[1L]
    if (first == "goto") return(instruction("goto", name = words[2L]))
    if (first == "if") return(instruction("if", a = operand(words[2L]), b = operand(words[4L]), operation = words[3L], name = words[6L]))
    if (first %in% c("param", "print")) return(instruction(first, a = operand(words[2L])))
    if (first == "return") return(instruction("return", a = if (length(words) == 2L) operand(words[2L]) else NULL))
    if (first == "read") return(instruction("read", destination = words[2L]))
    if (first == "call") return(instruction("call", name = words[2L], count = as.integer(words[3L])))
    if ("[" %in% strsplit(first, "", fixed = TRUE)[[1L]]) {
        array <- array_operand(first)
        return(instruction("store", a = array$index, b = operand(words[3L]), name = array$name))
    }
    if (words[3L] == "call") return(instruction("call", destination = first, name = words[4L], count = as.integer(words[5L])))
    if (length(words) == 5L) return(instruction("bin", destination = first, a = operand(words[3L]), b = operand(words[5L]), operation = words[4L]))
    if ("[" %in% strsplit(words[3L], "", fixed = TRUE)[[1L]]) {
        array <- array_operand(words[3L])
        return(instruction("load", destination = first, a = array$index, name = array$name))
    }
    instruction("copy", destination = first, a = operand(words[3L]))
}
words_of <- function(line) strsplit(trimws(line, whitespace = " "), " +")[[1L]]
read_program <- function(path) {
    arrays <- functions <- list()
    current <- NULL
    for (line in readLines(path, warn = FALSE)) {
        words <- words_of(line)
        if (!length(words) || words[1L] == "" || startsWith(words[1L], "#")) next
        if (words[1L] == "array") arrays[[length(arrays) + 1L]] <- list(name = words[2L], size = as.integer(words[3L])) else if (words[1L] == "func") {
            current <- new_function(words[2L], words[-c(1L, 2L)])
            functions[[length(functions) + 1L]] <- current
        } else if (words[1L] == "end") current <- NULL else if (length(words) == 1L && endsWith(words[1L], ":")) {
            current$code[[length(current$code) + 1L]] <- substr(words[1L], 1L, nchar(words[1L]) - 1L)
        } else current$code[[length(current$code) + 1L]] <- parse_instruction(words)
    }
    list(arrays = arrays, functions = functions)
}
calculate <- function(operation, first, second) {
    if (operation == "+") return(first + second)
    if (operation == "-") return(first - second)
    if (operation == "*") return(first * second)
    if (operation %in% c("/", "%")) {
        quotient <- abs(first) %/% abs(second)
        if ((first < 0L) != (second < 0L)) quotient <- -quotient
        return(if (operation == "/") quotient else first - second * quotient)
    }
    result <- switch(operation, "<" = first < second, "<=" = first <= second, ">" = first > second,
        ">=" = first >= second, "==" = first == second, "!=" = first != second)
    gmp::as.bigz(as.integer(result))
}
instruction_string <- function(entry) {
    kind <- entry$kind
    if (kind == "copy") return(paste(entry$destination, "=", operand_text(entry$a)))
    if (kind == "bin") return(paste(entry$destination, "=", operand_text(entry$a), entry$operation, operand_text(entry$b)))
    if (kind == "load") return(paste0(entry$destination, " = ", entry$name, "[", operand_text(entry$a), "]"))
    if (kind == "store") return(paste0(entry$name, "[", operand_text(entry$a), "] = ", operand_text(entry$b)))
    if (kind == "goto") return(paste("goto", entry$name))
    if (kind == "if") return(paste("if", operand_text(entry$a), entry$operation, operand_text(entry$b), "goto", entry$name))
    if (kind == "call") return(paste0(if (is.null(entry$destination)) "" else paste0(entry$destination, " = "), "call ", entry$name, " ", entry$count))
    if (kind == "read") return(paste("read", entry$destination))
    if (kind == "return" && is.null(entry$a)) return("return")
    paste(kind, operand_text(entry$a))
}
function_lines <- function(function_node) {
    lines <- paste(c("func", function_node$name, function_node$parameters), collapse = " ")
    for (line in function_node$code) lines <- c(lines, if (is.character(line)) paste0(line, ":") else paste0("    ", instruction_string(line)))
    c(lines, "end")
}
program_lines <- function(program) {
    sections <- list()
    if (length(program$arrays)) sections[[1L]] <- vapply(program$arrays, function(array) paste("array", array$name, array$size), character(1L))
    sections <- c(sections, lapply(program$functions, function_lines))
    lines <- character()
    for (section in sections) {
        if (length(lines)) lines <- c(lines, "")
        lines <- c(lines, section)
    }
    lines
}
