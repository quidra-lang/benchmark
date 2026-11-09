can_complete <- function(statement) {
  pending <- list(list(node = statement, expanded = FALSE))
  while (length(pending)) {
    entry <- pending[[length(pending)]]
    pending <- head(pending, -1L)
    node <- entry$node
    if (!is.null(node$completes)) next
    if (node$kind %in% c("return", "break", "continue")) {
      node$completes <- FALSE
    } else if (node$kind == "block") {
      if (entry$expanded) {
        node$completes <- all(vapply(node$statements, function(child) child$completes, logical(1L)))
      } else {
        pending[[length(pending) + 1L]] <- list(node = node, expanded = TRUE)
        pending <- c(pending, lapply(node$statements, function(child) list(node = child, expanded = FALSE)))
      }
    } else if (node$kind == "if" && !is.null(node$otherwise)) {
      if (entry$expanded) {
        node$completes <- node$then$completes || node$otherwise$completes
      } else {
        pending <- c(pending, list(list(node = node, expanded = TRUE), list(node = node$then, expanded = FALSE), list(node = node$otherwise, expanded = FALSE)))
      }
    } else {
      node$completes <- TRUE
    }
  }
  statement$completes
}
new_analyzer <- function(declarations, end_position) {
  new_record(declarations = declarations, end_position = end_position, globals = list(),
             functions = list(), variables = list(), scopes = list(), current_function = NULL)
}
semantic_error <- function(position, message) compile_error("semantic", position, message)
prepare <- function(analyzer, declaration) {
  declaration$references <- list()
  declaration$read_accesses <- 0L
  if (declaration$kind == "function") {
    declaration$calls <- list()
    analyzer$functions[[length(analyzer$functions) + 1L]] <- declaration
  } else {
    analyzer$variables[[length(analyzer$variables) + 1L]] <- declaration
  }
}
lookup <- function(analyzer, name, position, read = TRUE) {
  referent <- NULL
  for (scope in rev(analyzer$scopes)) {
    if (!is.null(scope[[name]])) {
      referent <- scope[[name]]
      break
    }
  }
  if (is.null(referent)) referent <- analyzer$globals[[name]]
  if (!is.null(referent)) {
    referent$references[[length(referent$references) + 1L]] <- position
    referent$read_accesses <- referent$read_accesses + as.integer(read)
  }
  referent
}
variable <- function(analyzer, name, position, indexed, read = TRUE) {
  referent <- lookup(analyzer, name, position, read)
  if (is.null(referent)) semantic_error(position, paste0("undeclared identifier '", name, "'"))
  if (referent$kind == "function") semantic_error(position, paste0("'", name, "' is a function, not a variable"))
  is_array <- referent$kind == "global" && !is.null(referent$size)
  if (indexed && !is_array) semantic_error(position, paste0("'", name, "' is not an array"))
  if (!indexed && is_array) semantic_error(position, paste0("array '", name, "' used without index"))
  referent
}
analyze_expression <- function(analyzer, node, call_statement = FALSE) {
  kind <- node$kind
  if (kind %in% c("integer", "read")) {
    result <- "int"
  } else if (kind == "boolean") {
    result <- "bool"
  } else if (kind %in% c("variable", "array")) {
    node$referent <- variable(analyzer, node$name, node$position, kind == "array")
    if (kind == "array" && analyze_expression(analyzer, node$index) != "int") semantic_error(node$position, paste0("index of '", node$name, "' must be int"))
    result <- node$referent$type
  } else if (kind == "call") {
    referent <- lookup(analyzer, node$name, node$position)
    if (is.null(referent)) semantic_error(node$position, paste0("undeclared function '", node$name, "'"))
    if (referent$kind != "function") semantic_error(node$position, paste0("'", node$name, "' is not a function"))
    node$referent <- referent
    current <- analyzer$current_function
    if (!referent$id %in% vapply(current$calls, function(callee) callee$id, integer(1L))) current$calls[[length(current$calls) + 1L]] <- referent
    expected <- length(referent$parameters)
    found <- length(node$arguments)
    if (expected != found) semantic_error(node$position, paste0("wrong number of arguments to '", node$name, "' (expected ", expected, ", found ", found, ")"))
    for (number in seq_along(node$arguments)) {
      parameter <- referent$parameters[[number]]
      if (analyze_expression(analyzer, node$arguments[[number]]) != parameter$type) semantic_error(node$position, paste0("argument ", number, " of '", node$name, "' must be ", parameter$type))
    }
    if (!call_statement && referent$type == "void") semantic_error(node$position, paste0("void function '", node$name, "' used as a value"))
    result <- referent$type
  } else if (kind == "unary") {
    result <- analyze_expression(analyzer, node$operand)
    required <- if (node$operator == "-") "int" else "bool"
    if (result != required) semantic_error(node$position, paste0("operator '", node$operator, "' requires ", required, " operand"))
  } else {
    left <- analyze_expression(analyzer, node$left)
    right <- analyze_expression(analyzer, node$right)
    operator <- node$operator
    if (operator %in% c("+", "-", "*", "/", "%", "<", "<=", ">", ">=")) {
      if (left != "int" || right != "int") semantic_error(node$position, paste0("operator '", operator, "' requires int operands"))
      result <- if (operator %in% c("+", "-", "*", "/", "%")) "int" else "bool"
    } else if (operator %in% c("==", "!=")) {
      if (left != right) semantic_error(node$position, paste0("operator '", operator, "' requires operands of the same type"))
      result <- "bool"
    } else {
      if (left != "bool" || right != "bool") semantic_error(node$position, paste0("operator '", operator, "' requires bool operands"))
      result <- "bool"
    }
  }
  node$type <- result
  result
}
constant_initializer <- function(analyzer, node) {
  positions <- list()
  pending <- list(node)
  while (length(pending)) {
    current <- pending[[length(pending)]]
    pending <- head(pending, -1L)
    if (current$kind %in% c("variable", "array", "call", "read")) positions[[length(positions) + 1L]] <- current$position
    pending <- c(pending, expression_children(current))
  }
  if (length(positions)) {
    ordering <- order(vapply(positions, `[[`, integer(1L), 1L), vapply(positions, `[[`, integer(1L), 2L), method = "radix")
    semantic_error(positions[[ordering[[1L]]]], "global initializer must be constant")
  }
  analyze_expression(analyzer, node)
}
analyze_statement <- function(analyzer, node, loop_depth = 0L) {
  kind <- node$kind
  if (kind == "declaration") {
    if (node$type == "void") semantic_error(node$name_position, paste0("variable '", node$name, "' cannot have type void"))
    scope <- length(analyzer$scopes)
    if (!is.null(analyzer$scopes[[scope]][[node$name]])) semantic_error(node$name_position, paste0("redeclaration of '", node$name, "'"))
    if (!is.null(node$initializer) && analyze_expression(analyzer, node$initializer) != node$type) semantic_error(node$name_position, paste0("type mismatch in initialization of '", node$name, "'"))
    prepare(analyzer, node)
    analyzer$scopes[[scope]][[node$name]] <- node
  } else if (kind == "assignment") {
    node$referent <- variable(analyzer, node$name, node$position, !is.null(node$index), FALSE)
    if (!is.null(node$index) && analyze_expression(analyzer, node$index) != "int") semantic_error(node$position, paste0("index of '", node$name, "' must be int"))
    if (analyze_expression(analyzer, node$value) != node$referent$type) semantic_error(node$position, paste0("type mismatch in assignment to '", node$name, "'"))
  } else if (kind == "call_statement") {
    analyze_expression(analyzer, node$expression, TRUE)
  } else if (kind %in% c("if", "while")) {
    if (analyze_expression(analyzer, node$condition) != "bool") semantic_error(node$position, paste0("condition of '", kind, "' must be bool"))
    if (kind == "if") {
      analyze_statement(analyzer, node$then, loop_depth)
      if (!is.null(node$otherwise)) analyze_statement(analyzer, node$otherwise, loop_depth)
    } else {
      analyze_statement(analyzer, node$body, loop_depth + 1L)
    }
  } else if (kind == "for") {
    analyzer$scopes[[length(analyzer$scopes) + 1L]] <- list()
    if (!is.null(node$initial)) analyze_statement(analyzer, node$initial, loop_depth)
    if (!is.null(node$condition) && analyze_expression(analyzer, node$condition) != "bool") semantic_error(node$position, "condition of 'for' must be bool")
    if (!is.null(node$update)) analyze_statement(analyzer, node$update, loop_depth)
    analyze_statement(analyzer, node$body, loop_depth + 1L)
    analyzer$scopes <- head(analyzer$scopes, -1L)
  } else if (kind %in% c("break", "continue")) {
    if (!loop_depth) semantic_error(node$position, paste0("'", kind, "' outside loop"))
  } else if (kind == "return") {
    current <- analyzer$current_function
    if (current$type == "void" && !is.null(node$value)) semantic_error(node$position, paste0("function '", current$name, "' must not return a value"))
    if (current$type != "void") {
      if (is.null(node$value)) semantic_error(node$position, paste0("function '", current$name, "' must return a value"))
      if (analyze_expression(analyzer, node$value) != current$type) semantic_error(node$position, paste0("return value of '", current$name, "' must be ", current$type))
    }
  } else if (kind == "print") {
    for (number in seq_along(node$arguments)) if (analyze_expression(analyzer, node$arguments[[number]]) != "int") semantic_error(node$position, paste0("argument ", number, " of 'print' must be int"))
  } else if (kind == "block") {
    analyzer$scopes[[length(analyzer$scopes) + 1L]] <- list()
    for (child in node$statements) analyze_statement(analyzer, child, loop_depth)
    analyzer$scopes <- head(analyzer$scopes, -1L)
  }
}
analyze <- function(analyzer) {
  for (node in analyzer$declarations) {
    if (node$kind == "global") {
      if (!is.null(node$size)) {
        if (node$type != "int") semantic_error(node$name_position, paste0("array '", node$name, "' must have element type int"))
        if (node$size == 0L) semantic_error(node$size_position, paste0("array '", node$name, "' must have a positive size"))
      } else if (node$type == "void") {
        semantic_error(node$name_position, paste0("variable '", node$name, "' cannot have type void"))
      }
    }
    if (!is.null(analyzer$globals[[node$name]])) semantic_error(node$name_position, paste0("redeclaration of '", node$name, "'"))
    if (node$kind == "global") {
      if (!is.null(node$initializer) && constant_initializer(analyzer, node$initializer) != node$type) semantic_error(node$name_position, paste0("type mismatch in initialization of '", node$name, "'"))
    } else {
      names <- character()
      for (parameter in node$parameters) {
        if (parameter$type == "void") semantic_error(parameter$name_position, paste0("parameter '", parameter$name, "' cannot have type void"))
        if (parameter$name %in% names) semantic_error(parameter$name_position, paste0("redeclaration of '", parameter$name, "'"))
        names <- c(names, parameter$name)
        prepare(analyzer, parameter)
      }
    }
    prepare(analyzer, node)
    analyzer$globals[[node$name]] <- node
  }
  main <- analyzer$globals[["main"]]
  if (is.null(main) || main$kind != "function") semantic_error(analyzer$end_position, "no main function")
  if (main$type != "void" || length(main$parameters)) semantic_error(main$name_position, "main must be declared as 'void main()'")
  for (function_node in analyzer$functions) {
    analyzer$current_function <- function_node
    scope <- setNames(function_node$parameters, vapply(function_node$parameters, function(parameter) parameter$name, character(1L)))
    analyzer$scopes <- list(scope)
    for (statement in function_node$body$statements) analyze_statement(analyzer, statement)
    if (function_node$type != "void" && can_complete(function_node$body)) semantic_error(function_node$name_position, paste0("missing return in function '", function_node$name, "'"))
  }
  analyzer
}
