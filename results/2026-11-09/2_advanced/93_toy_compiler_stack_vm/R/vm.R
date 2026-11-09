MIN_INT <- -2147483648
MAX_INT <- 2147483647
BINARY_OPS <- c("ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE")
runtime_fault <- function(message) stop(structure(list(message = message), class = c("runtime_fault", "error", "condition")))
trunc_div <- function(a, b) {
  quotient <- abs(a) %/% abs(b)
  if ((a < 0) != (b < 0)) -quotient else quotient
}
calculate <- function(op, a, b = 0) {
  a <- force(a)
  b <- force(b)
  if (op %in% c("DIV", "MOD") && b == 0) runtime_fault("division by zero")
  result <- switch(op, ADD = a + b, SUB = a - b, MUL = a * b,
                   DIV = trunc_div(a, b), MOD = a - trunc_div(a, b) * b,
                   NEG = -a, NOT = as.numeric(a == 0), LT = as.numeric(a < b),
                   LE = as.numeric(a <= b), GT = as.numeric(a > b), GE = as.numeric(a >= b),
                   EQ = as.numeric(a == b), NE = as.numeric(a != b))
  if (result < MIN_INT || result > MAX_INT) runtime_fault("integer overflow")
  if (result == 0) 0 else result
}
new_execution <- function(code, owners, starts, global_size, inputs) {
  new_record(code = code, owners = owners, starts = starts, inputs = inputs,
             globals = numeric(global_size), stack = numeric(), frames = list(),
             read_position = 1L, pc = 0L, executed = 0L, counts = integer(length(code)),
             calls = list(), pairs = list(), max_stack = 0L, max_depth = 0L,
             output = character(), error = NULL, error_pc = NULL)
}
pop_stack <- function(execution) {
  value <- tail(execution$stack, 1L)
  execution$stack <- head(execution$stack, -1L)
  value
}
push_stack <- function(execution, value) {
  value <- force(value)
  execution$stack <- c(execution$stack, if (value == 0) 0 else as.numeric(value))
}
vm_step <- function(execution) {
  entry <- execution$code[[execution$pc + 1L]]
  op <- entry$op
  args <- entry$args
  next_pc <- execution$pc + 1L
  if (op == "PUSH") {
    push_stack(execution, args[[1L]])
  } else if (op == "POP") {
    pop_stack(execution)
  } else if (op == "LOADG") {
    push_stack(execution, execution$globals[[args[[1L]] + 1L]])
  } else if (op == "STOREG") {
    value <- pop_stack(execution)
    execution$globals[[args[[1L]] + 1L]] <- value
  } else if (op == "LOADL") {
    push_stack(execution, execution$frames[[length(execution$frames)]]$locals[[args[[1L]] + 1L]])
  } else if (op == "STOREL") {
    value <- pop_stack(execution)
    execution$frames[[length(execution$frames)]]$locals[[args[[1L]] + 1L]] <- value
  } else if (op %in% c("LOADA", "STOREA")) {
    value <- if (op == "STOREA") pop_stack(execution) else 0
    index <- pop_stack(execution)
    address <- args[[1L]]
    size <- args[[2L]]
    if (index < 0 || index >= size) runtime_fault(sprintf("index %.0f out of bounds for array of size %d", index, size))
    if (op == "LOADA") push_stack(execution, execution$globals[[address + index + 1L]]) else execution$globals[[address + index + 1L]] <- value
  } else if (op %in% BINARY_OPS) {
    b <- pop_stack(execution)
    a <- pop_stack(execution)
    push_stack(execution, calculate(op, a, b))
  } else if (op %in% c("NEG", "NOT")) {
    value <- pop_stack(execution)
    push_stack(execution, calculate(op, value))
  } else if (op == "JUMP") {
    next_pc <- args[[1L]]
  } else if (op %in% CONDITIONAL) {
    value <- pop_stack(execution)
    if ((value == 0) == (op == "JUMPF")) next_pc <- args[[1L]]
  } else if (op == "CALL") {
    if (length(execution$frames) == 100L) runtime_fault("call depth limit exceeded")
    target <- args[[1L]]
    count <- args[[2L]]
    values <- if (count) tail(execution$stack, count) else numeric()
    if (count) execution$stack <- head(execution$stack, -count)
    execution$frames[[length(execution$frames) + 1L]] <- list(locals = values, return_address = next_pc)
    callee <- execution$starts[[as.character(target)]]
    calls <- execution$calls[[callee]]
    execution$calls[[callee]] <- if (is.null(calls)) 1L else calls + 1L
    caller <- execution$owners[[execution$pc + 1L]]
    key <- paste(caller, callee, sep = ":")
    pair <- execution$pairs[[key]]
    execution$pairs[[key]] <- list(caller = caller, callee = callee, count = if (is.null(pair)) 1L else pair$count + 1L)
    next_pc <- target
  } else if (op == "ENTER") {
    frame <- length(execution$frames)
    locals <- execution$frames[[frame]]$locals
    execution$frames[[frame]]$locals <- c(locals, numeric(args[[1L]] - length(locals)))
  } else if (op %in% c("RET", "RETV")) {
    next_pc <- execution$frames[[length(execution$frames)]]$return_address
    execution$frames <- head(execution$frames, -1L)
  } else if (op == "READ") {
    if (execution$read_position > length(execution$inputs)) runtime_fault("read past end of input")
    push_stack(execution, execution$inputs[[execution$read_position]])
    execution$read_position <- execution$read_position + 1L
  } else if (op == "PRINT") {
    count <- args[[1L]]
    values <- tail(execution$stack, count)
    execution$stack <- head(execution$stack, -count)
    execution$output <- c(execution$output, paste(sprintf("%.0f", values), collapse = " "))
  }
  execution$max_stack <- max(execution$max_stack, length(execution$stack))
  execution$max_depth <- max(execution$max_depth, length(execution$frames))
  execution$pc <- next_pc
  op != "HALT"
}
run_vm <- function(execution) {
  repeat {
    if (execution$executed == 100000L) {
      execution$error <- "instruction limit exceeded"
      execution$error_pc <- execution$pc
      break
    }
    execution$executed <- execution$executed + 1L
    execution$counts[[execution$pc + 1L]] <- execution$counts[[execution$pc + 1L]] + 1L
    running <- tryCatch(vm_step(execution), runtime_fault = function(error) error)
    if (inherits(running, "runtime_fault")) {
      execution$error <- running$message
      execution$error_pc <- execution$pc
      break
    }
    if (!running) break
  }
  execution
}
