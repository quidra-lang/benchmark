wrong_type <- "WRONGTYPE Operation against a key holding the wrong kind of value"
not_integer <- "ERR value is not an integer or out of range"
positive <- "ERR value is out of range, must be positive"
upper <- function(text) chartr("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", text)
lower <- function(text) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", text)
fail <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
}
quoted <- function(value) if (is.null(value)) "(nil)" else encodeString(value, quote = '"', justify = "none")
integer_reply <- function(value) paste0("(integer) ", as.character(value))
array_reply <- function(values) {
    if (!length(values)) return("(empty array)")
    labels <- as.character(seq_along(values))
    items <- vapply(seq_along(values), function(i) quoted(values[[i]]), character(1L))
    paste0(strrep(" ", nchar(as.character(length(values))) - nchar(labels)), labels, ") ", items)
}
split_line <- function(line) {
    chars <- strsplit(line, "", fixed = TRUE)[[1L]]
    n <- length(chars)
    i <- 1L
    words <- character()
    while (i <= n) {
        if (chars[i] == " ") { i <- i + 1L; next }
        if (chars[i] != '"') {
            start <- i
            while (i <= n && chars[i] != " ") i <- i + 1L
            words <- c(words, paste(chars[seq.int(start, i - 1L)], collapse = ""))
            next
        }
        i <- i + 1L
        text <- character()
        closed <- FALSE
        while (i <= n) {
            value <- chars[i]
            i <- i + 1L
            if (value == '"') { closed <- TRUE; break }
            if (value == "\\") {
                if (i > n) return(NULL)
                value <- chars[i]
                i <- i + 1L
                if (!value %in% c("\\", '"')) return(NULL)
            }
            text <- c(text, value)
        }
        if (!closed || (i <= n && chars[i] != " ")) return(NULL)
        words <- c(words, paste(text, collapse = ""))
    }
    words
}
valid_integer <- function(text) grepl("^(0|-?[1-9][0-9]{0,8})$", text)
number <- function(text) {
    if (!valid_integer(text)) fail(not_integer)
    as.integer(text)
}
incremented <- function(previous, delta) {
    value <- previous + delta
    if (abs(value) > 999999999L) fail("ERR increment or decrement would overflow")
    value
}
selected_indices <- function(n, first, last) {
    start <- max(0L, if (first < 0L) first + n else first)
    stop <- min(n - 1L, if (last < 0L) last + n else last)
    if (start <= stop) seq.int(start + 1L, stop + 1L) else integer()
}
score_bound <- function(text) {
    if (text == "-inf") return(list(infinity = -1L, value = 0L, exclusive = FALSE))
    if (text == "+inf") return(list(infinity = 1L, value = 0L, exclusive = FALSE))
    exclusive <- startsWith(text, "(")
    if (exclusive) text <- substring(text, 2L)
    if (!valid_integer(text)) fail("ERR min or max is not a float")
    list(infinity = 0L, value = as.integer(text), exclusive = exclusive)
}
within_bound <- function(scores, bound, lower) {
    if (bound$infinity) return(rep(lower == (bound$infinity < 0L), length(scores)))
    (if (lower) scores > bound$value else scores < bound$value) | (!bound$exclusive & scores == bound$value)
}
parse_pattern <- function(text) {
    chars <- strsplit(text, "", fixed = TRUE)[[1L]]
    parts <- list()
    i <- 1L
    while (i <= length(chars)) {
        value <- chars[i]
        i <- i + 1L
        if (value == "\\") {
            if (i > length(chars)) fail("ERR invalid pattern")
            part <- list(kind = "literal", value = chars[i])
            i <- i + 1L
        } else if (value == "[") {
            end <- i
            while (end <= length(chars) && chars[end] != "]") end <- end + 1L
            if (end > length(chars)) fail("ERR invalid pattern")
            negated <- i < end && chars[i] == "^"
            if (negated) i <- i + 1L
            if (i == end) fail("ERR invalid pattern")
            members <- rep(FALSE, 128L)
            while (i < end) {
                first <- utf8ToInt(chars[i])
                if (i + 2L < end && chars[i + 1L] == "-") {
                    last <- utf8ToInt(chars[i + 2L])
                    members[seq.int(min(first, last), max(first, last)) + 1L] <- TRUE
                    i <- i + 3L
                } else {
                    members[first + 1L] <- TRUE
                    i <- i + 1L
                }
            }
            part <- list(kind = "class", members = members, negated = negated)
            i <- end + 1L
        } else part <- list(kind = if (value %in% c("*", "?")) value else "literal", value = value)
        parts <- c(parts, list(part))
    }
    parts
}
matches <- function(parts, text) {
    chars <- strsplit(text, "", fixed = TRUE)[[1L]]
    previous <- c(TRUE, rep(FALSE, length(chars)))
    for (part in parts) {
        following <- rep(FALSE, length(previous))
        if (part$kind == "*") {
            following[1L] <- previous[1L]
            for (i in seq_along(chars)) following[i + 1L] <- previous[i + 1L] || following[i]
        } else {
            accepted <- switch(part$kind, "?" = rep(TRUE, length(chars)), literal = chars == part$value,
                               class = part$members[utf8ToInt(text) + 1L] != part$negated)
            following <- c(FALSE, head(previous, -1L) & accepted)
        }
        previous <- following
    }
    tail(previous, 1L)
}

