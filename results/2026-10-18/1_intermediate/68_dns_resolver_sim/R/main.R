types <- c("A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA")
kinds <- c("ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT")
roots <- numeric()
zones <- list()
current_zone <- NULL
down <- numeric()
cache <- list()
settings <- c(MINTTL = 1, MAXTTL = 86400, NEGTTL = 3600)
clock <- 0
hits <- 0
queries <- list()
resolutions <- c(NOERROR = 0, NODATA = 0, NXDOMAIN = 0, SERVFAIL = 0)
emit <- function(...) cat(paste0(...), "\n", sep = "")
fmt <- function(number) sprintf("%.0f", number)
fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("dns_error", "error", "condition")))
split_keep <- function(text, separator) {
    parts <- strsplit(paste0(text, "\001"), separator, fixed = TRUE)[[1]]
    last <- length(parts)
    parts[last] <- substr(parts[last], 1, nchar(parts[last]) - 1)
    parts
}
labels <- function(name) if (name == ".") character() else strsplit(substr(name, 1, nchar(name) - 1), ".", fixed = TRUE)[[1]]
name_key <- function(name) paste(rev(labels(name)), collapse = "\001")
below <- function(name, ancestor) ancestor == "." || name == ancestor || endsWith(name, paste0(".", ancestor))
ancestors <- function(name) {
    parts <- labels(name)
    c(vapply(seq_along(parts), function(i) paste0(paste(parts[seq.int(i, length(parts))], collapse = "."), "."), character(1)), ".")
}
parse_name <- function(word, wildcard = FALSE, origin = NULL) {
    if (!is.null(origin) && word == "@") return(origin)
    if (word == ".") return(".")
    parts <- split_keep(if (endsWith(word, ".")) substr(word, 1, nchar(word) - 1) else word, ".")
    for (i in seq_along(parts)) {
        part <- parts[i]
        if (wildcard && i == 1 && part == "*") next
        if (nchar(part) < 1 || nchar(part) > 63 || !grepl("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", part)) fail(paste0("bad name ", word))
    }
    result <- paste0(chartr("A-Z", "a-z", paste(parts, collapse = ".")), ".")
    if (!is.null(origin) && origin != "." && !endsWith(word, ".")) result <- paste0(result, origin)
    result
}
address <- function(word) {
    if (!grepl("^(0|[1-9][0-9]{0,2})(\\.(0|[1-9][0-9]{0,2})){3}$", word)) fail(paste0("bad address ", word))
    parts <- as.numeric(strsplit(word, ".", fixed = TRUE)[[1]])
    if (any(parts > 255)) fail(paste0("bad address ", word))
    sum(parts * 256^(3:0))
}
ip <- function(number) paste(floor(number / 256^(3:0)) %% 256, collapse = ".")
ipv6 <- function(word) {
    parts <- split_keep(word, "::")
    if (length(parts) > 2) fail(paste0("bad address ", word))
    sides <- lapply(parts, function(part) if (part == "") character() else split_keep(part, ":"))
    groups <- unlist(sides, use.names = FALSE)
    if (any(!grepl("^[0-9A-Fa-f]{1,4}$", groups)) || (if (length(parts) == 1) length(groups) != 8 else length(groups) > 7)) fail(paste0("bad address ", word))
    if (length(parts) == 1) as.numeric(strtoi(groups, 16)) else c(as.numeric(strtoi(sides[[1]], 16)), rep(0, 8 - length(groups)), as.numeric(strtoi(sides[[2]], 16)))
}
ipv6_text <- function(groups) {
    best_start <- 0
    best_length <- 1
    index <- 1
    while (index <= 8) {
        if (groups[index] != 0) {
            index <- index + 1
            next
        }
        finish <- index
        while (finish <= 8 && groups[finish] == 0) finish <- finish + 1
        if (finish - index > best_length) {
            best_start <- index
            best_length <- finish - index
        }
        index <- finish
    }
    words <- sprintf("%x", as.integer(groups))
    if (!best_start) return(paste(words, collapse = ":"))
    left <- if (best_start > 1) words[seq_len(best_start - 1)] else character()
    right <- if (best_start + best_length <= 8) words[seq.int(best_start + best_length, 8)] else character()
    paste0(paste(left, collapse = ":"), "::", paste(right, collapse = ":"))
}
integer_word <- function(word) grepl("^(0|[1-9][0-9]{0,8})$", word)
parse_ttl <- function(word) {
    if (integer_word(word)) seconds <- as.numeric(word) else {
        text <- chartr("A-Z", "a-z", word)
        if (!grepl("^((0|[1-9][0-9]{0,2})[wdhms])+$", text)) fail(paste0("bad ttl ", word))
        pairs <- regmatches(text, gregexpr("[0-9]+[wdhms]", text))[[1]]
        units <- c(w = 604800, d = 86400, h = 3600, m = 60, s = 1)
        previous <- 0
        seconds <- 0
        for (pair in pairs) {
            unit <- substr(pair, nchar(pair), nchar(pair))
            rank <- match(unit, names(units))
            if (rank <= previous) fail(paste0("bad ttl ", word))
            previous <- rank
            seconds <- seconds + as.numeric(substr(pair, 1, nchar(pair) - 1)) * units[unit]
        }
    }
    if (seconds < 1 || seconds > 604800) fail(paste0("bad ttl ", word))
    unname(seconds)
}
check_type <- function(type) {
    if (!(type %in% types)) fail(paste0("bad type ", type))
    type
}
sorted_records <- function(records) {
    if (!length(records)) return(records)
    type <- records[[1]]$type
    if (type == "A") indices <- order(vapply(records, function(record) record$data, numeric(1)))
    else if (type == "AAAA") {
        groups <- do.call(rbind, lapply(records, function(record) record$data))
        indices <- do.call(order, as.data.frame(groups))
    } else if (type == "MX") indices <- order(vapply(records, function(record) record$data[[1]], numeric(1)), vapply(records, function(record) name_key(record$data[[2]]), character(1)), method = "radix")
    else if (type == "TXT") indices <- order(vapply(records, function(record) record$data, character(1)), method = "radix")
    else if (type == "SOA") indices <- seq_along(records)
    else indices <- order(vapply(records, function(record) name_key(record$data), character(1)), method = "radix")
    records[indices]
}
record_text <- function(record, remaining = NULL) {
    data <- record$data
    text <- switch(record$type, A = ip(data), AAAA = ipv6_text(data), MX = paste(fmt(data[[1]]), data[[2]]),
                   SOA = paste(vapply(data, function(item) if (is.numeric(item)) fmt(item) else item, character(1)), collapse = " "), data)
    paste(record$owner, fmt(if (is.null(remaining)) record$ttl else remaining), record$type, text)
}
zone_line <- function(words, number) {
    if (words[1] == "ROOT") {
        added <- numeric()
        for (word in words[-1]) {
            number <- address(word)
            if (number %in% c(roots, added)) fail(paste0("duplicate root ", word))
            added <- c(added, number)
        }
        roots <<- c(roots, added)
    } else if (words[1] == "ZONE") {
        current_zone <<- NULL
        origin <- parse_name(words[2])
        server <- address(words[3])
        for (zone in zones) if (zone$origin == origin && zone$server == server) fail(paste0("duplicate zone ", origin, " at ", words[3]))
        current_zone <<- list2env(list(origin = origin, server = server, line = number, records = list()), parent = emptyenv())
        zones[[length(zones) + 1]] <<- current_zone
    } else {
        if (is.null(current_zone)) fail("no current zone")
        owner <- parse_name(words[1], TRUE, current_zone$origin)
        if (!below(owner, current_zone$origin)) fail(paste0("out of zone ", owner))
        ttl <- parse_ttl(words[2])
        type <- check_type(words[3])
        fields <- words[-(1:3)]
        count <- switch(type, MX = 2, SOA = 7, 1)
        if (type != "TXT" && length(fields) != count) fail("wrong field count")
        if (type == "A") data <- address(fields[1])
        else if (type == "AAAA") data <- ipv6(fields[1])
        else if (type %in% c("NS", "CNAME", "PTR")) data <- parse_name(fields[1], FALSE, current_zone$origin)
        else if (type == "MX") {
            if (!integer_word(fields[1]) || as.numeric(fields[1]) > 65535) fail(paste0("bad preference ", fields[1]))
            data <- list(as.numeric(fields[1]), parse_name(fields[2], FALSE, current_zone$origin))
        } else if (type == "TXT") {
            data <- paste(fields, collapse = " ")
            if (!grepl('^"[^"]*"$', data)) fail(paste0("bad text ", data))
        } else {
            data <- lapply(fields[1:2], parse_name, origin = current_zone$origin)
            for (field in fields[3:6]) if (!integer_word(field)) fail(paste0("bad number ", field))
            if (!integer_word(fields[7]) || as.numeric(fields[7]) < 1 || as.numeric(fields[7]) > 86400) fail(paste0("bad minimum ", fields[7]))
            data <- c(data, as.list(as.numeric(fields[3:7])))
        }
        records <- current_zone$records
        if (type == "NS" && length(labels(owner)) && labels(owner)[1] == "*") fail("ns at wildcard")
        if (type == "SOA" && owner != current_zone$origin) fail("soa not at origin")
        if (type == "SOA" && any(vapply(records, function(record) record$type == "SOA", logical(1)))) fail("duplicate soa")
        if (any(vapply(records, function(record) record$owner == owner && record$type == type && identical(record$data, data), logical(1)))) fail("duplicate record")
        if (any(vapply(records, function(record) record$owner == owner && (type == "CNAME" || record$type == "CNAME"), logical(1)))) fail(paste0("cname conflict ", owner))
        current_zone$records[[length(records) + 1]] <- list(owner = owner, ttl = ttl, type = type, data = data)
    }
}
response <- function(kind, answer = list(), authority = list(), additional = list(), cut = NULL) list(kind = kind, answer = answer, authority = authority, additional = additional, cut = cut)
known <- function(server) any(vapply(zones, function(zone) zone$server == server, logical(1)))
authoritative <- function(server, name, type, cut) {
    if (server %in% down || !known(server)) return(response("TIMEOUT"))
    chosen <- NULL
    for (zone in zones) if (zone$server == server && below(name, zone$origin) && (is.null(chosen) || length(labels(zone$origin)) > length(labels(chosen$origin)))) chosen <- zone
    if (is.null(chosen) || length(labels(chosen$origin)) < length(labels(cut))) return(response("LAME"))
    records <- chosen$records
    soa <- Filter(function(record) record$type == "SOA", records)[[1]]
    for (ancestor in rev(ancestors(name))) {
        if (ancestor == chosen$origin || !below(ancestor, chosen$origin)) next
        authority <- sorted_records(Filter(function(record) record$owner == ancestor && record$type == "NS", records))
        if (!length(authority)) next
        glue <- list()
        for (record in authority) glue <- c(glue, sorted_records(Filter(function(item) item$owner == record$data && item$type == "A", records)))
        return(response("REFERRAL", authority = authority, additional = glue, cut = ancestor))
    }
    found <- Filter(function(record) record$owner == name, records)
    if (!length(found)) {
        exists <- function(ancestor) any(vapply(records, function(record) below(record$owner, ancestor), logical(1)))
        if (exists(name)) return(response("NODATA", authority = list(soa)))
        closest <- "."
        for (ancestor in ancestors(name)[-1]) if (exists(ancestor)) {
            closest <- ancestor
            break
        }
        wildcard <- if (closest == ".") "*." else paste0("*.", closest)
        found <- Filter(function(record) record$owner == wildcard, records)
        if (!length(found)) return(response("NXDOMAIN", authority = list(soa)))
    }
    answer <- Filter(function(record) record$type == type, found)
    kind <- "ANSWER"
    if (!length(answer) && type != "CNAME") {
        answer <- Filter(function(record) record$type == "CNAME", found)
        kind <- "CNAME"
    }
    if (!length(answer)) return(response("NODATA", authority = list(soa)))
    answer <- lapply(sorted_records(answer), function(record) {
        record$owner <- name
        record
    })
    response(kind, answer)
}
describe <- function(result) switch(result$kind, REFERRAL = paste0("REFERRAL ", result$cut), CNAME = paste0("CNAME ", result$answer[[1]]$data), result$kind)
ask <- function(server, name, type, cut) {
    result <- authoritative(server, name, type, cut)
    key <- ip(server)
    record <- queries[[key]]
    if (is.null(record)) record <- list(server = server, counts = setNames(rep(0, length(kinds)), kinds))
    record$counts[result$kind] <- record$counts[result$kind] + 1
    queries[[key]] <<- record
    result
}
trace <- function(depth, text) emit(strrep("  ", depth + 1), text)
cache_key <- function(name, type) paste0(name, "|", type)
store <- function(records) {
    ttl <- min(max(min(vapply(records, function(record) record$ttl, numeric(1))), settings["MINTTL"]), settings["MAXTTL"])
    first <- records[[1]]
    cache[[cache_key(first$owner, first$type)]] <<- list(name = first$owner, type = first$type, kind = "POS", records = sorted_records(records), expiry = clock + ttl)
    lapply(records, function(record) {
        record$ttl <- unname(ttl)
        record
    })
}
cache_records <- function(entry) lapply(entry$records, function(record) {
    record$ttl <- entry$expiry - clock
    record
})
query_servers <- function(name, type, cut, nameservers, depth, resolving) {
    if (is.null(nameservers)) {
        for (server in roots) {
            result <- ask(server, name, type, cut)
            trace(depth, paste0("ASK ", ip(server), " ", name, " ", type, " -> ", describe(result)))
            if (!(result$kind %in% c("LAME", "TIMEOUT"))) return(result)
        }
    } else {
        nameservers <- nameservers[order(vapply(nameservers, name_key, character(1)), method = "radix")]
        for (host in nameservers) {
            entry <- cache[[cache_key(host, "A")]]
            if (!is.null(entry) && entry$kind == "POS") addresses <- vapply(entry$records, function(record) record$data, numeric(1))
            else if (cache_key(host, "A") %in% resolving) {
                trace(depth, paste0("GLUELESS ", host, " -> LOOP"))
                addresses <- numeric()
            } else {
                trace(depth, paste0("GLUELESS ", host))
                result <- resolve(host, "A", depth + 1, resolving)
                addresses <- if (result$status == "NOERROR") vapply(Filter(function(record) record$type == "A", result$answer), function(record) record$data, numeric(1)) else numeric()
            }
            for (server in sort(unique(addresses))) {
                result <- ask(server, name, type, cut)
                trace(depth, paste0("ASK ", ip(server), " ", name, " ", type, " -> ", describe(result)))
                if (!(result$kind %in% c("LAME", "TIMEOUT"))) return(result)
            }
        }
    }
    NULL
}
lookup <- function(name, type, depth, resolving) {
    entry <- cache[[cache_key(name, type)]]
    result <- NULL
    if (!is.null(entry)) result <- if (entry$kind == "POS") response("ANSWER", cache_records(entry)) else response(entry$kind)
    else if (any(vapply(cache, function(item) item$kind == "NXDOMAIN" && below(name, item$name), logical(1)))) result <- response("NXDOMAIN")
    if (is.null(result) && type != "CNAME") {
        entry <- cache[[cache_key(name, "CNAME")]]
        if (!is.null(entry) && entry$kind == "POS") result <- response("CNAME", cache_records(entry))
    }
    if (!is.null(result)) {
        hits <<- hits + 1
        trace(depth, paste0("CACHE HIT ", name, " ", type, " -> ", describe(result)))
        return(result)
    }
    cut <- "."
    servers <- NULL
    for (ancestor in ancestors(name)) {
        entry <- cache[[cache_key(ancestor, "NS")]]
        if (!is.null(entry) && entry$kind == "POS") {
            cut <- ancestor
            servers <- vapply(entry$records, function(record) record$data, character(1))
            hits <<- hits + 1
            trace(depth, paste0("CACHE HIT ", name, " ", type, " -> REFERRAL ", cut))
            break
        }
    }
    repeat {
        result <- query_servers(name, type, cut, servers, depth, resolving)
        if (is.null(result)) return(response(paste0("SERVFAIL no server for ", cut)))
        if (result$kind == "REFERRAL") {
            store(result$authority)
            owners <- unique(vapply(result$additional, function(record) record$owner, character(1)))
            for (owner in owners) store(Filter(function(record) record$owner == owner, result$additional))
            cut <- result$cut
            servers <- vapply(result$authority, function(record) record$data, character(1))
        } else if (result$kind %in% c("ANSWER", "CNAME")) {
            result$answer <- store(result$answer)
            return(result)
        } else {
            soa <- result$authority[[1]]
            ttl <- min(soa$ttl, soa$data[[7]], settings["NEGTTL"])
            cache[[cache_key(name, type)]] <<- list(name = name, type = type, kind = result$kind, expiry = clock + ttl)
            return(result)
        }
    }
}
resolve <- function(name, type, depth = 0, resolving = character()) {
    resolving <- c(resolving, cache_key(name, type))
    seen <- name
    chain <- list()
    current <- name
    repeat {
        result <- lookup(current, type, depth, resolving)
        if (result$kind == "CNAME") {
            record <- result$answer[[1]]
            chain[[length(chain) + 1]] <- record
            target <- record$data
            if (target %in% seen) {
                status <- "SERVFAIL cname loop"
                answer <- list()
                break
            }
            if (length(chain) == 9) {
                status <- "SERVFAIL cname chain too long"
                answer <- list()
                break
            }
            seen <- c(seen, target)
            current <- target
        } else {
            status <- if (result$kind == "ANSWER") "NOERROR" else result$kind
            answer <- if (startsWith(status, "SERVFAIL")) list() else c(chain, result$answer)
            break
        }
    }
    key <- if (startsWith(status, "SERVFAIL")) "SERVFAIL" else status
    resolutions[key] <<- resolutions[key] + 1
    list(status = status, answer = answer)
}
print_result <- function(result) {
    for (record in result$answer) emit("answer ", record_text(record))
    emit("status ", result$status)
}
address_resolution <- function(host) {
    output <- character()
    for (type in c("A", "AAAA")) {
        result <- resolve(host, type)
        if (result$status != "NOERROR") next
        for (record in result$answer) if (record$type == type) output <- c(output, if (type == "A") ip(record$data) else ipv6_text(record$data))
    }
    if (length(output)) paste(output, collapse = " ") else "no address"
}
command <- function(w) {
    kind <- w[1]
    if (kind %in% c("RESOLVE", "MX")) {
        name <- parse_name(w[2], TRUE)
        type <- if (kind == "MX") "MX" else check_type(w[3])
        emit(tolower(kind), " ", name, if (kind == "MX") "" else paste0(" ", type))
        result <- resolve(name, type)
        print_result(result)
        if (kind == "MX" && result$status == "NOERROR") {
            for (record in result$answer) {
                if (record$type != "MX") next
                preference <- record$data[[1]]
                host <- record$data[[2]]
                addresses <- if (host == ".") "null" else address_resolution(host)
                emit("exchange ", preference, " ", host, " -> ", addresses)
            }
        } else if (kind == "MX" && result$status == "NODATA") {
            host <- name
            for (record in result$answer) if (record$type == "CNAME") host <- record$data
            addresses <- address_resolution(host)
            emit("implicit ", host, " -> ", addresses)
        }
    } else if (kind == "REVERSE") {
        if (grepl(":", w[2], fixed = TRUE)) {
            groups <- ipv6(w[2])
            text <- ipv6_text(groups)
            digits <- paste(sprintf("%04x", as.integer(groups)), collapse = "")
            reverse <- paste0(paste(rev(strsplit(digits, "", fixed = TRUE)[[1]]), collapse = "."), ".ip6.arpa.")
        } else {
            text <- ip(address(w[2]))
            reverse <- paste0(paste(rev(strsplit(text, ".", fixed = TRUE)[[1]]), collapse = "."), ".in-addr.arpa.")
        }
        emit("reverse ", text, " ", reverse)
        print_result(resolve(reverse, "PTR"))
    } else if (kind %in% c("QUERY", "DUMP")) {
        server <- address(w[2])
        name <- parse_name(w[3], kind == "QUERY")
        if (kind == "QUERY") {
            type <- check_type(w[4])
            result <- ask(server, name, type, ".")
            emit("query ", ip(server), " ", name, " ", type, " -> ", describe(result))
            for (section in c("answer", "authority", "additional")) for (record in result[[section]]) emit(section, " ", record_text(record))
        } else {
            chosen <- NULL
            for (zone in zones) if (zone$server == server && zone$origin == name) chosen <- zone
            if (server %in% down || !known(server)) emit("dump ", ip(server), " ", name, " -> TIMEOUT")
            else if (is.null(chosen)) emit("dump ", ip(server), " ", name, " -> REFUSED")
            else {
                emit("dump ", ip(server), " ", name, " records=", length(chosen$records))
                owners <- unique(vapply(chosen$records, function(record) record$owner, character(1)))
                for (owner in owners[order(vapply(owners, name_key, character(1)), method = "radix")]) for (type in types) {
                    for (record in sorted_records(Filter(function(record) record$owner == owner && record$type == type, chosen$records))) emit("  ", record_text(record))
                }
            }
        }
    } else if (kind %in% c("DOWN", "UP")) {
        server <- address(w[2])
        if (kind == "DOWN" && server %in% down) fail(paste0("server ", w[2], " already down"))
        if (kind == "UP" && !(server %in% down)) fail(paste0("server ", w[2], " not down"))
        down <<- if (kind == "DOWN") c(down, server) else down[down != server]
        emit(tolower(kind), " ", ip(server))
    } else if (kind == "SET") {
        key <- w[2]
        if (!(key %in% names(settings))) fail(paste0("bad setting ", key))
        if (!integer_word(w[3]) || as.numeric(w[3]) < 1 || as.numeric(w[3]) > 604800) fail(paste0("bad value ", w[3]))
        changed <- settings
        changed[key] <- as.numeric(w[3])
        if (changed["MINTTL"] > changed["MAXTTL"]) fail("minttl above maxttl")
        settings <<- changed
        emit("set ", key, "=", fmt(changed[key]))
    } else if (kind == "TIME") {
        if (!integer_word(w[2]) || as.numeric(w[2]) < 1 || as.numeric(w[2]) > 1000000) fail(paste0("bad time ", w[2]))
        clock <<- clock + as.numeric(w[2])
        before <- length(cache)
        cache <<- Filter(function(entry) entry$expiry > clock, cache)
        emit("time now=", fmt(clock), " expired=", before - length(cache))
    } else if (kind %in% c("CACHE", "FLUSH")) {
        name <- if (length(w) > 1) parse_name(w[2]) else NULL
        entries <- Filter(function(entry) is.null(name) || below(entry$name, name), cache)
        if (kind == "FLUSH") {
            cache[names(entries)] <<- NULL
            emit("flush removed=", length(entries))
        } else {
            emit("cache entries=", length(entries))
            indices <- order(vapply(entries, function(entry) name_key(entry$name), character(1)), vapply(entries, function(entry) match(entry$type, types), integer(1)), method = "radix")
            for (entry in entries[indices]) {
                remaining <- entry$expiry - clock
                if (entry$kind == "POS") for (record in entry$records) emit("  ", record_text(record, remaining))
                else emit("  ", entry$name, " ", fmt(remaining), " ", entry$type, " ", entry$kind)
            }
        }
    } else if (kind == "STATS") {
        emit("stats queries=", sum(vapply(queries, function(record) sum(record$counts), numeric(1))), " hits=", hits)
        indices <- order(vapply(queries, function(record) record$server, numeric(1)))
        for (record in queries[indices]) emit("  ", ip(record$server), " sent=", sum(record$counts), " ", paste(paste0(tolower(kinds), "=", record$counts[kinds]), collapse = " "))
        emit("resolutions ", paste(paste0(tolower(names(resolutions)), "=", resolutions), collapse = " "))
    }
}
input <- readLines(file("stdin"), warn = FALSE)
zone_section <- TRUE
for (number in seq_along(input)) {
    line <- input[number]
    if (!zone_section && line == "END") break
    if (zone_section && line == "END ZONES") {
        kept <- list()
        for (zone in zones) {
            if (!any(vapply(zone$records, function(record) record$type == "SOA", logical(1)))) emit("error line ", zone$line, ": zone ", zone$origin, " at ", ip(zone$server), " has no soa")
            else {
                emit("zone ", zone$origin, " at ", ip(zone$server), " records=", length(zone$records))
                kept[[length(kept) + 1]] <- zone
            }
        }
        zones <- kept
        emit("loaded roots=", length(roots), " zones=", length(zones), " records=", sum(vapply(zones, function(zone) length(zone$records), integer(1))))
        zone_section <- FALSE
        next
    }
    tryCatch({
        words <- strsplit(line, " ", fixed = TRUE)[[1]]
        if (zone_section) zone_line(words, number) else command(words)
    }, dns_error = function(e) emit("error line ", number, ": ", e$message))
}
