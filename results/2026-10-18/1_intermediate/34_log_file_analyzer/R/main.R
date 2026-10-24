methods <- c("GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS")
reasons <- c("fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency")
classes <- paste0(1:5, "xx")
filter_keys <- c("METHOD", "STATUS", "IP", "PATH")
forms <- list(
    SUMMARY = character(), MALFORMED = character(), STATUS = character(),
    METHODS = character(), TOP = c("kind", "limit"), HOURLY = character(),
    TIMELINE = "minutes", BANDWIDTH = character(), VISITORS = character(),
    LATENCY = "path", HISTOGRAM = "width", APDEX = "threshold", ERRORS = character(),
    SLOWEST = "limit", SESSIONS = c("ip", "minutes"), BURST = c("length", "times"),
    PEAK = "length", GAPS = "length", IP = "ip",
    RANGE = c("date", "time", "date", "time"), FILTER = c("key", "value"),
    UNFILTER = "subject", RESET = character(), STATE = character()
)
require_records <- c("STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH",
                     "VISITORS", "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS")
ranges <- list(limit = c(1, 100), minutes = c(1, 1440), width = c(1, 100000),
               threshold = c(1, 100000), length = c(1, 86400), times = c(1, 1000))
argument_errors <- c(limit = "invalid number", minutes = "invalid number",
    width = "invalid number", threshold = "invalid number", length = "invalid number",
    times = "invalid number", kind = "invalid kind", path = "invalid path",
    ip = "invalid ip", date = "invalid timestamp", time = "invalid timestamp",
    key = "invalid key", subject = "invalid key", value = "invalid value")

ensure <- function(condition, reason) {
    if (!condition) {
        stop(structure(list(message = reason, call = NULL),
                       class = c("query_error", "error", "condition")))
    }
}

