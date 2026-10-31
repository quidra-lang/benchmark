BINARY <- c("+" = "ADD", "-" = "SUB", "*" = "MUL", "/" = "DIV", "%" = "MOD", "<" = "LT", "<=" = "LE", ">" = "GT", ">=" = "GE", "==" = "EQ", "!=" = "NE")
JUMPS <- c("JUMP", "JUMPF", "JUMPT")
CONDITIONAL <- c("JUMPF", "JUMPT")
TRANSFERS <- c("JUMP", "RET", "RETV", "HALT")
NEGATED <- c(LT = "GE", LE = "GT", GT = "LE", GE = "LT", EQ = "NE", NE = "EQ")
INVERSE <- c(JUMPF = "JUMPT", JUMPT = "JUMPF")
instruction <- function(op, position, ...) list(op = op, args = list(...), position = position)
new_label <- function() new_record(position = -1L)
new_unit <- function(name, function_node, slots, code) {
  new_record(name = name, function_node = function_node, slots = slots, before = code,
             after = list(), blocks = list(), depth = 0L, recursive = FALSE,
             before_start = 0L, after_start = 0L)
}
new_generator <- function() new_record(code = list(), loops = list())
emit <- function(generator, op, position, ...) generator$code[[length(generator$code) + 1L]] <- instruction(op, position, ...)
mark <- function(generator, label) label$position <- length(generator$code)
finish_code <- function(generator) lapply(generator$code, function(entry) {
  if (entry$op %in% JUMPS) entry$args <- list(entry$args[[1L]]$position)
  entry
})
generate_expression <- function(generator, node) {
  kind <- node$kind
  position <- node$position
  if (kind %in% c("integer", "boolean")) {
    emit(generator, "PUSH", position, as.numeric(node$value))
  } else if (kind == "variable") {
    referent <- node$referent
    emit(generator, if (referent$kind == "global") "LOADG" else "LOADL", position, if (referent$kind == "global") referent$address else referent$slot)
  } else if (kind == "array") {
    generate_expression(generator, node$index)
    emit(generator, "LOADA", position, node$referent$address, node$referent$size)
  } else if (kind == "read") {
    emit(generator, "READ", position)
  } else if (kind == "call") {
    for (argument in node$arguments) generate_expression(generator, argument)
    emit(generator, "CALL", position, node$referent$name, length(node$arguments))
  } else if (kind == "unary") {
    generate_expression(generator, node$operand)
    emit(generator, if (node$operator == "-") "NEG" else "NOT", position)
  } else if (node$operator %in% c("&&", "||")) {
    shortcut <- new_label()
    ending <- new_label()
    generate_expression(generator, node$left)
    emit(generator, if (node$operator == "&&") "JUMPF" else "JUMPT", position, shortcut)
    generate_expression(generator, node$right)
    emit(generator, "JUMP", position, ending)
    mark(generator, shortcut)
    emit(generator, "PUSH", position, as.integer(node$operator == "||"))
    mark(generator, ending)
  } else {
    generate_expression(generator, node$left)
    generate_expression(generator, node$right)
    emit(generator, BINARY[[node$operator]], position)
  }
}
generate_statement <- function(generator, node) {
  kind <- node$kind
  position <- node$position
  if (kind == "declaration") {
    if (is.null(node$initializer)) emit(generator, "PUSH", node$name_position, 0L) else generate_expression(generator, node$initializer)
    emit(generator, "STOREL", node$name_position, node$slot)
  } else if (kind == "assignment") {
    if (!is.null(node$index)) generate_expression(generator, node$index)
    generate_expression(generator, node$value)
    referent <- node$referent
    if (!is.null(node$index)) emit(generator, "STOREA", position, referent$address, referent$size) else emit(generator, if (referent$kind == "global") "STOREG" else "STOREL", position, if (referent$kind == "global") referent$address else referent$slot)
  } else if (kind == "call_statement") {
    generate_expression(generator, node$expression)
    if (node$expression$type != "void") emit(generator, "POP", position)
  } else if (kind == "print") {
    for (argument in node$arguments) generate_expression(generator, argument)
    emit(generator, "PRINT", position, length(node$arguments))
  } else if (kind == "if") {
    alternative <- new_label()
    ending <- new_label()
    generate_expression(generator, node$condition)
    emit(generator, "JUMPF", position, alternative)
    generate_statement(generator, node$then)
    if (is.null(node$otherwise)) {
      mark(generator, alternative)
    } else {
      emit(generator, "JUMP", position, ending)
      mark(generator, alternative)
      generate_statement(generator, node$otherwise)
      mark(generator, ending)
    }
  } else if (kind == "while") {
    start <- new_label()
    ending <- new_label()
    mark(generator, start)
    generate_expression(generator, node$condition)
    emit(generator, "JUMPF", position, ending)
    generator$loops[[length(generator$loops) + 1L]] <- list(ending, start)
    generate_statement(generator, node$body)
    generator$loops <- head(generator$loops, -1L)
    emit(generator, "JUMP", position, start)
    mark(generator, ending)
  } else if (kind == "for") {
    start <- new_label()
    update <- new_label()
    ending <- new_label()
    if (!is.null(node$initial)) generate_statement(generator, node$initial)
    mark(generator, start)
    if (!is.null(node$condition)) {
      generate_expression(generator, node$condition)
      emit(generator, "JUMPF", position, ending)
    }
    generator$loops[[length(generator$loops) + 1L]] <- list(ending, update)
    generate_statement(generator, node$body)
    generator$loops <- head(generator$loops, -1L)
    mark(generator, update)
    if (!is.null(node$update)) generate_statement(generator, node$update)
    emit(generator, "JUMP", position, start)
    mark(generator, ending)
  } else if (kind %in% c("break", "continue")) {
    emit(generator, "JUMP", position, generator$loops[[length(generator$loops)]][[if (kind == "continue") 2L else 1L]])
  } else if (kind == "return") {
    if (!is.null(node$value)) generate_expression(generator, node$value)
    emit(generator, if (is.null(node$value)) "RET" else "RETV", position)
  } else if (kind == "block") {
    for (child in node$statements) generate_statement(generator, child)
  }
}
assign_slots <- function(function_node) {
  declarations <- list()
  pending <- list(function_node$body)
  while (length(pending)) {
    node <- pending[[length(pending)]]
    pending <- head(pending, -1L)
    if (node$kind == "declaration") declarations[[length(declarations) + 1L]] <- node
    pending <- c(pending, statement_children(node))
  }
  if (length(declarations)) {
    ordering <- order(vapply(declarations, function(node) node$name_position[[1L]], integer(1L)), vapply(declarations, function(node) node$name_position[[2L]], integer(1L)), method = "radix")
    declarations <- declarations[ordering]
  }
  slots <- c(function_node$parameters, declarations)
  for (index in seq_along(slots)) slots[[index]]$slot <- index - 1L
  slots
}
generate <- function(globals, functions, main) {
  address <- 0L
  for (variable in globals) {
    variable$address <- address
    address <- address + if (is.null(variable$size)) 1L else variable$size
  }
  initialization <- new_generator()
  for (variable in globals) if (!is.null(variable$initializer)) {
    generate_expression(initialization, variable$initializer)
    emit(initialization, "STOREG", variable$name_position, variable$address)
  }
  emit(initialization, "CALL", main$name_position, "main", 0L)
  emit(initialization, "HALT", main$name_position)
  units <- list(new_unit("<init>", NULL, list(), finish_code(initialization)))
  for (function_node in functions) {
    slots <- assign_slots(function_node)
    generator <- new_generator()
    emit(generator, "ENTER", function_node$name_position, length(slots))
    generate_statement(generator, function_node$body)
    if (function_node$type == "void") emit(generator, "RET", function_node$body$end_position)
    units[[length(units) + 1L]] <- new_unit(function_node$name, function_node, slots, finish_code(generator))
  }
  list(units = units, global_size = address)
}
