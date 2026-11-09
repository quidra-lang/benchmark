for (file in c("heap", "mutator", "mark_sweep", "copying", "generational")) source(paste0(file, ".R"))

SUMMARY_HEADER <- "collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation"
line_text <- function(...) paste(c(...), collapse = " ")
reachable_numbers <- function(roots, objects) {
    reached <- integer()
    stack <- roots[roots != 0L]
    while (length(stack)) {
        id <- tail(stack, 1L)
        stack <- head(stack, -1L)
        if (id %in% reached) next
        reached <- c(reached, id)
        children <- objects[[id]]$fields
        stack <- c(stack, children[children != 0L])
    }
    reached
}
state_error <- function(command, roots, objects, labels) {
    name <- command$name
    depth <- length(roots)
    if (name %in% c("ALLOC", "PUSH", "LOAD") && depth == 64L) return("stack")
    if (name %in% c("LOAD", "SET", "OVERWRITE") && command$slot >= depth) return("stack")
    if (name %in% c("PUSH", "SET", "OVERWRITE") && command$source >= depth) return("stack")
    if (name == "POP" && command$count > depth) return("stack")
    if (name %in% c("LOAD", "SET")) {
        target <- roots[command$slot + 1L]
        if (target == 0L) return("null")
        if (command$field >= length(objects[[target]]$fields)) return("field")
    }
    if (name == "CHECKPOINT" && command$label %in% labels) return("duplicate")
    NULL
}
source_value <- function(roots, source) if (source == -1L) 0L else roots[source + 1L]
plain_command <- function(command, roots, objects) {
    name <- command$name
    if (name == "PUSH") roots <- c(roots, source_value(roots, command$source)) else if (name == "LOAD") roots <- c(
        roots,
        objects[[roots[command$slot + 1L]]]$fields[command$field + 1L]
    ) else if (name == "POP") roots <- head(roots, length(roots) - command$count) else if (name == "SET") objects[[roots[command$slot + 1L]]]$fields[command$field + 1L] <- source_value(roots, command$source) else if (name == "OVERWRITE") roots[command$slot + 1L] <- source_value(roots, command$source)
    roots
}
analyze_script <- function(parsed) {
    commands <- errors <- checkpoints <- objects <- list()
    counts <- setNames(integer(length(COMMAND_NAMES)), COMMAND_NAMES)
    roots <- births <- deaths <- lifetimes <- integer()
    clock <- phase_start <- peak_line <- 0L
    labels <- character()
    alive <- integer()
    live <- peak <- c(0L, 0L)
    for (line in seq_along(parsed)) {
        command <- parsed[[line]]$command
        reason <- parsed[[line]]$reason
        if (is.null(reason)) reason <- state_error(command, roots, objects, labels)
        if (!is.null(reason)) {
            errors <- c(errors, list(list(line = line, reason = reason)))
            next
        }
        commands <- c(commands, list(command))
        counts[command$name] <- counts[command$name] + 1L
        if (command$name == "ALLOC") {
            object <- heap_object(length(objects) + 1L, command$pointers, command$data)
            objects <- c(objects, list(object))
            births <- c(births, clock)
            deaths <- c(deaths, 0L)
            lifetimes <- c(lifetimes, -1L)
            clock <- clock + object$size
            roots <- c(roots, object$number)
        } else roots <- plain_command(command, roots, objects)
        reachable <- reachable_numbers(roots, objects)
        for (id in setdiff(alive, reachable)) {
            deaths[id] <- command$line
            lifetimes[id] <- clock - births[id] - objects[[id]]$size
        }
        alive <- reachable
        live <- object_pair(objects[alive])
        if (peak_line == 0L || live[2L] > peak[2L]) {
            peak <- live
            peak_line <- command$line
        }
        if (command$name == "CHECKPOINT") {
            labels <- c(labels, command$label)
            phase_objects <- if (phase_start < length(objects)) objects[seq.int(
                phase_start + 1L,
                length(objects)
            )] else list()
            survivors <- Filter(function(object) object$number %in% reachable, phase_objects)
            checkpoint <- list(
                label = command$label,
                line = command$line,
                stack = length(roots),
                live = live,
                allocated = object_pair(objects),
                phase = object_pair(phase_objects),
                survivors = object_pair(survivors),
                reachable = reachable
            )
            checkpoints <- c(checkpoints, list(checkpoint))
            phase_start <- length(objects)
        }
    }
    list(
        line_count = length(parsed),
        commands = commands,
        errors = errors,
        counts = counts,
        roots = roots,
        objects = objects,
        deaths = deaths,
        lifetimes = lifetimes,
        live = live,
        peak = peak,
        peak_line = peak_line,
        checkpoints = checkpoints,
        alive = alive
    )
}
script_lines <- function(script) {
    lines <- line_text(
        "script",
        "lines",
        script$line_count,
        "valid",
        length(script$commands),
        "errors",
        length(script$errors)
    )
    add <- function(...) lines <<- c(lines, line_text(...))
    for (error in script$errors) add("error", "line", error$line, error$reason)
    add(
        "commands",
        unlist(lapply(COMMAND_NAMES, function(name) c(name, script$counts[name])), use.names = FALSE)
    )
    sizes <- vapply(script$objects, function(object) object$size, 0L)
    add("allocated", "objects", length(sizes), "words", sum(sizes), "sizes", class_table(sizes))
    add("peak_live", "objects", script$peak[1L], "words", script$peak[2L], "line", script$peak_line)
    add("end_live", "objects", script$live[1L], "words", script$live[2L], "stack", length(script$roots))
    counts <- integer(6L)
    for (lifetime in script$lifetimes) {
        if (lifetime == -1L) index <- 6L else {
            found <- which(lifetime <= c(63L, 255L, 1023L, 4095L))
            index <- if (length(found)) found[1L] else 5L
        }
        counts[index] <- counts[index] + 1L
    }
    labels <- c("0-63", "64-255", "256-1023", "1024-4095", "4096+", "live")
    add(
        "lifetimes",
        unlist(lapply(seq_along(labels), function(i) c(labels[i], counts[i])), use.names = FALSE)
    )
    for (checkpoint in script$checkpoints) add(
        "checkpoint",
        checkpoint$label,
        "line",
        checkpoint$line,
        "stack",
        checkpoint$stack,
        "live",
        checkpoint$live,
        "allocated",
        checkpoint$allocated,
        "phase",
        checkpoint$phase,
        "survivors",
        checkpoint$survivors,
        "survival",
        pct(checkpoint$survivors[2L], checkpoint$phase[2L])
    )
    lines
}
leak_report <- function(title, garbage, deaths, placed) {
    members <- vapply(garbage, function(object) object$number, 0L)
    neighbors <- setNames(lapply(members, function(id) integer()), as.character(members))
    for (object in garbage) for (id in object$fields) if (id %in% members) {
        key <- as.character(object$number)
        other <- as.character(id)
        neighbors[[key]] <- c(neighbors[[key]], id)
        neighbors[[other]] <- c(neighbors[[other]], object$number)
    }
    groups <- list()
    grouped <- integer()
    for (id in sort(members)) {
        if (id %in% grouped) next
        stack <- id
        group <- integer()
        grouped <- c(grouped, id)
        while (length(stack)) {
            current <- tail(stack, 1L)
            stack <- head(stack, -1L)
            group <- c(group, current)
            for (other in neighbors[[as.character(current)]]) if (!(other %in% grouped)) {
                grouped <- c(grouped, other)
                stack <- c(stack, other)
            }
        }
        groups <- c(groups, list(sort(group)))
    }
    on_cycle <- function(id) {
        visited <- integer()
        children <- placed[[id]]$fields
        stack <- children[children %in% members]
        while (length(stack)) {
            current <- tail(stack, 1L)
            stack <- head(stack, -1L)
            if (current == id) return(TRUE)
            if (current %in% visited) next
            visited <- c(visited, current)
            children <- placed[[current]]$fields
            stack <- c(stack, children[children %in% members])
        }
        FALSE
    }
    lines <- line_text(
        title,
        "groups",
        length(groups),
        "objects",
        length(garbage),
        "words",
        object_pair(garbage)[2L]
    )
    for (number in seq_along(groups)) {
        group <- groups[[number]]
        cycles <- vapply(group, on_cycle, FALSE)
        ids <- paste0(group, ifelse(cycles, "*", ""))
        lines <- c(
            lines,
            line_text(
                "group",
                number,
                "objects",
                length(group),
                "words",
                object_pair(placed[group])[2L],
                "cycle",
                sum(cycles),
                "died",
                max(deaths[group]),
                "ids",
                ids
            )
        )
    }
    lines
}
retain <- function(state, id) {
    if (id == 0L) return(invisible(NULL))
    state$placed[[id]]$count <- state$placed[[id]]$count + 1L
    state$increments <- state$increments + 1L
}
release <- function(state, id) {
    if (id == 0L) return(invisible(NULL))
    state$decrements <- state$decrements + 1L
    state$placed[[id]]$count <- state$placed[[id]]$count - 1L
    if (state$placed[[id]]$count != 0L) return(invisible(NULL))
    pending <- id
    while (length(pending)) {
        id <- tail(pending, 1L)
        pending <- head(pending, -1L)
        object <- state$placed[[id]]
        state$objects <- Filter(function(current) current$number != object$number, state$objects)
        state$released <- c(state$released, list(object))
        for (child in object$fields) {
            if (child == 0L) next
            state$decrements <- state$decrements + 1L
            state$placed[[child]]$count <- state$placed[[child]]$count - 1L
            if (state$placed[[child]]$count == 0L) pending <- c(pending, child)
        }
    }
}
collect_backup <- function(state, roots, line, request) {
    record <- collection_record(length(state$records) + 1L, line, request, "backup", free_list(state))
    mark(record, roots, state$objects, state$placed)
    garbage <- Filter(function(object) !object$marked, state$objects)
    title <- line_text("backup", record$number, "line", line)
    state$reports <- c(state$reports, list(leak_report(title, garbage, state$deaths, state$placed)))
    sweep(state, record)
    for (object in garbage) for (id in object$fields) if (id != 0L && state$placed[[id]]$marked) {
        state$placed[[id]]$count <- state$placed[[id]]$count - 1L
        state$decrements <- state$decrements + 1L
    }
    finish_record(state, record)
}
new_run <- function(entry, config, script) {
    run <- new.env(parent = emptyenv())
    run$entry <- entry
    run$config <- config
    run$script <- script
    run$collector <- collector(entry, config$heap_size, script$deaths)
    run$roots <- integer()
    run$cascades <- run$timeline <- run$observations <- list()
    run$peak_used <- run$failed_line <- run$failed_size <- 0L
    run
}
add_time <- function(run, mutator, units) {
    if (units == 0L) return(invisible(NULL))
    last <- length(run$timeline)
    if (last && run$timeline[[last]]$flag == mutator) run$timeline[[last]]$units <- run$timeline[[last]]$units + units else run$timeline <- c(
        run$timeline,
        list(list(flag = mutator, units = units))
    )
}
allocate <- function(run, object, line) {
    state <- run$collector
    accepted <- switch(
        state$kind,
        MARK_SWEEP = allocate_sweep(state, object, run$roots, line),
        REFCOUNT = allocate_sweep(state, object, run$roots, line),
        MARK_COMPACT = allocate_compact(state, object, run$roots, line),
        COPYING = allocate_copying(state, object, run$roots, line),
        GENERATIONAL = allocate_generational(state, object, run$roots, line)
    )
    if (!accepted) return(FALSE)
    state$placed <- c(state$placed, list(object))
    if (state$kind == "REFCOUNT") retain(state, object$number)
    run$roots <- c(run$roots, object$number)
    run$peak_used <- max(run$peak_used, object_pair(state$objects)[2L])
    TRUE
}
observe <- function(run, checkpoint) {
    state <- run$collector
    reachable <- checkpoint$reachable
    objects <- state$objects
    live <- Filter(function(object) object$number %in% reachable, objects)
    garbage <- Filter(function(object) !(object$number %in% reachable), objects)
    blocks <- free_list(state)
    lines <- c(
        line_text(
            "heap",
            "objects",
            object_pair(objects),
            "reachable",
            object_pair(live),
            "garbage",
            object_pair(garbage)
        ),
        line_text(
            "free",
            "total",
            total_free(blocks),
            "largest",
            largest_free(blocks),
            "blocks",
            length(blocks),
            "sizes",
            class_table(vapply(blocks, function(block) block[2L], 0L)),
            "fragmentation",
            fragmentation(blocks)
        )
    )
    pointers <- forward <- backward <- distance <- 0L
    for (object in live) for (id in object$fields) {
        if (id == 0L) next
        child <- state$placed[[id]]
        pointers <- pointers + 1L
        forward <- forward + as.integer(child$address > object$address)
        backward <- backward + as.integer(child$address < object$address)
        distance <- distance + abs(child$address - object$address)
    }
    mean <- if (pointers == 0L) "-" else dec2(distance, pointers)
    lines <- c(
        lines,
        line_text(
            "locality",
            "pointers",
            pointers,
            "forward",
            forward,
            "backward",
            backward,
            "mean_distance",
            mean
        )
    )
    if (state$kind == "GENERATIONAL") {
        young <- Filter(function(object) is_young(state, object), objects)
        old <- Filter(function(object) !is_young(state, object), objects)
        ages <- vapply(
            seq.int(0L, 3L),
            function(age) sum(vapply(young, function(object) min(object$age, 3L) == age, FALSE)),
            0L
        )
        lines <- c(
            lines,
            line_text(
                "generations",
                "young",
                object_pair(young),
                "old",
                object_pair(old),
                "remembered",
                length(state$remembered),
                "ages",
                paste0(c("0:", "1:", "2:", "3+:"), ages)
            )
        )
    }
    if (checkpoint$label %in% run$config$maps) {
        text <- heap_map(state$size, objects, reachable, inactive_range(state))
        width <- run$config$width
        for (start in seq.int(0L, state$size - 1L, width)) lines <- c(
            lines,
            paste(sprintf("%04d", start), substr(text, start + 1L, start + width))
        )
    }
    lines
}
execute <- function(run, command) {
    state <- run$collector
    refcount <- state$kind == "REFCOUNT"
    value <- source_value(run$roots, command$source)
    if (command$name %in% c("PUSH", "LOAD")) {
        id <- if (command$name == "PUSH") value else state$placed[[run$roots[command$slot + 1L]]]$fields[command$field + 1L]
        if (refcount) retain(state, id)
        run$roots <- c(run$roots, id)
    } else if (command$name == "POP") {
        for (i in seq_len(command$count)) {
            id <- tail(run$roots, 1L)
            run$roots <- head(run$roots, -1L)
            if (refcount) release(state, id)
        }
    } else if (command$name == "SET") {
        target <- state$placed[[run$roots[command$slot + 1L]]]
        if (state$kind == "GENERATIONAL") write_barrier(state, target, value)
        if (refcount) retain(state, value)
        previous <- target$fields[command$field + 1L]
        target$fields[command$field + 1L] <- value
        if (refcount) release(state, previous)
    } else if (command$name == "OVERWRITE") {
        if (refcount) retain(state, value)
        previous <- run$roots[command$slot + 1L]
        run$roots[command$slot + 1L] <- value
        if (refcount) release(state, previous)
    } else if (command$name == "CHECKPOINT") {
        checkpoint <- run$script$checkpoints[[length(run$observations) + 1L]]
        run$observations <- c(run$observations, list(observe(run, checkpoint)))
    }
}
simulate <- function(run) {
    state <- run$collector
    for (command in run$script$commands) {
        previous <- length(state$records)
        units <- 1L
        if (command$name == "ALLOC") {
            object <- heap_object(length(state$placed) + 1L, command$pointers, command$data)
            units <- object$size
            placed <- allocate(run, object, command$line)
        } else {
            execute(run, command)
            placed <- TRUE
        }
        if (previous < length(state$records)) for (record in state$records[seq.int(
            previous + 1L,
            length(state$records)
        )]) add_time(run, FALSE, record$work)
        if (!placed) {
            run$failed_line <- command$line
            run$failed_size <- units
            return(invisible(NULL))
        }
        add_time(run, TRUE, units)
        if (length(state$released)) {
            freed <- object_pair(state$released)
            work <- sum(vapply(state$released, function(object) 1L + length(object$fields), 0L))
            run$cascades <- c(run$cascades, list(list(line = command$line, freed = freed, work = work)))
            state$released <- list()
            add_time(run, FALSE, work)
        }
    }
    if (state$kind == "REFCOUNT") {
        garbage <- Filter(function(object) !(object$number %in% run$script$alive), state$objects)
        state$reports <- c(state$reports, list(leak_report("end", garbage, state$deaths, state$placed)))
    }
}
pauses <- function(run) c(
    lapply(
        run$collector$records,
        function(record) list(
            line = record$line,
            work = record$work,
            freed_words = record$freed[2L],
            collection = TRUE
        )
    ),
    lapply(
        run$cascades,
        function(cascade) list(
            line = cascade$line,
            work = cascade$work,
            freed_words = cascade$freed[2L],
            collection = FALSE
        )
    )
)
pause_stats <- function(pauses) {
    works <- sort(vapply(pauses, function(pause) pause$work, 0L))
    n <- length(works)
    percentile <- function(x) if (n == 0L) "-" else as.character(works[(x * n + 99L) %/% 100L])
    list(
        count = n,
        collections = sum(vapply(pauses, function(pause) pause$collection, FALSE)),
        work = sum(works),
        freed_words = sum(vapply(pauses, function(pause) pause$freed_words, 0L)),
        maximum = max(c(0L, works)),
        p50 = percentile(50L),
        p90 = percentile(90L)
    )
}
timeline_stats <- function(run) {
    starts <- prefix <- integer()
    total <- mutator <- 0L
    for (segment in run$timeline) {
        starts <- c(starts, total)
        prefix <- c(prefix, mutator)
        total <- total + segment$units
        if (segment$flag) mutator <- mutator + segment$units
    }
    until <- function(position) {
        index <- findInterval(position, starts)
        prefix[index] + if (run$timeline[[index]]$flag) position - starts[index] else 0L
    }
    mmu <- function(width) {
        if (width > total) return("-")
        lowest <- width
        for (i in seq_along(run$timeline)) for (begin in c(
            starts[i],
            starts[i] + run$timeline[[i]]$units - width
        )) if (begin >= 0L && begin <= total - width) lowest <- min(lowest, until(begin + width) - until(begin))
        pct(lowest, width)
    }
    list(
        utilization = pct(mutator, total),
        mmu = vapply(run$config$windows, function(width) paste(width, mmu(width), sep = ":"), "")
    )
}
collection_lines <- function(run) {
    state <- run$collector
    lines <- line_text("collector", run$entry$name, run$entry$kind)
    add <- function(...) lines <<- c(lines, line_text(...))
    for (record in state$records) add(
        record$number,
        "line",
        record$line,
        "size",
        record$request,
        "kind",
        record$kind,
        "live",
        record$live,
        "freed",
        record$freed,
        "moved",
        record$moved,
        "promoted",
        record$promoted,
        "stack",
        record$stack,
        "work",
        record$work,
        "before",
        record$before,
        "after",
        record$after
    )
    all_pauses <- pauses(run)
    stats <- pause_stats(all_pauses)
    add(
        "totals",
        "collections",
        stats$collections,
        "pauses",
        stats$count,
        "work",
        stats$work,
        "freed",
        stats$freed_words,
        "pause",
        "p50",
        stats$p50,
        "p90",
        stats$p90,
        "max",
        stats$maximum
    )
    timeline <- timeline_stats(run)
    add("utilization", timeline$utilization, "mmu", timeline$mmu)
    if (state$kind == "GENERATIONAL") {
        parts <- "generational"
        for (kind in c("minor", "major", "tenure", "full")) {
            records <- Filter(function(record) record$kind == kind, state$records)
            parts <- c(parts, kind, length(records), sum(vapply(records, function(record) record$work, 0L)))
        }
        promoted <- c(
            sum(vapply(state$records, function(record) record$promoted[1L], 0L)),
            sum(vapply(state$records, function(record) record$promoted[2L], 0L))
        )
        add(parts, "promoted", promoted, "barrier", state$barriers, "remembered", state$remembers)
    } else if (state$kind == "REFCOUNT") {
        freed <- c(
            sum(vapply(run$cascades, function(cascade) cascade$freed[1L], 0L)),
            sum(vapply(run$cascades, function(cascade) cascade$freed[2L], 0L))
        )
        if (!length(run$cascades)) maximum <- "max_cascade 0 0 line -" else {
            largest <- run$cascades[[which.max(vapply(run$cascades, function(cascade) cascade$work, 0L))]]
            maximum <- line_text("max_cascade", largest$freed[1L], largest$work, "line", largest$line)
        }
        add(
            "refcount",
            "increments",
            state$increments,
            "decrements",
            state$decrements,
            "cascades",
            length(run$cascades),
            "freed",
            freed,
            maximum
        )
    }
    previous <- 0L
    for (checkpoint in run$script$checkpoints) {
        if (run$failed_line != 0L && run$failed_line < checkpoint$line) add(
            "phase",
            checkpoint$label,
            "out_of_memory"
        ) else {
            stats <- pause_stats(Filter(
                function(pause) pause$line > previous && pause$line <= checkpoint$line,
                all_pauses
            ))
            add(
                "phase",
                checkpoint$label,
                "collections",
                stats$collections,
                "pauses",
                stats$count,
                "work",
                stats$work,
                "freed",
                stats$freed_words,
                "max_pause",
                stats$maximum
            )
        }
        previous <- checkpoint$line
    }
    if (run$failed_line == 0L) add("status", "completed") else add(
        "status",
        "out_of_memory",
        "line",
        run$failed_line,
        "size",
        run$failed_size
    )
    lines
}
summary_row <- function(run) {
    state <- run$collector
    stats <- pause_stats(pauses(run))
    moves <- vapply(
        Filter(function(object) object$moves > 0L, state$placed),
        function(object) object$moves,
        0L
    )
    if (run$failed_line == 0L) {
        blocks <- free_list(state)
        status <- "completed"
        ending <- c(
            object_pair(state$objects)[2L],
            total_free(blocks),
            largest_free(blocks),
            fragmentation(blocks)
        )
    } else {
        status <- "out_of_memory"
        ending <- rep("-", 4L)
    }
    fields <- c(
        run$entry$name,
        run$entry$kind,
        status,
        length(state$records),
        stats$count,
        sum(vapply(state$records, function(record) record$live[1L], 0L)),
        sum(vapply(state$records, function(record) record$moved[1L], 0L)),
        length(moves),
        max(c(0L, moves)),
        stats$freed_words,
        stats$work,
        stats$p50,
        stats$p90,
        stats$maximum,
        run$peak_used,
        ending
    )
    paste(fields, collapse = ",")
}
join_blocks <- function(blocks) {
    lines <- character()
    for (block in blocks) {
        if (length(lines)) lines <- c(lines, "")
        lines <- c(lines, block)
    }
    lines
}
main <- function() {
    options(scipen = 999)
    config <- read_config("input/config.txt")
    script <- analyze_script(read_script("input/mutator.txt"))
    runs <- lapply(config$collectors, function(entry) new_run(entry, config, script))
    for (run in runs) simulate(run)
    maps <- list()
    for (i in seq_along(script$checkpoints)) {
        checkpoint <- script$checkpoints[[i]]
        for (run in runs) {
            block <- line_text(
                "checkpoint",
                checkpoint$label,
                "line",
                checkpoint$line,
                "collector",
                run$entry$name
            )
            block <- c(block, if (i <= length(run$observations)) run$observations[[i]] else "out_of_memory")
            maps <- c(maps, list(block))
        }
    }
    leaks <- list()
    for (run in runs) {
        if (run$entry$kind != "REFCOUNT") next
        lines <- line_text("collector", run$entry$name)
        for (report in run$collector$reports) lines <- c(lines, report)
        if (run$failed_line != 0L) lines <- c(lines, "status out_of_memory")
        leaks <- c(leaks, list(lines))
    }
    outputs <- list(
        "mutator.txt" = script_lines(script),
        "heap_maps.txt" = join_blocks(maps),
        "collections.txt" = join_blocks(lapply(runs, collection_lines)),
        "summary.csv" = c(SUMMARY_HEADER, vapply(runs, summary_row, "")),
        "leaks.txt" = if (length(leaks)) join_blocks(leaks) else "none"
    )
    dir.create("output", showWarnings = FALSE)
    for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
