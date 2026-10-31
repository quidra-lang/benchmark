options(expressions = 50000, scipen = 999)

forth <- function() {
  compile_only <- c("IF", "ELSE", "THEN", "DO", "?DO", "LOOP", "+LOOP", "LEAVE", "UNLOOP", "I", "J", "BEGIN", "UNTIL", "WHILE", "REPEAT", "AGAIN", "CASE", "OF", "ENDOF", "ENDCASE", "EXIT", "RECURSE", "DOES>", ";", ">R", "R>", "R@", 'ABORT"', "[']", "{:")
  interpret_only <- c(":", ":NONAME", "FORGET")
  special <- c(compile_only, interpret_only, '."', "(", "\\", "TO", "IS")
  builtin_names <- strsplit("+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS", " ", fixed = TRUE)[[1]]
  codes <- c(aborted = -1, "stack overflow" = -3, "stack underflow" = -4, "return stack overflow" = -5, "return stack underflow" = -6, "nesting too deep" = -7, "invalid address" = -9, "division by zero" = -10, "undefined word" = -13, "missing name" = -16, "invalid name" = -19, "deferred word not set" = -21, "invalid argument" = -24, "no CREATE word" = -31, "invalid base" = -40)
  state <- new.env(parent = emptyenv())
  state$stack <- numeric()
  state$returns <- numeric()
  state$memory <- 10
  state$dictionary <- list()
  state$tokens <- list()
  state$pending <- ""
  state$compiling <- NULL
  state$depth <- 0L
  state$line <- ""
  state$position <- 1L
  word <- function(name, kind, value = NULL, here = 0) {
    result <- new.env(parent = emptyenv())
    result$name <- name
    result$kind <- kind
    result$value <- value
    result$here <- here
    result$code <- list()
    result$local_count <- 0L
    result$does_word <- NULL
    result$does_start <- 1L
    result$xt <- NULL
    result
  }
  builtins <- setNames(lapply(builtin_names, function(name) word(name, "builtin")), builtin_names)
  upper <- function(text) chartr("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", text)
  fail <- function(source, reason, code = NULL) {
    if (is.null(code) && reason %in% names(codes)) code <- unname(codes[[reason]])
    stop(structure(list(message = reason, call = NULL, word = source, reason = reason, code = code), class = c("forth_error", "error", "condition")))
  }
  read_word <- function() {
    length <- nchar(state$line)
    while (state$position <= length && substr(state$line, state$position, state$position) == " ") state$position <- state$position + 1L
    if (state$position > length) return(NULL)
    start <- state$position
    while (state$position <= length && substr(state$line, state$position, state$position) != " ") state$position <- state$position + 1L
    substr(state$line, start, state$position - 1L)
  }
  read_name <- function(source) {
    result <- read_word()
    if (is.null(result)) fail(source, "missing name")
    result
  }
  number <- function(text, base = state$memory[[1]]) {
    if (nchar(text) == 3L && substr(text, 1L, 1L) == "'" && substr(text, 3L, 3L) == "'") return(utf8ToInt(substr(text, 2L, 2L)))
    first <- substr(text, 1L, 1L)
    if (first %in% c("$", "#", "%")) {
      base <- c("$" = 16, "#" = 10, "%" = 2)[[first]]
      text <- substring(text, 2L)
    } else if (base < 2 || base > 36) {
      fail(text, "invalid base")
    }
    negative <- startsWith(text, "-")
    digits <- upper(if (negative) substring(text, 2L) else text)
    if (digits == "") return(NULL)
    chars <- utf8ToInt(digits)
    values <- ifelse(chars >= 48L & chars <= 57L, chars - 48L, ifelse(chars >= 65L & chars <= 90L, chars - 55L, -1L))
    if (any(values < 0L | values >= base)) return(NULL)
    result <- 0
    for (d in values) result <- result * base + d
    if (negative) -result else result
  }
  check_name <- function(name) {
    key <- upper(name)
    if (key %in% special || !is.null(number(name, 10))) fail(name, "invalid name")
    key
  }
  lookup <- function(name) {
    key <- upper(name)
    for (i in rev(seq_along(state$dictionary))) if (state$dictionary[[i]]$name == key) return(state$dictionary[[i]])
    builtins[[key]]
  }
  token <- function(w) {
    if (is.null(w$xt)) {
      state$tokens[[length(state$tokens) + 1L]] <- w
      w$xt <- length(state$tokens)
    }
    w$xt
  }
  valid_token <- function(value) value >= 1 && value <= length(state$tokens)
  take <- function(count, source) {
    size <- length(state$stack)
    if (size < count) fail(source, "stack underflow")
    if (count == 0L) return(numeric())
    result <- tail(state$stack, count)
    state$stack <- head(state$stack, size - count)
    result
  }
  push <- function(value, source) {
    force(value)
    state$stack <- c(state$stack, value)
    if (length(state$stack) > 1000L) fail(source, "stack overflow")
  }
  push_all <- function(values, source) {
    for (value in values) push(value, source)
  }
  return_need <- function(count, source) {
    if (length(state$returns) < count) fail(source, "return stack underflow")
  }
  return_push <- function(value, source) {
    force(value)
    state$returns <- c(state$returns, value)
    if (length(state$returns) > 1000L) fail(source, "return stack overflow")
  }
  address <- function(value, source) {
    if (value < 0 || value %% 8 != 0 || value >= length(state$memory) * 8) fail(source, "invalid address")
    value / 8 + 1L
  }
  divmod <- function(a, b) {
    x <- abs(a)
    y <- abs(b)
    q <- floor(x / y)
    r <- x - q * y
    if (r < 0) {
      q <- q - 1
      r <- r + y
    } else if (r >= y) {
      q <- q + 1
      r <- r - y
    }
    if ((a < 0) != (b < 0)) {
      q <- -q
      if (r != 0) {
        q <- q - 1
        r <- y - r
      }
    }
    c(q, if (b < 0) -r else r)
  }
  output_number <- function(value, source) {
    base <- state$memory[[1]]
    if (base < 2 || base > 36) fail(source, "invalid base")
    n <- abs(value)
    digits <- strsplit("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", "", fixed = TRUE)[[1]]
    text <- ""
    repeat {
      qr <- divmod(n, base)
      text <- paste0(digits[[qr[[2]] + 1L]], text)
      n <- qr[[1]]
      if (n == 0) break
    }
    paste0(if (value < 0) "-" else "", text)
  }
  write <- function(text) state$pending <- paste0(state$pending, text)
  flush <- function() {
    cat(sub(" +$", "", state$pending), "\n", sep = "")
    state$pending <- ""
  }
  emit <- function(op, source, ...) {
    index <- length(state$compiling$code) + 1L
    state$compiling$code[[index]] <- list(op = op, source = source, args = list(...))
    index
  }
  record <- function(kind, ...) {
    item <- list2env(c(list(kind = kind), list(...)), parent = emptyenv())
    state$control[[length(state$control) + 1L]] <- item
    item
  }
  top <- function() tail(state$control, 1L)[[1]]
  pop_control <- function() {
    item <- top()
    state$control <- head(state$control, -1L)
    item
  }
  mismatch <- function(source, kinds) {
    if (length(state$control) == 0L || !(top()$kind %in% kinds)) fail(source, "control structure mismatch")
  }
  patch <- function(index, target) state$compiling$code[[index]]$args[[1]] <- target
  compile <- function(source) {
    key <- upper(source)
    if (key == "IF") {
      record("IF", at = emit("zero_jump", source, NULL))
    } else if (key == "ELSE") {
      mismatch(source, "IF")
      old <- pop_control()
      index <- emit("jump", source, NULL)
      patch(old$at, length(state$compiling$code) + 1L)
      record("ELSE", at = index)
    } else if (key == "THEN") {
      mismatch(source, c("IF", "ELSE"))
      patch(pop_control()$at, length(state$compiling$code) + 1L)
    } else if (key == "BEGIN") {
      record("BEGIN", begin = length(state$compiling$code) + 1L)
    } else if (key %in% c("UNTIL", "AGAIN")) {
      mismatch(source, "BEGIN")
      item <- pop_control()
      emit(if (key == "UNTIL") "zero_jump" else "jump", source, item$begin)
    } else if (key == "WHILE") {
      mismatch(source, "BEGIN")
      item <- pop_control()
      record("WHILE", begin = item$begin, at = emit("zero_jump", source, NULL))
    } else if (key == "REPEAT") {
      mismatch(source, "WHILE")
      item <- pop_control()
      emit("jump", source, item$begin)
      patch(item$at, length(state$compiling$code) + 1L)
    } else if (key %in% c("DO", "?DO")) {
      record(key, at = emit("do", source, NULL, key == "?DO"), leaves = integer())
    } else if (key %in% c("LOOP", "+LOOP")) {
      mismatch(source, c("DO", "?DO"))
      item <- pop_control()
      emit("loop", source, item$at + 1L, key == "+LOOP")
      finish <- length(state$compiling$code) + 1L
      patch(item$at, finish)
      for (index in item$leaves) patch(index, finish)
    } else if (key == "LEAVE") {
      found <- NULL
      for (item in rev(state$control)) {
        if (item$kind %in% c("DO", "?DO")) {
          found <- item
          break
        }
      }
      if (is.null(found)) fail(source, "control structure mismatch")
      found$leaves <- c(found$leaves, emit("leave", source, NULL))
    } else if (key == "CASE") {
      record("CASE", ends = integer())
    } else if (key == "OF") {
      mismatch(source, "CASE")
      record("OF", at = emit("of", source, NULL))
    } else if (key == "ENDOF") {
      mismatch(source, "OF")
      item <- pop_control()
      case <- top()
      case$ends <- c(case$ends, emit("jump", source, NULL))
      patch(item$at, length(state$compiling$code) + 1L)
    } else if (key == "ENDCASE") {
      mismatch(source, "CASE")
      item <- pop_control()
      emit("drop", source)
      for (index in item$ends) patch(index, length(state$compiling$code) + 1L)
    } else if (key == "EXIT") {
      emit("exit", source)
    } else if (key == "RECURSE") {
      emit("call", source, state$compiling)
    } else if (key == "DOES>") {
      if (length(state$control) != 0L) fail(source, "control structure mismatch")
      emit("does", source, state$compiling, length(state$compiling$code) + 2L)
    } else if (key == ";") {
      if (length(state$control) != 0L) {
        kind <- top()$kind
        if (kind == "ELSE") kind <- "IF"
        if (kind == "WHILE") kind <- "BEGIN"
        fail(source, paste0("unclosed ", kind))
      }
      w <- state$compiling
      state$compiling <- NULL
      if (state$anonymous) push(token(w), source) else state$dictionary[[length(state$dictionary) + 1L]] <- w
    } else if (key == "[']") {
      name <- read_name(source)
      w <- lookup(name)
      if (is.null(w)) fail(name, "undefined word")
      emit("literal", source, token(w))
    } else if (key == "{:") {
      names <- character()
      repeat {
        name <- read_word()
        if (is.null(name)) fail(source, "unterminated locals")
        if (upper(name) == ":}") break
        names <- c(names, name)
      }
      slots <- integer()
      for (name in names) {
        if (name == "--") break
        key_name <- check_name(name)
        state$compiling$local_count <- state$compiling$local_count + 1L
        slot <- state$compiling$local_count
        assign(key_name, slot, envir = state$locals)
        slots <- c(slots, slot)
      }
      emit("locals", source, slots)
    } else if (key %in% c(">R", "R>", "R@", "I", "J", "UNLOOP")) {
      emit("return_stack", source, key)
    } else if (exists(key, envir = state$locals, inherits = FALSE)) {
      emit("local", source, get(key, envir = state$locals, inherits = FALSE))
    } else {
      w <- lookup(source)
      if (!is.null(w)) {
        emit("call", source, w)
      } else {
        value <- number(source)
        if (is.null(value)) fail(source, "undefined word")
        emit("literal", source, value)
      }
    }
  }
  assign_word <- function(w, source, deferred) {
    value <- take(1L, source)[[1]]
    if (deferred) {
      if (!valid_token(value)) fail(source, "invalid argument")
      w$value <- value
    } else {
      state$memory[[w$value / 8 + 1L]] <- value
    }
  }
  process <- function(source) {
    key <- upper(source)
    if (key == "\\") {
      state$position <- nchar(state$line) + 1L
      return(invisible(NULL))
    }
    if (key == "(") {
      remainder <- substring(state$line, state$position)
      finish <- regexpr(")", remainder, fixed = TRUE)[[1]]
      if (finish < 0L) fail(source, "unterminated comment")
      state$position <- state$position + finish
      return(invisible(NULL))
    }
    if (is.null(state$compiling) && key %in% compile_only) fail(source, "compile only")
    if (!is.null(state$compiling) && key %in% interpret_only) fail(source, "interpret only")
    if (key %in% c('."', 'ABORT"')) {
      start <- state$position + 1L
      finish <- regexpr('"', substring(state$line, start), fixed = TRUE)[[1]]
      if (state$position > nchar(state$line) || finish < 0L) fail(source, "unterminated string")
      finish <- start + finish - 1L
      text <- substr(state$line, start, finish - 1L)
      state$position <- finish + 1L
      if (is.null(state$compiling)) write(text) else emit(if (key == '."') "write" else "abort_string", source, text)
    } else if (key %in% c("TO", "IS")) {
      name <- read_name(source)
      if (key == "TO" && !is.null(state$compiling) && exists(upper(name), envir = state$locals, inherits = FALSE)) {
        emit("set_local", source, get(upper(name), envir = state$locals, inherits = FALSE))
        return(invisible(NULL))
      }
      w <- lookup(name)
      if (is.null(w)) fail(name, "undefined word")
      expected <- if (key == "TO") "value" else "defer"
      if (w$kind != expected) fail(name, if (key == "TO") "not a value" else "not deferred")
      if (is.null(state$compiling)) assign_word(w, source, key == "IS") else emit(if (key == "TO") "to" else "is", source, w)
    } else if (key %in% c(":", ":NONAME")) {
      name <- if (key == ":") read_name(source) else source
      if (key == ":") check_name(name)
      state$compiling <- word(upper(name), "colon", here = length(state$memory) * 8)
      state$definition_name <- name
      state$anonymous <- key == ":NONAME"
      state$control <- list()
      state$locals <- new.env(parent = emptyenv())
    } else if (key == "FORGET") {
      name <- read_name(source)
      index <- NULL
      for (i in rev(seq_along(state$dictionary))) {
        if (state$dictionary[[i]]$name == upper(name)) {
          index <- i
          break
        }
      }
      if (is.null(index)) fail(name, "undefined word")
      state$memory <- head(state$memory, state$dictionary[[index]]$here / 8)
      state$dictionary <- head(state$dictionary, index - 1L)
    } else if (!is.null(state$compiling)) {
      compile(source)
    } else {
      w <- lookup(source)
      if (!is.null(w)) {
        execute(w, source)
      } else {
        value <- number(source)
        if (is.null(value)) fail(source, "undefined word")
        push(value, source)
      }
    }
  }
  return_operation <- function(key, source) {
    if (key == ">R") {
      return_push(take(1L, source)[[1]], source)
    } else if (key == "R>") {
      return_need(1L, source)
      value <- tail(state$returns, 1L)
      state$returns <- head(state$returns, -1L)
      push(value, source)
    } else if (key %in% c("R@", "I")) {
      return_need(1L, source)
      push(tail(state$returns, 1L), source)
    } else if (key == "J") {
      return_need(3L, source)
      push(state$returns[[length(state$returns) - 2L]], source)
    } else {
      return_need(2L, source)
      state$returns <- head(state$returns, -2L)
    }
  }
  execute_definition <- function(w, start, source) {
    if (state$depth == 100L) fail(source, "nesting too deep")
    state$depth <- state$depth + 1L
    return_size <- length(state$returns)
    locals <- numeric(w$local_count)
    pc <- start
    while (pc <= length(w$code)) {
      instruction <- w$code[[pc]]
      pc <- pc + 1L
      op <- instruction$op
      spelling <- instruction$source
      args <- instruction$args
      a <- if (length(args) >= 1L) args[[1]] else NULL
      b <- if (length(args) >= 2L) args[[2]] else NULL
      if (op == "literal") {
        push(a, spelling)
      } else if (op == "call") {
        execute(a, spelling)
      } else if (op == "write") {
        write(a)
      } else if (op == "local") {
        push(locals[[a]], spelling)
      } else if (op == "set_local") {
        locals[[a]] <- take(1L, spelling)[[1]]
      } else if (op == "locals") {
        values <- take(length(a), spelling)
        locals[a] <- values
      } else if (op %in% c("to", "is")) {
        assign_word(a, spelling, op == "is")
      } else if (op == "exit") {
        break
      } else if (op == "does") {
        created <- if (length(state$dictionary) == 0L) NULL else tail(state$dictionary, 1L)[[1]]
        if (is.null(created) || created$kind != "create") fail(spelling, "no CREATE word")
        created$does_word <- a
        created$does_start <- b
        break
      } else if (op == "jump") {
        pc <- a
      } else if (op == "zero_jump") {
        if (take(1L, spelling)[[1]] == 0) pc <- a
      } else if (op == "do") {
        values <- take(2L, spelling)
        if (b && values[[1]] == values[[2]]) {
          pc <- a
        } else {
          return_push(values[[1]], spelling)
          return_push(values[[2]], spelling)
        }
      } else if (op == "loop") {
        step <- if (b) take(1L, spelling)[[1]] else 1
        return_need(2L, spelling)
        last <- length(state$returns)
        index <- state$returns[[last]]
        limit <- state$returns[[last - 1L]]
        next_index <- index + step
        if ((index - limit < 0) != (next_index - limit < 0)) {
          state$returns <- head(state$returns, -2L)
        } else {
          state$returns[[last]] <- next_index
          pc <- a
        }
      } else if (op == "leave") {
        return_need(2L, spelling)
        state$returns <- head(state$returns, -2L)
        pc <- a
      } else if (op == "of") {
        values <- take(2L, spelling)
        if (values[[1]] != values[[2]]) {
          push(values[[1]], spelling)
          pc <- a
        }
      } else if (op == "drop") {
        take(1L, spelling)
      } else if (op == "return_stack") {
        return_operation(a, spelling)
      } else if (op == "abort_string") {
        if (take(1L, spelling)[[1]] != 0) fail(spelling, a, -2)
      }
    }
    if (length(state$returns) > return_size) state$returns <- head(state$returns, return_size)
    state$depth <- state$depth - 1L
  }
  execute_token <- function(value, source) {
    if (!valid_token(value)) fail(source, "invalid argument")
    w <- state$tokens[[value]]
    execute(w, w$name)
  }
  execute <- function(w, source) {
    while (w$kind == "defer") {
      if (is.null(w$value)) fail(source, "deferred word not set")
      if (!valid_token(w$value)) fail(source, "invalid argument")
      w <- state$tokens[[w$value]]
      source <- w$name
    }
    if (w$kind == "colon") {
      execute_definition(w, 1L, source)
    } else if (w$kind %in% c("create", "variable")) {
      push(w$value, source)
      if (!is.null(w$does_word)) execute_definition(w$does_word, w$does_start, source)
    } else if (w$kind == "constant") {
      push(w$value, source)
    } else if (w$kind == "value") {
      push(state$memory[[w$value / 8 + 1L]], source)
    } else {
      builtin(w$name, source)
    }
  }
  builtin <- function(key, source) {
    binary <- c("+", "-", "*", "/", "MOD", "/MOD", "MIN", "MAX", "=", "<>", "<", ">", "AND", "OR", "XOR")
    unary <- c("NEGATE", "ABS", "1+", "1-", "2*", "2/", "0=", "0<>", "0<", "0>", "INVERT", "CELLS", "CELL+")
    stack_counts <- c(DUP = 1L, "?DUP" = 1L, DROP = 1L, SWAP = 2L, OVER = 2L, ROT = 3L, "-ROT" = 3L, NIP = 2L, TUCK = 2L, "2DUP" = 2L, "2DROP" = 2L, "2SWAP" = 4L, "2OVER" = 4L)
    if (key %in% binary) {
      values <- take(2L, source)
      a <- values[[1]]
      b <- values[[2]]
      if (key %in% c("/", "MOD", "/MOD")) {
        if (b == 0) fail(source, "division by zero")
        qr <- divmod(a, b)
        push_all(if (key == "/") qr[[1]] else if (key == "MOD") qr[[2]] else rev(qr), source)
      } else {
        result <- switch(key, "+" = a + b, "-" = a - b, "*" = a * b, MIN = min(a, b), MAX = max(a, b), "=" = if (a == b) -1 else 0, "<>" = if (a != b) -1 else 0, "<" = if (a < b) -1 else 0, ">" = if (a > b) -1 else 0, AND = bitwAnd(as.integer(a), as.integer(b)), OR = bitwOr(as.integer(a), as.integer(b)), XOR = bitwXor(as.integer(a), as.integer(b)))
        push(result, source)
      }
    } else if (key %in% unary) {
      a <- take(1L, source)[[1]]
      result <- switch(key, NEGATE = -a, ABS = abs(a), "1+" = a + 1, "1-" = a - 1, "2*" = 2 * a, "2/" = divmod(a, 2)[[1]], "0=" = if (a == 0) -1 else 0, "0<>" = if (a != 0) -1 else 0, "0<" = if (a < 0) -1 else 0, "0>" = if (a > 0) -1 else 0, INVERT = -a - 1, CELLS = a * 8, "CELL+" = a + 8)
      push(result, source)
    } else if (key %in% names(stack_counts)) {
      values <- take(stack_counts[[key]], source)
      indices <- switch(key, DUP = c(1L, 1L), "?DUP" = if (values[[1]] == 0) 1L else c(1L, 1L), DROP = integer(), SWAP = c(2L, 1L), OVER = c(1L, 2L, 1L), ROT = c(2L, 3L, 1L), "-ROT" = c(3L, 1L, 2L), NIP = 2L, TUCK = c(2L, 1L, 2L), "2DUP" = c(1L, 2L, 1L, 2L), "2DROP" = integer(), "2SWAP" = c(3L, 4L, 1L, 2L), "2OVER" = c(1L, 2L, 3L, 4L, 1L, 2L))
      push_all(values[indices], source)
    } else if (key %in% c("*/", "*/MOD")) {
      values <- take(3L, source)
      if (values[[3]] == 0) fail(source, "division by zero")
      qr <- divmod(values[[1]] * values[[2]], values[[3]])
      push_all(if (key == "*/") qr[[1]] else rev(qr), source)
    } else if (key == "WITHIN") {
      values <- take(3L, source)
      push(if (values[[2]] <= values[[1]] && values[[1]] < values[[3]]) -1 else 0, source)
    } else if (key %in% c("TRUE", "FALSE", "BL", "BASE", "HERE")) {
      value <- switch(key, "TRUE" = -1, "FALSE" = 0, BL = 32, BASE = 0, HERE = length(state$memory) * 8)
      push(value, source)
    } else if (key == "DEPTH") {
      push(length(state$stack), source)
    } else if (key %in% c("PICK", "ROLL")) {
      u <- take(1L, source)[[1]]
      if (u < 0) fail(source, "invalid argument")
      if (length(state$stack) <= u) fail(source, "stack underflow")
      index <- length(state$stack) - u
      value <- state$stack[[index]]
      if (key == "ROLL") state$stack <- state$stack[-index]
      push(value, source)
    } else if (key %in% c(".", ".R", "?")) {
      values <- take(if (key == ".R") 2L else 1L, source)
      n <- if (key == "?") state$memory[[address(values[[1]], source)]] else values[[1]]
      text <- output_number(n, source)
      write(if (key == ".R") paste0(strrep(" ", max(0, values[[2]] - nchar(text))), text) else paste0(text, " "))
    } else if (key == ".S") {
      output_number(0, source)
      write(paste0("<", output_number(length(state$stack), source), "> "))
      for (value in state$stack) write(paste0(output_number(value, source), " "))
    } else if (key == "CR") {
      flush()
    } else if (key == "EMIT") {
      c <- take(1L, source)[[1]]
      if (c < 32 || c > 126) fail(source, "invalid argument")
      write(intToUtf8(c))
    } else if (key == "SPACE") {
      write(" ")
    } else if (key == "SPACES") {
      write(strrep(" ", max(0, take(1L, source)[[1]])))
    } else if (key %in% c("!", "+!")) {
      values <- take(2L, source)
      index <- address(values[[2]], source)
      state$memory[[index]] <- if (key == "!") values[[1]] else state$memory[[index]] + values[[1]]
    } else if (key == "@") {
      push(state$memory[[address(take(1L, source)[[1]], source)]], source)
    } else if (key == ",") {
      state$memory <- c(state$memory, take(1L, source)[[1]])
    } else if (key == "ALLOT") {
      n <- take(1L, source)[[1]]
      if (n < 0 || n %% 8 != 0) fail(source, "invalid argument")
      state$memory <- c(state$memory, numeric(n / 8))
    } else if (key %in% c("HEX", "DECIMAL")) {
      state$memory[[1]] <- if (key == "HEX") 16 else 10
    } else if (key %in% c("CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER")) {
      name <- check_name(read_name(source))
      value <- if (key %in% c("CONSTANT", "VALUE")) take(1L, source)[[1]] else NULL
      here <- length(state$memory) * 8
      stored <- if (key %in% c("CREATE", "VARIABLE", "VALUE")) here else value
      state$dictionary[[length(state$dictionary) + 1L]] <- word(name, tolower(key), stored, here)
      if (key %in% c("VARIABLE", "VALUE")) state$memory <- c(state$memory, if (key == "VARIABLE") 0 else value)
    } else if (key == "'") {
      name <- read_name(source)
      w <- lookup(name)
      if (is.null(w)) fail(name, "undefined word")
      push(token(w), source)
    } else if (key == "EXECUTE") {
      execute_token(take(1L, source)[[1]], source)
    } else if (key == "CATCH") {
      xt <- take(1L, source)[[1]]
      if (!valid_token(xt)) fail(source, "invalid argument")
      saved <- state$stack
      saved_returns <- length(state$returns)
      saved_depth <- state$depth
      code <- tryCatch({
        execute_token(xt, source)
        0
      }, forth_error = function(exception) {
        if (is.null(exception$code)) stop(exception)
        state$stack <- saved
        if (length(state$returns) > saved_returns) state$returns <- head(state$returns, saved_returns)
        state$depth <- saved_depth
        exception$code
      })
      push(code, source)
    } else if (key == "THROW") {
      n <- take(1L, source)[[1]]
      if (n != 0) fail(source, paste0("exception ", sprintf("%.0f", n)), n)
    } else if (key == "ABORT") {
      fail(source, "aborted")
    } else if (key == "WORDS") {
      for (w in rev(state$dictionary)) write(paste0(w$name, " "))
    }
  }
  input <- file("stdin", open = "r")
  on.exit(close(input))
  repeat {
    lines <- readLines(input, n = 1L, warn = FALSE)
    if (length(lines) == 0L) break
    state$line <- lines[[1]]
    if (state$line == "BYE") {
      if (!is.null(state$compiling)) cat("ERROR ", state$definition_name, ": unterminated definition\n", sep = "")
      break
    }
    state$position <- 1L
    tryCatch({
      repeat {
        source <- read_word()
        if (is.null(source)) break
        process(source)
      }
    }, forth_error = function(exception) {
      if (nchar(state$pending) > 0L) flush()
      cat("ERROR ", exception$word, ": ", exception$reason, "\n", sep = "")
      state$stack <- numeric()
      state$returns <- numeric()
      state$depth <- 0L
      state$compiling <- NULL
    })
    if (nchar(state$pending) > 0L) flush()
  }
}

forth()
