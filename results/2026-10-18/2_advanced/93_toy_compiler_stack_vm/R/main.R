source("lexer.R")
source("parser.R")
source("semantic.R")
source("codegen.R")
source("vm.R")
options(expressions = 500000L)
RULES <- c("const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable")
PUSHING <- c("PUSH", "LOADG", "LOADL", "READ")
POPPING <- c("POP", "STOREG", "STOREL", "JUMPF", "JUMPT", "RETV", "ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE")
REPORTS <- c("listing.txt", "output.txt", "diagnostics.txt", "stats.txt")
new_program <- function(name) new_record(name = name, lines = list(), inputs = numeric(), error = NULL,
                                        warnings = list(), folds = 0L, peephole = integer(length(RULES)))
collect_warnings <- function(analysis) {
  warnings <- list()
  for (variable in analysis$variables) if (!variable$read_accesses) {
    role <- if (variable$kind == "parameter") "parameter" else "variable"
    warnings[[length(warnings) + 1L]] <- list(position = variable$name_position, message = paste0("unused ", role, " '", variable$name, "'"))
  }
  for (function_node in analysis$functions) {
    pending <- list(function_node$body)
    while (length(pending)) {
      statement <- pending[[length(pending)]]
      pending <- head(pending, -1L)
      if (statement$kind == "block" && length(statement$statements) > 1L) for (index in seq_len(length(statement$statements) - 1L)) {
        if (!can_complete(statement$statements[[index]])) {
          warnings[[length(warnings) + 1L]] <- list(position = statement$statements[[index + 1L]]$position, message = "unreachable statement")
          break
        }
      }
      pending <- c(pending, statement_children(statement))
    }
  }
  reachable <- integer()
  pending <- list(analysis$globals[["main"]])
  while (length(pending)) {
    function_node <- pending[[length(pending)]]
    pending <- head(pending, -1L)
    if (!function_node$id %in% reachable) {
      reachable <- c(reachable, function_node$id)
      pending <- c(pending, function_node$calls)
    }
  }
  for (function_node in analysis$functions) if (!function_node$id %in% reachable) warnings[[length(warnings) + 1L]] <- list(position = function_node$name_position, message = paste0("function '", function_node$name, "' is never called"))
  if (length(warnings)) warnings <- warnings[order(vapply(warnings, function(warning) warning$position[[1L]], integer(1L)), vapply(warnings, function(warning) warning$position[[2L]], integer(1L)), method = "radix")]
  list(warnings = warnings, reachable = reachable)
}
is_recursive <- function(function_node) {
  visited <- integer()
  pending <- function_node$calls
  while (length(pending)) {
    current <- pending[[length(pending)]]
    pending <- head(pending, -1L)
    if (current$id == function_node$id) return(TRUE)
    if (!current$id %in% visited) {
      visited <- c(visited, current$id)
      pending <- c(pending, current$calls)
    }
  }
  FALSE
}
literal_value <- function(node, kind, value) node$kind == kind && node$value == value
new_folder <- function() new_record(count = 0L)
folded_literal <- function(folder, node, value) {
  folder$count <- folder$count + 1L
  kind <- if (node$type == "bool") "boolean" else "integer"
  toy_node(kind, node$position, value = if (kind == "boolean") as.logical(value) else as.numeric(value), type = node$type)
}
folded_identity <- function(folder, expression) {
  folder$count <- folder$count + 1L
  expression
}
fold_expression <- function(folder, node) {
  if (node$kind == "unary") {
    node$operand <- fold_expression(folder, node$operand)
    if (node$operand$kind %in% c("integer", "boolean")) {
      value <- tryCatch(calculate(if (node$operator == "-") "NEG" else "NOT", as.numeric(node$operand$value)), runtime_fault = function(error) error)
      if (!inherits(value, "runtime_fault")) return(folded_literal(folder, node, value))
    }
  } else if (node$kind == "binary") {
    node$left <- fold_expression(folder, node$left)
    node$right <- fold_expression(folder, node$right)
    left <- node$left
    right <- node$right
    operator <- node$operator
    if (left$kind %in% c("integer", "boolean") && right$kind %in% c("integer", "boolean")) {
      a <- as.numeric(left$value)
      b <- as.numeric(right$value)
      value <- tryCatch(if (operator == "&&") a != 0 && b != 0 else if (operator == "||") a != 0 || b != 0 else calculate(BINARY[[operator]], a, b), runtime_fault = function(error) error)
      if (!inherits(value, "runtime_fault")) return(folded_literal(folder, node, value))
    }
    if (operator == "&&" && literal_value(left, "boolean", FALSE)) return(folded_literal(folder, node, FALSE))
    if (operator == "||" && literal_value(left, "boolean", TRUE)) return(folded_literal(folder, node, TRUE))
    if (operator == "&&" && literal_value(left, "boolean", TRUE)) return(folded_identity(folder, right))
    if (operator == "||" && literal_value(left, "boolean", FALSE)) return(folded_identity(folder, right))
    if (operator == "+" && literal_value(left, "integer", 0)) return(folded_identity(folder, right))
    if (operator == "*" && literal_value(left, "integer", 1)) return(folded_identity(folder, right))
    if (operator %in% c("+", "-") && literal_value(right, "integer", 0)) return(folded_identity(folder, left))
    if (operator %in% c("*", "/") && literal_value(right, "integer", 1)) return(folded_identity(folder, left))
    if (operator == "&&" && literal_value(right, "boolean", TRUE)) return(folded_identity(folder, left))
    if (operator == "||" && literal_value(right, "boolean", FALSE)) return(folded_identity(folder, left))
  } else if (node$kind == "array") {
    node$index <- fold_expression(folder, node$index)
  } else if (node$kind == "call") {
    node$arguments <- lapply(node$arguments, function(argument) fold_expression(folder, argument))
  }
  node
}
fold_statement <- function(folder, node) {
  kind <- node$kind
  if (kind == "declaration") {
    if (!is.null(node$initializer)) node$initializer <- fold_expression(folder, node$initializer)
  } else if (kind == "assignment") {
    if (!is.null(node$index)) node$index <- fold_expression(folder, node$index)
    node$value <- fold_expression(folder, node$value)
  } else if (kind == "call_statement") {
    node$expression <- fold_expression(folder, node$expression)
  } else if (kind == "print") {
    node$arguments <- lapply(node$arguments, function(argument) fold_expression(folder, argument))
  } else if (kind == "return") {
    if (!is.null(node$value)) node$value <- fold_expression(folder, node$value)
  } else if (kind == "block") {
    node$statements <- lapply(node$statements, function(child) fold_statement(folder, child))
  } else if (kind == "if") {
    node$condition <- fold_expression(folder, node$condition)
    if (node$condition$kind == "boolean") {
      selected <- if (node$condition$value) node$then else node$otherwise
      replacement <- if (is.null(selected)) toy_node("empty", node$position) else fold_statement(folder, selected)
      folder$count <- folder$count + 1L
      return(replacement)
    }
    node$then <- fold_statement(folder, node$then)
    if (!is.null(node$otherwise)) node$otherwise <- fold_statement(folder, node$otherwise)
  } else if (kind == "while") {
    node$condition <- fold_expression(folder, node$condition)
    if (literal_value(node$condition, "boolean", FALSE)) {
      folder$count <- folder$count + 1L
      return(toy_node("empty", node$position))
    }
    node$body <- fold_statement(folder, node$body)
  } else if (kind == "for") {
    if (!is.null(node$initial)) node$initial <- fold_statement(folder, node$initial)
    if (!is.null(node$condition)) node$condition <- fold_expression(folder, node$condition)
    if (!is.null(node$update)) node$update <- fold_statement(folder, node$update)
    node$body <- fold_statement(folder, node$body)
  }
  node
}
jumps_on <- function(op, value) (value == 0) == (op == "JUMPF")
delete_instruction <- function(code, index) {
  code <- code[-(index + 1L)]
  for (position in seq_along(code)) {
    entry <- code[[position]]
    if (entry$op %in% JUMPS && entry$args[[1L]] > index) code[[position]] <- instruction(entry$op, entry$position, entry$args[[1L]] - 1L)
  }
  code
}
rewrite_at <- function(code, index, targets) {
  first <- code[[index + 1L]]
  second <- if (index + 1L < length(code)) code[[index + 2L]] else NULL
  free <- !is.null(second) && !((index + 1L) %in% targets)
  if (free && first$op == "PUSH" && second$op %in% CONDITIONAL) {
    if (jumps_on(second$op, first$args[[1L]])) {
      code[[index + 1L]] <- instruction("JUMP", second$position, second$args[[1L]])
      code <- delete_instruction(code, index + 1L)
    } else {
      code <- delete_instruction(code, index + 1L)
      code <- delete_instruction(code, index)
    }
    return(list(code = code, rule = 1L))
  }
  if (free && first$op %in% names(NEGATED) && second$op == "NOT") {
    code[[index + 1L]] <- instruction(NEGATED[[first$op]], first$position)
    return(list(code = delete_instruction(code, index + 1L), rule = 2L))
  }
  if (free && first$op == "NOT" && second$op %in% CONDITIONAL) {
    code[[index + 1L]] <- instruction(INVERSE[[second$op]], second$position, second$args[[1L]])
    return(list(code = delete_instruction(code, index + 1L), rule = 3L))
  }
  if (free && first$op %in% CONDITIONAL && first$args[[1L]] == index + 2L && second$op == "JUMP") {
    code[[index + 1L]] <- instruction(INVERSE[[first$op]], first$position, second$args[[1L]])
    return(list(code = delete_instruction(code, index + 1L), rule = 4L))
  }
  if (first$op %in% JUMPS) {
    target <- first$args[[1L]]
    if (target < length(code)) {
      destination <- code[[target + 1L]]
      new_target <- NULL
      if (destination$op == "JUMP") {
        new_target <- destination$args[[1L]]
      } else if (destination$op == "PUSH" && target + 1L < length(code)) {
        following <- code[[target + 2L]]
        if (following$op %in% CONDITIONAL) new_target <- if (jumps_on(following$op, destination$args[[1L]])) following$args[[1L]] else target + 2L
      }
      if (!is.null(new_target) && new_target != target) {
        code[[index + 1L]] <- instruction(first$op, first$position, new_target)
        return(list(code = code, rule = 5L))
      }
    }
    if (target == index + 1L) {
      if (first$op == "JUMP") code <- delete_instruction(code, index) else code[[index + 1L]] <- instruction("POP", first$position)
      return(list(code = code, rule = 6L))
    }
  }
  if (free && first$op %in% TRANSFERS) return(list(code = delete_instruction(code, index + 1L), rule = 7L))
  list(code = code, rule = 0L)
}
optimize <- function(original) {
  code <- original
  counts <- integer(length(RULES))
  repeat {
    targets <- vapply(Filter(function(entry) entry$op %in% JUMPS, code), function(entry) entry$args[[1L]], integer(1L))
    changed <- FALSE
    for (index in seq_along(code) - 1L) {
      rewritten <- rewrite_at(code, index, targets)
      if (rewritten$rule) {
        code <- rewritten$code
        counts[[rewritten$rule]] <- counts[[rewritten$rule]] + 1L
        changed <- TRUE
        break
      }
    }
    if (!changed) return(list(code = code, counts = counts))
  }
}
successors <- function(code, index) {
  entry <- code[[index + 1L]]
  result <- integer()
  if (!entry$op %in% TRANSFERS && index + 1L < length(code)) result <- index + 1L
  if (entry$op %in% JUMPS) {
    target <- entry$args[[1L]]
    if (target < length(code) && !target %in% result) result <- c(result, target)
  }
  result
}
stack_effect <- function(entry, functions) {
  if (entry$op %in% PUSHING) return(1L)
  if (entry$op %in% POPPING) return(-1L)
  if (entry$op == "STOREA") return(-2L)
  if (entry$op == "CALL") return(-entry$args[[2L]] + as.integer(functions[[entry$args[[1L]]]]$type != "void"))
  if (entry$op == "PRINT") return(-entry$args[[1L]])
  0L
}
analyze_flow <- function(unit, functions) {
  code <- unit$after
  leaders <- 0L
  for (position in seq_along(code)) {
    entry <- code[[position]]
    index <- position - 1L
    if (entry$op %in% JUMPS && entry$args[[1L]] < length(code)) leaders <- c(leaders, entry$args[[1L]])
    if ((entry$op %in% JUMPS || entry$op %in% TRANSFERS) && index + 1L < length(code)) leaders <- c(leaders, index + 1L)
  }
  starts <- sort(unique(leaders))
  block_numbers <- setNames(seq_along(starts) - 1L, as.character(starts))
  unit$blocks <- list()
  for (number in seq_along(starts)) {
    start <- starts[[number]]
    ending <- if (number < length(starts)) starts[[number + 1L]] - 1L else length(code) - 1L
    following <- unname(block_numbers[as.character(successors(code, ending))])
    unit$blocks[[number]] <- list(start = start, end = ending, following = following)
  }
  depths <- rep(NA_integer_, length(code))
  depths[[1L]] <- 0L
  pending <- 0L
  maximum_depth <- 0L
  while (length(pending)) {
    index <- tail(pending, 1L)
    pending <- head(pending, -1L)
    after <- depths[[index + 1L]] + stack_effect(code[[index + 1L]], functions)
    maximum_depth <- max(maximum_depth, after)
    for (target in successors(code, index)) if (is.na(depths[[target + 1L]])) {
      depths[[target + 1L]] <- after
      pending <- c(pending, target)
    }
  }
  unit$depth <- maximum_depth
}
link_units <- function(units, version) {
  addresses <- list()
  offset <- 0L
  for (unit in units) {
    addresses[[unit$name]] <- offset
    unit[[paste0(version, "_start")]] <- offset
    offset <- offset + length(unit[[version]])
  }
  code <- list()
  owners <- character()
  for (unit in units) {
    start <- addresses[[unit$name]]
    for (entry in unit[[version]]) {
      args <- entry$args
      if (entry$op %in% JUMPS) args <- list(start + args[[1L]]) else if (entry$op == "CALL") args <- list(addresses[[args[[1L]]]], args[[2L]])
      code[[length(code) + 1L]] <- do.call(instruction, c(list(entry$op, entry$position), args))
      owners <- c(owners, unit$name)
    }
  }
  starts <- setNames(as.list(names(addresses)), vapply(addresses, as.character, character(1L)))
  list(code = code, owners = owners, starts = starts)
}
compile_program <- function(program) {
  program$source_text <- setNames(lapply(program$lines, function(line) line$text), vapply(program$lines, function(line) as.character(line$number), character(1L)))
  compiled <- tryCatch({
    tokens <- tokenize(program$lines)
    declarations <- parse_program(new_parser(tokens))
    list(declarations = declarations, analysis = analyze(new_analyzer(declarations, tokens[[length(tokens)]]$position)))
  }, compile_error = function(error) error)
  if (inherits(compiled, "compile_error")) {
    program$error <- compiled
    return(invisible(NULL))
  }
  program$analysis <- compiled$analysis
  warnings <- collect_warnings(compiled$analysis)
  program$warnings <- warnings$warnings
  program$globals <- Filter(function(node) node$kind == "global", compiled$declarations)
  functions <- Filter(function(node) node$id %in% warnings$reachable, compiled$analysis$functions)
  folder <- new_folder()
  for (variable in program$globals) if (!is.null(variable$initializer)) variable$initializer <- fold_expression(folder, variable$initializer)
  for (function_node in functions) function_node$body <- fold_statement(folder, function_node$body)
  program$folds <- folder$count
  generated <- generate(program$globals, functions, compiled$analysis$globals[["main"]])
  program$units <- generated$units
  program$global_size <- generated$global_size
  function_table <- setNames(functions, vapply(functions, function(node) node$name, character(1L)))
  for (unit in program$units) {
    optimized <- optimize(unit$before)
    unit$after <- optimized$code
    program$peephole <- program$peephole + optimized$counts
    analyze_flow(unit, function_table)
    unit$recursive <- !is.null(unit$function_node) && is_recursive(unit$function_node)
  }
  before <- link_units(program$units, "before")
  after <- link_units(program$units, "after")
  program$before <- before$code
  program$after <- after$code
  program$owners <- after$owners
  program$execution <- run_vm(new_execution(after$code, after$owners, after$starts, program$global_size, program$inputs))
  program$comparison <- run_vm(new_execution(before$code, before$owners, before$starts, program$global_size, program$inputs))
}
spelling <- function(entry) {
  operands <- vapply(entry$args, function(argument) if (is.character(argument)) argument else sprintf("%.0f", argument), character(1L))
  paste(c(entry$op, operands), collapse = " ")
}
format_position <- function(position) paste(position, collapse = ":")
position_display <- function(program, position) c(paste0("  ", program$source_text[[as.character(position[[1L]])]]), paste0(strrep(" ", position[[2L]] + 1L), "^"))
listing <- function(program) {
  lines <- character()
  if (length(program$globals)) {
    lines <- "globals:"
    for (variable in program$globals) {
      type_name <- if (is.null(variable$size)) variable$type else paste0("int[", variable$size, "]")
      lines <- c(lines, paste0("  ", variable$address, " ", variable$name, " ", type_name))
    }
  } else {
    lines <- "globals: none"
  }
  lines <- c(lines, "functions:")
  for (unit in program$units) {
    signature <- ""
    callees <- "main"
    if (!is.null(unit$function_node)) {
      parameter_types <- paste(vapply(unit$function_node$parameters, function(parameter) parameter$type, character(1L)), collapse = ",")
      signature <- paste0(" ", unit$function_node$type, "(", parameter_types, ")")
      names <- sort(vapply(unit$function_node$calls, function(node) node$name, character(1L)), method = "radix")
      callees <- if (length(names)) paste(names, collapse = ",") else "-"
    }
    line <- paste0("  ", unit$name, signature, " address=", unit$before_start, "->", unit$after_start,
                   " size=", length(unit$before), "->", length(unit$after), " slots=", length(unit$slots),
                   " stack=", unit$depth, " blocks=", length(unit$blocks), " calls=", callees)
    if (unit$recursive) line <- paste0(line, " recursive")
    lines <- c(lines, line)
    for (number in seq_along(unit$slots)) {
      slot <- unit$slots[[number]]
      lines <- c(lines, paste0("    slot ", number - 1L, " ", slot$name, " ", slot$type))
    }
  }
  lines <- c(lines, "references:")
  for (declaration in c(program$globals, program$analysis$functions)) {
    used_lines <- sort(unique(vapply(declaration$references, `[[`, integer(1L), 1L)))
    used <- if (length(used_lines)) paste(used_lines, collapse = " ") else "-"
    lines <- c(lines, paste0("  ", declaration$name, " defined ", declaration$name_position[[1L]], " used ", used))
  }
  for (version in c("before", "after")) {
    code <- program[[version]]
    lines <- c(lines, paste0(version, " peephole: ", length(code), " instructions"))
    for (unit in program$units) {
      lines <- c(lines, paste0(unit$name, ":"))
      start <- unit[[paste0(version, "_start")]]
      for (offset in seq_along(unit[[version]]) - 1L) {
        address <- start + offset
        lines <- c(lines, sprintf("%5d  %s", address, spelling(code[[address + 1L]])))
      }
    }
  }
  lines <- c(lines, "control flow:")
  for (unit in program$units) {
    lines <- c(lines, paste0("  ", unit$name))
    for (number in seq_along(unit$blocks)) {
      block <- unit$blocks[[number]]
      line <- paste0("    B", number - 1L, " ", unit$after_start + block$start, "-", unit$after_start + block$end)
      if (length(block$following)) line <- paste0(line, " -> ", paste0("B", block$following, collapse = " "))
      lines <- c(lines, line)
    }
  }
  lines
}
diagnostics <- function(program) {
  if (!is.null(program$error)) {
    error <- program$error
    return(c(paste0(error$kind, " error ", format_position(error$position), ": ", error$message), position_display(program, error$position), "status: compile error"))
  }
  lines <- vapply(program$warnings, function(warning) paste0("warning ", format_position(warning$position), ": ", warning$message), character(1L))
  execution <- program$execution
  if (is.null(execution$error)) return(c(lines, "status: ok"))
  entry <- program$after[[execution$error_pc + 1L]]
  owner <- program$owners[[execution$error_pc + 1L]]
  lines <- c(lines, paste0("runtime error ", format_position(entry$position), ": ", execution$error, " in ", owner), position_display(program, entry$position))
  callers <- rev(tail(execution$frames, -1L))
  for (frame in head(callers, 5L)) {
    address <- frame$return_address - 1L
    lines <- c(lines, paste0("  called from ", program$owners[[address + 1L]], " at ", format_position(program$after[[address + 1L]]$position)))
  }
  if (length(callers) > 5L) lines <- c(lines, paste0("  ... ", length(callers) - 5L, " more"))
  c(lines, "status: runtime error")
}
count_value <- function(counts, key) if (is.null(counts[[key]])) 0L else counts[[key]]
statistics <- function(program) {
  execution <- program$execution
  comparison <- program$comparison
  same <- identical(execution$output, comparison$output) && identical(execution$error, comparison$error)
  lines <- c(paste0("code: ", length(program$before), " -> ", length(program$after)),
             paste0("folds: ", program$folds), paste0("peephole: ", sum(program$peephole)),
             paste0("  ", RULES, " ", program$peephole), paste0("executed: ", execution$executed),
             paste0("executed before peephole: ", comparison$executed),
             paste0("behaviour: ", if (same) "same" else "different"),
             paste0("max call depth: ", execution$max_depth), paste0("max stack: ", execution$max_stack))
  opcodes <- functions <- source_lines <- list()
  for (address in seq_along(program$after)) {
    entry <- program$after[[address]]
    count <- execution$counts[[address]]
    opcodes[[entry$op]] <- count_value(opcodes, entry$op) + count
    owner <- program$owners[[address]]
    functions[[owner]] <- count_value(functions, owner) + count
    source_line <- as.character(entry$position[[1L]])
    source_lines[[source_line]] <- count_value(source_lines, source_line) + count
  }
  lines <- c(lines, "opcodes:")
  op_names <- names(opcodes)
  op_counts <- unlist(opcodes, use.names = FALSE)
  for (index in order(-op_counts, op_names, method = "radix")) if (op_counts[[index]]) lines <- c(lines, paste0("  ", op_names[[index]], " ", op_counts[[index]]))
  lines <- c(lines, "functions:")
  names <- vapply(Filter(function(unit) !is.null(unit$function_node), program$units), function(unit) unit$name, character(1L))
  counts <- vapply(names, function(name) count_value(functions, name), integer(1L))
  for (index in order(-counts, names, method = "radix")) {
    name <- names[[index]]
    lines <- c(lines, paste0("  ", name, " calls=", count_value(execution$calls, name), " executed=", counts[[index]]))
  }
  lines <- c(lines, "calls:")
  pairs <- execution$pairs
  if (length(pairs)) {
    ordering <- order(-vapply(pairs, function(pair) pair$count, integer(1L)), vapply(pairs, function(pair) pair$caller, character(1L)), vapply(pairs, function(pair) pair$callee, character(1L)), method = "radix")
    for (pair in pairs[ordering]) lines <- c(lines, paste0("  ", pair$caller, " -> ", pair$callee, " ", pair$count))
  }
  lines <- c(lines, "hot lines:")
  line_numbers <- as.integer(names(source_lines))
  line_counts <- unlist(source_lines, use.names = FALSE)
  executed_lines <- which(line_counts > 0L)
  ordering <- executed_lines[order(-line_counts[executed_lines], line_numbers[executed_lines])]
  for (index in head(ordering, 5L)) lines <- c(lines, paste0("  line ", line_numbers[[index]], ": ", line_counts[[index]]))
  lines <- c(lines, paste0("coverage: ", length(executed_lines), " of ", length(source_lines), " lines"))
  unexecuted <- sort(line_numbers[line_counts == 0L])
  lines <- c(lines, paste0("not executed: ", if (length(unexecuted)) paste(unexecuted, collapse = " ") else "none"), "hot spots:")
  hot_spots <- which(execution$counts > 0L)
  ordering <- hot_spots[order(-execution$counts[hot_spots], hot_spots)]
  for (address in head(ordering, 5L)) lines <- c(lines, paste0("  pc=", address - 1L, " count=", execution$counts[[address]], " ", spelling(program$after[[address]])))
  lines
}
summary_lines <- function(programs) {
  compiled <- Filter(function(program) is.null(program$error), programs)
  error_count <- function(kind) sum(vapply(programs, function(program) !is.null(program$error) && program$error$kind == kind, logical(1L)))
  runtime_errors <- sum(vapply(compiled, function(program) !is.null(program$execution$error), logical(1L)))
  folds <- sum(vapply(compiled, function(program) program$folds, integer(1L)))
  peephole <- integer(length(RULES))
  for (program in compiled) peephole <- peephole + program$peephole
  executed <- sum(vapply(compiled, function(program) program$execution$executed, integer(1L)))
  lines <- c("== summary ==", paste0("programs: ", length(programs)), paste0("compiled: ", length(compiled)),
             paste0("compile errors: lexical ", error_count("lexical"), " syntax ", error_count("syntax"), " semantic ", error_count("semantic")),
             paste0("runtime errors: ", runtime_errors), paste0("folds: ", folds), paste0("peephole: ", sum(peephole)),
             paste0("  ", RULES, " ", peephole), paste0("executed: ", executed))
  rows <- list(c("program", "status", "code", "executed", "output"))
  for (program in programs) {
    if (!is.null(program$error)) {
      row <- c(program$name, paste(program$error$kind, "error"), "-", "-", "-")
    } else {
      execution <- program$execution
      status <- if (is.null(execution$error)) "ok" else "runtime error"
      row <- c(program$name, status, as.character(length(program$after)), as.character(execution$executed), as.character(length(execution$output)))
    }
    rows[[length(rows) + 1L]] <- row
  }
  widths <- vapply(seq_len(5L), function(column) max(vapply(rows, function(row) nchar(row[[column]]), integer(1L))), integer(1L))
  for (row in rows) {
    fields <- vapply(seq_len(5L), function(column) {
      value <- row[[column]]
      padding <- strrep(" ", widths[[column]] - nchar(value))
      if (column <= 2L) paste0(value, padding) else paste0(padding, value)
    }, character(1L))
    lines <- c(lines, paste0("  ", paste(fields, collapse = "  ")))
  }
  lines
}
read_programs <- function() {
  programs <- list()
  source <- readLines("input/program.src", warn = FALSE)
  for (number in seq_along(source)) {
    line <- source[[number]]
    if (startsWith(line, "#program ")) {
      programs[[length(programs) + 1L]] <- new_program(substring(line, 10L))
    } else {
      program <- programs[[length(programs)]]
      program$lines[[length(program$lines) + 1L]] <- list(number = number, text = line)
    }
  }
  by_name <- setNames(programs, vapply(programs, function(program) program$name, character(1L)))
  current <- NULL
  for (line in readLines("input/input.txt", warn = FALSE)) {
    if (startsWith(line, "#input ")) current <- by_name[[substring(line, 8L)]] else current$inputs <- c(current$inputs, as.numeric(strsplit(line, " ", fixed = TRUE)[[1L]]))
  }
  programs
}
main <- function() {
  programs <- read_programs()
  reports <- setNames(rep(list(character()), length(REPORTS)), REPORTS)
  for (program in programs) {
    compile_program(program)
    heading <- paste0("== program ", program$name, " ==")
    for (name in REPORTS) reports[[name]] <- c(reports[[name]], heading)
    reports[["diagnostics.txt"]] <- c(reports[["diagnostics.txt"]], diagnostics(program))
    if (!is.null(program$error)) {
      reports[["listing.txt"]] <- c(reports[["listing.txt"]], "not compiled")
      reports[["stats.txt"]] <- c(reports[["stats.txt"]], "not compiled")
    } else {
      reports[["listing.txt"]] <- c(reports[["listing.txt"]], listing(program))
      reports[["output.txt"]] <- c(reports[["output.txt"]], program$execution$output)
      reports[["stats.txt"]] <- c(reports[["stats.txt"]], statistics(program))
    }
  }
  reports[["stats.txt"]] <- c(reports[["stats.txt"]], summary_lines(programs))
  dir.create("output", showWarnings = FALSE)
  for (name in REPORTS) {
    connection <- file(file.path("output", name), open = "wb")
    writeChar(paste0(paste(reports[[name]], collapse = "\n"), "\n"), connection, eos = NULL, useBytes = TRUE)
    close(connection)
  }
}
main()
