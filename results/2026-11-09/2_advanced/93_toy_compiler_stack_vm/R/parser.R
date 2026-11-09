TYPES <- c("int", "bool", "void")
OPERATORS <- list("||", "&&", c("==", "!="), c("<", "<=", ">", ">="), c("+", "-"), c("*", "/", "%"))
NODE_IDS <- new.env(parent = emptyenv())
NODE_IDS$next_id <- 0L
toy_node <- function(kind, position, ...) {
  NODE_IDS$next_id <- NODE_IDS$next_id + 1L
  new_record(kind = kind, position = position, id = NODE_IDS$next_id, ...)
}
expression_children <- function(node) {
  switch(node$kind, binary = list(node$left, node$right), unary = list(node$operand),
         array = list(node$index), call = node$arguments, list())
}
statement_children <- function(node) {
  if (node$kind == "block") return(node$statements)
  if (node$kind == "if") return(c(list(node$then), if (is.null(node$otherwise)) list() else list(node$otherwise)))
  if (node$kind == "while") return(list(node$body))
  if (node$kind == "for") return(Filter(Negate(is.null), list(node$initial, node$update, node$body)))
  list()
}
new_parser <- function(tokens) new_record(tokens = tokens, index = 1L)
next_token <- function(parser) parser$tokens[[parser$index]]
syntax_error <- function(parser) {
  token <- next_token(parser)
  message <- if (token$kind == "end") "unexpected end of program" else paste0("unexpected '", token$spelling, "'")
  compile_error("syntax", token$position, message)
}
take_token <- function(parser) {
  token <- next_token(parser)
  parser$index <- parser$index + 1L
  token
}
accept_token <- function(parser, spelling) if (next_token(parser)$spelling == spelling) take_token(parser) else NULL
expect_token <- function(parser, spelling) {
  if (next_token(parser)$spelling != spelling) syntax_error(parser)
  take_token(parser)
}
identifier <- function(parser) {
  if (next_token(parser)$kind != "identifier") syntax_error(parser)
  take_token(parser)
}
declaration_head <- function(parser) {
  if (!next_token(parser)$spelling %in% TYPES) syntax_error(parser)
  type_token <- take_token(parser)
  name <- identifier(parser)
  list(position = type_token$position, fields = list(type = type_token$spelling, name = name$spelling, name_position = name$position))
}
parse_program <- function(parser) {
  declarations <- list()
  while (next_token(parser)$kind != "end") {
    head <- declaration_head(parser)
    if (!is.null(accept_token(parser, "("))) {
      parameters <- list()
      if (next_token(parser)$spelling != ")") repeat {
        parameter_head <- declaration_head(parser)
        parameters[[length(parameters) + 1L]] <- do.call(toy_node, c(list("parameter", parameter_head$position), parameter_head$fields))
        if (is.null(accept_token(parser, ","))) break
      }
      expect_token(parser, ")")
      body <- parse_block(parser)
      node <- do.call(toy_node, c(list("function", head$position, parameters = parameters, body = body), head$fields))
    } else {
      size <- size_position <- initializer <- NULL
      if (!is.null(accept_token(parser, "["))) {
        if (next_token(parser)$kind != "integer") syntax_error(parser)
        token <- take_token(parser)
        size <- as.integer(token$spelling)
        size_position <- token$position
        expect_token(parser, "]")
      } else if (!is.null(accept_token(parser, "="))) {
        initializer <- parse_expression(parser)
      }
      expect_token(parser, ";")
      node <- do.call(toy_node, c(list("global", head$position, size = size, size_position = size_position, initializer = initializer), head$fields))
    }
    declarations[[length(declarations) + 1L]] <- node
  }
  declarations
}
parse_declaration <- function(parser, for_initial = FALSE) {
  head <- declaration_head(parser)
  initializer <- NULL
  if (for_initial) {
    expect_token(parser, "=")
    initializer <- parse_expression(parser)
  } else {
    if (!is.null(accept_token(parser, "="))) initializer <- parse_expression(parser)
    expect_token(parser, ";")
  }
  do.call(toy_node, c(list("declaration", head$position, initializer = initializer), head$fields))
}
parse_block <- function(parser) {
  opening <- expect_token(parser, "{")
  statements <- list()
  while (next_token(parser)$spelling != "}") statements[[length(statements) + 1L]] <- if (next_token(parser)$spelling %in% TYPES) parse_declaration(parser) else parse_statement(parser)
  closing <- expect_token(parser, "}")
  toy_node("block", opening$position, statements = statements, end_position = closing$position)
}
parse_statement <- function(parser) {
  token <- next_token(parser)
  spelling <- token$spelling
  if (spelling == "{") return(parse_block(parser))
  if (spelling %in% c("if", "while")) {
    take_token(parser)
    expect_token(parser, "(")
    condition <- parse_expression(parser)
    expect_token(parser, ")")
    body <- parse_statement(parser)
    if (spelling == "while") return(toy_node("while", token$position, condition = condition, body = body))
    otherwise <- if (is.null(accept_token(parser, "else"))) NULL else parse_statement(parser)
    return(toy_node("if", token$position, condition = condition, then = body, otherwise = otherwise))
  }
  if (spelling == "for") {
    take_token(parser)
    expect_token(parser, "(")
    initial <- NULL
    if (next_token(parser)$spelling %in% TYPES) initial <- parse_declaration(parser, TRUE) else if (next_token(parser)$spelling != ";") initial <- parse_simple(parser)
    expect_token(parser, ";")
    condition <- if (next_token(parser)$spelling == ";") NULL else parse_expression(parser)
    expect_token(parser, ";")
    update <- if (next_token(parser)$spelling == ")") NULL else parse_simple(parser)
    expect_token(parser, ")")
    body <- parse_statement(parser)
    return(toy_node("for", token$position, initial = initial, condition = condition, update = update, body = body))
  }
  if (spelling %in% c("break", "continue")) {
    take_token(parser)
    expect_token(parser, ";")
    return(toy_node(spelling, token$position))
  }
  if (spelling == "return") {
    take_token(parser)
    value <- if (next_token(parser)$spelling == ";") NULL else parse_expression(parser)
    expect_token(parser, ";")
    return(toy_node("return", token$position, value = value))
  }
  if (spelling == "print") {
    take_token(parser)
    expect_token(parser, "(")
    arguments <- list(parse_expression(parser))
    while (!is.null(accept_token(parser, ","))) arguments[[length(arguments) + 1L]] <- parse_expression(parser)
    expect_token(parser, ")")
    expect_token(parser, ";")
    return(toy_node("print", token$position, arguments = arguments))
  }
  if (token$kind == "identifier" || spelling == "read") {
    result <- parse_simple(parser)
    expect_token(parser, ";")
    return(result)
  }
  syntax_error(parser)
}
parse_simple <- function(parser) {
  token <- next_token(parser)
  if (token$kind != "identifier" && token$spelling != "read") syntax_error(parser)
  value <- parse_primary(parser)
  if (value$kind %in% c("call", "read")) return(toy_node("call_statement", value$position, expression = value))
  expect_token(parser, "=")
  index <- if (value$kind == "array") value$index else NULL
  right <- parse_expression(parser)
  toy_node("assignment", value$position, name = value$name, index = index, value = right)
}
parse_expression <- function(parser, level = 1L) {
  if (level > length(OPERATORS)) {
    if (next_token(parser)$spelling %in% c("-", "!")) {
      operator <- take_token(parser)
      operand <- parse_expression(parser, level)
      return(toy_node("unary", operator$position, operator = operator$spelling, operand = operand))
    }
    return(parse_primary(parser))
  }
  result <- parse_expression(parser, level + 1L)
  while (next_token(parser)$spelling %in% OPERATORS[[level]]) {
    operator <- take_token(parser)
    right <- parse_expression(parser, level + 1L)
    result <- toy_node("binary", operator$position, operator = operator$spelling, left = result, right = right)
  }
  result
}
parse_primary <- function(parser) {
  token <- next_token(parser)
  if (token$kind == "integer") {
    take_token(parser)
    return(toy_node("integer", token$position, value = as.numeric(token$spelling)))
  }
  if (token$spelling %in% c("true", "false")) {
    take_token(parser)
    return(toy_node("boolean", token$position, value = token$spelling == "true"))
  }
  if (token$spelling == "read") {
    take_token(parser)
    expect_token(parser, "(")
    expect_token(parser, ")")
    return(toy_node("read", token$position))
  }
  if (!is.null(accept_token(parser, "("))) {
    result <- parse_expression(parser)
    expect_token(parser, ")")
    return(result)
  }
  if (token$kind == "identifier") {
    take_token(parser)
    if (!is.null(accept_token(parser, "("))) {
      arguments <- list()
      if (next_token(parser)$spelling != ")") {
        arguments <- list(parse_expression(parser))
        while (!is.null(accept_token(parser, ","))) arguments[[length(arguments) + 1L]] <- parse_expression(parser)
      }
      expect_token(parser, ")")
      return(toy_node("call", token$position, name = token$spelling, arguments = arguments))
    }
    if (!is.null(accept_token(parser, "["))) {
      index <- parse_expression(parser)
      expect_token(parser, "]")
      return(toy_node("array", token$position, name = token$spelling, index = index))
    }
    return(toy_node("variable", token$position, name = token$spelling))
  }
  syntax_error(parser)
}
