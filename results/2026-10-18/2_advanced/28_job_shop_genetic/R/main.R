for (file in c("instance", "minstd", "dispatch_rules", "genetic", "gantt")) source(paste0(file, ".R"))

RULES <- c("SPT", "LPT", "MWKR", "FIFO")
percentage <- function(a, b) {
    t <- (2000L * a + b) %/% (2L * b)
    paste0(t %/% 10L, ".", t %% 10L, "%")
}
job_letter <- function(j) LETTERS[j]
parameter <- function(params, key) as.integer(params[[key]][1L])
probability <- function(params, key) as.integer(strsplit(params[[key]][1L], "/", fixed = TRUE)[[1L]])
makespan <- function(starts, durations) max(starts + durations)
line_text <- function(...) paste(c(...), collapse = " ")
jackson_bound <- function(instance, machine) {
    tasks <- instance$operations[machine$operations]
    remaining <- vapply(tasks, function(op) op$duration, 0L)
    time <- bound <- 0L
    while (any(remaining > 0L)) {
        pending <- which(remaining > 0L)
        heads <- vapply(tasks, function(op) op$head, 0L)
        if (all(heads[pending] > time)) time <- min(heads[pending])
        released <- pending[heads[pending] <= time]
        tails <- vapply(tasks[released], function(op) op$tail, 0L)
        jobs <- vapply(tasks[released], function(op) op$job, 0L)
        selected <- released[order(-tails, jobs)[1L]]
        later <- heads[heads > time]
        step <- if (length(later)) min(remaining[selected], min(later) - time) else remaining[selected]
        time <- time + step
        remaining[selected] <- remaining[selected] - step
        if (remaining[selected] == 0L) bound <- max(bound, time + tasks[[selected]]$tail)
    }
    bound
}
order_starts <- function(instance, machine_order, durations = instance$durations) {
    starts <- rep(-1L, length(durations))
    completions <- integer(length(durations))
    positions <- rep(1L, instance$machine_count)
    placed <- 0L
    while (placed < length(durations)) {
        for (m in seq_along(machine_order)) {
            sequence <- machine_order[[m]]
            while (positions[m] <= length(sequence)) {
                position <- positions[m]
                id <- sequence[position]
                previous <- instance$operations[[id]]$job_prev
                if (previous != 0L && starts[previous] == -1L) break
                ready <- if (previous == 0L) 0L else completions[previous]
                free <- if (position == 1L) 0L else completions[sequence[position - 1L]]
                starts[id] <- max(ready, free)
                completions[id] <- starts[id] + durations[id]
                positions[m] <- positions[m] + 1L
                placed <- placed + 1L
            }
        }
    }
    starts
}
schedule <- function(instance, starts) {
    completions <- starts + instance$durations
    by_start <- order(starts, seq_along(starts))
    machine_order <- lapply(
        seq_len(instance$machine_count),
        function(m) by_start[vapply(instance$operations[by_start], function(op) op$machine == m, FALSE)]
    )
    previous <- following <- integer(length(starts))
    for (sequence in machine_order) if (length(sequence) > 1L) for (i in seq.int(2L, length(sequence))) {
        previous[sequence[i]] <- sequence[i - 1L]
        following[sequence[i - 1L]] <- sequence[i]
    }
    list(
        instance = instance,
        starts = starts,
        completions = completions,
        makespan = max(completions),
        by_start = by_start,
        order = machine_order,
        machine_prev = previous,
        machine_next = following
    )
}
schedule_of_order <- function(instance, machine_order) schedule(
    instance,
    order_starts(instance, machine_order)
)
critical_path <- function(s) {
    current <- which(s$completions == s$makespan)[1L]
    path <- current
    while (s$starts[current] != 0L) {
        previous <- s$machine_prev[current]
        current <- if (previous != 0L && s$completions[previous] == s$starts[current]) previous else s$instance$operations[[current]]$job_prev
        path <- c(current, path)
    }
    path
}
path_blocks <- function(s, path = critical_path(s)) {
    blocks <- list()
    for (id in path) {
        last <- length(blocks)
        if (last && s$instance$operations[[tail(
            blocks[[last]],
            1L
        )]]$machine == s$instance$operations[[id]]$machine) blocks[[last]] <- c(
            blocks[[last]],
            id
        ) else blocks <- c(blocks, list(id))
    }
    blocks
}
moves <- function(s) {
    result <- list()
    for (block in path_blocks(s)) if (length(block) > 1L) for (i in seq.int(2L, length(block))) result <- c(
        result,
        list(c(block[i - 1L], block[i]))
    )
    result
}
path_count <- function(s) {
    ways <- integer(length(s$starts))
    for (id in s$by_start) {
        if (s$starts[id] == 0L) ways[id] <- 1L else {
            sources <- c(s$instance$operations[[id]]$job_prev, s$machine_prev[id])
            for (source in sources) if (source != 0L && s$completions[source] == s$starts[id]) ways[id] <- ways[id] + ways[source]
        }
    }
    sum(ways[s$completions == s$makespan])
}
left_shift <- function(s, id) {
    op <- s$instance$operations[[id]]
    sequence <- s$order[[op$machine]]
    position <- match(id, sequence)
    ready <- if (op$job_prev == 0L) 0L else s$completions[op$job_prev]
    for (insertion in seq_len(position - 1L)) {
        begin <- if (insertion == 1L) 0L else s$completions[sequence[insertion - 1L]]
        start <- max(begin, ready)
        if (start + op$duration <= s$starts[sequence[insertion]]) return(c(start, insertion))
    }
    NULL
}
slacks <- function(s) {
    latest <- slack <- free <- integer(length(s$starts))
    for (id in rev(s$by_start)) {
        successors <- c(s$instance$operations[[id]]$job_next, s$machine_next[id])
        successors <- successors[successors != 0L]
        latest[id] <- (if (length(successors)) min(latest[successors]) else s$makespan) - s$instance$durations[id]
        slack[id] <- latest[id] - s$starts[id]
        free[id] <- (if (length(successors)) min(s$starts[successors]) else s$makespan) - s$completions[id]
    }
    list(slack = slack, free = free)
}
path_counts <- function(s, path = critical_path(s)) vapply(
    seq_len(s$instance$machine_count),
    function(m) sum(vapply(s$instance$operations[path], function(op) op$machine == m, FALSE)),
    0L
)
bottleneck <- function(s, path = critical_path(s)) which.max(path_counts(s, path))
chromosome <- function(s) vapply(s$instance$operations[s$by_start], function(op) op$job, 0L)
flow_time <- function(s) sum(vapply(
    s$instance$jobs,
    function(job) s$completions[tail(job$operations, 1L)],
    0L
))
total_idle <- function(s) s$instance$machine_count * s$makespan - sum(s$instance$durations)
utilization <- function(s, machine) percentage(machine$load, s$makespan)
sequence_letters <- function(s, m) paste(
    vapply(s$instance$operations[s$order[[m]]], function(op) job_letter(op$job), ""),
    collapse = ""
)
apply_move <- function(instance, machine_order, move) {
    m <- instance$operations[[move[1L]]]$machine
    position <- match(move[1L], machine_order[[m]])
    machine_order[[m]][c(position, position + 1L)] <- rev(move)
    machine_order
}
machine_distances <- function(first, second) {
    vapply(seq_along(first$order), function(m) {
        a <- first$order[[m]]
        ranks <- match(a, second$order[[m]])
        count <- 0L
        for (i in seq_along(a)) if (i < length(a)) count <- count + sum(ranks[i] > ranks[seq.int(
            i + 1L,
            length(a)
        )])
        count
    }, 0L)
}
tabu_search <- function(instance, start_order, iterations, tenure) {
    current <- best_order <- start_order
    start_value <- makespan(order_starts(instance, current), instance$durations)
    best <- start_value
    found <- 0L
    records <- list()
    expiry <- list()
    reason <- "limit"
    for (iteration in seq_len(iterations)) {
        neighborhood <- moves(schedule_of_order(instance, current))
        if (!length(neighborhood)) {
            reason <- "no_moves"
            break
        }
        values <- vapply(
            neighborhood,
            function(move) makespan(
                order_starts(instance, apply_move(instance, current, move)),
                instance$durations
            ),
            0L
        )
        tabu <- vapply(neighborhood, function(move) {
            value <- expiry[[paste(move, collapse = ":")]]
            !is.null(value) && value >= iteration
        }, FALSE)
        selectable <- which(!tabu | values < best)
        if (!length(selectable)) {
            reason <- "all_tabu"
            break
        }
        chosen <- selectable[which.min(values[selectable])]
        move <- neighborhood[[chosen]]
        current <- apply_move(instance, current, move)
        expiry[[paste(rev(move), collapse = ":")]] <- iteration + tenure
        if (values[chosen] < best) {
            best_order <- current
            best <- values[chosen]
            found <- iteration
        }
        records <- c(
            records,
            list(list(
                iteration = iteration,
                move_count = length(neighborhood),
                tabu_count = sum(tabu),
                move = move,
                aspiration = tabu[chosen],
                value = values[chosen],
                best = best
            ))
        )
    }
    list(
        start_value = start_value,
        best_order = best_order,
        best_value = best,
        found = found,
        records = records,
        reason = reason,
        iterations = iterations,
        tenure = tenure
    )
}
activate <- function(instance, machine_order) {
    shifts <- list()
    repeat {
        s <- schedule_of_order(instance, machine_order)
        found <- FALSE
        for (id in s$by_start) {
            shift <- left_shift(s, id)
            if (is.null(shift)) next
            m <- instance$operations[[id]]$machine
            sequence <- machine_order[[m]]
            sequence <- sequence[sequence != id]
            machine_order[[m]] <- append(sequence, id, after = shift[2L] - 1L)
            shifts <- c(shifts, list(list(ident = id, old_start = s$starts[id], new_start = shift[1L])))
            found <- TRUE
            break
        }
        if (!found) return(list(order = machine_order, shifts = shifts))
    }
}
gcd <- function(a, b) {
    while (b != 0L) {
        remainder <- a %% b
        a <- b
        b <- remainder
    }
    a
}
genetic_algorithm <- function(instance, params, seeds) {
    rng <- minstd(parameter(params, "seed"))
    population <- seeds
    p <- parameter(params, "population")
    g <- parameter(params, "generations")
    e <- parameter(params, "elitism")
    k <- parameter(params, "tournament")
    jobs <- vapply(instance$jobs, function(job) job$number, 0L)
    checkpoints <- as.integer(params$checkpoints)
    while (length(population) < p) {
        basic <- unlist(
            lapply(instance$jobs, function(job) rep(job$number, length(job$operations))),
            use.names = FALSE
        )
        population <- c(population, list(shuffle_genes(rng, basic)))
    }
    records <- progress <- list()
    crossovers <- swaps <- inserts <- 0L
    previous_best <- .Machine$integer.max
    for (generation in seq.int(0L, g)) {
        values <- vapply(
            population,
            function(genes) makespan(decode(instance, genes), instance$durations),
            0L
        )
        ranking <- order(values, seq_along(values))
        best <- ranking[1L]
        if (values[best] < previous_best) records <- c(records, list(c(generation, values[best], best)))
        previous_best <- values[best]
        if (generation %in% checkpoints) {
            total <- sum(values)
            divisor <- gcd(total, p)
            distinct <- length(unique(vapply(population, paste, "", collapse = ":")))
            progress <- c(
                progress,
                list(list(
                    generation = generation,
                    best = min(values),
                    mean = paste(total %/% divisor, p %/% divisor, sep = "/"),
                    worst = max(values),
                    distinct = distinct
                ))
            )
        }
        if (generation == g) break
        offspring <- population[ranking[seq_len(e)]]
        for (pair in seq_len((p - e) %/% 2L)) {
            first <- population[[tournament(rng, values, k)]]
            second <- population[[tournament(rng, values, k)]]
            if (chance(rng, probability(params, "crossover"))) {
                crossovers <- crossovers + 1L
                children <- crossover(rng, first, second, jobs)
            } else children <- list(first, second)
            for (child in children) {
                if (chance(rng, probability(params, "swap_mutation"))) {
                    swaps <- swaps + 1L
                    child <- swap_mutation(rng, child)
                }
                if (chance(rng, probability(params, "insert_mutation"))) {
                    inserts <- inserts + 1L
                    child <- insert_mutation(rng, child)
                }
                offspring <- c(offspring, list(child))
            }
        }
        population <- offspring
    }
    ranking <- order(values, seq_along(values))
    seen <- character()
    top <- integer()
    for (i in ranking) {
        key <- paste(population[[i]], collapse = ":")
        if (!(key %in% seen)) {
            seen <- c(seen, key)
            top <- c(top, i)
            if (length(top) == 5L) break
        }
    }
    list(
        population = population,
        values = values,
        records = records,
        progress = progress,
        crossovers = crossovers,
        swaps = swaps,
        inserts = inserts,
        best_index = ranking[1L],
        top = top
    )
}
solve <- function(instance, params) {
    iterations <- parameter(params, "tabu_iterations")
    tenure <- parameter(params, "tabu_tenure")
    jacksons <- vapply(instance$machines, function(machine) jackson_bound(instance, machine), 0L)
    job_bound <- which.max(vapply(instance$jobs, function(job) job$work, 0L))
    machine_bound <- which.max(vapply(instance$machines, function(machine) machine$bound, 0L))
    jackson_index <- which.max(jacksons)
    lower_bound <- max(
        instance$jobs[[job_bound]]$work,
        instance$machines[[machine_bound]]$bound,
        jacksons[jackson_index]
    )
    baselines <- lapply(RULES, function(rule) {
        result <- giffler_thompson(instance, rule)
        s <- schedule(instance, result$starts)
        list(
            rule = rule,
            schedule = s,
            decisions = result$decisions,
            ties = result$ties,
            path = critical_path(s),
            search = tabu_search(instance, s$order, iterations, tenure)
        )
    })
    ga <- genetic_algorithm(
        instance,
        params,
        lapply(baselines, function(baseline) chromosome(baseline$schedule))
    )
    genes <- ga$population[[ga$best_index]]
    ga_schedule <- schedule(instance, decode(instance, genes))
    positions <- integer(length(instance$operations))
    ids <- gene_operations(instance, genes)
    positions[ids] <- seq_along(ids)
    active <- giffler_thompson(instance, "GENES", positions)
    activated <- activate(instance, ga_schedule$order)
    search <- tabu_search(instance, activated$order, iterations, tenure)
    list(instance = instance, params = params, jacksons = jacksons, job_bound = job_bound, machine_bound = machine_bound, jackson_index = jackson_index, lower_bound = lower_bound,
         baselines = baselines, genetic = ga, ga_schedule = ga_schedule, active_makespan = makespan(
             active$starts,
             instance$durations
         ), active_decisions = active$decisions,
         activated_value = search$start_value, shifts = activated$shifts, search = search, final = schedule_of_order(
             instance,
             search$best_order
         ))
}
baseline_lines <- function(solver) {
    instance <- solver$instance
    lb <- solver$lower_bound
    lines <- line_text(
        "INSTANCE",
        "jobs",
        length(instance$jobs),
        "machines",
        instance$machine_count,
        "operations",
        length(instance$operations),
        "work",
        sum(instance$durations),
        "errors",
        length(instance$errors)
    )
    add <- function(...) lines <<- c(lines, line_text(...))
    for (error in instance$errors) add("ERROR", error)
    for (job in instance$jobs) add(
        "JOB",
        paste0("J", job$number),
        "operations",
        length(job$operations),
        "work",
        job$work,
        "route",
        vapply(instance$operations[job$operations], function(op) paste0("M", op$machine), "")
    )
    for (m in instance$machines) add(
        "MACHINE",
        paste0("M", m$number),
        "operations",
        length(m$operations),
        "load",
        m$load,
        "head",
        m$head,
        "tail",
        m$tail,
        "bound",
        m$bound,
        "jackson",
        solver$jacksons[m$number]
    )
    job <- instance$jobs[[solver$job_bound]]
    machine <- instance$machines[[solver$machine_bound]]
    add("BOUND", "job", job$work, paste0("J", job$number))
    add("BOUND", "machine", machine$bound, paste0("M", machine$number))
    add("BOUND", "jackson", solver$jacksons[solver$jackson_index], paste0("M", solver$jackson_index))
    add("BOUND", "lower", lb)
    for (b in solver$baselines) {
        s <- b$schedule
        search <- b$search
        add(
            "RULE",
            b$rule,
            "makespan",
            s$makespan,
            "gap",
            percentage(s$makespan - lb, lb),
            "flow",
            flow_time(s),
            "idle",
            total_idle(s),
            "decisions",
            b$decisions,
            "ties",
            b$ties
        )
        add(
            "PATH",
            b$rule,
            "operations",
            length(b$path),
            "blocks",
            length(path_blocks(s, b$path)),
            "critical_paths",
            path_count(s),
            "bottleneck",
            paste0("M", bottleneck(s, b$path))
        )
        add(
            "TABU",
            b$rule,
            "makespan",
            s$makespan,
            "->",
            search$best_value,
            "found",
            search$found,
            "iterations",
            length(search$records),
            "stop",
            search$reason
        )
    }
    best <- solver$baselines[[which.min(vapply(solver$baselines, function(b) b$schedule$makespan, 0L))]]
    add("BEST", best$rule, "makespan", best$schedule$makespan)
    for (m in instance$machines) add(
        "UTILIZATION",
        paste0("M", m$number),
        unlist(lapply(solver$baselines, function(b) c(b$rule, utilization(b$schedule, m))), use.names = FALSE)
    )
    lines
}
progress_lines <- function(solver) c(
    "generation,best,mean,worst,distinct",
    vapply(
        solver$genetic$progress,
        function(p) paste(p$generation, p$best, p$mean, p$worst, p$distinct, sep = ","),
        ""
    )
)
gantt_lines <- function(solver, path) {
    instance <- solver$instance
    s <- solver$final
    dimensions <- chart_scale(s$makespan, parameter(solver$params, "gantt_width"))
    scale <- dimensions[1L]
    columns <- dimensions[2L]
    intervals <- lapply(
        instance$machines,
        function(m) lapply(
            instance$operations[m$operations],
            function(op) list(
                start = s$starts[op$id],
                end = s$completions[op$id],
                symbol = if (op$id %in% path) tolower(job_letter(op$job)) else job_letter(op$job)
            )
        )
    )
    lines <- c(
        line_text("GANTT", "scale", scale, "columns", columns),
        time_row(scale, columns),
        rule_row(columns)
    )
    for (m in instance$machines) lines <- c(
        lines,
        chart_row(paste0("M", m$number), intervals[[m$number]], scale, columns)
    )
    lines <- c(lines, busy_row(intervals, scale, columns))
    for (job in instance$jobs) {
        row <- lapply(
            instance$operations[job$operations],
            function(op) list(
                start = s$starts[op$id],
                end = s$completions[op$id],
                symbol = as.character(op$machine %% 10L)
            )
        )
        lines <- c(lines, chart_row(paste0("J", job$number), row, scale, columns))
    }
    lines
}
schedule_lines <- function(solver) {
    instance <- solver$instance
    s <- solver$final
    ga <- solver$genetic
    ops <- instance$operations
    lb <- solver$lower_bound
    lines <- line_text(
        "GA",
        "best",
        solver$ga_schedule$makespan,
        "generation",
        tail(ga$records, 1L)[[1L]][1L],
        "crossovers",
        ga$crossovers,
        "swaps",
        ga$swaps,
        "inserts",
        ga$inserts
    )
    add <- function(...) lines <<- c(lines, line_text(...))
    for (record in ga$records) add(
        "RECORD",
        "generation",
        record[1L],
        "makespan",
        record[2L],
        "individual",
        record[3L]
    )
    for (rank in seq_along(ga$top)) {
        index <- ga$top[rank]
        other <- schedule(instance, decode(instance, ga$population[[index]]))
        add(
            "TOP",
            rank,
            "individual",
            index,
            "makespan",
            ga$values[index],
            "distance",
            sum(machine_distances(other, solver$ga_schedule))
        )
    }
    add("GA_CHROMOSOME", ga$population[[ga$best_index]])
    add("ACTIVE_DECODE", "makespan", solver$active_makespan, "decisions", solver$active_decisions)
    for (number in seq_along(solver$shifts)) {
        shift <- solver$shifts[[number]]
        op <- ops[[shift$ident]]
        add(
            "SHIFT",
            number,
            op$code,
            paste0("M", op$machine),
            "start",
            shift$old_start,
            "->",
            shift$new_start
        )
    }
    add(
        "ACTIVATED",
        "makespan",
        solver$ga_schedule$makespan,
        "->",
        solver$activated_value,
        "shifts",
        length(solver$shifts)
    )
    shiftable <- sum(vapply(seq_along(ops), function(id) !is.null(left_shift(s, id)), FALSE))
    add(
        "SCHEDULE",
        "makespan",
        s$makespan,
        "lower_bound",
        lb,
        "gap",
        percentage(s$makespan - lb, lb),
        "improvement",
        solver$ga_schedule$makespan - s$makespan,
        "shiftable",
        shiftable
    )
    add("CHROMOSOME", chromosome(s))
    add("LEGEND", vapply(instance$jobs, function(job) paste0(job_letter(job$number), "=J", job$number), ""))
    lines <- c(lines, gantt_lines(solver, critical_path(s)))
    for (m in instance$machines) add(
        "ORDER",
        paste0("M", m$number),
        "FINAL",
        sequence_letters(s, m$number),
        unlist(
            lapply(solver$baselines, function(b) c(b$rule, sequence_letters(b$schedule, m$number))),
            use.names = FALSE
        )
    )
    for (m in instance$machines) {
        sequence <- s$order[[m$number]]
        gaps <- integer()
        intervals <- list(c(0L, s$starts[sequence[1L]]))
        if (length(sequence) > 1L) for (i in seq.int(2L, length(sequence))) {
            gap <- s$starts[sequence[i]] - s$completions[sequence[i - 1L]]
            if (gap > 0L) gaps <- c(gaps, gap)
            intervals <- c(intervals, list(c(s$completions[sequence[i - 1L]], s$starts[sequence[i]])))
        }
        intervals <- c(intervals, list(c(s$completions[tail(sequence, 1L)], s$makespan)))
        intervals <- Filter(function(interval) interval[2L] > interval[1L], intervals)
        text <- vapply(
            sequence,
            function(id) paste0("J", ops[[id]]$job, ":", s$starts[id], "-", s$completions[id]),
            ""
        )
        add(
            "MACHINE",
            paste0("M", m$number),
            "load",
            m$load,
            "idle",
            s$makespan - m$load,
            "utilization",
            utilization(s, m),
            "gaps",
            length(gaps),
            "longest_gap",
            max(c(0L, gaps)),
            "sequence",
            text
        )
        idle <- if (length(intervals)) vapply(
            intervals,
            function(interval) paste(interval, collapse = "-"),
            ""
        ) else "none"
        add("IDLE", paste0("M", m$number), idle)
    }
    waiting_total <- 0L
    for (job in instance$jobs) {
        completion <- s$completions[tail(job$operations, 1L)]
        waiting <- completion - job$work
        waiting_total <- waiting_total + waiting
        add(
            "JOB",
            paste0("J", job$number),
            "operations",
            length(job$operations),
            "work",
            job$work,
            "start",
            s$starts[job$operations[1L]],
            "completion",
            completion,
            "waiting",
            waiting
        )
    }
    add("TOTAL", "flow", flow_time(s), "waiting", waiting_total, "idle", total_idle(s))
    others <- c(lapply(solver$baselines, function(b) b$schedule), list(solver$ga_schedule))
    labels <- c(RULES, "GA")
    distances <- lapply(others, function(other) machine_distances(s, other))
    pairs_total <- 0L
    for (m in instance$machines) {
        q <- length(m$operations)
        pairs <- (q * (q - 1L)) %/% 2L
        pairs_total <- pairs_total + pairs
        text <- unlist(
            lapply(seq_along(labels), function(i) c(labels[i], distances[[i]][m$number])),
            use.names = FALSE
        )
        add("DISTANCE", paste0("M", m$number), "pairs", pairs, text)
    }
    text <- unlist(
        lapply(seq_along(labels), function(i) c(labels[i], sum(distances[[i]]))),
        use.names = FALSE
    )
    add("DISTANCE", "total", "pairs", pairs_total, text)
    lines
}
path_lines <- function(solver) {
    instance <- solver$instance
    s <- solver$final
    search <- solver$search
    ops <- instance$operations
    lines <- line_text(
        "SEARCH",
        "start",
        search$start_value,
        "iterations",
        search$iterations,
        "tenure",
        search$tenure
    )
    add <- function(...) lines <<- c(lines, line_text(...))
    for (record in search$records) {
        a <- ops[[record$move[1L]]]
        b <- ops[[record$move[2L]]]
        kind <- if (record$aspiration) "aspiration" else "free"
        add(
            "ITER",
            record$iteration,
            "moves",
            record$move_count,
            "tabu",
            record$tabu_count,
            "swap",
            paste0("M", a$machine),
            a$code,
            b$code,
            kind,
            "makespan",
            record$value,
            "best",
            record$best
        )
    }
    add(
        "STOP",
        "iterations",
        length(search$records),
        "reason",
        search$reason,
        "best",
        search$best_value,
        "found",
        search$found
    )
    path <- critical_path(s)
    blocks <- path_blocks(s, path)
    add(
        "PATH",
        "operations",
        length(path),
        "blocks",
        length(blocks),
        "makespan",
        s$makespan,
        "critical_paths",
        path_count(s)
    )
    for (number in seq_along(path)) {
        id <- path[number]
        op <- ops[[id]]
        link <- if (number == 1L) "start" else if (s$machine_prev[id] == path[number - 1L]) "machine" else "job"
        add(
            "NODE",
            number,
            op$code,
            paste0("M", op$machine),
            paste(s$starts[id], s$completions[id], sep = "-"),
            link
        )
    }
    for (number in seq_along(blocks)) {
        block <- blocks[[number]]
        add(
            "BLOCK",
            number,
            paste0("M", ops[[block[1L]]]$machine),
            paste(s$starts[block[1L]], s$completions[tail(block, 1L)], sep = "-"),
            vapply(ops[block], function(op) op$code, "")
        )
    }
    neighborhood <- moves(s)
    for (number in seq_along(neighborhood)) {
        move <- neighborhood[[number]]
        a <- ops[[move[1L]]]
        b <- ops[[move[2L]]]
        value <- makespan(order_starts(instance, apply_move(instance, s$order, move)), instance$durations)
        add("NEIGHBOUR", number, paste0("M", a$machine), a$code, b$code, "makespan", value)
    }
    slack <- slacks(s)
    add("CRITICAL", "operations", sum(slack$slack == 0L), "total", length(ops))
    for (job in instance$jobs) add("SLACK", paste0("J", job$number), slack$slack[job$operations])
    for (job in instance$jobs) add("FREE", paste0("J", job$number), slack$free[job$operations])
    counts <- path_counts(s, path)
    for (m in instance$machines) {
        durations <- vapply(
            ops,
            function(op) op$duration + if (op$machine == m$number) (op$duration + 9L) %/% 10L else 0L,
            0L
        )
        sensitivity <- makespan(order_starts(instance, s$order, durations), durations)
        critical <- sum(slack$slack[m$operations] == 0L)
        add(
            "MACHINE",
            paste0("M", m$number),
            "critical",
            critical,
            "path",
            counts[m$number],
            "sensitivity",
            sensitivity,
            "delta",
            sensitivity - s$makespan
        )
    }
    machine <- which.max(counts)
    add("BOTTLENECK", paste0("M", machine), "path", counts[machine])
    lines
}
main <- function() {
    options(scipen = 999)
    params <- list()
    for (fields in strsplit(
        readLines("input/ga_params.txt"),
        " ",
        fixed = TRUE
    )) params[[fields[1L]]] <- fields[-1L]
    solver <- solve(load_instance("input/instance.txt"), params)
    dir.create("output", showWarnings = FALSE)
    outputs <- list(
        "baselines.txt" = baseline_lines(solver),
        "ga_progress.csv" = progress_lines(solver),
        "best_schedule.txt" = schedule_lines(solver),
        "critical_path.txt" = path_lines(solver)
    )
    for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
