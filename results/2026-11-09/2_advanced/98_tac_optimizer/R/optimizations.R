rewrite_code <- function(function_node, replacements, insertions = vector("list", length(function_node$code) + 1L)) {
    result <- list()
    number <- 0L
    for (index in seq_along(function_node$code)) {
        result <- c(result, insertions[[index]])
        line <- function_node$code[[index]]
        if (is.character(line)) result[[length(result) + 1L]] <- line else {
            number <- number + 1L
            replacement <- replacements[[number]]
            result <- c(result, if (is.null(replacement)) list(line) else replacement)
        }
    }
    function_node$code <- c(result, insertions[[length(function_node$code) + 1L]])
}
fold_instruction <- function(entry) {
    unchanged <- list(entry = entry, changed = FALSE)
    if (!entry$kind %in% c("bin", "if")) return(unchanged)
    a <- entry$a
    b <- entry$b
    first_constant <- is_constant(a)
    second_constant <- is_constant(b)
    if (first_constant && second_constant) {
        if (entry$operation %in% c("/", "%") && b == 0L) return(unchanged)
        result <- calculate(entry$operation, a, b)
        if (entry$kind == "if") return(list(entry = if (result != 0L) instruction("goto", name = entry$name) else NULL, changed = TRUE))
        if (result >= gmp::as.bigz("-2147483648") && result <= gmp::as.bigz("2147483647")) {
            return(list(entry = instruction("copy", destination = entry$destination, a = result), changed = TRUE))
        }
        return(unchanged)
    }
    if (entry$kind != "bin" || first_constant == second_constant) return(unchanged)
    op <- entry$operation
    replacement <- NULL
    if (op == "+" && (a == 0L || b == 0L)) {
        replacement <- if (first_constant) b else a
    } else if (op == "-" && b == 0L) {
        replacement <- a
    } else if (op == "*" && (a == 1L || b == 1L)) {
        replacement <- if (first_constant) b else a
    } else if (op == "/" && b == 1L) {
        replacement <- a
    } else if (op == "*" && (a == 0L || b == 0L)) replacement <- gmp::as.bigz(0L)
    if (is.null(replacement)) unchanged else list(entry = instruction("copy", destination = entry$destination, a = replacement), changed = TRUE)
}
cse_replacements <- function(function_node, graph, sources, candidates) {
    function_node$temporary_serial <- function_node$temporary_serial + 1L
    temporary <- paste0("_t", function_node$temporary_serial)
    replacements <- vector("list", length(graph$instructions))
    for (number in sources) {
        entry <- graph$instructions[[number]]
        replacements[[number]] <- list(replace_instruction(entry, destination = temporary), instruction("copy", destination = entry$destination, a = temporary))
    }
    for (number in candidates) replacements[[number]] <- list(instruction("copy", destination = graph$instructions[[number]]$destination, a = temporary))
    list(temporary = temporary, replacements = replacements)
}
hoist <- function(function_node, graph, loop, moves) {
    header <- graph$blocks[[loop$header]]
    outside <- setdiff(header$predecessors, loop$blocks)
    replacements <- vector("list", length(graph$instructions))
    for (number in moves) replacements[[number]] <- list()
    moved <- lapply(moves, function(number) graph$instructions[[number]])
    if (loop$header != 1L && length(outside) == 1L && identical(graph$blocks[[outside[1L]]]$successors, loop$header)) {
        preheader <- graph$blocks[[outside[1L]]]
        last <- tail(preheader$instructions, 1L)
        position <- graph$positions[last]
        if (!graph$instructions[[last]]$kind %in% c("goto", "if")) position <- position + 1L
        insertion <- moved
        destination <- paste0("B", preheader$number)
    } else {
        function_node$preheader_serial <- function_node$preheader_serial + 1L
        label <- paste0("_p", function_node$preheader_serial)
        position <- header$start
        insertion <- c(list(label), moved)
        destination <- paste("new", label)
        for (number in outside) {
            last <- tail(graph$blocks[[number]]$instructions, 1L)
            entry <- graph$instructions[[last]]
            if (entry$kind %in% c("goto", "if") && entry$name %in% header$labels) replacements[[last]] <- list(replace_instruction(entry, name = label))
        }
    }
    insertions <- vector("list", length(function_node$code) + 1L)
    insertions[[position]] <- insertion
    rewrite_code(function_node, replacements, insertions)
    destination
}
remove_unreachable <- function(function_node, graph) {
    blocks <- setdiff(seq_along(graph$blocks), graph$reachable)
    deleted <- rep(FALSE, length(function_node$code))
    for (number in blocks) {
        block <- graph$blocks[[number]]
        deleted[seq.int(block$start, block$finish - 1L)] <- TRUE
    }
    numbers <- integer(length(function_node$code))
    numbers[graph$positions] <- seq_along(graph$instructions)
    remaining <- lapply(which(!deleted), function(index) list(line = function_node$code[[index]], number = numbers[index]))
    jumps <- integer()
    for (index in seq_along(remaining)) {
        line <- remaining[[index]]$line
        if (is.character(line) || !line$kind %in% c("goto", "if")) next
        labels <- character()
        following <- index + 1L
        while (following <= length(remaining) && is.character(remaining[[following]]$line)) {
            labels <- c(labels, remaining[[following]]$line)
            following <- following + 1L
        }
        if (line$name %in% labels) jumps <- c(jumps, remaining[[index]]$number)
    }
    remaining <- Filter(function(pair) !pair$number %in% jumps, remaining)
    targets <- character()
    for (pair in remaining) if (!is.character(pair$line) && pair$line$kind %in% c("goto", "if")) targets <- union(targets, pair$line$name)
    labels <- vapply(Filter(function(pair) is.character(pair$line) && !pair$line %in% targets, remaining), function(pair) pair$line, character(1L))
    kept <- Filter(function(pair) !is.character(pair$line) || pair$line %in% targets, remaining)
    function_node$code <- lapply(kept, function(pair) pair$line)
    list(blocks = blocks, jumps = jumps, labels = labels)
}
