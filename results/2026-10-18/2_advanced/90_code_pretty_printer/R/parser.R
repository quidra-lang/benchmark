PRECEDENCE <- c("||" = 1L, "&&" = 2L, "==" = 3L, "!=" = 3L, "<" = 4L, "<=" = 4L, ">" = 4L, ">=" = 4L, "+" = 5L, "-" = 5L, "*" = 6L, "/" = 6L, "%" = 6L)
syntax_node <- function(tag, first, ...) c(list(tag = tag, first = first), list(...))
new_parser <- function(tokens) new_record(tokens = tokens, cursor = 1L)
next_token <- function(parser) parser$tokens[[parser$cursor]]
at_symbol <- function(parser, symbol) next_token(parser)$text == symbol
syntax_error <- function(parser, expected) {
  token <- next_token(parser)
  found <- if (token$kind == "end") "end of file" else paste0("'", token$text, "'")
  source_error(token$line, token$column, paste0("expected ", expected, ", found ", found))
}
take_symbol <- function(parser, symbol) {
  if (!at_symbol(parser, symbol)) syntax_error(parser, paste0("'", symbol, "'"))
  token <- next_token(parser)
  parser$cursor <- parser$cursor + 1L
  token
}
take_identifier <- function(parser) {
  if (next_token(parser)$kind != "identifier") syntax_error(parser, "identifier")
  token <- next_token(parser)
  parser$cursor <- parser$cursor + 1L
  token
}
take_type <- function(parser) {
  if (!next_token(parser)$text %in% TYPE_NAMES) syntax_error(parser, "type")
  token <- next_token(parser)
  parser$cursor <- parser$cursor + 1L
  token
}
parse_program <- function(parser) {
  items <- list()
  while (next_token(parser)$kind != "end") {
    typ <- take_type(parser)
    typ$allowed <- TRUE
    name <- take_identifier(parser)
    if (at_symbol(parser, "(")) {
      parameters <- parse_list(parser, "(", ")", parse_parameter, FALSE)
      body <- parse_block(parser)
      item <- syntax_node("function", typ, typ = typ, name = name, parameters = parameters, body = body)
    } else {
      item <- parse_variable(parser, typ, name, TRUE)
    }
    items[[length(items) + 1L]] <- item
  }
  items
}
parse_parameter <- function(parser) {
  typ <- take_type(parser)
  name <- take_identifier(parser)
  brackets <- list()
  while (at_symbol(parser, "[")) {
    left <- take_symbol(parser, "[")
    right <- take_symbol(parser, "]")
    brackets[[length(brackets) + 1L]] <- list(left, right)
  }
  syntax_node("parameter", typ, typ = typ, name = name, brackets = brackets)
}
parse_variable <- function(parser, typ, name, semicolon) {
  dimensions <- list()
  while (at_symbol(parser, "[")) {
    left <- take_symbol(parser, "[")
    expression <- if (at_symbol(parser, "]")) NULL else parse_expression(parser)
    right <- take_symbol(parser, "]")
    dimensions[[length(dimensions) + 1L]] <- list(left, expression, right)
  }
  equals <- if (at_symbol(parser, "=")) take_symbol(parser, "=") else NULL
  initializer <- if (is.null(equals)) NULL else parse_initializer(parser)
  semi <- if (semicolon) take_symbol(parser, ";") else NULL
  syntax_node("variable", typ, typ = typ, name = name, dimensions = dimensions, equals = equals, initializer = initializer, semi = semi)
}
parse_initializer <- function(parser) {
  if (at_symbol(parser, "{")) parse_list(parser, "{", "}", parse_initializer, TRUE) else parse_expression(parser)
}
parse_list <- function(parser, opening, closing, element, trailing_allowed) {
  left <- take_symbol(parser, opening)
  elements <- commas <- list()
  trailing <- NULL
  if (!at_symbol(parser, closing)) {
    item <- element(parser)
    item$first$allowed <- TRUE
    elements[[1L]] <- item
    while (at_symbol(parser, ",")) {
      comma <- take_symbol(parser, ",")
      if (trailing_allowed && at_symbol(parser, closing)) {
        comma$trailing_comma <- TRUE
        trailing <- comma
        break
      }
      commas[[length(commas) + 1L]] <- comma
      item <- element(parser)
      item$first$allowed <- TRUE
      elements[[length(elements) + 1L]] <- item
    }
  }
  right <- take_symbol(parser, closing)
  syntax_node("list", left, left = left, right = right, elements = elements, commas = commas, trailing = trailing, role = opening)
}
parse_block <- function(parser) {
  left <- take_symbol(parser, "{")
  statements <- list()
  while (!at_symbol(parser, "}") && next_token(parser)$kind != "end") {
    item <- parse_statement(parser)
    item$first$allowed <- TRUE
    statements[[length(statements) + 1L]] <- item
  }
  right <- take_symbol(parser, "}")
  right$allowed <- TRUE
  syntax_node("block", left, left = left, right = right, statements = statements)
}
parse_statement <- function(parser) {
  token <- next_token(parser)
  if (token$text == "{") return(parse_block(parser))
  if (token$text %in% TYPE_NAMES) {
    typ <- take_type(parser)
    name <- take_identifier(parser)
    return(parse_variable(parser, typ, name, TRUE))
  }
  if (token$text == "if") return(parse_if(parser))
  if (token$text == "for") return(parse_for(parser))
  if (token$text == "switch") return(parse_switch(parser))
  if (token$text == "while") {
    keyword <- take_symbol(parser, "while")
    left <- take_symbol(parser, "(")
    test <- parse_expression(parser)
    right <- take_symbol(parser, ")")
    body <- parse_body(parser)
    return(syntax_node("while", keyword, keyword = keyword, left = left, test = test, right = right, body = body))
  }
  if (token$text == "return") {
    keyword <- take_symbol(parser, "return")
    expr <- if (at_symbol(parser, ";")) NULL else parse_expression(parser)
    semi <- take_symbol(parser, ";")
    return(syntax_node("return", keyword, keyword = keyword, expr = expr, semi = semi))
  }
  if (token$text %in% c("break", "continue")) {
    parser$cursor <- parser$cursor + 1L
    semi <- take_symbol(parser, ";")
    return(syntax_node("flow", token, keyword = token, semi = semi))
  }
  value <- parse_simple(parser)
  semi <- take_symbol(parser, ";")
  syntax_node("simple_stmt", value$first, value = value, semi = semi)
}
parse_body <- function(parser) {
  body <- parse_statement(parser)
  if (body$tag != "block") body$first$allowed <- TRUE
  body
}
parse_if <- function(parser) {
  keyword <- take_symbol(parser, "if")
  left <- take_symbol(parser, "(")
  test <- parse_expression(parser)
  right <- take_symbol(parser, ")")
  body <- parse_body(parser)
  else_token <- if (at_symbol(parser, "else")) take_symbol(parser, "else") else NULL
  alternative <- NULL
  if (!is.null(else_token)) {
    if (at_symbol(parser, "if")) {
      alternative <- parse_if(parser)
      alternative$first$allowed <- FALSE
    } else {
      alternative <- parse_body(parser)
    }
  }
  syntax_node("if", keyword, keyword = keyword, left = left, test = test, right = right, body = body, else_token = else_token, alternative = alternative)
}
parse_for <- function(parser) {
  keyword <- take_symbol(parser, "for")
  left <- take_symbol(parser, "(")
  if (at_symbol(parser, ";")) {
    initial <- NULL
  } else if (next_token(parser)$text %in% TYPE_NAMES) {
    typ <- take_type(parser)
    name <- take_identifier(parser)
    initial <- parse_variable(parser, typ, name, FALSE)
  } else {
    initial <- parse_simple(parser)
  }
  first_semi <- take_symbol(parser, ";")
  condition <- if (at_symbol(parser, ";")) NULL else parse_expression(parser)
  second_semi <- take_symbol(parser, ";")
  update <- if (at_symbol(parser, ")")) NULL else parse_simple(parser)
  right <- take_symbol(parser, ")")
  body <- parse_body(parser)
  syntax_node("for", keyword, keyword = keyword, left = left, initial = initial, first_semi = first_semi, condition = condition, second_semi = second_semi, update = update, right = right, body = body)
}
parse_switch <- function(parser) {
  keyword <- take_symbol(parser, "switch")
  left <- take_symbol(parser, "(")
  test <- parse_expression(parser)
  right <- take_symbol(parser, ")")
  opening <- take_symbol(parser, "{")
  clauses <- list()
  while (next_token(parser)$text %in% c("case", "default")) {
    label <- next_token(parser)
    parser$cursor <- parser$cursor + 1L
    label$allowed <- TRUE
    value <- if (label$text == "case") parse_expression(parser) else NULL
    colon <- take_symbol(parser, ":")
    statements <- list()
    while (!next_token(parser)$text %in% c("case", "default", "}") && next_token(parser)$kind != "end") {
      item <- parse_statement(parser)
      item$first$allowed <- TRUE
      statements[[length(statements) + 1L]] <- item
    }
    clauses[[length(clauses) + 1L]] <- syntax_node("clause", label, label = label, value = value, colon = colon, statements = statements)
  }
  closing <- take_symbol(parser, "}")
  closing$allowed <- TRUE
  syntax_node("switch", keyword, keyword = keyword, left = left, test = test, right = right, opening = opening, closing = closing, clauses = clauses)
}
parse_simple <- function(parser) {
  left <- parse_expression(parser)
  if (next_token(parser)$text %in% ASSIGNMENTS) {
    op <- next_token(parser)
    parser$cursor <- parser$cursor + 1L
    right <- parse_expression(parser)
    return(syntax_node("assign", left$first, left = left, op = op, right = right))
  }
  syntax_node("expr_stmt", left$first, expr = left)
}
parse_expression <- function(parser) {
  test <- parse_binary(parser, 1L)
  if (!at_symbol(parser, "?")) return(test)
  question <- take_symbol(parser, "?")
  yes <- parse_expression(parser)
  colon <- take_symbol(parser, ":")
  no <- parse_expression(parser)
  syntax_node("conditional", test$first, test = test, question = question, yes = yes, colon = colon, no = no, level = 0L)
}
parse_binary <- function(parser, precedence) {
  if (precedence > 6L) return(parse_unary(parser))
  left <- parse_binary(parser, precedence + 1L)
  repeat {
    rank <- unname(PRECEDENCE[next_token(parser)$text])
    if (is.na(rank) || rank != precedence) return(left)
    op <- next_token(parser)
    parser$cursor <- parser$cursor + 1L
    right <- parse_binary(parser, precedence + 1L)
    left <- syntax_node("binary", left$first, left = left, op = op, right = right, level = precedence)
  }
}
parse_unary <- function(parser) {
  if (next_token(parser)$text %in% c("-", "!")) {
    op <- next_token(parser)
    parser$cursor <- parser$cursor + 1L
    operand <- parse_unary(parser)
    return(syntax_node("unary", op, op = op, operand = operand, level = 7L))
  }
  target <- parse_primary(parser)
  repeat {
    if (at_symbol(parser, "(")) {
      arguments <- parse_list(parser, "(", ")", parse_expression, FALSE)
      target <- syntax_node("call", target$first, target = target, arguments = arguments, level = 8L)
    } else if (at_symbol(parser, "[")) {
      left <- take_symbol(parser, "[")
      index <- parse_expression(parser)
      right <- take_symbol(parser, "]")
      target <- syntax_node("index", target$first, target = target, left = left, index = index, right = right, level = 8L)
    } else if (at_symbol(parser, ".")) {
      dot <- take_symbol(parser, ".")
      member <- take_identifier(parser)
      target <- syntax_node("member", target$first, target = target, dot = dot, member = member, level = 8L)
    } else {
      return(target)
    }
  }
}
parse_primary <- function(parser) {
  token <- next_token(parser)
  if (token$kind %in% c("identifier", "number", "string") || token$text %in% c("true", "false")) {
    parser$cursor <- parser$cursor + 1L
    return(syntax_node("primary", token, value = token, level = 8L))
  }
  if (at_symbol(parser, "(")) {
    left <- take_symbol(parser, "(")
    inner <- parse_expression(parser)
    right <- take_symbol(parser, ")")
    return(syntax_node("paren", left, left = left, inner = inner, right = right, level = 8L))
  }
  syntax_error(parser, "expression")
}
