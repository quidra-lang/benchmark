message_key <- function(message) c(message$arrival, message$receiver, message$sender, message$serial)
message_less <- function(first, second) {
    left <- message_key(first)
    right <- message_key(second)
    different <- which(left != right)
    length(different) > 0L && left[different[1L]] < right[different[1L]]
}
new_message_queue <- function() {
    queue <- new.env(parent = emptyenv())
    queue$heap <- list()
    queue$serial <- 0L
    queue
}
heap_push <- function(queue, message) {
    index <- length(queue$heap) + 1L
    queue$heap[[index]] <- message
    while (index > 1L) {
        parent <- index %/% 2L
        if (!message_less(queue$heap[[index]], queue$heap[[parent]])) break
        saved <- queue$heap[[parent]]
        queue$heap[[parent]] <- queue$heap[[index]]
        queue$heap[[index]] <- saved
        index <- parent
    }
}
send_message <- function(queue, time, sender, receiver, link, prefix, content) {
    queue$serial <- queue$serial + 1L
    message <- list(
        serial = queue$serial,
        sender = sender,
        receiver = receiver,
        link = link$number,
        prefix = prefix,
        content = content,
        arrival = time + link$delay
    )
    heap_push(queue, message)
    message
}
next_message_time <- function(queue) if (length(queue$heap)) queue$heap[[1L]]$arrival else NULL
ordered_messages <- function(queue) {
    if (!length(queue$heap)) return(list())
    messages <- queue$heap
    messages[order(
        vapply(messages, function(message) message$arrival, 0L),
        vapply(messages, function(message) message$receiver, 0L),
        vapply(messages, function(message) message$sender, 0L),
        vapply(messages, function(message) message$serial, 0L)
    )]
}
take_message <- function(queue) {
    result <- queue$heap[[1L]]
    last <- tail(queue$heap, 1L)[[1L]]
    queue$heap <- head(queue$heap, -1L)
    if (length(queue$heap)) {
        queue$heap[[1L]] <- last
        index <- 1L
        while (2L * index <= length(queue$heap)) {
            child <- 2L * index
            if (child < length(queue$heap) && message_less(
                queue$heap[[child + 1L]],
                queue$heap[[child]]
            )) child <- child + 1L
            if (!message_less(queue$heap[[child]], queue$heap[[index]])) break
            saved <- queue$heap[[index]]
            queue$heap[[index]] <- queue$heap[[child]]
            queue$heap[[child]] <- saved
            index <- child
        }
    }
    result
}
remove_link_messages <- function(queue, link) {
    removed <- Filter(function(message) message$link == link, ordered_messages(queue))
    kept <- Filter(function(message) message$link != link, queue$heap)
    queue$heap <- list()
    for (message in kept) heap_push(queue, message)
    removed
}
read_events <- function() {
    events <- list(list(time = 0L, text = "INITIAL", fields = "INITIAL", kind = "INITIAL"))
    for (line in readLines("input/events.txt", warn = FALSE)) {
        space <- regexpr(" ", line, fixed = TRUE)[1L]
        text <- substr(line, space + 1L, nchar(line))
        fields <- strsplit(text, " ", fixed = TRUE)[[1L]]
        kind <- if (fields[1L] %in% c("LINK", "POLICY")) paste(fields[1:2], collapse = "_") else fields[1L]
        events[[length(events) + 1L]] <- list(
            time = as.integer(substr(line, 1L, space - 1L)),
            text = text,
            fields = fields,
            kind = kind
        )
    }
    events
}
read_params <- function() {
    lines <- readLines("input/params.txt", warn = FALSE)
    defaults <- setNames(
        as.integer(strsplit(lines[1L], " ", fixed = TRUE)[[1L]][-1L]),
        c("customer", "peer", "provider")
    )
    stepcap <- as.integer(strsplit(lines[2L], " ", fixed = TRUE)[[1L]][2L])
    traces <- lapply(lines[-c(1L, 2L)], function(line) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        list(source = as.integer(fields[2L]), address = fields[3L], value = address_value(fields[3L]))
    })
    list(defaults = defaults, stepcap = stepcap, traces = traces)
}
