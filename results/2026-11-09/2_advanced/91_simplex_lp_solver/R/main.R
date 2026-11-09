source("rational.R")
source("lp_parser.R")
source("tableau.R")
source("simplex.R")
source("branch_bound.R")
dot_exact <- function(left, right) qsum(Map(`*`, left, right))
coefficients <- function(terms, variables) {
  values <- rep(list(ZERO), length(variables))
  for (term in terms) {
    j <- match(term$name, variables)
    values[[j]] <- values[[j]] + term$coefficient
  }
  values
}
model_error <- function(model, line, message) {
  model$error <- list(line = line, message = message)
  model
}
content_check <- function(parsed) {
  if (!is.null(parsed$error)) return(parsed)
  variables <- character()
  expressions <- c(list(parsed$objective), lapply(parsed$constraints, function(row) row$terms))
  for (terms in expressions) for (term in terms) if (!term$name %in% variables) variables <- c(variables, term$name)
  model <- list(name = parsed$name, error = NULL, direction = parsed$direction,
                variables = variables, constraints = parsed$constraints,
                costs = coefficients(parsed$objective, variables),
                matrix = lapply(parsed$constraints, function(row) coefficients(row$terms, variables)),
                rhs = lapply(parsed$constraints, function(row) row$rhs),
                comparisons = vapply(parsed$constraints, function(row) row$comparison, character(1L)),
                lower = rep(list(ZERO), length(variables)), upper = rep(list(NULL), length(variables)),
                integer = rep(FALSE, length(variables)))
  seen <- character()
  for (row in model$constraints) {
    if (row$name %in% seen) return(model_error(model, row$line, paste("duplicate constraint", row$name)))
    seen <- c(seen, row$name)
  }
  inconsistent <- function(j) !is.null(model$lower[[j]]) && !is.null(model$upper[[j]]) && model$lower[[j]] > model$upper[[j]]
  for (bound in parsed$bounds) {
    j <- match(bound$name, variables)
    if (is.na(j)) return(model_error(model, bound$line, paste("unknown variable", bound$name)))
    if (bound$kind %in% c("lower", "both")) model$lower[j] <- list(bound$lower)
    if (bound$kind %in% c("upper", "both")) model$upper[j] <- list(bound$upper)
    if (inconsistent(j)) return(model_error(model, bound$line, paste("inconsistent bounds", bound$name)))
  }
  for (declaration in parsed$integers) for (name in declaration$names) {
    j <- match(name, variables)
    if (is.na(j)) return(model_error(model, declaration$line, paste("unknown variable", name)))
    model$integer[[j]] <- TRUE
    if (!is.null(model$lower[[j]])) model$lower[[j]] <- fraction(ceiling(model$lower[[j]]))
    if (!is.null(model$upper[[j]])) model$upper[[j]] <- fraction(floor(model$upper[[j]]))
    if (inconsistent(j)) return(model_error(model, declaration$line, paste("inconsistent bounds", name)))
  }
  for (declaration in parsed$binaries) for (name in declaration$names) {
    j <- match(name, variables)
    if (is.na(j)) return(model_error(model, declaration$line, paste("unknown variable", name)))
    model$integer[[j]] <- TRUE
    model$lower[[j]] <- ZERO
    model$upper[[j]] <- fraction(1)
  }
  model
}
standard_form <- function(model, lower, upper) {
  column_names <- character()
  owners <- directions <- integer()
  mappings <- list()
  for (j in seq_along(model$variables)) {
    name <- model$variables[[j]]
    first_column <- length(column_names) + 1L
    if (!is.null(lower[[j]])) {
      kind <- "shift"
      offset <- lower[[j]]
      columns <- first_column
      signs <- 1L
      names <- name
    } else if (!is.null(upper[[j]])) {
      kind <- "reflect"
      offset <- upper[[j]]
      columns <- first_column
      signs <- -1L
      names <- paste0(name, "'")
    } else {
      kind <- "split"
      offset <- ZERO
      columns <- c(first_column, first_column + 1L)
      signs <- c(1L, -1L)
      names <- paste0(name, c("+", "-"))
    }
    column_names <- c(column_names, names)
    owners <- c(owners, rep(j, length(columns)))
    directions <- c(directions, signs)
    mappings[[j]] <- list(kind = kind, offset = offset, columns = columns, directions = signs, upper_row = NULL)
  }
  offsets <- lapply(mappings, function(mapping) mapping$offset)
  row_names <- vapply(model$constraints, function(row) row$name, character(1L))
  matrix <- lapply(model$matrix, function(row) lapply(seq_along(owners), function(k) directions[[k]] * row[[owners[[k]]]]))
  rhs <- Map(function(row, value) value - dot_exact(row, offsets), model$matrix, model$rhs)
  comparisons <- model$comparisons
  for (j in seq_along(mappings)) {
    mapping <- mappings[[j]]
    if (mapping$kind != "shift" || is.null(upper[[j]])) next
    mappings[[j]]$upper_row <- length(row_names) + 1L
    row_names <- c(row_names, paste0(model$variables[[j]], ".ub"))
    row <- rep(list(ZERO), length(column_names))
    row[[mapping$columns[[1L]]]] <- fraction(1)
    matrix[[length(matrix) + 1L]] <- row
    rhs[[length(rhs) + 1L]] <- upper[[j]] - lower[[j]]
    comparisons <- c(comparisons, "<=")
  }
  signs <- rep(1L, length(row_names))
  for (i in seq_along(row_names)) {
    if (rhs[[i]] < 0) {
      matrix[[i]] <- lapply(matrix[[i]], `-`)
      rhs[[i]] <- -rhs[[i]]
      signs[[i]] <- -1L
      comparisons[[i]] <- if (comparisons[[i]] == "<=") ">=" else if (comparisons[[i]] == ">=") "<=" else "="
    }
  }
  slack <- initial <- rep(0L, length(row_names))
  artificial <- integer()
  for (i in seq_along(comparisons)) {
    comparison <- comparisons[[i]]
    if (comparison == "=") next
    slack[[i]] <- length(column_names) + 1L
    column_names <- c(column_names, paste0("s:", row_names[[i]]))
    for (t in seq_along(matrix)) matrix[[t]][[length(matrix[[t]]) + 1L]] <- fraction(if (t == i) if (comparison == "<=") 1 else -1 else 0)
    if (comparison == "<=") initial[[i]] <- slack[[i]]
  }
  for (i in seq_along(comparisons)) {
    if (comparisons[[i]] == "<=") next
    column <- length(column_names) + 1L
    artificial <- c(artificial, column)
    initial[[i]] <- column
    column_names <- c(column_names, paste0("a:", row_names[[i]]))
    for (t in seq_along(matrix)) matrix[[t]][[length(matrix[[t]]) + 1L]] <- fraction(if (t == i) 1 else 0)
  }
  direction <- if (model$direction == "minimize") 1L else -1L
  phase2 <- lapply(seq_along(owners), function(k) direction * directions[[k]] * model$costs[[owners[[k]]]])
  phase2 <- c(phase2, rep(list(ZERO), length(column_names) - length(phase2)))
  phase1 <- lapply(seq_along(column_names), function(k) fraction(as.integer(k %in% artificial)))
  list(column_names = column_names, row_names = row_names, mappings = mappings,
       matrix = matrix, rhs = rhs, signs = signs, slack = slack, artificial = artificial,
       initial = initial, phase1 = phase1, phase2 = phase2,
       constant = dot_exact(model$costs, offsets), direction = direction)
}
tableau_solution <- function(form, tableau) {
  values <- rep(list(ZERO), length(form$column_names))
  for (row in seq_along(tableau$basic)) values[[tableau$basic[[row]]]] <- tableau$rhs[[row]]
  lapply(form$mappings, function(mapping) mapping$offset + qsum(Map(function(column, direction) direction * values[[column]], mapping$columns, mapping$directions)))
}
farkas_multipliers <- function(result) {
  form <- result$form
  reduced <- reduced_costs(result$tableau, form$phase1)
  lapply(seq_along(form$initial), function(i) form$signs[[i]] * (form$phase1[[form$initial[[i]]]] - reduced[[form$initial[[i]]]]))
}
unbounded_ray <- function(model, result) {
  tableau <- result$tableau
  form <- result$form
  column <- result$unbounded
  delta <- rep(list(ZERO), length(form$column_names))
  delta[[column]] <- fraction(1)
  for (row in seq_along(tableau$basic)) delta[[tableau$basic[[row]]]] <- -tableau$values[[row]][[column]]
  ray <- lapply(form$mappings, function(mapping) qsum(Map(function(k, direction) direction * delta[[k]], mapping$columns, mapping$directions)))
  list(ray = ray, rate = dot_exact(model$costs, ray))
}
mapping_lines <- function(model, form, lower, upper) {
  lines <- character()
  for (j in seq_along(form$mappings)) {
    mapping <- form$mappings[[j]]
    name <- model$variables[[j]]
    if (mapping$kind == "split") {
      lines <- c(lines, paste("MAP", name, "split"))
    } else if (mapping$kind == "reflect") {
      lines <- c(lines, paste("MAP", name, "reflect", fraction_text(upper[[j]])))
    } else {
      text <- paste("MAP", name, "shift", fraction_text(lower[[j]]))
      if (!is.null(upper[[j]])) text <- paste(text, "upper", fraction_text(upper[[j]]))
      lines <- c(lines, text)
    }
  }
  for (i in seq_along(form$row_names)) if (form$signs[[i]] == -1L) lines <- c(lines, paste("FLIP", form$row_names[[i]]))
  lines
}
solve_lp <- function(model, lower, upper, number, level) {
  form <- standard_form(model, lower, upper)
  tableau <- new_tableau(form)
  lines <- character()
  emit <- function(required, text) {
    if (level >= required) lines <<- c(lines, text)
  }
  display <- function(heading, costs, objective) {
    if (level >= 2L) lines <<- c(lines, tableau_display(tableau, heading, costs, objective))
  }
  phase2_value <- function(value) form$constant + form$direction * value
  emit(0L, paste("SOLVE node", number, "rows", length(form$row_names), "columns", length(form$column_names), "artificials", length(form$artificial)))
  for (line in mapping_lines(model, form, lower, upper)) emit(1L, line)
  phase1_count <- phase2_count <- drives <- redundant <- 0L
  infeasibility <- ZERO
  status <- "OPTIMAL"
  unbounded <- NULL
  if (length(form$artificial)) {
    emit(1L, "PHASE 1")
    display("phase 1 start", form$phase1, identity)
    phase <- run_phase(tableau, form$phase1, seq_along(form$column_names), identity)
    phase1_count <- phase$iterations
    for (line in phase$lines) emit(1L, line)
    infeasibility <- phase_value(tableau, form$phase1)
    emit(1L, paste("PHASE 1 END objective", fraction_text(infeasibility), "iterations", phase1_count))
    if (infeasibility > 0) {
      status <- "INFEASIBLE"
      display("final", form$phase1, identity)
    } else {
      for (row in seq_along(tableau$basic)) {
        basic <- tableau$basic[[row]]
        if (!basic %in% form$artificial) next
        eligible <- which(vapply(seq_along(form$column_names), function(k) !k %in% form$artificial && tableau$values[[row]][[k]] != 0, logical(1L)))
        if (!length(eligible)) {
          redundant <- redundant + 1L
          emit(1L, paste("REDUNDANT row", form$row_names[[row]]))
        } else {
          entering <- eligible[[1L]]
          leaving <- form$column_names[[basic]]
          pivot(tableau, row, entering)
          drives <- drives + 1L
          emit(1L, paste("DRIVE row", form$row_names[[row]], "enter", form$column_names[[entering]], "leave", leaving))
        }
      }
    }
  }
  if (status != "INFEASIBLE") {
    emit(1L, "PHASE 2")
    display("phase 2 start", form$phase2, phase2_value)
    candidates <- setdiff(seq_along(form$column_names), form$artificial)
    phase <- run_phase(tableau, form$phase2, candidates, phase2_value)
    phase2_count <- phase$iterations
    for (line in phase$lines) emit(1L, line)
    unbounded <- phase$unbounded
    if (!is.null(unbounded)) {
      status <- "UNBOUNDED"
      emit(1L, paste("UNBOUNDED enter", form$column_names[[unbounded]]))
    }
    value <- phase2_value(phase_value(tableau, form$phase2))
    emit(1L, paste("PHASE 2 END objective", fraction_text(value), "iterations", phase2_count))
    display("final", form$phase2, phase2_value)
  }
  objective <- if (status == "OPTIMAL") phase2_value(phase_value(tableau, form$phase2)) else NULL
  emit(0L, paste("RESULT", status, "objective", shown(objective), "phase1", phase1_count, "phase2", phase2_count, "drives", drives, "redundant", redundant))
  list(status = status, objective = objective, solution = tableau_solution(form, tableau),
       form = form, tableau = tableau, unbounded = unbounded, infeasibility = infeasibility,
       phase1 = phase1_count, phase2 = phase2_count, drives = drives, redundant = redundant,
       pivots = phase1_count + phase2_count + drives, lines = lines)
}
statistics_line <- function(model) {
  matrix <- list()
  for (row in model$matrix) for (value in row) if (value != 0) matrix[[length(matrix) + 1L]] <- value
  objective <- Filter(function(value) value != 0, model$costs)
  rhs <- Filter(function(value) value != 0, model$rhs)
  bounds <- Filter(function(value) !is.null(value) && value != 0, c(model$lower, model$upper))
  parts <- paste("STATS nonzeros", length(matrix))
  sets <- list(matrix = matrix, objective = objective, rhs = rhs, bounds = bounds)
  for (name in names(sets)) {
    values <- sets[[name]]
    if (length(values)) {
      magnitudes <- lapply(values, abs)
      parts <- c(parts, paste(name, fraction_text(qmin(magnitudes)), fraction_text(qmax(magnitudes))))
    } else {
      parts <- c(parts, paste(name, "- -"))
    }
  }
  paste(parts, collapse = " ")
}
range_endpoints <- function(origin, coefficients, numerators) {
  lower <- upper <- list()
  for (index in seq_along(coefficients)) {
    coefficient <- coefficients[[index]]
    if (coefficient > 0) lower[[length(lower) + 1L]] <- numerators[[index]] / coefficient
    if (coefficient < 0) upper[[length(upper) + 1L]] <- numerators[[index]] / coefficient
  }
  list(lower = if (length(lower)) origin + qmax(lower) else NULL,
       upper = if (length(upper)) origin + qmin(upper) else NULL)
}
objective_range <- function(model, result, variable, reduced, nonbasic) {
  form <- result$form
  tableau <- result$tableau
  h <- rep(list(ZERO), length(form$column_names))
  mapping <- form$mappings[[variable]]
  for (index in seq_along(mapping$columns)) h[[mapping$columns[[index]]]] <- fraction(form$direction * mapping$directions[[index]])
  eta <- lapply(nonbasic, function(column) h[[column]] - qsum(lapply(seq_along(tableau$basic), function(row) h[[tableau$basic[[row]]]] * tableau$values[[row]][[column]])))
  range_endpoints(model$costs[[variable]], eta, lapply(nonbasic, function(column) -reduced[[column]]))
}
rhs_range <- function(model, result, constraint) {
  form <- result$form
  tableau <- result$tableau
  rho <- lapply(tableau$values, function(row) form$signs[[constraint]] * row[[form$initial[[constraint]]]])
  if (any(vapply(seq_along(rho), function(row) rho[[row]] != 0 && tableau$basic[[row]] %in% form$artificial, logical(1L)))) return(list(lower = model$rhs[[constraint]], upper = model$rhs[[constraint]]))
  range_endpoints(model$rhs[[constraint]], rho, lapply(tableau$rhs, `-`))
}
variable_status <- function(form, basic, variable) {
  mapping <- form$mappings[[variable]]
  if (mapping$kind == "split") return(if (any(mapping$columns %in% basic)) "basic" else "zero")
  if (mapping$kind == "reflect") return(if (mapping$columns[[1L]] %in% basic) "basic" else "upper")
  if (!mapping$columns[[1L]] %in% basic) return("lower")
  if (!is.null(mapping$upper_row) && !form$slack[[mapping$upper_row]] %in% basic) "upper" else "basic"
}
sensitivity_lines <- function(model, result) {
  form <- result$form
  tableau <- result$tableau
  reduced <- reduced_costs(tableau, form$phase2)
  basic <- tableau$basic
  nonbasic <- setdiff(seq_along(form$column_names), c(basic, form$artificial))
  dual <- lapply(seq_along(model$constraints), function(i) -form$direction * form$signs[[i]] * reduced[[form$initial[[i]]]])
  variable_reduced <- lapply(seq_along(model$costs), function(j) model$costs[[j]] - dot_exact(dual, lapply(model$matrix, function(row) row[[j]])))
  primal_degeneracy <- sum(vapply(seq_along(basic), function(row) !basic[[row]] %in% form$artificial && tableau$rhs[[row]] == 0, logical(1L)))
  dual_degeneracy <- sum(vapply(nonbasic, function(column) reduced[[column]] == 0, logical(1L)))
  dual_objective <- dot_exact(dual, model$rhs) + dot_exact(variable_reduced, result$solution)
  kind <- if (any(model$integer)) "relaxation" else "lp"
  lines <- c(paste("MODEL", model$name, kind, "objective", fraction_text(result$objective)),
             paste("BASIS", paste(form$column_names[basic], collapse = " ")),
             paste("DEGENERACY primal", primal_degeneracy, "dual", dual_degeneracy),
             paste("DUAL objective", fraction_text(dual_objective)))
  for (i in seq_along(model$constraints)) {
    range <- rhs_range(model, result, i)
    lines <- c(lines, paste("CONSTRAINT", model$constraints[[i]]$name, "price", fraction_text(dual[[i]]), "rhs", fraction_text(model$rhs[[i]]), "range", endpoint(range$lower, TRUE), endpoint(range$upper, FALSE)))
  }
  for (j in seq_along(model$variables)) {
    range <- objective_range(model, result, j, reduced, nonbasic)
    lines <- c(lines, paste("VARIABLE", model$variables[[j]], variable_status(form, basic, j), "value", fraction_text(result$solution[[j]]), "reduced", fraction_text(variable_reduced[[j]]), "cost", fraction_text(model$costs[[j]]), "range", endpoint(range$lower, TRUE), endpoint(range$upper, FALSE)))
  }
  lines
}
solve_model <- function(model, level, limit) {
  solve <- function(lower, upper, number) solve_lp(model, lower, upper, number, level)
  if (any(model$integer)) return(branch_search(model, limit, solve))
  result <- solve(model$lower, model$upper, 1L)
  list(status = result$status, objective = result$objective,
       solution = if (result$status == "OPTIMAL") result$solution else NULL,
       solves = list(result), root = result, nodes = 1L, lines = character())
}
solution_lines <- function(model, result) {
  root <- result$root
  integer_count <- sum(model$integer)
  lines <- c(paste("MODEL", model$name, model$direction, "variables", length(model$variables), "constraints", length(model$constraints), "integers", integer_count), statistics_line(model), paste("STATUS", result$status))
  if (!is.null(result$solution)) lines <- c(lines, paste("OBJECTIVE", fraction_text(result$objective), "approx", approximate(result$objective)))
  if (integer_count && root$status == "OPTIMAL") lines <- c(lines, paste("RELAXATION", fraction_text(root$objective), "approx", approximate(root$objective)))
  if (root$status == "INFEASIBLE") {
    lines <- c(lines, paste("INFEASIBILITY", fraction_text(root$infeasibility)))
    multipliers <- farkas_multipliers(root)
    for (i in seq_along(multipliers)) lines <- c(lines, paste("FARKAS", root$form$row_names[[i]], fraction_text(multipliers[[i]])))
  }
  values <- if (result$status == "UNBOUNDED") root$solution else result$solution
  if (!is.null(values)) for (j in seq_along(model$variables)) lines <- c(lines, paste("VALUE", model$variables[[j]], fraction_text(values[[j]])))
  if (result$status == "UNBOUNDED") {
    ray <- unbounded_ray(model, root)
    for (j in seq_along(model$variables)) lines <- c(lines, paste("RAY", model$variables[[j]], fraction_text(ray$ray[[j]])))
    lines <- c(lines, paste("RATE", fraction_text(ray$rate)))
  }
  if (!is.null(result$solution)) for (i in seq_along(model$constraints)) {
    value <- dot_exact(model$matrix[[i]], result$solution)
    margin <- if (model$comparisons[[i]] == "<=") model$rhs[[i]] - value else value - model$rhs[[i]]
    lines <- c(lines, paste("ROW", model$constraints[[i]]$name, fraction_text(value), fraction_text(margin)))
  }
  if (integer_count) lines <- c(lines, paste("NODES", result$nodes))
  c(lines, paste("PIVOTS", sum(vapply(result$solves, function(lp) lp$pivots, integer(1L)))))
}
write_lines <- function(name, lines) {
  connection <- file(file.path("output", name), open = "wb")
  on.exit(close(connection))
  writeChar(paste0(paste(lines, collapse = "\n"), "\n"), connection, eos = NULL, useBytes = TRUE)
}
main <- function() {
  settings <- read_settings()
  iterations <- solutions <- sensitivity <- tree <- character()
  summary <- "model,status,objective,approx,relaxation,nodes,pivots"
  statuses <- setNames(integer(5L), c("OPTIMAL", "INFEASIBLE", "UNBOUNDED", "NODE_LIMIT", "ERROR"))
  solves <- phase1 <- phase2 <- drives <- analyzed <- integer_models <- integer_nodes <- limited_models <- 0L
  for (parsed in read_models()) {
    model <- content_check(parsed)
    if (!is.null(model$error)) {
      statuses[["ERROR"]] <- statuses[["ERROR"]] + 1L
      iterations <- c(iterations, paste("MODEL", model$name, "error"))
      solutions <- c(solutions, paste("MODEL", model$name), paste("STATUS ERROR line", model$error$line, model$error$message))
      sensitivity <- c(sensitivity, paste("MODEL", model$name, "skipped ERROR"))
      summary <- c(summary, paste0(model$name, ",ERROR,-,-,-,0,0"))
      next
    }
    level <- settings$logs[[model$name]]
    if (is.null(level)) level <- settings$level
    limit <- settings$limits[[model$name]]
    if (is.null(limit)) limit <- settings$limit
    result <- solve_model(model, level, limit)
    statuses[[result$status]] <- statuses[[result$status]] + 1L
    iterations <- c(iterations, paste("MODEL", model$name, "level", level))
    for (lp in result$solves) {
      iterations <- c(iterations, lp$lines)
      solves <- solves + 1L
      phase1 <- phase1 + lp$phase1
      phase2 <- phase2 + lp$phase2
      drives <- drives + lp$drives
    }
    solutions <- c(solutions, solution_lines(model, result))
    if (result$root$status == "OPTIMAL") {
      analyzed <- analyzed + 1L
      sensitivity <- c(sensitivity, sensitivity_lines(model, result$root))
    } else {
      sensitivity <- c(sensitivity, paste("MODEL", model$name, "skipped", result$root$status))
    }
    if (any(model$integer)) {
      integer_models <- integer_models + 1L
      integer_nodes <- integer_nodes + result$nodes
      limited_models <- limited_models + as.integer(result$status == "NODE_LIMIT")
      tree <- c(tree, paste("MODEL", model$name, model$direction, "integers", sum(model$integer), "node_limit", limit), result$lines)
    }
    objective <- shown(result$objective)
    approx <- if (is.null(result$objective)) "-" else approximate(result$objective)
    relaxation <- shown(result$root$objective)
    pivots <- sum(vapply(result$solves, function(lp) lp$pivots, integer(1L)))
    summary <- c(summary, paste(model$name, result$status, objective, approx, relaxation, length(result$solves), pivots, sep = ","))
  }
  models <- sum(statuses)
  pivots <- phase1 + phase2 + drives
  iterations <- c(iterations, paste("TOTAL solves", solves, "phase1", phase1, "phase2", phase2, "drives", drives, "pivots", pivots))
  solutions <- c(solutions, paste("SUMMARY models", models, "optimal", statuses[["OPTIMAL"]], "infeasible", statuses[["INFEASIBLE"]], "unbounded", statuses[["UNBOUNDED"]], "node_limit", statuses[["NODE_LIMIT"]], "error", statuses[["ERROR"]]))
  sensitivity <- c(sensitivity, paste("SUMMARY analyzed", analyzed, "skipped", models - analyzed))
  tree <- c(tree, paste("SUMMARY models", integer_models, "nodes", integer_nodes, "node_limit", limited_models))
  dir.create("output", showWarnings = FALSE)
  outputs <- list("iterations.txt" = iterations, "solutions.txt" = solutions, "sensitivity.txt" = sensitivity, "bnb_tree.txt" = tree, "summary.csv" = summary)
  for (name in names(outputs)) write_lines(name, outputs[[name]])
}
main()