# Database entries and payloads contain only value lists and vectors.
db_get <- function(db, key) {
    at <- match(key, names(db), nomatch = 0L)
    if (at) db[[at]] else NULL
}
db_put <- function(db, key, value) {
    force(value)
    at <- match(key, names(db), nomatch = 0L)
    if (at) db[at] <- list(value) else db <- c(db, setNames(list(value), key))
    db
}
erase <- function(state, key) {
    at <- match(key, names(state$db), nomatch = 0L)
    if (!at) return(FALSE)
    state$db <- state$db[-at]
    TRUE
}
associations <- function(numeric = FALSE) list(keys = character(), values = if (numeric) integer() else character())
read_value <- function(state, key, kind) {
    entry <- db_get(state$db, key)
    if (!is.null(entry)) {
        if (entry$kind != kind) fail(wrong_type)
        return(entry$value)
    }
    switch(kind, string = "", list = character(), hash = associations(), set = character(), zset = associations(TRUE))
}
replace_value <- function(state, key, kind, value, expiry = NULL) {
    force(value)
    force(expiry)
    empty <- kind != "string" && if (kind %in% c("hash", "zset")) !length(value$keys) else !length(value)
    if (empty) erase(state, key) else state$db <- db_put(state$db, key, list(kind = kind, value = value, expiry = expiry))
    invisible(NULL)
}
update_value <- function(state, key, kind, value) {
    force(value)
    expiry <- db_get(state$db, key)$expiry
    replace_value(state, key, kind, value, expiry)
}
assoc_put <- function(value, key, item) {
    at <- match(key, value$keys, nomatch = 0L)
    if (!at) {
        value$keys <- c(value$keys, key)
        value$values <- c(value$values, item)
    } else value$values[at] <- item
    value
}
assoc_remove <- function(value, keys) {
    keep <- !value$keys %in% keys
    list(keys = value$keys[keep], values = value$values[keep])
}
purge <- function(state) {
    expired <- vapply(state$db, function(entry) !is.null(entry$expiry) && entry$expiry <= state$clock, logical(1L))
    state$db <- state$db[!expired]
    sum(expired)
}

