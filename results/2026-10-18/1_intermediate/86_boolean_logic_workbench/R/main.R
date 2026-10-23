options(expressions = 50000)

precedence <- c("<->" = 1L, "->" = 2L, "|" = 3L, "^" = 4L, "&" = 5L)
logic_error <- function(message) stop(structure(list(message = message, call = NULL), class = c("logic_error", "error", "condition")))
bool_variable <- function(name) list(kind = "variable", value = name)
bool_constant <- function(value) list(kind = "constant", value = as.integer(value))
bool_not <- function(node) list(kind = "not", child = node)
bool_binary <- function(op, left, right) {
  force(left)
  force(right)
  list(kind = op, left = left, right = right)
}
is_binary <- function(node) node$kind %in% names(precedence)
notation <- function(node) {
  if (node$kind %in% c("variable", "constant")) return(as.character(node$value))
  if (node$kind == "not") {
    text <- notation(node$child)
    return(paste0("~", if (is_binary(node$child)) paste0("(", text, ")") else text))
  }
  op <- node$kind
  a <- node$left
  b <- node$right
  left <- notation(a)
  right <- notation(b)
  if (is_binary(a) && (precedence[[a$kind]] < precedence[[op]] || (a$kind == "->" && op == "->"))) left <- paste0("(", left, ")")
  if (is_binary(b) && (precedence[[b$kind]] < precedence[[op]] || (b$kind == op && op != "->"))) right <- paste0("(", right, ")")
  paste(left, op, right)
}
variable_names <- function(node) {
  if (node$kind == "variable") return(node$value)
  if (node$kind == "constant") return(character())
  if (node$kind == "not") return(variable_names(node$child))
  sort(unique(c(variable_names(node$left), variable_names(node$right))), method = "radix")
}
measures <- function(node) {
  if (node$kind %in% c("variable", "constant")) return(c(1L, 1L))
  a <- measures(if (node$kind == "not") node$child else node$left)
  if (node$kind == "not") return(a + 1L)
  b <- measures(node$right)
  c(a[[1]] + b[[1]] + 1L, max(a[[2]], b[[2]]) + 1L)
}
parse_formula <- function(text, start, definitions) {
  tokens <- list()
  i <- 1L
  while (i <= nchar(text)) {
    c <- substr(text, i, i)
    if (c == " ") {
      i <- i + 1L
      next
    }
    from <- i
    if (substr(text, i, i + 2L) == "<->") {
      i <- i + 3L
    } else if (substr(text, i, i + 1L) == "->") {
      i <- i + 2L
    } else if (grepl("^[a-z]$", c)) {
      i <- i + 1L
      while (i <= nchar(text) && grepl("^[a-z0-9]$", substr(text, i, i))) i <- i + 1L
    } else if (c %in% c(LETTERS, "0", "1", "~", "&", "^", "|", "(", ")")) {
      i <- i + 1L
    } else {
      logic_error(paste0("invalid character '", c, "' at ", start + i - 1L))
    }
    tokens[[length(tokens) + 1L]] <- list(text = substr(text, from, i - 1L), position = start + from - 1L)
  }
  tokens[[length(tokens) + 1L]] <- list(text = "", position = start + nchar(text))
  position <- 1L
  peek <- function() tokens[[position]]$text
  advance <- function() {
    result <- peek()
    position <<- position + 1L
    result
  }
  unexpected <- function() {
    token <- tokens[[position]]
    logic_error(if (token$text == "") paste0("unexpected end of formula at ", token$position) else paste0("unexpected '", token$text, "' at ", token$position))
  }
  unary <- function() {
    if (peek() == "~") {
      advance()
      return(bool_not(unary()))
    }
    if (peek() == "(") {
      advance()
      result <- expression(1L)
      if (peek() != ")") unexpected()
      advance()
      return(result)
    }
    if (grepl("^[A-Z]$", peek())) return(bool_variable(advance()))
    if (peek() %in% c("0", "1")) return(bool_constant(as.integer(advance())))
    if (grepl("^[a-z][a-z0-9]*$", peek())) {
      token <- tokens[[position]]
      if (is.null(definitions[[token$text]])) logic_error(paste0("undefined name '", token$text, "' at ", token$position))
      advance()
      return(definitions[[token$text]])
    }
    unexpected()
  }
  expression <- function(level) {
    if (level == 6L) return(unary())
    op <- c("<->", "->", "|", "^", "&")[[level]]
    result <- expression(level + 1L)
    while (peek() == op) {
      advance()
      result <- bool_binary(op, result, expression(if (op == "->") level else level + 1L))
    }
    result
  }
  result <- expression(1L)
  if (peek() != "") unexpected()
  result
}
nnf <- function(node, positive = TRUE) {
  memo <- list()
  serial <- 0L
  visit <- function(current, sign) {
    key <- paste0(if (sign) "p" else "n", paste(as.integer(serialize(current, NULL)), collapse = "."))
    if (!is.null(memo[[key]])) return(memo[[key]])
    if (current$kind == "variable") {
      result <- if (sign) current else bool_not(current)
    } else if (current$kind == "constant") {
      result <- bool_constant(if (sign) current$value else 1L - current$value)
    } else if (current$kind == "not") {
      result <- visit(current$child, !sign)
    } else if (current$kind %in% c("&", "|")) {
      op <- if (sign) current$kind else if (current$kind == "&") "|" else "&"
      result <- bool_binary(op, visit(current$left, sign), visit(current$right, sign))
    } else if (current$kind == "->") {
      result <- bool_binary(if (sign) "|" else "&", visit(current$left, !sign), visit(current$right, sign))
    } else {
      same <- if (current$kind == "<->") sign else !sign
      result <- bool_binary("|", bool_binary("&", visit(current$left, TRUE), visit(current$right, same)),
                            bool_binary("&", visit(current$left, FALSE), visit(current$right, !same)))
    }
    serial <<- serial + 1L
    attr(result, "memo_id") <- serial
    memo[[key]] <<- result
    result
  }
  visit(node, positive)
}

