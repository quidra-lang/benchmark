ast <- function(operation,...) list(operation=operation,arguments=list(...))
expression_tokens <- function(text) {
  tokens <- character()
  i <- 1L
  n <- nchar(text)
  at <- function(i) substr(text,i,i)
  while (i <= n) {
    if (at(i) == " ") {
      i <- i+1L
      next
    }
    first <- i
    if (at(i) == '"') {
      i <- i+1L
      while (at(i) != '"') i <- i+1L
      i <- i+1L
    } else if (at(i) %in% as.character(0L:9L)) {
      while (i <= n && at(i) %in% as.character(0L:9L)) i <- i+1L
    } else if (at(i) %in% c(LETTERS,letters)) {
      while (i <= n && at(i) %in% c(LETTERS,letters,as.character(0L:9L),"_",".")) i <- i+1L
    } else if (i < n && substr(text,i,i+1L) %in% c("==","!=","<=",">=")) i <- i+2L else i <- i+1L
    tokens <- c(tokens,substr(text,first,i-1L))
  }
  tokens
}
peek <- function(p) if (p$position <= length(p$tokens)) p$tokens[p$position] else ""
take_token <- function(p) {
  token <- p$tokens[p$position]
  p$position <- p$position+1L
  token
}
joined_expression <- function(p,next_level,operators) {
  result <- next_level(p)
  while (peek(p) %in% operators) {
    op <- take_token(p)
    result <- ast(op,result,next_level(p))
  }
  result
}
disjunction <- function(p) joined_expression(p,conjunction,"or")
conjunction <- function(p) joined_expression(p,negation,"and")
negation <- function(p) {
  if (peek(p) == "not") {
    take_token(p)
    return(ast("not",negation(p)))
  }
  comparison(p)
}
comparison <- function(p) {
  result <- expression_sum(p)
  if (peek(p) %in% c("==","!=","<","<=",">",">=","in")) {
    op <- take_token(p)
    result <- ast(op,result,expression_sum(p))
  }
  result
}
expression_sum <- function(p) joined_expression(p,expression_product,c("+","-"))
expression_product <- function(p) joined_expression(p,unary,"*")
unary <- function(p) {
  if (peek(p) == "-") {
    take_token(p)
    return(ast("-",unary(p)))
  }
  primary(p)
}
primary <- function(p) {
  token <- take_token(p)
  if (grepl("^[0-9]+$",token)) return(ast("literal",as.integer(token)))
  if (startsWith(token,'"')) return(ast("literal",substr(token,2L,nchar(token)-1L)))
  if (token %in% c("true","false")) return(ast("literal",token == "true"))
  if (token == "it") return(ast("it"))
  if (grepl(".",token,fixed=TRUE)) return(ast("attribute",token))
  if (token == "(") {
    result <- disjunction(p)
    take_token(p)
    return(result)
  }
  if (token == "[") {
    values <- character()
    while (peek(p) != "]") {
      value <- take_token(p)
      values <- c(values,substr(value,2L,nchar(value)-1L))
      if (peek(p) != "]") take_token(p)
    }
    take_token(p)
    return(ast("literal",structure(list(items=values),class="policy_bag")))
  }
  take_token(p)
  arguments <- list()
  while (peek(p) != ")") {
    arguments[[length(arguments)+1L]] <- disjunction(p)
    if (peek(p) != ")") take_token(p)
  }
  take_token(p)
  list(operation=token,arguments=arguments)
}
parse_expression <- function(text) {
  p <- new.env(parent=emptyenv())
  p$tokens <- expression_tokens(text)
  p$position <- 1L
  disjunction(p)
}