words <- function(line) strsplit(trimws(line), " +")[[1L]]
canonical <- function(s, width) {
    nchar(s) <= width && grepl("^(0|[1-9][0-9]*)$", s)
}
valid_date <- function(s) {
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", s)) return(FALSE)
    year <- as.integer(substr(s, 1, 4))
    year >= 2000 && year <= 2059 && !is.na(as.Date(s, format = "%Y-%m-%d"))
}
valid_time <- function(s) {
    grepl("^[0-9]{2}:[0-9]{2}:[0-9]{2}$", s) &&
        as.integer(substr(s, 1, 2)) < 24 &&
        as.integer(substr(s, 4, 5)) < 60 && as.integer(substr(s, 7, 8)) < 60
}
valid_ip <- function(s) {
    if (!grepl("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", s)) return(FALSE)
    parts <- strsplit(s, ".", fixed = TRUE)[[1L]]
    all(vapply(parts, function(p) canonical(p, 3) && as.numeric(p) <= 255, logical(1)))
}
valid_status <- function(s) {
    grepl("^[0-9]{3}$", s) && as.integer(s) >= 100 && as.integer(s) <= 599
}
valid_filter <- function(key, value) {
    switch(key,
        METHOD = value %in% methods,
        STATUS = value %in% classes || valid_status(value),
        IP = valid_ip(value),
        PATH = startsWith(value, "/")
    )
}
valid_argument <- function(kind, value, args) {
    if (kind %in% names(ranges)) {
        bounds <- ranges[[kind]]
        return(canonical(value, 6) && as.numeric(value) >= bounds[1] &&
                   as.numeric(value) <= bounds[2])
    }
    switch(kind,
        kind = value %in% c("PATHS", "IPS"), path = startsWith(value, "/"),
        ip = valid_ip(value), date = valid_date(value), time = valid_time(value),
        key = value %in% filter_keys, subject = value %in% c(filter_keys, "RANGE"),
        value = valid_filter(args[1], value)
    )
}
malformed_reason <- function(f) {
    if (length(f) != 8) return("fields")
    if (!valid_date(f[1])) return("date")
    if (!valid_time(f[2])) return("time")
    if (!valid_ip(f[3])) return("ip")
    if (!f[4] %in% methods) return("method")
    if (!startsWith(f[5], "/")) return("path")
    if (!valid_status(f[6])) return("status")
    if (!canonical(f[7], 8)) return("bytes")
    if (!canonical(f[8], 6)) return("latency")
    NA_character_
}
seconds_of <- function(date, clock) {
    days <- as.numeric(as.Date(date, format = "%Y-%m-%d") - as.Date("2000-01-01"))
    hms <- as.numeric(strsplit(clock, ":", fixed = TRUE)[[1L]])
    days * 86400 + sum(hms * c(3600, 60, 1))
}
interval_label <- function(seconds) {
    date <- as.Date(seconds %/% 86400, origin = "2000-01-01")
    minutes <- seconds %% 86400 %/% 60
    sprintf("%s %02d:%02d", format(date, "%Y-%m-%d"),
            as.integer(minutes %/% 60), as.integer(minutes %% 60))
}
normalize_path <- function(raw) {
    parts <- character()
    for (part in strsplit(sub("\\?.*$", "", raw), "/", fixed = TRUE)[[1L]]) {
        if (part == "..") {
            if (length(parts)) parts <- head(parts, -1L)
        } else if (part != "" && part != ".") {
            parts <- c(parts, part)
        }
    }
    numeric_part <- grepl("^[0-9]+$", parts)
    hex_part <- nchar(parts) >= 8 & grepl("^[0-9a-f]+$", parts) & grepl("[0-9]", parts)
    parts[hex_part] <- "{hex}"
    parts[numeric_part] <- "{id}"
    paste0("/", paste(parts, collapse = "/"))
}
ip_number <- function(ips) {
    vapply(strsplit(ips, ".", fixed = TRUE),
           function(p) sum(as.numeric(p) * 256^(3:0)), numeric(1))
}
status_matches <- function(value, status) {
    if (value %in% classes) status %/% 100 == as.numeric(substr(value, 1, 1))
    else status == as.numeric(value)
}
fixed <- function(numerator, denominator, places) {
    scale <- 10^places
    value <- (numerator * scale) %/% denominator
    paste0(sprintf("%.0f", value %/% scale), ".",
           sprintf(paste0("%0", places, "d"), as.integer(value %% scale)))
}
percent <- function(part, total) paste0(fixed(part * 100, total, 2), "%")
bytes_text <- function(value) {
    if (value >= 1073741824) return(paste0(fixed(value, 1073741824, 1), "GB"))
    if (value >= 1048576) return(paste0(fixed(value, 1048576, 1), "MB"))
    if (value >= 1024) return(paste0(fixed(value, 1024, 1), "KB"))
    paste0(sprintf("%.0f", value), "B")
}
key_counts <- function(values, ip = FALSE) {
    keys <- unique(values)
    counts <- tabulate(match(values, keys), nbins = length(keys))
    index <- order(-counts, if (ip) ip_number(keys) else keys, method = "radix")
    data.frame(key = keys[index], count = counts[index], stringsAsFactors = FALSE)
}
class_counts <- function(rows) tabulate(rows$status %/% 100, nbins = 5)
buckets <- function(values) {
    first <- min(values)
    width <- max(values) - first + 1
    ensure(width <= 60, "too many buckets")
    list(first = first, counts = tabulate(as.integer(values - first + 1), nbins = width))
}
percentile <- function(values, rank) values[(rank * length(values) + 99) %/% 100]
window_peak <- function(rows, width) {
    first <- 1L
    best <- c(count = 0, first = 1, last = 1)
    for (last in seq_len(nrow(rows))) {
        while (rows$seconds[last] - rows$seconds[first] >= width) first <- first + 1L
        if (last - first + 1 > best["count"]) {
            best <- c(count = last - first + 1, first = first, last = last)
        }
    }
    best
}
apdex <- function(rows, threshold) {
    satisfied <- sum(rows$status < 500 & rows$latency <= threshold)
    tolerating <- sum(rows$status < 500 & rows$latency > threshold & rows$latency <= 4 * threshold)
    n <- nrow(rows)
    c(count = n, satisfied = satisfied, tolerating = tolerating,
      frustrated = n - satisfied - tolerating, points = 2 * satisfied + tolerating, total = 2 * n)
}
apdex_rating <- function(score) {
    points <- score["points"] * 100
    total <- score["total"]
    if (points >= 94 * total) "excellent"
    else if (points >= 85 * total) "good"
    else if (points >= 70 * total) "fair"
    else if (points >= 50 * total) "poor"
    else "unacceptable"
}
fraction_rank <- function(numerator, denominator) {
    # Cross products stay below 2^53 under the input constraints.
    vapply(seq_along(numerator), function(i) {
        sum(numerator * denominator[i] < numerator[i] * denominator)
    }, numeric(1))
}