dual <- function(node) {
  if (node$kind == "variable") return(node)
  if (node$kind == "constant") return(bool_constant(1L - node$value))
  if (node$kind == "not") return(bool_not(dual(node$child)))
  if (node$kind == "->") return(bool_binary("&", bool_not(dual(node$left)), dual(node$right)))
  op <- c("&" = "|", "|" = "&", "^" = "<->", "<->" = "^")[[node$kind]]
  bool_binary(op, dual(node$left), dual(node$right))
}
reduce_negation <- function(node) {
  if (node$kind == "constant") return(bool_constant(1L - node$value))
  if (node$kind == "not") node$child else bool_not(node)
}
simplify_binary <- function(op, a, b) {
  zero <- bool_constant(0L)
  one <- bool_constant(1L)
  equal <- identical(a, b)
  complementary <- identical(a, bool_not(b)) || identical(b, bool_not(a))
  if (op == "&") {
    if (identical(a, zero) || identical(b, zero)) return(zero)
    if (identical(a, one)) return(b)
    if (identical(b, one) || equal) return(a)
    if (complementary) return(zero)
  } else if (op == "|") {
    if (identical(a, one) || identical(b, one)) return(one)
    if (identical(a, zero)) return(b)
    if (identical(b, zero) || equal) return(a)
    if (complementary) return(one)
  } else if (op == "^") {
    if (identical(a, zero)) return(b)
    if (identical(b, zero)) return(a)
    if (identical(a, one)) return(reduce_negation(b))
    if (identical(b, one)) return(reduce_negation(a))
    if (equal) return(zero)
    if (complementary) return(one)
  } else if (op == "->") {
    if (identical(a, zero) || identical(b, one)) return(one)
    if (identical(a, one)) return(b)
    if (identical(b, zero)) return(reduce_negation(a))
    if (equal) return(one)
    if (complementary) return(b)
  } else {
    if (identical(a, one)) return(b)
    if (identical(b, one)) return(a)
    if (identical(a, zero)) return(reduce_negation(b))
    if (identical(b, zero)) return(reduce_negation(a))
    if (equal) return(one)
    if (complementary) return(zero)
  }
  bool_binary(op, a, b)
}
simplify <- function(node, assignments = list()) {
  if (node$kind == "variable") return(if (is.null(assignments[[node$value]])) node else bool_constant(assignments[[node$value]]))
  if (node$kind == "constant") return(node)
  if (node$kind == "not") return(reduce_negation(simplify(node$child, assignments)))
  simplify_binary(node$kind, simplify(node$left, assignments), simplify(node$right, assignments))
}
evaluate <- function(node, assignments) {
  if (node$kind == "variable") return(assignments[[node$value]])
  if (node$kind == "constant") return(node$value)
  if (node$kind == "not") return(1L - evaluate(node$child, assignments))
  a <- evaluate(node$left, assignments)
  b <- evaluate(node$right, assignments)
  switch(node$kind, "&" = bitwAnd(a, b), "|" = bitwOr(a, b), "^" = bitwXor(a, b), "->" = if (a == 1L && b == 0L) 0L else 1L, "<->" = if (a == b) 1L else 0L)
}
pattern <- function(row, size) {
  paste(vapply(seq_len(size), function(i) as.character(bitwAnd(bitwShiftR(as.integer(row), size - i), 1L)), character(1)), collapse = "")
}
pattern_key <- function(text) chartr("10-", "012", text)
literal_count <- function(text) nchar(gsub("-", "", text, fixed = TRUE))
complement_pattern <- function(text) chartr("01", "10", text)
contains_row <- function(text, row) {
  a <- strsplit(text, "", fixed = TRUE)[[1]]
  b <- strsplit(row, "", fixed = TRUE)[[1]]
  all(a == "-" | a == b)
}
pattern_part <- function(text, names, product = TRUE) {
  chars <- strsplit(text, "", fixed = TRUE)[[1]]
  literals <- vapply(which(chars != "-"), function(i) paste0(if (chars[[i]] == "1") "" else "~", names[[i]]), character(1))
  if (length(literals) == 0L) return(if (product) "1" else "0")
  paste(literals, collapse = if (product) " & " else " | ")
}
cover_text <- function(patterns, names, product = TRUE) {
  if (length(patterns) == 0L) return(if (product) "0" else "1")
  parts <- vapply(patterns, function(text) {
    part <- pattern_part(text, names, product)
    if (!product && length(patterns) >= 2L && literal_count(text) >= 2L) paste0("(", part, ")") else part
  }, character(1))
  paste(parts, collapse = if (product) " | " else " & ")
}
sort_patterns <- function(patterns) patterns[order(pattern_key(patterns), method = "radix")]
coefficients <- function(values, size) {
  for (i in seq_len(size) - 1L) {
    bit <- bitwShiftL(1L, i)
    for (row in seq_along(values) - 1L) if (bitwAnd(row, bit) != 0L) values[[row + 1L]] <- bitwXor(values[[row + 1L]], values[[bitwXor(row, bit) + 1L]])
  }
  values
}
cover_key_compare <- function(a, b) {
  if (a$count != b$count) return(sign(a$count - b$count))
  if (a$literals != b$literals) return(sign(a$literals - b$literals))
  for (i in seq_along(a$patterns)) {
    x <- a$patterns[[i]]
    y <- b$patterns[[i]]
    if (x != y) return(if (sort(c(x, y), method = "radix")[[1]] == x) -1L else 1L)
  }
  0L
}
minimize <- function(on, dc, names, pos = FALSE) {
  rows <- setNames(vapply(on, pattern, character(1), size = length(names)), as.character(on))
  stage <- unique(vapply(unique(c(on, dc)), pattern, character(1), size = length(names)))
  primes <- character()
  lines <- character()
  number <- 0L
  repeat {
    used <- next_stage <- character()
    for (text in stage) {
      for (i in seq_len(nchar(text))) {
        if (substr(text, i, i) != "0") next
        partner <- text
        substr(partner, i, i) <- "1"
        if (!(partner %in% stage)) next
        combined <- text
        substr(combined, i, i) <- "-"
        used <- c(used, text, partner)
        next_stage <- c(next_stage, combined)
      }
    }
    fresh <- setdiff(stage, used)
    primes <- union(primes, fresh)
    if (!pos) lines <- c(lines, paste0("stage ", number, ": implicants ", length(stage), " primes ", length(fresh)))
    next_stage <- unique(next_stage)
    if (length(next_stage) == 0L) break
    stage <- next_stage
    number <- number + 1L
  }
  targets <- sort_patterns(primes[vapply(primes, function(text) any(vapply(rows, function(row) contains_row(text, row), logical(1))), logical(1))])
  coverage <- lapply(targets, function(text) on[vapply(on, function(row) contains_row(text, rows[[as.character(row)]]), logical(1))])
  essential <- integer()
  for (row in on) {
    candidates <- which(vapply(coverage, function(covered) row %in% covered, logical(1)))
    if (length(candidates) == 1L) essential <- union(essential, candidates)
  }
  optional <- setdiff(seq_along(targets), essential)
  best <- best_key <- NULL
  for (mask in seq_len(2 ^ length(optional)) - 1L) {
    chosen <- c(essential, optional[vapply(seq_along(optional) - 1L, function(i) bitwAnd(mask, bitwShiftL(1L, i)) != 0L, logical(1))])
    covered <- unique(unlist(coverage[chosen], use.names = FALSE))
    if (!all(on %in% covered)) next
    texts <- if (pos) complement_pattern(targets[chosen]) else targets[chosen]
    texts <- sort_patterns(texts)
    key <- list(count = length(texts), literals = sum(literal_count(texts)), patterns = pattern_key(texts))
    if (is.null(best_key) || cover_key_compare(key, best_key) < 0L) {
      best_key <- key
      best <- texts
    }
  }
  if (pos) return(c(paste0("minimal: ", cover_text(best, names, FALSE)), paste0("clauses ", length(best), " literals ", best_key$literals)))
  terms <- vapply(targets, pattern_part, character(1), names = names)
  essentials <- vapply(targets[sort(essential)], pattern_part, character(1), names = names)
  c(lines, paste0("primes: ", if (length(terms) == 0L) "none" else paste(terms, collapse = ", ")),
    paste0("essential: ", if (length(essentials) == 0L) "none" else paste(essentials, collapse = ", ")),
    paste0("minimal: ", cover_text(best, names)), paste0("terms ", length(best), " literals ", best_key$literals))
}
merge_clause <- function(a, b) {
  x <- strsplit(a, "", fixed = TRUE)[[1]]
  y <- strsplit(b, "", fixed = TRUE)[[1]]
  if (any(x != "-" & y != "-" & x != y)) return(NULL)
  paste(ifelse(x == "-", y, x), collapse = "")
}
tidy <- function(clauses) {
  unique <- unique(clauses)
  keep <- vapply(unique, function(clause) !any(vapply(unique, function(other) clause != other && contains_row(other, clause), logical(1))), logical(1))
  sort_patterns(unique[keep])
}
clauses <- function(node, names) {
  memo <- list()
  visit <- function(current) {
    id <- attr(current, "memo_id", exact = TRUE)
    key <- if (is.null(id)) NULL else paste0("n", id)
    if (!is.null(key) && !is.null(memo[[key]])) return(memo[[key]])
    if (current$kind %in% c("variable", "not")) {
      name <- if (current$kind == "variable") current$value else current$child$value
      text <- strrep("-", length(names))
      index <- match(name, names)
      substr(text, index, index) <- if (current$kind == "variable") "1" else "0"
      result <- text
    } else if (current$kind == "constant") {
      result <- if (current$value == 1L) character() else strrep("-", length(names))
    } else {
      left <- visit(current$left)
      right <- visit(current$right)
      if (current$kind == "&") {
        result <- tidy(c(left, right))
      } else {
        result <- character()
        for (a in left) {
          for (b in right) {
            merged <- merge_clause(a, b)
            if (!is.null(merged)) result <- c(result, merged)
          }
        }
        result <- tidy(result)
      }
    }
    if (!is.null(key)) memo[[key]] <<- result
    result
  }
  visit(node)
}