arity_groups <- list(
    strsplit("TIME DBSIZE FLUSH INFO BEGIN COMMIT ROLLBACK", " ")[[1L]],
    strsplit("GET INCR DECR STRLEN LLEN HGETALL HLEN HKEYS HVALS SMEMBERS SCARD ZCARD TYPE KEYS TTL PERSIST TICK SNAPSHOT RESTORE", " ")[[1L]],
    strsplit("INCRBY DECRBY APPEND LINDEX HGET HEXISTS SISMEMBER ZSCORE ZRANK RENAME RENAMENX", " ")[[1L]],
    strsplit("GETRANGE LRANGE LSET LREM LTRIM HINCRBY ZINCRBY", " ")[[1L]],
    "LINSERT", c("LPOP", "RPOP"), "EXPIRE", c("ZRANGE", "ZRANGEBYSCORE"),
    c("MGET", "SINTER", "SUNION", "SDIFF", "DEL", "EXISTS"),
    strsplit("SET LPUSH RPUSH HDEL SADD SREM ZREM SINTERSTORE SUNIONSTORE SDIFFSTORE", " ")[[1L]],
    "MSET", c("HSET", "ZADD")
)
arity_limits <- list(c(0L, 0L), c(1L, 1L), c(2L, 2L), c(3L, 3L), c(4L, 4L), c(1L, 2L),
                     c(2L, 3L), c(3L, 4L), c(1L, -1L), c(2L, -1L), c(2L, -1L, 0L), c(3L, -1L, 1L))
