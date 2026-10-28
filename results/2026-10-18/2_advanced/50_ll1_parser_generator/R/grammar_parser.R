END_MARKER <- "$"
is_nonterminal <- function(symbol) startsWith(symbol,"<") && endsWith(symbol,">")
format_alternative <- function(symbols) if (length(symbols)) paste(symbols,collapse=" ") else "%empty"
format_production <- function(symbol,alternative) paste(symbol,"->",format_alternative(alternative))
lex_line <- function(line) {
  tokens <- list()
  i <- 1L
  n <- nchar(line,type="bytes")
  while (i <= n) {
    character <- substr(line,i,i)
    if (character == " ") {
      i <- i+1L
      next
    }
    if (character == "#") break
    start <- i
    suffix <- substring(line,i)
    kind <- "invalid"
    value <- character
    if (character == "<") {
      matched <- regexpr("^<[A-Za-z][A-Za-z0-9_]*>",suffix)
      if (matched[1L] == 1L) {
        kind <- "nonterminal"
        value <- regmatches(suffix,matched)
        i <- i+nchar(value)
      } else i <- i+1L
    } else if (character == '"') {
      j <- i+1L
      while (j <= n && !substr(line,j,j) %in% c(" ",'"')) j <- j+1L
      if (j > i+1L && j <= n && substr(line,j,j) == '"') {
        kind <- "terminal"
        value <- substr(line,i+1L,j-1L)
        i <- j+1L
      } else i <- i+1L
    } else if (grepl("^[A-Za-z]$",character)) {
      matched <- regexpr("^[A-Za-z][A-Za-z0-9_]*",suffix)
      kind <- "word"
      value <- regmatches(suffix,matched)
      i <- i+nchar(value)
    } else if (startsWith(suffix,"::=")) {
      kind <- "definition"
      value <- "::="
      i <- i+3L
    } else if (character == "|") {
      kind <- "separator"
      value <- "|"
      i <- i+1L
    } else if (character == "%") {
      directive <- regmatches(suffix,regexpr("^%[A-Za-z]*",suffix))
      if (directive %in% c("%empty","%start","%token")) {
        kind <- "directive"
        value <- directive
        i <- i+nchar(value)
      } else i <- i+1L
    } else i <- i+1L
    tokens[[length(tokens)+1L]] <- list(kind=kind,value=value,start=start,finish=i-1L)
    if (kind == "invalid") break
  }
  tokens
}
error_column <- function(
    tokens,
    cursor
) if (cursor <= length(tokens)) tokens[[cursor]]$start else tail(tokens,1L)[[1L]]$finish+1L
alternative_list <- function(tokens,cursor) {
  alternatives <- list()
  repeat {
    if (cursor > length(tokens)) return(list(alternatives=alternatives,error=error_column(tokens,cursor)))
    token <- tokens[[cursor]]
    if (token$kind == "directive" && token$value == "%empty") {
      alternative <- character()
      cursor <- cursor+1L
    } else if (token$kind %in% c("nonterminal","terminal","word")) {
      alternative <- character()
      while (cursor <= length(tokens) && tokens[[cursor]]$kind %in% c("nonterminal","terminal","word")) {
        alternative <- c(alternative,tokens[[cursor]]$value)
        cursor <- cursor+1L
      }
    } else return(list(alternatives=alternatives,error=error_column(tokens,cursor)))
    alternatives[[length(alternatives)+1L]] <- alternative
    if (cursor > length(tokens)) return(list(alternatives=alternatives,error=0L))
    if (tokens[[cursor]]$kind != "separator") return(list(
        alternatives=alternatives,
        error=error_column(tokens,cursor)
    ))
    cursor <- cursor+1L
  }
}
parse_line <- function(tokens) {
  result <- function(kind,lhs="",alternatives=list(),error=0L) list(
      kind=kind,
      lhs=lhs,
      alternatives=alternatives,
      error=error
  )
  if (!length(tokens)) return(result("blank"))
  token <- tokens[[1L]]
  if (token$kind == "nonterminal") {
    if (length(tokens) < 2L || tokens[[2L]]$kind != "definition") return(result(
        "rule",
        error=error_column(tokens,2L)
    ))
    parsed <- alternative_list(tokens,3L)
    return(result("rule",token$value,parsed$alternatives,parsed$error))
  }
  if (token$kind == "separator") {
    parsed <- alternative_list(tokens,2L)
    return(result("continuation",alternatives=parsed$alternatives,error=parsed$error))
  }
  if (token$kind == "directive" && token$value == "%start") {
    cursor <- if (length(tokens) < 2L || tokens[[2L]]$kind != "nonterminal") 2L else if (length(tokens) > 2L) 3L else 0L
    return(result(
        "start",
        lhs=if (cursor == 0L) tokens[[2L]]$value else "",
        error=if (cursor == 0L) 0L else error_column(tokens,cursor)
    ))
  }
  if (token$kind == "directive" && token$value == "%token") {
    bad <- if (length(tokens) < 2L) 2L else 0L
    if (length(tokens) >= 2L) for (i in seq.int(2L,length(tokens))) if (tokens[[i]]$kind != "word") {
      bad <- i
      break
    }
    words <- if (bad == 0L) vapply(tokens[-1L],function(t) t$value,character(1)) else character()
    return(result(
        "declaration",
        alternatives=list(words),
        error=if (bad == 0L) 0L else error_column(tokens,bad)
    ))
  }
  result("invalid",error=token$start)
}
parse_grammar <- function() {
  order <- character()
  rules <- list()
  start <- attachment <- ""
  declared <- character()
  word_lines <- integer()
  diagnostics <- character()
  has_declaration <- FALSE
  lines <- readLines("input/grammar.bnf")
  for (line_number in seq_along(lines)) {
    tokens <- lex_line(lines[line_number])
    parsed <- parse_line(tokens)
    if (parsed$error != 0L) {
      diagnostics <- c(diagnostics,paste0("line ",line_number,": syntax error at column ",parsed$error))
      attachment <- ""
      next
    }
    kind <- parsed$kind
    lhs <- parsed$lhs
    if (kind == "blank") next
    if (kind == "rule") {
      attachment <- lhs
      if (!lhs %in% names(rules)) {
        order <- c(order,lhs)
        rules[[lhs]] <- list()
      }
    } else if (kind == "continuation") {
      if (!nzchar(attachment)) {
        diagnostics <- c(diagnostics,paste0("line ",line_number,": continuation without a rule"))
        next
      }
      lhs <- attachment
    } else if (kind == "start") {
      attachment <- ""
      if (!nzchar(start)) start <- lhs else diagnostics <- c(
          diagnostics,
          paste0("line ",line_number,": duplicate %start")
      )
    } else {
      attachment <- ""
      has_declaration <- TRUE
      declared <- union(declared,parsed$alternatives[[1L]])
    }
    if (kind %in% c("rule","continuation")) {
      for (token in tokens) if (token$kind == "word" && !token$value %in% names(word_lines)) word_lines[token$value] <- line_number
      for (alternative in parsed$alternatives) {
        duplicate <- any(vapply(rules[[lhs]],function(existing) identical(existing,alternative),logical(1)))
        if (duplicate) diagnostics <- c(
            diagnostics,
            paste0("line ",line_number,": duplicate alternative ",format_production(lhs,alternative))
        ) else
          rules[[lhs]][[length(rules[[lhs]])+1L]] <- alternative
      }
    }
  }
  list(grammar=list(order=order,rules=rules,start=if (nzchar(start)) start else order[1L]),declared=declared,words=word_lines,
    has_declaration=has_declaration,diagnostics=diagnostics)
}