assignments <- function(names, row) setNames(lapply(seq_along(names), function(i) bitwAnd(bitwShiftR(as.integer(row), length(names) - i), 1L)), names)
assignment_text <- function(names, row) {
  values <- assignments(names, row)
  paste0("{", paste(vapply(names, function(name) paste0(name, "=", values[[name]]), character(1)), collapse = " "), "}")
}
workbench <- function() {
  commands <- c("DEF", "DEFSUM", "DEL", "LIST", "PRINT", "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "NNF", "DUAL", "ANF", "SIMPLIFY", "RESTRICT", "COFACTOR", "MINIMIZE", "MINDC", "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "BDD", "CLAUSES", "DP")
  split_commands <- c("RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES")
  table_commands <- c("TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "ANF", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "KMAP", "BDD", "MINIMIZE", "MINDC", "MINPOS")
  state <- new.env(parent = emptyenv())
  state$definitions <- list()
  valid_name <- function(name) grepl("^[a-z][a-z0-9]{0,7}$", name)
  parse <- function(text, start) parse_formula(text, start, state$definitions)
  words <- function(text) {
    result <- strsplit(text, " +")[[1]]
    result[nzchar(result)]
  }
  define <- function(name, formula) {
    line <- paste0(if (is.null(state$definitions[[name]])) "defined " else "redefined ", name, " = ", notation(formula))
    state$definitions[[name]] <- formula
    line
  }
  bdd <- function(values, names) {
    nodes <- list()
    unique <- new.env(parent = emptyenv())
    build <- function(i, table) {
      if (i > length(names)) return(table[[1]])
      half <- length(table) %/% 2L
      low <- build(i + 1L, head(table, half))
      high <- build(i + 1L, tail(table, half))
      if (low == high) return(low)
      key <- paste(i, low, high, sep = ",")
      if (!exists(key, envir = unique, inherits = FALSE)) {
        assign(key, length(nodes) + 2L, envir = unique)
        nodes[[length(nodes) + 1L]] <<- c(i, low, high)
      }
      get(key, envir = unique, inherits = FALSE)
    }
    root <- build(1L, values)
    counts <- list("0" = 0L, "1" = 1L)
    paths <- function(id) {
      key <- as.character(id)
      if (is.null(counts[[key]])) counts[[key]] <<- paths(nodes[[id - 1L]][[2]]) + paths(nodes[[id - 1L]][[3]])
      counts[[key]]
    }
    lines <- paste0("nodes: ", length(nodes))
    for (j in seq_along(nodes)) {
      node <- nodes[[j]]
      lines <- c(lines, paste0(j + 1L, " = ite(", names[[node[[1]]]], ", ", node[[3]], ", ", node[[2]], ")"))
    }
    c(lines, paste0("root: ", root), paste0("paths: ", paths(root)))
  }
  command <- function(line) {
    separator <- regexpr(" ", line, fixed = TRUE)[[1]]
    command <- if (separator < 0L) line else substr(line, 1L, separator - 1L)
    argument <- if (separator < 0L) "" else substring(line, separator + 1L)
    if (!(command %in% commands)) logic_error(paste0("unknown command ", command))
    if (command == "LIST" && separator > 0L) logic_error("unexpected argument")
    if (command != "LIST" && separator < 0L) logic_error("missing argument")
    if (command == "LIST") {
      names <- sort(names(state$definitions), method = "radix")
      return(c(paste0("names: ", length(names)), vapply(names, function(name) paste0(name, " = ", notation(state$definitions[[name]])), character(1))))
    }
    if (command == "DEF") {
      split <- regexpr(" ", argument, fixed = TRUE)[[1]]
      if (split < 0L) logic_error("missing argument")
      name <- substr(argument, 1L, split - 1L)
      if (!valid_name(name)) logic_error(paste0("invalid name '", name, "'"))
      return(define(name, parse(substring(argument, split + 1L), nchar(name) + 6L)))
    }
    if (command == "DEL") {
      if (!valid_name(argument)) logic_error(paste0("invalid name '", argument, "'"))
      if (is.null(state$definitions[[argument]])) logic_error(paste0("undefined name '", argument, "'"))
      state$definitions[[argument]] <- NULL
      return(paste0("deleted ", argument))
    }
    if (command == "DEFSUM") {
      split <- regexpr(";", argument, fixed = TRUE)[[1]]
      if (split < 0L) logic_error("missing ';'")
      front <- words(substr(argument, 1L, split - 1L))
      if (length(front) == 0L) logic_error("missing argument")
      name <- front[[1]]
      if (!valid_name(name)) logic_error(paste0("invalid name '", name, "'"))
      names <- front[-1L]
      if (length(names) == 0L || any(!grepl("^[A-Z]$", names)) || !identical(names, sort(unique(names), method = "radix"))) logic_error("bad variable list")
      if (length(names) >= 9L) logic_error(paste0("too many variables: ", length(names)))
      rows <- integer()
      previous <- -1L
      for (word in words(substring(argument, split + 1L))) {
        if (!grepl("^(0|[1-9][0-9]*)$", word) || as.numeric(word) >= 2 ^ length(names) || as.numeric(word) <= previous) logic_error(paste0("bad minterm '", word, "'"))
        previous <- as.integer(word)
        rows <- c(rows, previous)
      }
      terms <- lapply(rows, function(row) {
        text <- pattern(row, length(names))
        literals <- lapply(seq_along(names), function(i) if (substr(text, i, i) == "1") bool_variable(names[[i]]) else bool_not(bool_variable(names[[i]])))
        Reduce(function(a, b) bool_binary("&", a, b), literals)
      })
      return(define(name, if (length(terms) == 0L) bool_constant(0L) else Reduce(function(a, b) bool_binary("|", a, b), terms)))
    }
    front <- argument
    second <- NULL
    second_start <- NULL
    if (command %in% split_commands) {
      split <- regexpr(";", argument, fixed = TRUE)[[1]]
      if (split < 0L) logic_error("missing ';'")
      front <- substr(argument, 1L, split - 1L)
      second <- substring(argument, split + 1L)
      second_start <- nchar(command) + split + 2L
    }
    formula <- parse(front, nchar(command) + 2L)
    if (command == "RESTRICT") {
      items <- words(second)
      if (length(items) == 0L) logic_error("missing assignment")
      assignments <- list()
      for (word in items) {
        if (!grepl("^[A-Z]=[01]$", word)) logic_error(paste0("bad assignment '", word, "'"))
        name <- substr(word, 1L, 1L)
        if (!is.null(assignments[[name]])) logic_error(paste0("duplicate variable ", name))
        assignments[[name]] <- as.integer(substr(word, 3L, 3L))
      }
      return(paste0("restricted: ", notation(simplify(formula, assignments))))
    }
    if (command == "COFACTOR") {
      items <- words(second)
      if (length(items) != 1L || !grepl("^[A-Z]$", items[[1]])) logic_error("bad variable")
      name <- items[[1]]
      high <- simplify(formula, setNames(list(1L), name))
      low <- simplify(formula, setNames(list(0L), name))
      return(c(paste0("cofactor ", name, "=1: ", notation(high)), paste0("cofactor ", name, "=0: ", notation(low)), paste0("difference: ", notation(simplify_binary("^", high, low)))))
    }
    other <- if (is.null(second)) NULL else parse(second, second_start)
    names <- sort(unique(c(variable_names(formula), if (is.null(other)) character() else variable_names(other))), method = "radix")
    if (command %in% table_commands && length(names) >= 9L) logic_error(paste0("too many variables: ", length(names)))
    if (command == "PRINT") {
      measure <- measures(formula)
      return(c(paste0("formula: ", notation(formula)), paste0("variables: ", if (length(names) == 0L) "none" else paste(names, collapse = " ")), paste0("size ", measure[[1]], " depth ", measure[[2]])))
    }
    if (command == "NNF") return(paste0("nnf: ", notation(nnf(formula))))
    if (command == "DUAL") return(paste0("dual: ", notation(dual(formula))))
    if (command == "SIMPLIFY") return(paste0("simplified: ", notation(simplify(formula))))
    if (command %in% c("CLAUSES", "DP")) {
      set <- clauses(nnf(formula), names)
      if (command == "CLAUSES") return(paste0("clauses: ", cover_text(set, names, FALSE)))
      lines <- paste0("start: clauses ", length(set))
      empty <- strrep("-", length(names))
      for (i in seq_along(names)) {
        if (length(set) == 0L || empty %in% set) break
        positive <- set[substr(set, i, i) == "1"]
        negative <- set[substr(set, i, i) == "0"]
        resolvents <- character()
        for (a in positive) {
          for (b in negative) {
            substr(a, i, i) <- substr(b, i, i) <- "-"
            merged <- merge_clause(a, b)
            if (!is.null(merged)) resolvents <- c(resolvents, merged)
          }
        }
        resolvents <- unique(resolvents)
        set <- tidy(c(set[substr(set, i, i) == "-"], resolvents))
        lines <- c(lines, paste0("eliminate ", names[[i]], ": resolvents ", length(resolvents), " clauses ", length(set)))
      }
      return(c(lines, if (empty %in% set) "result: unsatisfiable" else "result: satisfiable"))
    }
    rows <- seq_len(2 ^ length(names)) - 1L
    values <- vapply(rows, function(row) evaluate(formula, assignments(names, row)), integer(1))
    other_values <- if (is.null(other)) NULL else vapply(rows, function(row) evaluate(other, assignments(names, row)), integer(1))
    on <- rows[values == 1L]
    off <- rows[values == 0L]
    if (command == "TABLE") return(c(paste(c(names, "|", "F"), collapse = " "), vapply(rows, function(row) paste(c(strsplit(pattern(row, length(names)), "", fixed = TRUE)[[1]], "|", values[[row + 1L]]), collapse = " "), character(1))))
    if (command %in% c("MINTERMS", "MAXTERMS")) {
      selected <- if (command == "MINTERMS") on else off
      return(paste0(tolower(command), ": ", if (length(selected) == 0L) "none" else paste(selected, collapse = " ")))
    }
    if (command %in% c("DNF", "CNF")) {
      texts <- vapply(if (command == "DNF") on else off, pattern, character(1), size = length(names))
      if (command == "CNF") texts <- complement_pattern(texts)
      return(paste0(tolower(command), ": ", cover_text(texts, names, command == "DNF")))
    }
    if (command == "ANF") {
      coeff <- coefficients(values, length(names))
      texts <- chartr("0", "-", vapply(rows[coeff == 1L], pattern, character(1), size = length(names)))
      texts <- texts[order(literal_count(texts), pattern_key(texts), method = "radix")]
      return(paste0("anf: ", if (length(texts) == 0L) "0" else paste(vapply(texts, pattern_part, character(1), names = names), collapse = " ^ ")))
    }
    if (command == "SAT") return(if (length(on) == 0L) "unsatisfiable" else paste0("satisfiable: ", assignment_text(names, on[[1]])))
    if (command == "TAUT") return(if (length(off) == 0L) "tautology" else paste0("not a tautology: ", assignment_text(names, off[[1]])))
    if (command == "COUNT") return(paste0("models: ", length(on), " of ", length(values)))
    if (command == "EQUIV") {
      differing <- which(values != other_values)
      if (length(differing) == 0L) return("equivalent")
      i <- differing[[1]]
      return(paste0("not equivalent: ", assignment_text(names, i - 1L), " f=", values[[i]], " g=", other_values[[i]]))
    }
    if (command == "IMPLIES") {
      failing <- which(values == 1L & other_values == 0L)
      if (length(failing) == 0L) return("implies")
      return(paste0("does not imply: ", assignment_text(names, failing[[1]] - 1L)))
    }
    if (command == "PROPS") {
      depends <- character()
      for (i in seq_along(names)) {
        bit <- bitwShiftL(1L, length(names) - i)
        if (any(values != values[bitwXor(rows, bit) + 1L])) depends <- c(depends, names[[i]])
      }
      monotone <- self_dual <- symmetric <- TRUE
      weights <- list()
      for (row in rows) {
        value <- values[[row + 1L]]
        if (value == values[[length(values) - row]]) self_dual <- FALSE
        for (i in seq_along(names) - 1L) {
          bit <- bitwShiftL(1L, i)
          if (bitwAnd(row, bit) == 0L && value > values[[bitwOr(row, bit) + 1L]]) monotone <- FALSE
        }
        weight <- as.character(sum(as.integer(intToBits(row))))
        if (!is.null(weights[[weight]]) && weights[[weight]] != value) symmetric <- FALSE
        weights[[weight]] <- value
      }
      coeff <- coefficients(values, length(names))
      linear <- all(vapply(rows[coeff == 1L], function(row) sum(as.integer(intToBits(row))) <= 1L, logical(1)))
      properties <- c("zero-preserving" = values[[1]] == 0L, "one-preserving" = tail(values, 1L) == 1L, "self-dual" = self_dual, monotone = monotone, linear = linear, symmetric = symmetric)
      return(c(paste0("depends: ", if (length(depends) == 0L) "none" else paste(depends, collapse = " ")), paste0(names(properties), ": ", ifelse(properties, "yes", "no"))))
    }
    if (command == "KMAP") {
      if (length(names) < 2L || length(names) > 4L) logic_error("kmap needs 2 to 4 variables")
      p <- length(names) %/% 2L
      q <- length(names) - p
      row_codes <- vapply(seq_len(2 ^ p) - 1L, function(i) pattern(bitwXor(i, i %/% 2L), p), character(1))
      columns <- vapply(seq_len(2 ^ q) - 1L, function(i) pattern(bitwXor(i, i %/% 2L), q), character(1))
      lines <- paste0(paste(head(names, p), collapse = ""), "\\", paste(tail(names, q), collapse = ""), " ", paste(columns, collapse = " "))
      for (row in row_codes) {
        text <- paste0(row, strrep(" ", length(names) + 1L - p))
        for (column in columns) {
          bits <- strsplit(paste0(row, column), "", fixed = TRUE)[[1]]
          index <- sum(as.integer(bits) * 2 ^ rev(seq_along(bits) - 1L))
          text <- paste0(text, strrep(" ", q), values[[index + 1L]])
        }
        lines <- c(lines, text)
      }
      return(lines)
    }
    if (command == "BDD") return(bdd(values, names))
    if (command == "MINIMIZE") return(minimize(on, integer(), names))
    if (command == "MINDC") {
      dc <- rows[other_values == 1L]
      return(minimize(setdiff(on, dc), dc, names))
    }
    minimize(off, integer(), names, TRUE)
  }
  input <- file("stdin", open = "r")
  on.exit(close(input))
  count <- as.integer(readLines(input, n = 1L, warn = FALSE))
  for (i in seq_len(count)) {
    line <- readLines(input, n = 1L, warn = FALSE)[[1]]
    output <- tryCatch(command(line), logic_error = function(error) paste0("error: ", error$message))
    for (text in output) cat(text, "\n", sep = "")
  }
}

workbench()
