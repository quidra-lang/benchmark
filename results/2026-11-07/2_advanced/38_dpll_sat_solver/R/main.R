for (name in c("cnf_io", "encoders", "preprocess", "dpll", "report")) source(paste0(name, ".R"))

COMMANDS <- c("SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC")
ARGUMENT_TYPES <- list(SOLVE = "file", ENUM = c("file", "limit"), CORE = "file", QUEENS = c("small", "limit"),
                       PIGEON = c("small", "small", "limit"), COLOR = c(
                           "graph",
                           "color",
                           "limit"
                       ), CHROMATIC = c("graph", "color"))
record <- function(...) list2env(list(...), parent = emptyenv())
load_graphs <- function() {
  graphs <- list()
  current <- NULL
  lines <- readLines(file.path("input", "graphs.txt"), warn = FALSE)
  for (number in seq_along(lines)) {
    line <- lines[[number]]
    if (is.null(current)) {
      if (!nzchar(line) || startsWith(line, "#")) next
      words <- strsplit(line, " ", fixed = TRUE)[[1L]]
      current <- record(
          name = words[[2L]],
          vertices = as.integer(words[[3L]]),
          edges = list(),
          invalid = NULL
      )
      next
    }
    if (line == "END") {
      if (length(current$edges)) current$edges <- current$edges[order(vapply(current$edges, `[[`, 0L, 1L), vapply(current$edges, `[[`, 0L, 2L), method = "radix")]
      graphs[[current$name]] <- current
      current <- NULL
      next
    }
    if (!is.null(current$invalid)) next
    tokens <- strsplit(line, " ", fixed = TRUE)[[1L]]
    reason <- NULL
    if (length(tokens) != 2L || !all(vapply(tokens, valid_number, FALSE))) reason <- "bad edge line" else {
      a <- as.integer(tokens[[1L]])
      b <- as.integer(tokens[[2L]])
      edge <- sort(c(a, b))
      if (a < 1L || a > current$vertices || b < 1L || b > current$vertices) reason <- "vertex out of range" else if (a == b) reason <- "self loop" else if (any(vapply(
          current$edges,
          function(previous) identical(previous, edge),
          FALSE
      ))) reason <- "duplicate edge" else current$edges[[length(current$edges) + 1L]] <- edge
    }
    if (!is.null(reason)) current$invalid <- paste(reason, "at line", number)
  }
  graphs
}
load_jobs <- function() {
  jobs <- list()
  for (line in readLines(file.path("input", "jobs.txt"), warn = FALSE)) {
    if (!nzchar(line) || startsWith(line, "#")) next
    tokens <- strsplit(line, " ", fixed = TRUE)[[1L]]
    jobs[[length(jobs) + 1L]] <- record(
        number = length(jobs) + 1L,
        text = line,
        command = tokens[[1L]],
        args = tokens[-1L],
        error = NULL
    )
  }
  jobs
}
validate_job <- function(job, graphs) {
  command <- job$command
  if (!(command %in% names(ARGUMENT_TYPES))) return(paste("unknown command", command))
  types <- ARGUMENT_TYPES[[command]]
  if (length(job$args) != length(types)) return("wrong argument count")
  for (i in seq_along(types)) {
    argument <- job$args[[i]]
    kind <- types[[i]]
    if (kind == "file") {
      if (!grepl("^[a-z0-9_]{1,20}\\.cnf$", argument)) return(paste("bad file name", argument))
    } else if (kind == "graph") {
      graph <- graphs[[argument]]
      if (is.null(graph)) return(paste("unknown graph", argument))
      if (!is.null(graph$invalid)) return(paste0("invalid graph ", argument, ": ", graph$invalid))
    } else {
      if (!valid_number(argument)) return(paste("bad number", argument))
      maximum <- switch(kind, small = 8L, color = 6L, limit = 200L)
      if (as.integer(argument) < 1L || as.integer(argument) > maximum) return(paste("out of range", argument))
    }
  }
  NULL
}
greedy_coloring <- function(graph) {
  n <- graph$vertices
  degree <- integer(n)
  neighbors <- vector("list", n)
  for (edge in graph$edges) {
    a <- edge[[1L]]
    b <- edge[[2L]]
    degree[[a]] <- degree[[a]] + 1L
    degree[[b]] <- degree[[b]] + 1L
    neighbors[[a]] <- c(neighbors[[a]], b)
    neighbors[[b]] <- c(neighbors[[b]], a)
  }
  positions <- order(-degree, seq_len(n), method = "radix")
  colors <- integer(n)
  for (vertex in positions) {
    used <- colors[neighbors[[vertex]]]
    candidate <- 1L
    while (candidate %in% used) candidate <- candidate + 1L
    colors[[vertex]] <- candidate
  }
  colors
}
solved_statistics <- function() setNames(
    integer(4L),
    c("decisions", "propagations", "conflicts", "max_depth")
)
accumulate_stats <- function(destination, source) {
  keys <- c("decisions", "propagations", "conflicts")
  destination[keys] <- destination[keys] + source[keys]
  destination[["max_depth"]] <- max(destination[["max_depth"]], source[["max_depth"]])
  destination
}
solve_formula <- function(variables, clauses, limit) {
  preparation <- preprocess(variables, clauses, limit == 1L)
  models <- blocking <- list()
  stats <- solved_statistics()
  rounds <- 0L
  trace <- character()
  stop <- "preprocess"
  if (is.null(preparation$empty_clause)) {
    stop <- "limit"
    while (length(models) < limit) {
      rounds <- rounds + 1L
      round <- run_round(variables, c(preparation$clauses, blocking))
      if (rounds == 1L) trace <- round$trace
      stats <- accumulate_stats(stats, round$stats)
      if (is.null(round$model)) {
        stop <- "all"
        break
      }
      model <- round$model
      fixed <- which(preparation$fixed != 0L)
      model[fixed] <- preparation$fixed[fixed] == 1L
      models[[length(models) + 1L]] <- model
      blocking[[length(blocking) + 1L]] <- ifelse(
          model[preparation$active],
          -preparation$active,
          preparation$active
      )
    }
  }
  record(variables = variables, clauses = clauses, models = models, status = if (length(models)) "SAT" else "UNSAT", rounds = rounds,
         stop = stop, trace = trace, stats = stats, preparation = preparation, removed = preparation$counts[["removed"]])
}
true_literal <- function(model, literal) if (literal > 0L) model[[abs(literal)]] else !model[[abs(literal)]]
satisfies <- function(model, clauses) all(vapply(
    clauses,
    function(clause) any(vapply(clause, function(literal) true_literal(model, literal), FALSE)),
    FALSE
))
analyze_models <- function(solution) {
  models <- solution$models
  clauses <- solution$clauses
  if (!length(models)) return(NULL)
  failure <- NULL
  for (i in seq_along(models)) {
    for (j in seq_along(clauses)) {
      if (!any(vapply(clauses[[j]], function(literal) true_literal(models[[i]], literal), FALSE))) {
        failure <- c(i, j)
        break
      }
    }
    if (!is.null(failure)) break
  }
  first <- models[[1L]]
  distribution <- vapply(
      clauses,
      function(clause) sum(vapply(clause, function(literal) true_literal(first, literal), FALSE)),
      0L
  )
  safe <- integer()
  for (variable in seq_along(first)) {
    inverted <- first
    inverted[[variable]] <- !inverted[[variable]]
    if (satisfies(inverted, clauses)) safe <- c(safe, variable)
  }
  diversity <- integer()
  if (length(models) >= 2L) {
    for (i in seq_len(length(models) - 1L)) for (j in seq.int(i + 1L, length(models))) diversity <- c(
        diversity,
        sum(models[[i]] != models[[j]])
    )
  }
  backbone <- integer()
  for (variable in seq_along(first)) if (all(vapply(
      models,
      function(model) model[[variable]] == first[[variable]],
      FALSE
  ))) backbone <- c(backbone, if (first[[variable]]) variable else -variable)
  list(
      failure = failure,
      true_distribution = distribution,
      safe = safe,
      diversity = diversity,
      backbone = backbone
  )
}
unsat_core <- function(variables, clauses) {
  remaining <- seq_along(clauses)
  decisions <- conflicts <- 0L
  for (removed in seq_along(clauses)) {
    test <- solve_formula(variables, clauses[remaining[remaining != removed]], 1L)
    decisions <- decisions + test$stats[["decisions"]]
    conflicts <- conflicts + test$stats[["conflicts"]]
    if (test$status == "UNSAT") remaining <- remaining[remaining != removed]
  }
  list(clauses = remaining, decisions = decisions, conflicts = conflicts)
}
execute_chromatic <- function(job, graphs) {
  graph <- graphs[[job$args[[1L]]]]
  attempts <- list()
  stats <- solved_statistics()
  rounds <- removed <- 0L
  for (colors in seq_len(as.integer(job$args[[2L]]))) {
    formula <- coloring(graph, colors)
    solution <- solve_formula(formula$variables, formula$clauses, 1L)
    solution$colors <- colors
    attempts[[length(attempts) + 1L]] <- solution
    stats <- accumulate_stats(stats, solution$stats)
    rounds <- rounds + solution$rounds
    removed <- removed + solution$removed
    if (solution$status == "SAT") break
  }
  solution <- tail(attempts, 1L)[[1L]]
  job$attempts <- attempts
  job$chromatic <- if (solution$status == "SAT") solution$colors else NULL
  job$solution <- solution
  job$aggregate_stats <- stats
  job$aggregate_rounds <- rounds
  job$aggregate_removed <- removed
  job$colors <- solution$colors
  job$graph <- graph
}
execute_standard <- function(job, graphs) {
  command <- job$command
  args <- job$args
  if (command %in% c("SOLVE", "ENUM", "CORE")) {
    formula <- read_dimacs(args[[1L]])
    limit <- if (command == "ENUM") as.integer(args[[2L]]) else 1L
  } else if (command == "QUEENS") {
    formula <- queens(as.integer(args[[1L]]))
    limit <- as.integer(args[[2L]])
  } else if (command == "PIGEON") {
    formula <- pigeon(as.integer(args[[1L]]), as.integer(args[[2L]]))
    limit <- as.integer(args[[3L]])
  } else {
    job$graph <- graphs[[args[[1L]]]]
    job$colors <- as.integer(args[[2L]])
    formula <- coloring(job$graph, job$colors)
    limit <- as.integer(args[[3L]])
  }
  solution <- solve_formula(formula$variables, formula$clauses, limit)
  job$solution <- solution
  job$aggregate_stats <- solution$stats
  job$aggregate_rounds <- solution$rounds
  job$aggregate_removed <- solution$removed
  if (command == "CORE" && solution$status == "UNSAT") job$core <- unsat_core(
      formula$variables,
      formula$clauses
  )
}
execute_jobs <- function(jobs, graphs) {
  for (job in jobs) {
    error <- validate_job(job, graphs)
    if (!is.null(error)) {
      job$error <- error
      next
    }
    failure <- tryCatch({
      if (job$command == "CHROMATIC") execute_chromatic(job, graphs) else execute_standard(job, graphs)
      NULL
    }, input_error = function(error) conditionMessage(error))
    if (!is.null(failure)) job$error <- failure else job$analysis <- analyze_models(job$solution)
  }
}
graph_summary <- function(graph) {
  degree <- integer(graph$vertices)
  for (edge in graph$edges) degree[edge] <- degree[edge] + 1L
  named(
      vertices = graph$vertices,
      edges = length(graph$edges),
      max_degree = max(degree),
      greedy = max(greedy_coloring(graph))
  )
}
preprocessing_report <- function(preparation) {
  counts <- preparation$counts
  records <- preparation$records
  lines <- c(paste("preprocess", named(pure = if (preparation$pure) "on" else "off", tautologies = counts[["tautologies"]],
                                       duplicate_literals = counts[["duplicate_literals"]], unit_fixed = counts[["unit_fixed"]], unit_removed = counts[["unit_removed"]],
                                       subsumed = counts[["subsumed"]], pure_fixed = counts[["pure_fixed"]], pure_removed = counts[["pure_removed"]], removed = counts[["removed"]])),
             paste(
                 "removed_clauses",
                 named(
                     tautology = number_list(records$tautology),
                     unit = number_list(records$unit),
                     subsumed = number_list(records$subsumed),
                     pure = number_list(records$pure)
                 )
             ))
  if (!is.null(preparation$empty_clause)) lines <- c(
      lines,
      paste0("simplified empty_clause=", preparation$empty_clause)
  ) else {
    lengths <- lengths(preparation$clauses)
    fixed <- which(preparation$fixed != 0L)
    lines <- c(lines, paste("simplified", named(clauses = length(lengths), literals = sum(lengths), lengths = frequency(lengths), fixed = length(fixed), active = length(preparation$active))),
               paste0("fixed literals=", number_list(ifelse(preparation$fixed[fixed] == 1L, fixed, -fixed))))
  }
  lines
}
search_report <- function(stats) paste(
    "search",
    named(
        decisions = stats[["decisions"]],
        propagations = stats[["propagations"]],
        conflicts = stats[["conflicts"]],
        max_depth = stats[["max_depth"]]
    )
)
verification_report <- function(solution, analysis) {
  if (is.null(analysis)) return(character())
  if (!is.null(analysis$failure)) return(paste0(
      "verify failed model=",
      analysis$failure[[1L]],
      " clause=",
      analysis$failure[[2L]]
  ))
  paste(
      "verify ok",
      named(
          models = length(solution$models),
          clauses = length(solution$clauses),
          true_literals = frequency(analysis$true_distribution)
      )
  )
}
analysis_report <- function(solution, analysis) {
  if (is.null(analysis)) return(character())
  lines <- paste("flips", named(safe = length(analysis$safe), variables = number_list(analysis$safe)))
  distances <- analysis$diversity
  if (length(distances)) lines <- c(
      lines,
      paste(
          "diversity",
          named(pairs = length(distances), min_distance = min(distances), max_distance = max(distances))
      )
  )
  if (solution$stop == "all") lines <- c(
      lines,
      paste("backbone", named(size = length(analysis$backbone), literals = number_list(analysis$backbone)))
  )
  lines
}
trace_report <- function(events) {
  if (!length(events)) return("trace -")
  text <- paste(head(events, 12L), collapse = " ")
  paste0("trace ", text, if (length(events) > 12L) paste0(" +", length(events) - 12L) else "")
}
standard_result <- function(job) {
  solution <- job$solution
  lines <- heading(job)
  if (job$command == "COLOR") lines <- c(lines, paste("graph", graph_summary(job$graph)))
  sizes <- lengths(solution$clauses)
  lines <- c(lines, paste("formula", named(variables = solution$variables, clauses = length(sizes), literals = sum(sizes), lengths = frequency(sizes))),
             preprocessing_report(solution$preparation), paste0(
                 "result ",
                 solution$status,
                 " ",
                 named(models = length(solution$models), rounds = solution$rounds, stop = solution$stop)
             ), search_report(solution$stats))
  if (solution$rounds) lines <- c(lines, trace_report(solution$trace))
  lines <- c(lines, verification_report(solution, job$analysis), analysis_report(solution, job$analysis))
  if (!is.null(job$core)) {
    core <- job$core
    lines <- c(
        lines,
        paste(
            "core",
            named(
                size = length(core$clauses),
                decisions = core$decisions,
                conflicts = core$conflicts,
                clauses = number_list(core$clauses)
            )
        )
    )
  }
  lines
}
chromatic_result <- function(job) {
  lines <- c(heading(job), paste("graph", graph_summary(job$graph)))
  for (attempt in job$attempts) {
    stats <- attempt$stats
    lines <- c(lines, paste("attempt", named(k = attempt$colors, clauses = length(attempt$clauses), removed = attempt$removed, result = attempt$status, stop = attempt$stop,
                                             decisions = stats[["decisions"]], propagations = stats[["propagations"]], conflicts = stats[["conflicts"]], max_depth = stats[["max_depth"]])))
  }
  lines <- c(
      lines,
      paste0(
          "result ",
          job$solution$status,
          " chromatic=",
          if (is.null(job$chromatic)) "-" else as.character(job$chromatic),
          " attempts=",
          length(job$attempts)
      ),
      search_report(job$aggregate_stats)
  )
  if (job$solution$status == "SAT") lines <- c(
      lines,
      verification_report(job$solution, job$analysis),
      paste("flips", named(safe = length(job$analysis$safe), variables = number_list(job$analysis$safe)))
  )
  lines
}
valid_jobs <- function(jobs) Filter(function(job) is.null(job$error), jobs)
job_total <- function(jobs, key) sum(vapply(jobs, function(job) job$aggregate_stats[[key]], 0L))
results_summary <- function(jobs) {
  valid <- valid_jobs(jobs)
  sat <- sum(vapply(valid, function(job) job$solution$status == "SAT", FALSE))
  lines <- c(paste("SUMMARY", named(jobs = length(jobs), sat = sat, unsat = length(valid) - sat, error = length(jobs) - length(valid))),
             paste("totals", named(models = sum(vapply(valid, function(job) length(job$solution$models), 0L)), rounds = sum(vapply(valid, function(job) job$aggregate_rounds, 0L)),
                                    decisions = job_total(valid, "decisions"), propagations = job_total(
                                        valid,
                                        "propagations"
                                    ), conflicts = job_total(valid, "conflicts"),
                                    removed_clauses = sum(vapply(
                                        valid,
                                        function(job) job$aggregate_removed,
                                        0L
                                    )))))
  for (command in COMMANDS) {
    members <- Filter(function(job) job$command == command, valid)
    if (!length(members)) next
    sat <- sum(vapply(members, function(job) job$solution$status == "SAT", FALSE))
    lines <- c(lines, paste0("command ", command, " ", named(jobs = length(members), sat = sat, unsat = length(members) - sat,
                                                            decisions = job_total(members, "decisions"), propagations = job_total(
                                                                members,
                                                                "propagations"
                                                            ), conflicts = job_total(members, "conflicts"))))
  }
  for (entry in list(c("hardest", "conflicts"), c("deepest", "max_depth"), c("busiest", "propagations"))) {
    if (!length(valid)) break
    key <- entry[[2L]]
    job <- valid[[which.max(vapply(valid, function(job) job$aggregate_stats[[key]], 0L))]]
    lines <- c(lines, paste0(entry[[1L]], " job=", job$number, " ", key, "=", job$aggregate_stats[[key]]))
  }
  lines
}
classes_for_models <- function(columns, canonicalize) {
  table <- new.env(hash = TRUE, parent = emptyenv())
  classes <- assignments <- list()
  for (index in seq_along(columns)) {
    value <- columns[[index]]
    canonical <- canonicalize(value)
    key <- number_list(canonical$value)
    if (!exists(key, envir = table, inherits = FALSE)) {
      group <- record(
          number = length(classes) + 1L,
          first = index,
          found = 0L,
          canonical = canonical$value,
          orbit = canonical$orbit
      )
      table[[key]] <- group
      classes[[length(classes) + 1L]] <- group
    }
    group <- table[[key]]
    group$found <- group$found + 1L
    assignments[[length(assignments) + 1L]] <- list(
        value = value,
        group = group$number,
        first = index == group$first
    )
  }
  list(assignments = assignments, classes = classes)
}
queens_boards <- function(job) {
  n <- as.integer(job$args[[1L]])
  solution <- job$solution
  columns <- lapply(solution$models, function(model) positions(model, n, n))
  canonical <- function(columns) {
    variants <- queens_symmetries(columns)
    matrix <- do.call(rbind, variants)
    order <- do.call(order, c(as.list(as.data.frame(matrix)), list(method = "radix")))
    list(value = variants[[order[[1L]]]], orbit = length(unique(vapply(variants, number_list, ""))))
  }
  groups <- classes_for_models(columns, canonical)
  lines <- paste0("QUEENS job=", job$number, " n=", n)
  for (index in seq_along(groups$assignments)) {
    assignment <- groups$assignments[[index]]
    lines <- c(
        lines,
        paste0("solution ", index, " columns=", number_list(assignment$value), " class=", assignment$group)
    )
    if (assignment$first) lines <- c(lines, queens_board(assignment$value))
  }
  for (group in groups$classes) lines <- c(
      lines,
      paste0(
          "class ",
          group$number,
          " ",
          named(
              orbit = group$orbit,
              found = group$found,
              first = group$first,
              canonical = number_list(group$canonical)
          )
      )
  )
  c(
      lines,
      paste(
          "summary",
          named(solutions = length(solution$models), stop = solution$stop, classes = length(groups$classes))
      )
  )
}
pigeon_boards <- function(job) {
  p <- as.integer(job$args[[1L]])
  h <- as.integer(job$args[[2L]])
  solution <- job$solution
  lines <- paste0("PIGEON job=", job$number, " pigeons=", p, " holes=", h)
  for (index in seq_along(solution$models)) {
    places <- positions(solution$models[[index]], p, h)
    empty <- seq_len(h)[!(seq_len(h) %in% places)]
    lines <- c(
        lines,
        paste0("assignment ", index, " holes=", number_list(places), " empty=", number_list(empty))
    )
  }
  expected <- if (p > h) 0L else as.integer(prod(seq.int(h, h - p + 1L)))
  c(
      lines,
      paste(
          "summary",
          named(assignments = length(solution$models), stop = solution$stop, expected = expected)
      )
  )
}
coloring_boards <- function(job) {
  graph <- job$graph
  colors <- job$colors
  solution <- job$solution
  decoded <- lapply(solution$models, function(model) positions(model, graph$vertices, colors))
  groups <- classes_for_models(decoded, function(value) list(value = canonical_coloring(value), orbit = NULL))
  lines <- paste0(
      job$command,
      " job=",
      job$number,
      " graph=",
      graph$name,
      " vertices=",
      graph$vertices,
      " edges=",
      length(graph$edges),
      " colors=",
      colors
  )
  greedy <- greedy_coloring(graph)
  lines <- c(lines, paste0("greedy used=", max(greedy), " colors=", number_list(greedy)))
  for (index in seq_along(groups$assignments)) {
    assignment <- groups$assignments[[index]]
    value <- assignment$value
    sizes <- vapply(seq_len(colors), function(color) sum(value == color), 0L)
    lines <- c(
        lines,
        paste0(
            "coloring ",
            index,
            " colors=",
            number_list(value),
            " used=",
            length(unique(value)),
            " sizes=",
            number_list(sizes),
            " class=",
            assignment$group
        )
    )
  }
  for (group in groups$classes) lines <- c(
      lines,
      paste0(
          "class ",
          group$number,
          " found=",
          group$found,
          " first=",
          group$first,
          " canonical=",
          number_list(group$canonical)
      )
  )
  c(
      lines,
      paste(
          "summary",
          named(colorings = length(solution$models), stop = solution$stop, classes = length(groups$classes))
      )
  )
}
main <- function() {
  graphs <- load_graphs()
  jobs <- load_jobs()
  execute_jobs(jobs, graphs)
  results <- models <- boards <- list()
  stats <- "job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"
  for (job in jobs) {
    if (!is.null(job$error)) {
      results[[length(results) + 1L]] <- c(heading(job), paste("error", job$error))
      next
    }
    results[[length(results) + 1L]] <- if (job$command == "CHROMATIC") chromatic_result(job) else standard_result(job)
    solution <- job$solution
    if (length(solution$models)) {
      lines <- heading(job)
      for (number in seq_along(solution$models)) lines <- c(
          lines,
          paste("model", number),
          model_lines(solution$models[[number]])
      )
      models[[length(models) + 1L]] <- lines
    }
    if (job$command == "QUEENS") boards[[length(boards) + 1L]] <- queens_boards(job) else if (job$command == "PIGEON") boards[[length(boards) + 1L]] <- pigeon_boards(job) else if (job$command %in% c(
        "COLOR",
        "CHROMATIC"
    )) boards[[length(boards) + 1L]] <- coloring_boards(job)
    counters <- job$aggregate_stats
    row <- c(job$number, job$command, solution$status, solution$variables, length(solution$clauses), job$aggregate_removed,
             counters[["decisions"]], counters[["propagations"]], counters[["conflicts"]], counters[["max_depth"]], length(solution$models), job$aggregate_rounds)
    stats <- c(stats, paste(row, collapse = ","))
  }
  results[[length(results) + 1L]] <- results_summary(jobs)
  save_paragraphs("results.txt", results)
  save_paragraphs("models.txt", models)
  save_paragraphs("boards.txt", boards)
  save_lines("stats.csv", stats)
}
main()
