source("pddl_parser.R")
source("grounding.R")
source("heuristics.R")
source("search.R")
source("graphplan.R")
notation <- function(atom) paste0("(", paste(atom, collapse=" "), ")")
action_text <- function(action) notation(c(action$source$name, action$arguments))
number_list <- function(values) if (length(values)) paste(sort(values), collapse=",") else "-"
headed <- function(heading, items) paste(heading, if (length(items)) paste(items, collapse=" ") else "-")
value_text <- function(value) if (value == INFINITY) "inf" else sprintf("%.0f", value)
heuristic_text <- function(values) paste(paste0(HEURISTIC_NAMES, "=", vapply(values, value_text, "")), collapse=" ")
read_settings <- function(text) {
    settings <- list(runs=list())
    for (row in strsplit(text, "\n", fixed=TRUE)[[1]]) {
        if (!nzchar(row) || startsWith(row, "#")) next
        fields <- strsplit(row, " ", fixed=TRUE)[[1]]
        if (fields[1] == "run") settings$runs[[length(settings$runs)+1L]] <- fields[-1] else {
            settings[[fields[1]]] <- if (fields[1] == "repair") fields[-1] else as.integer(fields[2])
        }
    }
    settings
}
read_candidates <- function(text) {
    candidates <- list()
    current <- NULL
    for (row in strsplit(text, "\n", fixed=TRUE)[[1]]) {
        if (!nzchar(row) || startsWith(row, "#")) next
        if (startsWith(row, "plan ")) {
            fields <- strsplit(row, " ", fixed=TRUE)[[1]]
            current <- list(number=length(candidates)+1L, problem=fields[2], label=fields[3], steps=list())
        } else if (row == "end") {
            candidates[[length(candidates)+1L]] <- current
        } else {
            fields <- strsplit(substr(row, 2L, nchar(row)-1L), " ", fixed=TRUE)[[1]]
            current$steps[[length(current$steps)+1L]] <- fields
        }
    }
    candidates
}
argument_error <- function(domain, arguments, expected, table, noun) {
    if (length(arguments) != length(expected)) {
        return(paste0("expected ", length(expected), " arguments, got ", length(arguments)))
    }
    for (i in seq_along(arguments)) {
        argument <- arguments[i]
        kind <- expected[i]
        if (!argument %in% names(table)) return(paste("unknown", noun, argument))
        if (!subtype(domain$parents, table[[argument]], kind)) {
            return(paste0("argument ", i, " (", argument, ") is not of type ", kind))
        }
    }
    ""
}
validate_domain <- function(domain) {
    kept <- list()
    diagnostics <- character()
    for (action in domain$actions) {
        error <- ""
        for (parameter in action$parameters) if (!parameter[2] %in% domain$type_order) {
            error <- paste("unknown type", parameter[2])
            break
        }
        if (!nzchar(error)) {
            parameters <- setNames(vapply(action$parameters, function(p) p[2], ""),
                vapply(action$parameters, function(p) p[1], ""))
            for (literal in c(action$condition, action$effects)) {
                atom <- literal$atom
                if (atom[1] != "=" && !atom[1] %in% domain$predicate_order) {
                    error <- paste("unknown predicate", atom[1])
                } else {
                    expected <- if (atom[1] == "=") c("object", "object") else domain$predicates[[atom[1]]]
                    error <- argument_error(domain, atom[-1], expected, parameters, "variable")
                }
                if (nzchar(error)) {
                    error <- paste0(notation(atom), ": ", error)
                    break
                }
            }
        }
        if (nzchar(error)) diagnostics <- c(diagnostics, paste0("error: action ", action$name, ": ", error)) else {
            kept[[length(kept)+1L]] <- action
        }
    }
    domain$actions <- kept
    domain$by_name <- setNames(kept, vapply(kept, function(a) a$name, ""))
    used <- unique(unlist(lapply(kept, function(a) vapply(c(a$condition, a$effects), function(l) l$atom[1], "")), use.names=FALSE))
    for (predicate in domain$predicate_order) if (!predicate %in% used) {
        diagnostics <- c(diagnostics, paste("warning: predicate", predicate, "is not used by any action"))
    }
    classes <- predicate_classes(domain)
    domain$fluent <- classes$fluent
    domain$static <- classes$static
    domain$diagnostics <- diagnostics
}
validate_problem <- function(domain, problem) {
    for (side in c("init", "goal")) {
        original <- if (side == "init") problem$initial else problem$goals
        kept <- list()
        seen <- character()
        for (atom in original) {
            error <- if (atom[1] %in% domain$predicate_order) {
                argument_error(domain, atom[-1], domain$predicates[[atom[1]]], problem$objects, "object")
            } else paste("unknown predicate", atom[1])
            key <- notation(atom)
            if (!nzchar(error) && key %in% seen) error <- "duplicate"
            if (nzchar(error)) {
                problem$diagnostics <- c(problem$diagnostics, paste0("warning: ", side, " ", key, ": ", error))
            } else {
                kept[[length(kept)+1L]] <- atom
                seen <- c(seen, key)
            }
        }
        if (side == "init") problem$initial <- kept else problem$goals <- kept
    }
}
validation_result <- function(status, messages, correct) list(status=status, messages=messages, correct=correct)
validate_steps <- function(domain, problem, steps) {
    world <- vapply(problem$initial, notation, "")
    cost <- 0L
    for (i in seq_along(steps)) {
        step <- steps[[i]]
        name <- step[1]
        arguments <- step[-1]
        heading <- paste0("step ", i, " ", notation(step), ": ")
        if (!name %in% names(domain$by_name)) {
            return(validation_result("invalid", paste0(heading, "unknown action ", name), i-1L))
        }
        schema <- domain$by_name[[name]]
        expected <- vapply(schema$parameters, function(p) p[2], "")
        error <- argument_error(domain, arguments, expected, problem$objects, "object")
        if (nzchar(error)) return(validation_result("invalid", paste0(heading, error), i-1L))
        binding <- setNames(arguments, vapply(schema$parameters, function(p) p[1], ""))
        for (literal in schema$condition) {
            bound <- substitute(literal$atom, binding)
            truth <- if (bound[1] == "=") bound[2] == bound[3] else notation(bound) %in% world
            if (truth != literal$sign) {
                text <- if (literal$sign) notation(bound) else paste0("(not ", notation(bound), ")")
                return(validation_result("invalid", paste0(heading, "precondition ", text, " is false"), i-1L))
            }
        }
        deletes <- adds <- character()
        for (literal in schema$effects) {
            key <- notation(substitute(literal$atom, binding))
            if (literal$sign) adds <- union(adds, key) else deletes <- union(deletes, key)
        }
        world <- union(setdiff(world, deletes), adds)
        cost <- cost+schema$cost
    }
    missing <- vapply(Filter(function(atom) !notation(atom) %in% world, problem$goals),
        function(atom) paste("unsatisfied goal", notation(atom)), "")
    if (length(missing)) validation_result("goal not reached", missing, length(steps)) else {
        validation_result("valid", paste0("length=", length(steps), " cost=", cost), length(steps))
    }
}
verdict <- function(checked) paste0(checked$status, if (checked$status == "valid") " " else ": ", checked$messages[1])
plan_steps <- function(problem, plan) lapply(plan, function(n) c(problem$actions[[n+1L]]$source$name, problem$actions[[n+1L]]$arguments))
plan_cost <- function(problem, plan) sum(vapply(plan, function(n) problem$actions[[n+1L]]$cost, 0L))
interferes <- function(a, b) {
    any(a$delete %in% union(b$pre, b$add)) || any(b$delete %in% union(a$pre, a$add)) ||
        any(a$add %in% b$neg) || any(b$add %in% a$neg)
}
parallelize <- function(problem, plan) {
    assigned <- integer()
    layers <- list()
    for (j in seq_along(plan)) {
        action <- problem$actions[[plan[j]+1L]]
        layer <- 1L
        for (i in seq_len(j-1L)) {
            previous <- problem$actions[[plan[i]+1L]]
            if (any(previous$add %in% action$pre) || any(previous$delete %in% action$neg) || interferes(previous, action)) {
                layer <- max(layer, assigned[i]+1L)
            }
        }
        assigned <- c(assigned, layer)
        while (length(layers) < layer) layers[[length(layers)+1L]] <- integer()
        layers[[layer]] <- c(layers[[layer]], plan[j])
    }
    layers
}
validate_parallel <- function(problem, layers) {
    state <- problem$initial
    for (k in seq_along(layers)) {
        actions <- problem$actions[layers[[k]]+1L]
        if (any(vapply(actions, function(a) !applicable(a, state), FALSE))) return(paste("invalid at layer", k))
        for (i in seq_along(actions)) if (i < length(actions)) for (j in seq.int(i+1L, length(actions))) {
            if (interferes(actions[[i]], actions[[j]])) return(paste("invalid at layer", k))
        }
        deletes <- unique(unlist(lapply(actions, function(a) a$delete), use.names=FALSE))
        adds <- unique(unlist(lapply(actions, function(a) a$add), use.names=FALSE))
        state <- sort(union(setdiff(state, deletes), adds))
    }
    if (all(problem$goal %in% state)) "valid" else "goal not reached"
}
improve <- function(problem, plan) {
    sequence <- plan
    position <- 1L
    while (position <= length(sequence)) {
        state <- problem$initial
        for (n in head(sequence, position-1L)) state <- apply_action(problem$actions[[n+1L]], state)
        applied <- integer()
        for (n in tail(sequence, length(sequence)-position)) {
            action <- problem$actions[[n+1L]]
            if (applicable(action, state)) {
                state <- apply_action(action, state)
                applied <- c(applied, n)
            }
        }
        if (all(problem$goal %in% state)) sequence <- c(head(sequence, position-1L), applied) else position <- position+1L
    }
    sequence
}
transform_negatives <- function(problem) {
    negative <- sort(unique(unlist(lapply(problem$actions, function(a) a$neg), use.names=FALSE)))
    complements <- setNames(length(problem$facts)+seq_along(negative)-1L, as.character(negative))
    mapped <- function(facts) unname(complements[as.character(intersect(facts, negative))])
    actions <- lapply(problem$actions, function(a) list(number=a$number, pre=union(a$pre, mapped(a$neg)),
        add=union(a$add, mapped(a$delete)), delete=union(a$delete, mapped(a$add))))
    initial <- union(problem$initial, mapped(setdiff(negative, problem$initial)))
    list(actions=actions, initial=sort(initial), count=length(negative))
}
domain_report <- function(domain) {
    lines <- c(paste0("== domain ", domain$name, " =="), domain$diagnostics)
    for (kind in domain$type_order) {
        chain <- character()
        current <- kind
        while (!is.null(current)) {
            chain <- c(chain, current)
            current <- domain$parents[[current]]
        }
        lines <- c(lines, paste("type", paste(chain, collapse=" < ")))
    }
    for (name in domain$predicate_order) lines <- c(lines, paste0("predicate ", name, "/", length(domain$predicates[[name]]), " ",
        if (name %in% domain$fluent) "fluent" else "static"))
    for (a in domain$actions) {
        adds <- sum(vapply(a$effects, function(l) l$sign, FALSE))
        lines <- c(lines, paste0("action ", a$name, "/", length(a$parameters), " cost=", a$cost,
            " pre=", length(a$condition), " add=", adds, " del=", length(a$effects)-adds))
    }
    lines
}
grounding_report <- function(domain, p) {
    lines <- c("", paste0("== problem ", p$name, " =="), p$source$diagnostics, paste("objects:", length(p$source$objects)))
    for (kind in domain$type_order) lines <- c(lines, headed(paste0("  ", kind, ":"), p$objects_by_type[[kind]]))
    lines <- c(lines, paste("static facts:", p$static_count))
    for (a in domain$actions) {
        counts <- p$statistics[[a$name]]
        lines <- c(lines, paste0("schema ", a$name, ": assignments=", counts[1], " candidates=", counts[2], " reachable=", counts[3]))
    }
    lines <- c(lines, paste0("candidates: ", p$candidate_count, " reachable: ", length(p$actions)),
        paste0("facts: ", length(p$facts), " init: ", length(p$initial), " goals: ", length(p$goal)))
    for (atom in p$unreachable) lines <- c(lines, paste("unreachable goal:", notation(atom)))
    fluent <- domain$predicate_order[domain$predicate_order %in% domain$fluent]
    counts <- vapply(fluent, function(name) paste0(name, "=", sum(vapply(p$facts, function(a) a[1] == name, FALSE))), "")
    lines <- c(lines, headed("facts by predicate:", counts), "facts:")
    for (i in seq_along(p$facts)) lines <- c(lines, paste0("  ", i-1L, " ", notation(p$facts[[i]])))
    lines <- c(lines, "actions:")
    for (a in p$actions) lines <- c(lines, paste0("  ", a$number, " ", action_text(a), " cost=", a$cost,
        " pre=", number_list(a$pre), " neg=", number_list(a$neg), " add=", number_list(a$add), " del=", number_list(a$delete)))
    lines
}
initial_report <- function(p, engine) {
    values <- heuristic_values(engine, p$initial)
    selected <- landmarks(engine, p$initial)
    if (is.null(selected)) selected <- integer()
    relaxed <- relaxed_plan(engine, p$initial)
    if (is.null(relaxed)) relaxed <- integer()
    lines <- c(paste0("initial h: ", heuristic_text(values)), paste("landmarks:", length(selected)))
    for (n in sort(selected)) lines <- c(lines, paste0("  ", notation(p$facts[[n+1L]])))
    lines <- c(lines, paste0("relaxed plan: length=", length(relaxed), " cost=", value_text(values[4])))
    for (n in relaxed) lines <- c(lines, paste0("  ", action_text(p$actions[[n+1L]])))
    lines <- c(lines, headed("helpful:", vapply(helpful(engine, p$initial), function(n) action_text(p$actions[[n+1L]]), "")))
    list(lines=lines, landmarks=selected)
}
plan_report <- function(domain, p, tag, plan, landmark_set, earlier) {
    key <- state_key(seq_along(plan))
    key <- paste0(key, ":", paste(plan, collapse=","))
    first_tag <- earlier[[key]]
    if (is.null(first_tag)) {
        earlier[[key]] <- tag
        first_tag <- tag
    }
    suffix <- if (first_tag == tag) "" else paste0(" (same as ", first_tag, ")")
    lines <- paste0("plan: length=", length(plan), " cost=", plan_cost(p, plan), suffix)
    for (i in seq_along(plan)) lines <- c(lines, paste0("  ", i, " ", action_text(p$actions[[plan[i]+1L]])))
    counts <- character()
    for (a in domain$actions) {
        count <- sum(vapply(plan, function(n) p$actions[[n+1L]]$source$name == a$name, FALSE))
        if (count > 0L) counts <- c(counts, paste0(a$name, "=", count))
    }
    lines <- c(lines, headed("schemas:", counts))
    layers <- parallelize(p, plan)
    lines <- c(lines, paste0("parallel: layers=", length(layers)))
    for (i in seq_along(layers)) lines <- c(lines, headed(paste0("  ", i, ":"),
        vapply(layers[[i]], function(n) action_text(p$actions[[n+1L]]), "")))
    improved <- improve(p, plan)
    removed <- length(plan)-length(improved)
    lines <- c(lines, paste0("improved: length=", length(improved), " cost=", plan_cost(p, improved), " removed=", removed))
    if (removed > 0L) for (i in seq_along(improved)) lines <- c(lines, paste0("  ", i, " ", action_text(p$actions[[improved[i]+1L]])))
    state <- p$initial
    reached <- integer()
    for (n in plan) {
        state <- apply_action(p$actions[[n+1L]], state)
        reached <- union(reached, intersect(state, landmark_set))
    }
    lines <- c(lines, paste0("landmarks reached: ", length(reached), "/", length(landmark_set)))
    for (n in sort(setdiff(landmark_set, reached))) lines <- c(lines, paste0("  missed ", notation(p$facts[[n+1L]])))
    checked <- validate_steps(domain, p$source, plan_steps(p, plan))
    checked_improved <- validate_steps(domain, p$source, plan_steps(p, improved))
    validations <- c(paste0(tag, ": ", verdict(checked)), paste0("  parallel: ", validate_parallel(p, layers)),
        paste0("  improved: ", verdict(checked_improved)))
    list(lines=lines, validations=validations, valid=checked$status == "valid")
}
profile_report <- function(p, engine, tag, plan) {
    lines <- paste0("-- profile (", tag, ") --")
    state <- p$initial
    remaining <- plan_cost(p, plan)
    overestimates <- integer(length(HEURISTIC_NAMES))
    for (k in 0:length(plan)) {
        values <- heuristic_values(engine, state)
        lines <- c(lines, paste0("  ", k, ": h*=", remaining, " ", heuristic_text(values)))
        overestimates <- overestimates+as.integer(values > remaining)
        if (k < length(plan)) {
            a <- p$actions[[plan[k+1L]+1L]]
            state <- apply_action(a, state)
            remaining <- remaining-a$cost
        }
    }
    lines <- c(lines, paste0("overestimates: ", paste(paste0(HEURISTIC_NAMES, "=", overestimates), collapse=" ")),
        paste0("-- causal links (", tag, ") --"))
    suppliers <- integer(length(p$facts))
    for (k in seq_along(plan)) {
        a <- p$actions[[plan[k]+1L]]
        links <- vapply(sort(a$pre), function(f) paste0(notation(p$facts[[f+1L]]), "<-", suppliers[f+1L]), "")
        lines <- c(lines, headed(paste0("  ", k, " ", action_text(a), ":"), links))
        suppliers[a$add+1L] <- k
    }
    links <- vapply(sort(p$goal), function(f) paste0(notation(p$facts[[f+1L]]), "<-", suppliers[f+1L]), "")
    c(lines, headed("  goal:", links))
}
read_text <- function(name) paste(readLines(file.path("input", name), warn=FALSE), collapse="\n")
main <- function() {
    domain <- read_domain(read_text("domain.txt"))
    sources <- read_problems(read_text("problems.txt"))
    settings <- read_settings(read_text("params.txt"))
    candidates <- read_candidates(read_text("candidates.txt"))
    validate_domain(domain)
    pairs <- c(settings$runs, list(c("graphplan", "none")))
    tags <- vapply(pairs, function(p) if (p[1] == "graphplan") "graphplan" else paste(p, collapse=" "), "")
    totals <- matrix(0L, nrow=length(tags), ncol=4L)
    grounding_lines <- domain_report(domain)
    plan_lines <- graph_lines <- validation_lines <- character()
    comparison <- "problem,algorithm,heuristic,length,cost,expanded,generated"
    problems <- evaluators <- summaries <- list()
    validated_plans <- valid_plans <- 0L
    for (source in sources) {
        validate_problem(domain, source)
        p <- ground(domain, source)
        problems[[p$name]] <- p
        grounding_lines <- c(grounding_lines, grounding_report(domain, p))
        heading <- paste0("== problem ", p$name, " ==")
        plan_lines <- c(plan_lines, heading)
        graph_lines <- c(graph_lines, heading)
        validation_lines <- c(validation_lines, heading)
        unreachable <- length(p$unreachable) > 0L
        engine <- if (unreachable) NULL else new_evaluator(p)
        landmark_set <- integer()
        if (unreachable) {
            plan_lines <- c(plan_lines, "initial h: unreachable goal")
        } else {
            evaluators[[p$name]] <- engine
            initial <- initial_report(p, engine)
            plan_lines <- c(plan_lines, initial$lines)
            landmark_set <- initial$landmarks
        }
        outcomes <- list()
        earlier <- new.env(hash=TRUE, parent=emptyenv())
        proof <- 0L
        for (i in seq_along(pairs)) {
            algorithm <- pairs[[i]][1]
            heuristic <- pairs[[i]][2]
            complements <- 0L
            if (unreachable) {
                outcome <- search_result("unreachable goal")
            } else if (algorithm == "graphplan") {
                transformed <- transform_negatives(p)
                complements <- transformed$count
                outcome <- solve_graphplan(transformed$actions, transformed$initial, p$goal, settings$graphplan)
            } else {
                outcome <- run_search(p, p$initial, algorithm, heuristic, settings$budget, settings$weight, engine)
            }
            outcomes[[i]] <- outcome
            plan_lines <- c(plan_lines, paste0("-- ", tags[i], " --"))
            if (unreachable) {
                plan_lines <- c(plan_lines, "result: FAIL (unreachable goal)")
            } else {
                status <- if (outcome$status == "solved") "solved" else paste0("FAIL (", outcome$status, ")")
                plan_lines <- c(plan_lines, paste0("result: ", status, " expanded=", outcome$expanded, " generated=", outcome$generated))
                if (outcome$status == "solved") {
                    report <- plan_report(domain, p, tags[i], outcome$plan, landmark_set, earlier)
                    plan_lines <- c(plan_lines, report$lines)
                    validation_lines <- c(validation_lines, report$validations)
                    validated_plans <- validated_plans+1L
                    valid_plans <- valid_plans+as.integer(report$valid)
                }
            }
            if (proof == 0L && ((algorithm == "ucs" && heuristic == "none") ||
                (algorithm == "astar" && heuristic == "hmax")) && outcome$status == "solved") proof <- i
            if (algorithm == "graphplan") {
                if (unreachable) {
                    graph_lines <- c(graph_lines, "result: FAIL (unreachable goal)")
                } else {
                    graph_lines <- c(graph_lines, paste("complementary facts:", complements), outcome$lines)
                    counts <- paste0(" searched=", outcome$expanded, " memo_hits=", outcome$memo_hits, " tried=", outcome$generated)
                    if (outcome$status == "solved") {
                        graph_lines <- c(graph_lines, paste0("result: solved levels=", length(outcome$layers),
                            " length=", length(outcome$plan), " cost=", plan_cost(p, outcome$plan), counts))
                        for (k in seq_along(outcome$layers)) graph_lines <- c(graph_lines,
                            headed(paste0("layer ", k, ":"), vapply(outcome$layers[[k]], function(n) action_text(p$actions[[n+1L]]), "")))
                    } else graph_lines <- c(graph_lines, paste0("result: FAIL (", outcome$status, ")", counts))
                }
            }
        }
        if (proof != 0L) plan_lines <- c(plan_lines, profile_report(p, engine, tags[proof], outcomes[[proof]]$plan))
        solved <- Filter(function(o) o$status == "solved", outcomes)
        best <- if (length(solved)) min(vapply(solved, function(o) plan_cost(p, o$plan), 0L)) else NULL
        optimal <- if (proof != 0L) as.character(plan_cost(p, outcomes[[proof]]$plan)) else if (
            any(vapply(outcomes, function(o) o$status %in% c("unreachable goal", "dead end", "exhausted", "unreachable"), FALSE))) "none" else "unknown"
        summaries[[p$name]] <- list(solved=length(solved), best=best, optimal=optimal)
        for (i in seq_along(outcomes)) {
            outcome <- outcomes[[i]]
            totals[i,3] <- totals[i,3]+outcome$expanded
            totals[i,4] <- totals[i,4]+outcome$generated
            if (outcome$status == "solved") {
                length_text <- as.character(length(outcome$plan))
                cost <- plan_cost(p, outcome$plan)
                cost_text <- as.character(cost)
                totals[i,1] <- totals[i,1]+1L
                totals[i,2] <- totals[i,2]+as.integer(cost == best)
            } else length_text <- cost_text <- "-"
            comparison <- c(comparison, paste(c(p$name, pairs[[i]], length_text, cost_text, outcome$expanded, outcome$generated), collapse=","))
        }
        plan_lines <- c(plan_lines, "")
        graph_lines <- c(graph_lines, "")
        validation_lines <- c(validation_lines, "")
    }
    plan_lines <- c(plan_lines, "== summary ==")
    for (source in sources) {
        s <- summaries[[source$name]]
        best <- if (is.null(s$best)) "-" else s$best
        plan_lines <- c(plan_lines, paste0(source$name, ": solved=", s$solved, "/", length(tags), " best=", best, " optimal=", s$optimal))
    }
    for (i in seq_along(tags)) plan_lines <- c(plan_lines, paste0(tags[i], ": solved=", totals[i,1],
        " best=", totals[i,2], " expanded=", totals[i,3], " generated=", totals[i,4]))
    validation_lines <- c(validation_lines, "== candidates ==")
    valid_candidates <- 0L
    for (candidate in candidates) {
        p <- problems[[candidate$problem]]
        checked <- validate_steps(domain, p$source, candidate$steps)
        heading <- paste0("candidate ", candidate$number, " ", candidate$problem, " ", candidate$label, ": ")
        map_steps <- function(steps) unname(p$action_numbers[vapply(steps, notation, "")])
        if (checked$status == "valid") {
            valid_candidates <- valid_candidates+1L
            validation_lines <- c(validation_lines, paste0(heading, verdict(checked)))
            mapped <- map_steps(candidate$steps)
            improved <- improve(p, mapped)
            best <- summaries[[p$name]]$best
            best_text <- if (is.null(best)) "-" else best
            validation_lines <- c(validation_lines, paste0("  improved: length=", length(improved),
                " cost=", plan_cost(p, improved), " removed=", length(mapped)-length(improved), " best known=", best_text))
        } else {
            validation_lines <- c(validation_lines, paste0(heading, checked$status), paste0("  ", checked$messages))
            if (length(p$unreachable)) {
                validation_lines <- c(validation_lines, "  repair: FAIL (unreachable goal)")
                next
            }
            prefix <- map_steps(head(candidate$steps, checked$correct))
            state <- p$initial
            for (n in prefix) state <- apply_action(p$actions[[n+1L]], state)
            outcome <- run_search(p, state, settings$repair[1], settings$repair[2], settings$budget, settings$weight, evaluators[[p$name]])
            if (outcome$status != "solved") {
                validation_lines <- c(validation_lines, paste0("  repair: FAIL (", outcome$status, ")"))
            } else {
                repaired <- c(prefix, outcome$plan)
                validation <- validate_steps(domain, p$source, plan_steps(p, repaired))
                validation_lines <- c(validation_lines, paste0("  repair: kept=", length(prefix), " added=", length(outcome$plan), " ", verdict(validation)))
                for (i in seq_along(repaired)) validation_lines <- c(validation_lines, paste0("    ", i, " ", action_text(p$actions[[repaired[i]+1L]])))
            }
        }
    }
    validation_lines <- c(validation_lines, "", "== summary ==", paste0("plans: ", validated_plans, " valid: ", valid_plans),
        paste0("candidates: ", length(candidates), " valid: ", valid_candidates))
    dir.create("output", showWarnings=FALSE)
    reports <- list(grounding.txt=grounding_lines, plans.txt=plan_lines, graphplan.txt=graph_lines,
        validation.txt=validation_lines, comparison.csv=comparison)
    for (name in names(reports)) writeLines(reports[[name]], file.path("output", name), useBytes=TRUE)
}
main()