check_arity <- function(original, count) {
    command <- upper(original)
    group <- which(vapply(arity_groups, function(names) command %in% names, logical(1L)))
    if (!length(group)) fail(paste0("ERR unknown command '", original, "'"))
    limit <- arity_limits[[group]]
    if (count < limit[1L] || (limit[2L] >= 0L && count > limit[2L]) ||
        (length(limit) == 3L && count %% 2L != limit[3L]))
        fail(paste0("ERR wrong number of arguments for '", lower(command), "' command"))
    command
}
set_string <- function(state, a) {
    key <- a[1L]
    options <- character()
    seconds_text <- NULL
    i <- 3L
    while (i <= length(a)) {
        option <- upper(a[i])
        i <- i + 1L
        if (!option %in% c("NX", "XX", "EX", "KEEPTTL", "GET") || option %in% options) fail("ERR syntax error")
        options <- c(options, option)
        if (option == "EX") {
            if (i > length(a)) fail("ERR syntax error")
            seconds_text <- a[i]
            i <- i + 1L
        }
    }
    if (all(c("NX", "XX") %in% options) || all(c("EX", "KEEPTTL") %in% options)) fail("ERR syntax error")
    expiry <- NULL
    if ("EX" %in% options) {
        seconds <- number(seconds_text)
        if (seconds <= 0L) fail("ERR invalid expire time in 'set' command")
        expiry <- state$clock + seconds
    }
    old <- db_get(state$db, key)
    old_text <- NULL
    if ("GET" %in% options) {
        text <- read_value(state, key, "string")
        if (!is.null(old)) old_text <- text
    }
    blocked <- ("NX" %in% options && !is.null(old)) || ("XX" %in% options && is.null(old))
    if (!blocked) {
        if ("KEEPTTL" %in% options && !is.null(old)) expiry <- old$expiry
        replace_value(state, key, "string", a[2L], expiry)
    }
    if ("GET" %in% options) quoted(old_text) else if (blocked) "(nil)" else "OK"
}
string_command <- function(state, command, a) {
    key <- a[1L]
    if (command == "SET") return(set_string(state, a))
    if (command == "MSET") {
        for (i in seq.int(1L, length(a), by = 2L)) replace_value(state, a[i], "string", a[i + 1L])
        return("OK")
    }
    if (command == "MGET") return(array_reply(lapply(a, function(name) {
        entry <- db_get(state$db, name)
        if (!is.null(entry) && entry$kind == "string") entry$value else NULL
    })))
    if (command %in% c("INCR", "DECR", "INCRBY", "DECRBY")) {
        delta <- if (length(a) == 2L) number(a[2L]) else 1L
        if (startsWith(command, "DECR")) delta <- -delta
        text <- read_value(state, key, "string")
        previous <- if (is.null(db_get(state$db, key))) 0L else number(text)
        value <- incremented(previous, delta)
        update_value(state, key, "string", as.character(value))
        return(integer_reply(value))
    }
    if (command == "APPEND") {
        value <- paste0(read_value(state, key, "string"), a[2L])
        update_value(state, key, "string", value)
        return(integer_reply(nchar(value)))
    }
    if (command == "GETRANGE") {
        first <- number(a[2L])
        last <- number(a[3L])
        chars <- strsplit(read_value(state, key, "string"), "", fixed = TRUE)[[1L]]
        return(quoted(paste(chars[selected_indices(length(chars), first, last)], collapse = "")))
    }
    value <- read_value(state, key, "string")
    if (command == "STRLEN") integer_reply(nchar(value)) else quoted(if (is.null(db_get(state$db, key))) NULL else value)
}
list_command <- function(state, command, a) {
    key <- a[1L]
    if (command %in% c("LPUSH", "RPUSH")) {
        value <- read_value(state, key, "list")
        value <- if (command == "LPUSH") c(rev(a[-1L]), value) else c(value, a[-1L])
        update_value(state, key, "list", value)
        return(integer_reply(length(value)))
    }
    if (command %in% c("LPOP", "RPOP")) {
        count <- 1L
        explicit <- length(a) == 2L
        if (explicit) {
            if (!valid_integer(a[2L])) fail(positive)
            count <- as.integer(a[2L])
            if (count < 0L) fail(positive)
        }
        value <- read_value(state, key, "list")
        if (is.null(db_get(state$db, key))) return("(nil)")
        count <- min(count, length(value))
        if (command == "LPOP") {
            removed <- head(value, count)
            kept <- tail(value, length(value) - count)
        } else {
            removed <- rev(tail(value, count))
            kept <- head(value, length(value) - count)
        }
        update_value(state, key, "list", kept)
        return(if (explicit) array_reply(removed) else quoted(removed[1L]))
    }
    if (command %in% c("LRANGE", "LTRIM")) {
        first <- number(a[2L])
        last <- number(a[3L])
        value <- read_value(state, key, "list")
        kept <- value[selected_indices(length(value), first, last)]
        if (command == "LRANGE") return(array_reply(kept))
        update_value(state, key, "list", kept)
        return("OK")
    }
    if (command == "LLEN") return(integer_reply(length(read_value(state, key, "list"))))
    if (command %in% c("LINDEX", "LSET")) {
        index <- number(a[2L])
        value <- read_value(state, key, "list")
        if (command == "LSET" && is.null(db_get(state$db, key))) fail("ERR no such key")
        if (index < 0L) index <- index + length(value)
        if (index < 0L || index >= length(value)) {
            if (command == "LINDEX") return("(nil)")
            fail("ERR index out of range")
        }
        if (command == "LINDEX") return(quoted(value[index + 1L]))
        value[index + 1L] <- a[3L]
        update_value(state, key, "list", value)
        return("OK")
    }
    if (command == "LREM") {
        count <- number(a[2L])
        value <- read_value(state, key, "list")
        remove <- which(value == a[3L])
        if (count > 0L) remove <- head(remove, min(count, length(remove)))
        if (count < 0L) remove <- tail(remove, min(-count, length(remove)))
        update_value(state, key, "list", value[!seq_along(value) %in% remove])
        return(integer_reply(length(remove)))
    }
    where <- upper(a[2L])
    if (!where %in% c("BEFORE", "AFTER")) fail("ERR syntax error")
    value <- read_value(state, key, "list")
    if (!length(value)) return(integer_reply(0L))
    at <- match(a[3L], value, nomatch = 0L)
    if (!at) return(integer_reply(-1L))
    before <- at - as.integer(where == "BEFORE")
    value <- c(head(value, before), a[4L], tail(value, length(value) - before))
    update_value(state, key, "list", value)
    integer_reply(length(value))
}
hash_command <- function(state, command, a) {
    key <- a[1L]
    if (command == "HINCRBY") delta <- number(a[3L])
    value <- read_value(state, key, "hash")
    if (command == "HINCRBY") {
        at <- match(a[2L], value$keys, nomatch = 0L)
        previous <- 0L
        if (at) {
            if (!valid_integer(value$values[at])) fail("ERR hash value is not an integer")
            previous <- as.integer(value$values[at])
        }
        result <- incremented(previous, delta)
        update_value(state, key, "hash", assoc_put(value, a[2L], as.character(result)))
        return(integer_reply(result))
    }
    if (command == "HSET") {
        old <- length(value$keys)
        for (i in seq.int(2L, length(a), by = 2L)) value <- assoc_put(value, a[i], a[i + 1L])
        update_value(state, key, "hash", value)
        return(integer_reply(length(value$keys) - old))
    }
    if (command == "HDEL") {
        kept <- assoc_remove(value, a[-1L])
        update_value(state, key, "hash", kept)
        return(integer_reply(length(value$keys) - length(kept$keys)))
    }
    if (command == "HGET") {
        at <- match(a[2L], value$keys, nomatch = 0L)
        return(quoted(if (at) value$values[at] else NULL))
    }
    if (command == "HEXISTS") return(integer_reply(as.integer(a[2L] %in% value$keys)))
    if (command == "HLEN") return(integer_reply(length(value$keys)))
    order <- order(value$keys, method = "radix")
    if (command == "HKEYS") return(array_reply(value$keys[order]))
    if (command == "HVALS") return(array_reply(value$values[order]))
    array_reply(as.vector(rbind(value$keys[order], value$values[order])))
}
set_command <- function(state, command, a) {
    key <- a[1L]
    if (startsWith(command, "SINTER") || startsWith(command, "SUNION") || startsWith(command, "SDIFF")) {
        saving <- endsWith(command, "STORE")
        sources <- lapply(if (saving) a[-1L] else a, function(name) read_value(state, name, "set"))
        operation <- if (startsWith(command, "SINTER")) intersect else if (startsWith(command, "SUNION")) union else setdiff
        result <- Reduce(operation, sources)
        if (!saving) return(array_reply(sort(result, method = "radix")))
        replace_value(state, key, "set", result)
        return(integer_reply(length(result)))
    }
    value <- read_value(state, key, "set")
    if (command %in% c("SADD", "SREM")) {
        result <- if (command == "SADD") union(value, a[-1L]) else setdiff(value, a[-1L])
        changed <- abs(length(result) - length(value))
        update_value(state, key, "set", result)
        return(integer_reply(changed))
    }
    if (command == "SCARD") return(integer_reply(length(value)))
    if (command == "SISMEMBER") return(integer_reply(as.integer(a[2L] %in% value)))
    array_reply(sort(value, method = "radix"))
}
zset_command <- function(state, command, a) {
    key <- a[1L]
    if (command == "ZADD") {
        indices <- seq.int(2L, length(a), by = 2L)
        scores <- vapply(a[indices], number, integer(1L), USE.NAMES = FALSE)
        value <- read_value(state, key, "zset")
        old <- length(value$keys)
        for (i in seq_along(scores)) value <- assoc_put(value, a[indices[i] + 1L], scores[i])
        update_value(state, key, "zset", value)
        return(integer_reply(length(value$keys) - old))
    }
    if (command == "ZINCRBY") {
        delta <- number(a[2L])
        value <- read_value(state, key, "zset")
        at <- match(a[3L], value$keys, nomatch = 0L)
        result <- incremented(if (at) value$values[at] else 0L, delta)
        update_value(state, key, "zset", assoc_put(value, a[3L], result))
        return(quoted(as.character(result)))
    }
    with_scores <- FALSE
    if (command %in% c("ZRANGE", "ZRANGEBYSCORE")) {
        with_scores <- length(a) == 4L
        if (with_scores && upper(a[4L]) != "WITHSCORES") fail("ERR syntax error")
        if (command == "ZRANGE") {
            first <- number(a[2L])
            last <- number(a[3L])
        } else {
            minimum <- score_bound(a[2L])
            maximum <- score_bound(a[3L])
        }
    }
    value <- read_value(state, key, "zset")
    if (command == "ZREM") {
        kept <- assoc_remove(value, a[-1L])
        update_value(state, key, "zset", kept)
        return(integer_reply(length(value$keys) - length(kept$keys)))
    }
    if (command == "ZCARD") return(integer_reply(length(value$keys)))
    if (command == "ZSCORE") {
        at <- match(a[2L], value$keys, nomatch = 0L)
        return(quoted(if (at) as.character(value$values[at]) else NULL))
    }
    positions <- order(value$values, value$keys, method = "radix")
    if (command == "ZRANK") {
        at <- match(a[2L], value$keys[positions], nomatch = 0L)
        return(if (at) integer_reply(at - 1L) else "(nil)")
    }
    if (command == "ZRANGE") positions <- positions[selected_indices(length(positions), first, last)] else
        positions <- positions[within_bound(value$values[positions], minimum, TRUE) & within_bound(value$values[positions], maximum, FALSE)]
    items <- value$keys[positions]
    if (with_scores) items <- as.vector(rbind(items, as.character(value$values[positions])))
    array_reply(items)
}
key_command <- function(state, command, a) {
    if (command == "TIME") return(integer_reply(state$clock))
    if (command == "DBSIZE") return(integer_reply(length(state$db)))
    if (command == "FLUSH") { state$db <- list(); return("OK") }
    if (command == "INFO") {
        kinds <- c("string", "list", "hash", "set", "zset")
        counts <- vapply(kinds, function(kind) sum(vapply(state$db, function(entry) entry$kind == kind, logical(1L))), integer(1L))
        expires <- sum(vapply(state$db, function(entry) !is.null(entry$expiry), logical(1L)))
        return(paste0("keys=", length(state$db), ",expires=", expires, ",string=", counts[1L], ",list=", counts[2L],
                      ",hash=", counts[3L], ",set=", counts[4L], ",zset=", counts[5L], ",time=", state$clock,
                      ",depth=", length(state$stack), ",snapshots=", length(state$snapshots)))
    }
    if (command == "DEL") return(integer_reply(sum(vapply(a, function(key) erase(state, key), logical(1L)))))
    if (command == "EXISTS") return(integer_reply(sum(a %in% names(state$db))))
    if (command == "KEYS") {
        parts <- parse_pattern(a[1L])
        keys <- names(state$db)
        found <- keys[vapply(keys, function(key) matches(parts, key), logical(1L))]
        return(array_reply(sort(found, method = "radix")))
    }
    if (command == "TICK") {
        ticks <- number(a[1L])
        if (ticks <= 0L) fail(positive)
        state$clock <- state$clock + ticks
        return(integer_reply(purge(state)))
    }
    key <- a[1L]
    if (command == "EXPIRE") {
        condition <- if (length(a) == 3L) upper(a[3L]) else ""
        if (length(a) == 3L && !condition %in% c("NX", "XX", "GT", "LT")) fail(paste0("ERR Unsupported option ", a[3L]))
        seconds <- number(a[2L])
        entry <- db_get(state$db, key)
        if (is.null(entry)) return(integer_reply(0L))
        deadline <- state$clock + seconds
        rejected <- switch(condition, NX = !is.null(entry$expiry), XX = is.null(entry$expiry),
                           GT = is.null(entry$expiry) || deadline <= entry$expiry,
                           LT = !is.null(entry$expiry) && deadline >= entry$expiry, FALSE)
        if (rejected) return(integer_reply(0L))
        if (seconds <= 0L) erase(state, key) else {
            entry$expiry <- deadline
            state$db <- db_put(state$db, key, entry)
        }
        return(integer_reply(1L))
    }
    entry <- db_get(state$db, key)
    if (command == "TYPE") return(if (is.null(entry)) "none" else entry$kind)
    if (command == "TTL") return(integer_reply(if (is.null(entry)) -2L else if (is.null(entry$expiry)) -1L else entry$expiry - state$clock))
    if (command == "PERSIST") {
        if (is.null(entry$expiry)) return(integer_reply(0L))
        entry$expiry <- NULL
        state$db <- db_put(state$db, key, entry)
        return(integer_reply(1L))
    }
    if (is.null(entry)) fail("ERR no such key")
    destination <- a[2L]
    if (command == "RENAMENX" && !is.null(db_get(state$db, destination))) return(integer_reply(0L))
    if (key != destination) {
        erase(state, key)
        state$db <- db_put(state$db, destination, entry)
    }
    if (command == "RENAME") "OK" else integer_reply(1L)
}
control_command <- function(state, command, a) {
    if (command == "BEGIN") state$stack <- c(state$stack, list(state$db)) else if (command %in% c("COMMIT", "ROLLBACK")) {
        if (!length(state$stack)) fail("ERR no transaction")
        if (command == "ROLLBACK") {
            state$db <- state$stack[[length(state$stack)]]
            purge(state)
        }
        state$stack <- head(state$stack, -1L)
    } else if (command == "SNAPSHOT") state$snapshots <- db_put(state$snapshots, a[1L], state$db) else {
        saved <- db_get(state$snapshots, a[1L])
        if (is.null(saved)) fail("ERR no such snapshot")
        state$db <- saved
        purge(state)
    }
    "OK"
}
execute <- function(state, words) {
    command <- check_arity(words[1L], length(words) - 1L)
    a <- words[-1L]
    if (command %in% strsplit("SET GET MSET MGET INCR DECR INCRBY DECRBY APPEND STRLEN GETRANGE", " ")[[1L]])
        return(string_command(state, command, a))
    if (command %in% strsplit("LPUSH RPUSH LPOP RPOP LRANGE LLEN LINDEX LSET LREM LTRIM LINSERT", " ")[[1L]])
        return(list_command(state, command, a))
    if (command %in% strsplit("HSET HGET HDEL HGETALL HLEN HEXISTS HKEYS HVALS HINCRBY", " ")[[1L]])
        return(hash_command(state, command, a))
    if (command %in% strsplit("SADD SREM SISMEMBER SMEMBERS SCARD SINTER SUNION SDIFF SINTERSTORE SUNIONSTORE SDIFFSTORE", " ")[[1L]])
        return(set_command(state, command, a))
    if (command %in% strsplit("ZADD ZSCORE ZINCRBY ZREM ZCARD ZRANK ZRANGE ZRANGEBYSCORE", " ")[[1L]])
        return(zset_command(state, command, a))
    if (command %in% c("BEGIN", "COMMIT", "ROLLBACK", "SNAPSHOT", "RESTORE"))
        return(control_command(state, command, a))
    key_command(state, command, a)
}

state <- new.env(parent = emptyenv())
state$db <- list()
state$stack <- list()
state$snapshots <- list()
state$clock <- 0L
input <- readLines(file("stdin"), warn = FALSE)
for (line in input[1L + seq_len(as.integer(input[1L]))]) {
    words <- split_line(line)
    reply <- if (is.null(words)) "Invalid argument(s)" else tryCatch(execute(state, words),
        command_error = function(error) paste0("(error) ", conditionMessage(error)))
    cat(paste(reply, collapse = "\n"), "\n", sep = "")
}