make_analyzer <- function(log_lines) {
    parsed <- lapply(log_lines, words)
    bad <- vapply(parsed, malformed_reason, character(1))
    records <- data.frame(line = integer(), date = character(), timestamp = character(),
        hour = integer(), seconds = numeric(), ip = character(), method = character(),
        path = character(), status = integer(), bytes = numeric(), latency = numeric())
    valid <- which(is.na(bad))
    if (length(valid)) {
        records <- do.call(rbind, lapply(valid, function(i) {
            f <- parsed[[i]]
            data.frame(line = i, date = f[1], timestamp = paste(f[1], f[2]),
                hour = as.integer(substr(f[2], 1, 2)), seconds = seconds_of(f[1], f[2]),
                ip = f[3], method = f[4], path = normalize_path(f[5]),
                status = as.integer(f[6]), bytes = as.numeric(f[7]), latency = as.numeric(f[8]),
                stringsAsFactors = FALSE)
        }))
        records <- records[order(records$seconds, records$line), , drop = FALSE]
    }
    conditions <- setNames(rep(NA_character_, length(filter_keys)), filter_keys)
    time_range <- NULL

    selected <- function() {
        keep <- rep(TRUE, nrow(records))
        if (!is.null(time_range)) {
            keep <- keep & records$seconds >= time_range$start & records$seconds <= time_range$end
        }
        if (!is.na(conditions["METHOD"])) keep <- keep & records$method == conditions["METHOD"]
        if (!is.na(conditions["STATUS"])) keep <- keep & status_matches(conditions["STATUS"], records$status)
        if (!is.na(conditions["IP"])) keep <- keep & records$ip == conditions["IP"]
        if (!is.na(conditions["PATH"])) keep <- keep & records$path == conditions["PATH"]
        records[keep, , drop = FALSE]
    }

    run <- function(name, args) {
        output <- character()
        emit <- function(...) {
            parts <- lapply(list(...), function(x) if (is.numeric(x)) sprintf("%.0f", x) else as.character(x))
            output <<- c(output, paste(unlist(parts, use.names = FALSE), collapse = " "))
        }
        bar_line <- function(label, count, maximum) {
            if (count == 0) emit(label, count)
            else emit(label, count, strrep("#", (count * 30 + maximum - 1) %/% maximum))
        }
        rows <- selected()
        n <- nrow(rows)
        if (name %in% require_records && n == 0) return(paste(name, "no records"))
        switch(name,
            SUMMARY = {
                emit("SUMMARY", "lines", length(log_lines), "valid", nrow(records), "malformed", sum(!is.na(bad)))
                emit("requests", n, "bytes", sum(rows$bytes), "ips", length(unique(rows$ip)), "paths", length(unique(rows$path)))
                if (n == 0) emit("span", "none")
                else emit("span", rows$timestamp[1], rows$timestamp[n], rows$seconds[n] - rows$seconds[1])
            },
            MALFORMED = {
                emit("MALFORMED", sum(!is.na(bad)))
                for (reason in reasons) {
                    indices <- which(bad == reason)
                    if (length(indices)) emit(reason, length(indices), indices)
                }
            },
            STATUS = {
                emit("STATUS", n)
                counts <- class_counts(rows)
                for (i in seq_along(classes)) emit(classes[i], counts[i], percent(counts[i], n))
                codes <- sort(unique(rows$status))
                for (code in codes) {
                    count <- sum(rows$status == code)
                    emit(code, count, percent(count, n))
                }
            },
            METHODS = {
                emit("METHODS", n)
                counts <- key_counts(rows$method)
                for (i in seq_len(nrow(counts))) emit(counts$key[i], counts$count[i], percent(counts$count[i], n))
            },
            TOP = {
                counts <- key_counts(if (args[1] == "PATHS") rows$path else rows$ip, ip = args[1] == "IPS")
                shown <- min(as.numeric(args[2]), nrow(counts))
                emit("TOP", args[1], shown, "of", nrow(counts))
                ranks <- match(counts$count, counts$count)
                for (i in seq_len(shown)) emit(ranks[i], counts$key[i], counts$count[i], percent(counts$count[i], n))
            },
            HOURLY = {
                counts <- tabulate(rows$hour + 1L, nbins = 24)
                emit("HOURLY", n, "peak", sprintf("%02d", which.max(counts) - 1L), max(counts))
                for (i in seq_along(counts)) bar_line(sprintf("%02d", i - 1L), counts[i], max(counts))
            },
            TIMELINE = {
                minutes <- as.numeric(args[1])
                width <- minutes * 60
                b <- buckets(rows$seconds %/% width)
                emit("TIMELINE", minutes, length(b$counts))
                for (i in seq_along(b$counts)) bar_line(interval_label((b$first + i - 1) * width), b$counts[i], max(b$counts))
            },
            BANDWIDTH = {
                dates <- sort(unique(rows$date), method = "radix")
                total <- sum(rows$bytes)
                emit("BANDWIDTH", length(dates), total, bytes_text(total))
                for (date in dates) {
                    group <- rows[rows$date == date, , drop = FALSE]
                    size <- sum(group$bytes)
                    emit(date, nrow(group), size, bytes_text(size))
                }
            },
            VISITORS = {
                dates <- sort(unique(rows$date), method = "radix")
                first <- rows[!duplicated(rows$ip), c("ip", "date"), drop = FALSE]
                emit("VISITORS", length(dates), nrow(first))
                for (date in dates) {
                    ips <- unique(rows$ip[rows$date == date])
                    fresh <- sum(first$date[match(ips, first$ip)] == date)
                    emit(date, "unique", length(ips), "new", fresh, "returning", length(ips) - fresh)
                }
            },
            LATENCY = {
                label <- if (length(args)) normalize_path(args[1]) else "all"
                values <- if (length(args)) rows$latency[rows$path == label] else rows$latency
                if (!length(values)) emit("LATENCY", "no records")
                else {
                    values <- sort(values)
                    count <- length(values)
                    trim <- count %/% 10
                    trimmed <- values[seq.int(trim + 1, count - trim)]
                    emit("LATENCY", label, "count", count, "min", values[1],
                         "p50", percentile(values, 50), "p90", percentile(values, 90),
                         "p99", percentile(values, 99), "max", values[count],
                         "mean", fixed(sum(values), count, 2), "trimmed", fixed(sum(trimmed), length(trimmed), 2))
                }
            },
            HISTOGRAM = {
                width <- as.numeric(args[1])
                b <- buckets(rows$latency %/% width)
                emit("HISTOGRAM", width, length(b$counts))
                for (i in seq_along(b$counts)) {
                    lower <- (b$first + i - 1) * width
                    bar_line(sprintf("%.0f-%.0f", lower, lower + width - 1), b$counts[i], max(b$counts))
                }
            },
            APDEX = {
                threshold <- as.numeric(args[1])
                s <- apdex(rows, threshold)
                emit("APDEX", threshold, fixed(s["points"], s["total"], 3), apdex_rating(s),
                     "satisfied", s["satisfied"], "tolerating", s["tolerating"], "frustrated", s["frustrated"])
                groups <- split(seq_len(n), rows$path)
                scores <- t(vapply(groups, function(i) apdex(rows[i, , drop = FALSE], threshold), numeric(6)))
                ranking <- order(fraction_rank(scores[, "points"], scores[, "total"]),
                                 -scores[, "count"], names(groups), method = "radix")
                for (i in ranking) {
                    s <- scores[i, ]
                    emit(names(groups)[i], fixed(s["points"], s["total"], 3), apdex_rating(s), s["count"])
                }
            },
            ERRORS = {
                failed <- sum(rows$status >= 400)
                emit("ERRORS", failed, "of", n, percent(failed, n))
                groups <- split(seq_len(n), rows$path)
                stats <- t(vapply(groups, function(i) {
                    c(count = length(i), client = sum(rows$status[i] %/% 100 == 4), server = sum(rows$status[i] %/% 100 == 5))
                }, numeric(3)))
                failures <- stats[, "client"] + stats[, "server"]
                ranking <- order(-fraction_rank(failures, stats[, "count"]), -failures, names(groups), method = "radix")
                for (i in ranking[failures[ranking] > 0]) {
                    emit(names(groups)[i], stats[i, "count"], stats[i, "client"], stats[i, "server"], percent(failures[i], stats[i, "count"]))
                }
            },
            SLOWEST = {
                groups <- split(seq_len(n), paste(rows$method, rows$path, sep = "\001"))
                stats <- do.call(rbind, lapply(groups, function(i) {
                    data.frame(method = rows$method[i[1]], path = rows$path[i[1]], count = length(i),
                               total = sum(rows$latency[i]), maximum = max(rows$latency[i]), stringsAsFactors = FALSE)
                }))
                ranking <- order(-fraction_rank(stats$total, stats$count), -stats$maximum, stats$path, stats$method, method = "radix")
                shown <- min(as.numeric(args[1]), nrow(stats))
                emit("SLOWEST", shown, "of", nrow(stats))
                for (rank in seq_len(shown)) {
                    s <- stats[ranking[rank], ]
                    emit(rank, s$method, s$path, "count", s$count, "avg", fixed(s$total, s$count, 2), "max", s$maximum)
                }
            },
            SESSIONS = {
                ip <- args[1]
                minutes <- if (length(args) == 2) as.numeric(args[2]) else 30
                found <- rows[rows$ip == ip, , drop = FALSE]
                if (!nrow(found)) emit("SESSIONS", "no records")
                else {
                    starts <- which(c(TRUE, diff(found$seconds) > minutes * 60))
                    ends <- c(starts[-1] - 1L, nrow(found))
                    durations <- found$seconds[ends] - found$seconds[starts]
                    emit("SESSIONS", ip, "timeout", minutes, "count", length(starts), "requests", nrow(found),
                         "avg_duration", fixed(sum(durations), length(starts), 1),
                         "avg_requests", fixed(nrow(found), length(starts), 1))
                    for (i in seq_along(starts)) {
                        emit(i, found$timestamp[starts[i]], found$timestamp[ends[i]], durations[i],
                             ends[i] - starts[i] + 1, length(unique(found$path[seq.int(starts[i], ends[i])])))
                    }
                }
            },
            BURST = {
                width <- as.numeric(args[1])
                threshold <- as.numeric(args[2])
                failed <- rows[rows$status >= 400, , drop = FALSE]
                groups <- split(seq_len(nrow(failed)), failed$ip)
                peaks <- lapply(groups, function(i) window_peak(failed[i, , drop = FALSE], width))
                sizes <- vapply(peaks, function(p) unname(p["count"]), numeric(1))
                ranking <- order(-sizes, ip_number(names(groups)), method = "radix")
                ranking <- ranking[sizes[ranking] >= threshold]
                emit("BURST", width, threshold, length(ranking))
                for (i in ranking) {
                    p <- peaks[[i]]
                    group <- failed[groups[[i]], , drop = FALSE]
                    emit(names(groups)[i], p["count"], group$timestamp[p["first"]], group$timestamp[p["last"]])
                }
            },
            PEAK = {
                width <- as.numeric(args[1])
                p <- window_peak(rows, width)
                emit("PEAK", width, p["count"], rows$timestamp[p["first"]], rows$timestamp[p["last"]])
            },
            GAPS = {
                width <- as.numeric(args[1])
                gaps <- which(diff(rows$seconds) >= width)
                emit("GAPS", width, length(gaps))
                for (i in gaps) emit(rows$timestamp[i], rows$timestamp[i + 1L], rows$seconds[i + 1L] - rows$seconds[i])
            },
            IP = {
                ip <- args[1]
                found <- rows[rows$ip == ip, , drop = FALSE]
                if (!nrow(found)) emit("IP", "no records")
                else {
                    paths <- key_counts(found$path)
                    emit("IP", ip, "requests", nrow(found), "bytes", sum(found$bytes),
                         "errors", sum(found$status >= 400), "paths", nrow(paths))
                    emit("first", found$timestamp[1], "last", tail(found$timestamp, 1))
                    counts <- key_counts(found$method)
                    emit("methods", as.vector(t(cbind(counts$key, sprintf("%d", counts$count)))))
                    emit("classes", as.vector(t(cbind(classes, sprintf("%d", class_counts(found))))))
                    for (i in seq_len(min(3, nrow(paths)))) emit("path", paths$key[i], paths$count[i])
                }
            },
            RANGE = {
                start <- seconds_of(args[1], args[2])
                end <- seconds_of(args[3], args[4])
                ensure(start <= end, "invalid range")
                time_range <<- list(start = start, end = end, from = paste(args[1], args[2]), to = paste(args[3], args[4]))
                emit("RANGE", time_range$from, time_range$to, "active", nrow(selected()))
            },
            FILTER = {
                key <- args[1]
                value <- if (key == "PATH") normalize_path(args[2]) else args[2]
                conditions[key] <<- value
                emit("FILTER", key, value, "active", nrow(selected()))
            },
            UNFILTER = {
                key <- args[1]
                if (key == "RANGE") {
                    ensure(!is.null(time_range), "not filtered")
                    time_range <<- NULL
                } else {
                    ensure(!is.na(conditions[key]), "not filtered")
                    conditions[key] <<- NA_character_
                }
                emit("UNFILTER", key, "active", nrow(selected()))
            },
            RESET = {
                time_range <<- NULL
                conditions[] <<- NA_character_
                emit("RESET", "active", nrow(selected()))
            },
            STATE = {
                window <- if (is.null(time_range)) "-" else paste(time_range$from, time_range$to)
                values <- ifelse(is.na(conditions), "-", conditions)
                emit("STATE", "active", n, "range", window,
                     as.vector(t(cbind(tolower(filter_keys), values))))
            }
        )
        output
    }

    function(line) {
        tryCatch({
            fields <- words(line)
            name <- fields[1]
            args <- fields[-1]
            ensure(name %in% names(forms), "unknown query")
            form <- forms[[name]]
            optional <- name %in% c("LATENCY", "SESSIONS") && length(args) == length(form) - 1
            ensure(length(args) == length(form) || optional, "wrong arguments")
            for (i in seq_along(args)) ensure(valid_argument(form[i], args[i], args), argument_errors[[form[i]]])
            run(name, args)
        }, query_error = function(error) paste("ERROR", error$message))
    }
}

main <- function() {
    input <- readLines(stdin(), warn = FALSE)
    separator <- match("---", input)
    queries <- input[seq.int(separator + 1L, length(input))]
    end <- match("END", queries)
    execute <- make_analyzer(input[seq_len(separator - 1L)])
    for (line in queries[seq_len(end - 1L)]) {
        cat(paste(execute(line), collapse = "\n"), "\n", sep = "")
    }
}

main()
