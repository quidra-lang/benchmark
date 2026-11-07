load_instance <- function(path) {
    lines <- readLines(path)
    header <- as.integer(strsplit(lines[1L], " ", fixed = TRUE)[[1L]])
    job_count <- header[1L]
    machine_count <- header[2L]
    jobs <- operations <- list()
    errors <- character()
    for (number in seq_len(job_count)) {
        tokens <- strsplit(lines[number + 1L], " ", fixed = TRUE)[[1L]]
        steps <- list()
        valid <- TRUE
        for (index in seq_along(tokens)) {
            pair <- as.integer(strsplit(tokens[index], ":", fixed = TRUE)[[1L]])
            machine <- pair[1L]
            duration <- pair[2L]
            reason <- if (machine < 1L || machine > machine_count) paste(
                "unknown machine",
                machine
            ) else if (duration < 1L || duration > 99L) paste("bad duration", duration) else if (any(vapply(
                steps,
                function(step) step[1L] == machine,
                FALSE
            ))) paste("repeated machine", machine) else NULL
            if (!is.null(reason)) {
                errors <- c(errors, paste0("job ", number, " operation ", index, ": ", reason))
                valid <- FALSE
                break
            }
            steps <- c(steps, list(pair))
        }
        if (!valid) next
        work <- sum(vapply(steps, function(step) step[2L], 0L))
        head <- 0L
        ids <- integer()
        for (index in seq_along(steps)) {
            machine <- steps[[index]][1L]
            duration <- steps[[index]][2L]
            id <- length(operations) + 1L
            ids <- c(ids, id)
            operations[[id]] <- list(id = id, job = number, index = index, machine = machine, duration = duration, head = head, tail = work - head - duration,
                job_prev = if (index == 1L) 0L else id - 1L, job_next = if (index == length(steps)) 0L else id + 1L, code = paste0(
                    "J",
                    number,
                    "-",
                    index
                ))
            head <- head + duration
        }
        jobs <- c(jobs, list(list(number = number, operations = ids, work = work)))
    }
    machines <- lapply(seq_len(machine_count), function(m) {
        ids <- which(vapply(operations, function(op) op$machine == m, FALSE))
        load <- sum(vapply(operations[ids], function(op) op$duration, 0L))
        head <- min(vapply(operations[ids], function(op) op$head, 0L))
        tail <- min(vapply(operations[ids], function(op) op$tail, 0L))
        list(number = m, operations = ids, load = load, head = head, tail = tail, bound = head + load + tail)
    })
    list(machine_count = machine_count, jobs = jobs, operations = operations, errors = errors, durations = vapply(operations, function(op) op$duration, 0L),
         job_map = setNames(
             jobs,
             vapply(jobs, function(job) as.character(job$number), "")
         ), machines = machines)
}
