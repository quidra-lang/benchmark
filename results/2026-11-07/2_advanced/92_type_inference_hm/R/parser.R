OPERATORS <- list("||" = c(1L, 1L), "&&" = c(2L, 1L), "=" = c(3L, 0L), "<>" = c(3L, 0L), "<" = c(3L, 0L), ">" = c(3L, 0L), "<=" = c(3L, 0L), ">=" = c(3L, 0L), "::" = c(4L, 1L), "^" = c(4L, 1L), "+" = c(5L, 0L), "-" = c(5L, 0L), "*" = c(6L, 0L), "/" = c(6L, 0L), "mod" = c(6L, 0L))
AST_IDS <- new.env(parent = emptyenv())
AST_IDS$next_id <- 0L
ml_node <- function(kind, position, children = list(), value = NULL) {
  AST_IDS$next_id <- AST_IDS$next_id + 1L
  new_record(kind = kind, position = position, children = children, value = value,
             inferred = NULL, id = AST_IDS$next_id)
}
new_binding <- function(name, expression) new_record(name = name$spelling, position = name$position, expression = expression, scheme = NULL, classification = "")
new_group <- function(bindings, rec_position) list(bindings = bindings, rec_position = rec_position)
new_item <- function(kind, value) list(kind = kind, value = value)
syntax_failure <- function(token) stop(structure(list(message = "syntax failure", token = token), class = c("syntax_failure", "error", "condition")))
new_parser <- function(tokens) new_record(tokens = tokens, index = 1L)
next_token <- function(parser) parser$tokens[[parser$index]]
accept_token <- function(parser, kind) {
  if (next_token(parser)$kind != kind) return(NULL)
  token <- next_token(parser)
  parser$index <- parser$index + 1L
  token
}
expect_token <- function(parser, kind) {
  token <- accept_token(parser, kind)
  if (is.null(token)) syntax_failure(next_token(parser))
  token
}
parse_name <- function(parser) {
  if (!is_name(next_token(parser))) syntax_failure(next_token(parser))
  expect_token(parser, "identifier")
}
recover <- function(parser) {
  while (!next_token(parser)$kind %in% c(";;", "EOF")) parser$index <- parser$index + 1L
  accept_token(parser, ";;")
}
parse_item <- function(parser) {
  if (!is.null(accept_token(parser, "val"))) {
    name <- parse_name(parser)
    expect_token(parser, ":")
    declared <- parse_type(parser)
    expect_token(parser, ";;")
    return(new_item("signature", list(name, declared)))
  }
  opening <- accept_token(parser, "let")
  if (!is.null(opening)) {
    group <- parse_group(parser)
    if (!is.null(accept_token(parser, "in"))) {
      result <- new_item("expression", ml_node("let", opening$position, list(parse_expression(parser)), group))
    } else {
      result <- new_item("declaration", group)
    }
  } else {
    result <- new_item("expression", parse_expression(parser))
  }
  expect_token(parser, ";;")
  result
}
parse_group <- function(parser) {
  rec <- accept_token(parser, "rec")
  bindings <- list(parse_binding(parser))
  while (!is.null(accept_token(parser, "and"))) bindings[[length(bindings) + 1L]] <- parse_binding(parser)
  new_group(bindings, if (is.null(rec)) NULL else rec$position)
}
parse_binding <- function(parser) {
  name <- parse_name(parser)
  parameters <- list()
  while (next_token(parser)$kind == "identifier") parameters[[length(parameters) + 1L]] <- expect_token(parser, "identifier")
  expect_token(parser, "=")
  expression <- parse_expression(parser)
  for (parameter in rev(parameters)) expression <- ml_node("fun", parameter$position, list(expression), parameter)
  new_binding(name, expression)
}
parse_expression <- function(parser) {
  opening <- accept_token(parser, "let")
  if (!is.null(opening)) {
    group <- parse_group(parser)
    expect_token(parser, "in")
    return(ml_node("let", opening$position, list(parse_expression(parser)), group))
  }
  opening <- accept_token(parser, "fun")
  if (!is.null(opening)) {
    parameters <- list(expect_token(parser, "identifier"))
    while (next_token(parser)$kind == "identifier") parameters[[length(parameters) + 1L]] <- expect_token(parser, "identifier")
    expect_token(parser, "->")
    expression <- parse_expression(parser)
    for (parameter in rev(parameters)) expression <- ml_node("fun", parameter$position, list(expression), parameter)
    expression$position <- opening$position
    return(expression)
  }
  opening <- accept_token(parser, "if")
  if (!is.null(opening)) {
    condition <- parse_expression(parser)
    expect_token(parser, "then")
    first <- parse_expression(parser)
    expect_token(parser, "else")
    second <- parse_expression(parser)
    return(ml_node("if", opening$position, list(condition, first, second)))
  }
  opening <- accept_token(parser, "match")
  if (!is.null(opening)) {
    expression <- parse_expression(parser)
    expect_token(parser, "with")
    accept_token(parser, "|")
    arms <- list(parse_arm(parser))
    while (!is.null(accept_token(parser, "|"))) arms[[length(arms) + 1L]] <- parse_arm(parser)
    return(ml_node("match", opening$position, list(expression), arms))
  }
  parse_binary(parser, 1L)
}
parse_arm <- function(parser) {
  pattern <- parse_pattern(parser)
  expect_token(parser, "->")
  list(pattern, parse_expression(parser))
}
parse_binary <- function(parser, minimum) {
  expression <- parse_unary(parser)
  repeat {
    entry <- OPERATORS[[next_token(parser)$kind]]
    if (is.null(entry) || entry[[1L]] < minimum) return(expression)
    operator <- next_token(parser)
    parser$index <- parser$index + 1L
    right <- parse_binary(parser, if (entry[[2L]]) entry[[1L]] else entry[[1L]] + 1L)
    expression <- ml_node("binary", expression$position, list(expression, right), operator)
  }
}
starts_atom <- function(parser) next_token(parser)$kind %in% c("integer", "string", "true", "false", "(", "[") || is_name(next_token(parser))
parse_unary <- function(parser) {
  operator <- accept_token(parser, "-")
  if (!is.null(operator)) return(ml_node("negate", operator$position, list(parse_unary(parser)), operator))
  expression <- parse_atom(parser)
  while (starts_atom(parser)) expression <- ml_node("apply", expression$position, list(expression, parse_atom(parser)))
  expression
}
parse_atom <- function(parser) {
  token <- next_token(parser)
  if (token$kind %in% c("integer", "string")) {
    parser$index <- parser$index + 1L
    return(ml_node(token$kind, token$position, value = token$value))
  }
  if (token$kind %in% c("true", "false")) {
    parser$index <- parser$index + 1L
    return(ml_node("boolean", token$position, value = token$kind == "true"))
  }
  if (is_name(token)) {
    parser$index <- parser$index + 1L
    return(ml_node("name", token$position, value = token$spelling))
  }
  if (!is.null(accept_token(parser, "("))) {
    first <- parse_expression(parser)
    if (!is.null(accept_token(parser, ","))) {
      second <- parse_expression(parser)
      expect_token(parser, ")")
      return(ml_node("pair", token$position, list(first, second)))
    }
    expect_token(parser, ")")
    return(first)
  }
  if (!is.null(accept_token(parser, "["))) {
    elements <- list()
    if (is.null(accept_token(parser, "]"))) {
      elements <- list(parse_expression(parser))
      while (!is.null(accept_token(parser, ";"))) elements[[length(elements) + 1L]] <- parse_expression(parser)
      expect_token(parser, "]")
    }
    return(ml_node("list", token$position, elements))
  }
  syntax_failure(token)
}
parse_pattern <- function(parser) {
  first <- parse_pattern_atom(parser)
  if (is.null(accept_token(parser, "::"))) first else ml_node("cons", first$position, list(first, parse_pattern(parser)))
}
parse_pattern_atom <- function(parser) {
  token <- next_token(parser)
  if (token$kind == "identifier") {
    parser$index <- parser$index + 1L
    return(ml_node(if (token$spelling == "_") "wildcard" else "name", token$position, value = token$spelling))
  }
  if (!is.null(accept_token(parser, "-"))) {
    integer <- expect_token(parser, "integer")
    return(ml_node("integer", token$position, value = -integer$value))
  }
  if (token$kind %in% c("integer", "string", "true", "false")) return(parse_atom(parser))
  if (!is.null(accept_token(parser, "("))) {
    first <- parse_pattern(parser)
    if (!is.null(accept_token(parser, ","))) {
      second <- parse_pattern(parser)
      expect_token(parser, ")")
      return(ml_node("pair", token$position, list(first, second)))
    }
    expect_token(parser, ")")
    return(first)
  }
  if (!is.null(accept_token(parser, "["))) {
    elements <- list()
    if (is.null(accept_token(parser, "]"))) {
      elements <- list(parse_pattern(parser))
      while (!is.null(accept_token(parser, ";"))) elements[[length(elements) + 1L]] <- parse_pattern(parser)
      expect_token(parser, "]")
    }
    return(ml_node("list", token$position, elements))
  }
  syntax_failure(token)
}
parse_type <- function(parser) {
  first <- parse_list_type(parser)
  if (!is.null(accept_token(parser, "*"))) first <- ml_node("pair", first$position, list(first, parse_list_type(parser)))
  if (!is.null(accept_token(parser, "->"))) first <- ml_node("function", first$position, list(first, parse_type(parser)))
  first
}
parse_list_type <- function(parser) {
  expression <- parse_type_atom(parser)
  while (next_token(parser)$kind == "identifier" && next_token(parser)$spelling == "list") {
    parser$index <- parser$index + 1L
    expression <- ml_node("list", expression$position, list(expression))
  }
  expression
}
parse_type_atom <- function(parser) {
  token <- next_token(parser)
  if (token$kind == "identifier" && token$spelling %in% c("int", "bool", "string")) {
    parser$index <- parser$index + 1L
    return(ml_node(token$spelling, token$position))
  }
  if (!is.null(accept_token(parser, "type_variable"))) return(ml_node("type_variable", token$position, value = token$spelling))
  if (!is.null(accept_token(parser, "("))) {
    expression <- parse_type(parser)
    expect_token(parser, ")")
    return(expression)
  }
  syntax_failure(token)
}
