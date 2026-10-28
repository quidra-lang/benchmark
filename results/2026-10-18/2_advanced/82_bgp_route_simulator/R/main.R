source("topology.R")
source("policy.R")
source("decision.R")
source("simulator.R")
source("report.R")

CONVERGENCE_HEADER <- "event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"
new_map <- function() new.env(parent = emptyenv())
map_keys <- function(table) ls(table, all.names = TRUE)
remove_key <- function(table, key) if (exists(key, table, inherits = FALSE)) rm(list = key, envir = table)
add_counter <- function(counts, key, amount = 1L) {
    value <- counts[[key]]
    counts[[key]] <- (if (is.null(value)) 0L else value) + amount
}
get_counter <- function(counts, key) if (is.null(counts[[key]])) 0L else counts[[key]]

new_simulation <- function(network, policies, defaults, stepcap, traces) {
    simulation <- new.env(parent = emptyenv())
    simulation$network <- network
    simulation$policies <- policies
    simulation$defaults <- defaults
    simulation$stepcap <- stepcap
    simulation$traces <- traces
    simulation$routers <- list()
    simulation$sessions <- list()
    simulation$by_session <- new_map()
    for (owner in network$ases) {
        router <- new.env(parent = emptyenv())
        router$origination <- new_map()
        router$rib <- new_map()
        router$sessions <- list()
        router$changes <- 0L
        for (link in network$at_as[[as.character(owner)]]) {
            session <- new.env(parent = emptyenv())
            session$owner <- owner
            session$link <- link
            session$incoming <- new_map()
            session$outgoing <- new_map()
            session$pending <- character()
            session$timer <- -1L
            session$sent <- session$received <- 0L
            router$sessions[[length(router$sessions) + 1L]] <- session
            simulation$sessions[[length(simulation$sessions) + 1L]] <- session
            simulation$by_session[[paste(owner, link)]] <- session
        }
        simulation$routers[[as.character(owner)]] <- router
    }
    simulation$messages <- new_message_queue()
    simulation$time <- 0L
    simulation$logs <- character()
    simulation$periods <- list()
    simulation$period <- NULL
    simulation$changed_prefixes <- character()
    simulation$trace_records <- simulation$ring_records <- list()
    simulation$ongoing_traces <- new_map()
    simulation$ongoing_rings <- new_map()
    simulation
}

log_update <- function(simulation, content) simulation$logs <- c(
    simulation$logs,
    paste(simulation$time, content)
)
message_text <- function(message, network) sprintf(
    "#%d %d->%d %s %s",
    message$serial,
    message$sender,
    message$receiver,
    network$links[[message$link]]$name,
    message$prefix
)

collapse_runs <- function(path) {
    if (!length(path)) return(integer())
    path[c(TRUE, path[-1L] != head(path, -1L))]
}

valley_position <- function(pattern) {
    symbols <- strsplit(pattern, "", fixed = TRUE)[[1L]]
    position <- 1L
    while (position <= length(symbols) && symbols[position] == "U") position <- position + 1L
    if (position <= length(symbols) && symbols[position] == "P") position <- position + 1L
    while (position <= length(symbols) && symbols[position] == "D") position <- position + 1L
    position - 1L
}

import_route <- function(simulation, session, prefix, attribute) {
    link <- simulation$network$links[[session$link]]
    rule <- applied_rule(
        simulation$policies,
        "IMPORT",
        session$owner,
        link,
        prefix,
        attribute$path,
        attribute$communities
    )
    local_pref <- simulation$defaults[[link_role(link, session$owner)]]
    if (rule_has(rule, "DENY")) return(list(route = NULL, rule = rule))
    med <- attribute$med
    communities <- attribute$communities
    if (!is.null(rule)) {
        local_pref <- rule_value(rule, "LOCALPREF", local_pref)
        med <- rule_value(rule, "MED", med)
        communities <- edit_communities(communities, rule)
    }
    list(route = learned_route(attribute, med, communities, local_pref, session$link), rule = rule)
}

candidate_routes <- function(simulation, owner, prefix) {
    routes <- list()
    for (session in simulation$routers[[as.character(owner)]]$sessions) {
        attribute <- session$incoming[[prefix]]
        if (!is.null(attribute)) {
            evaluated <- import_route(simulation, session, prefix, attribute)
            if (!is.null(evaluated$route)) routes[[length(routes) + 1L]] <- evaluated$route
        }
    }
    routes
}

advertised_content <- function(simulation, session, prefix) {
    owner <- session$owner
    link <- simulation$network$links[[session$link]]
    route <- simulation$routers[[as.character(owner)]]$rib[[prefix]]
    empty <- list(content = NULL, rule = NULL)
    if (is.null(route)) return(empty)
    if (!route_local(route) && route_neighbor(route) == other_end(link, owner)) return(empty)
    if (NO_EXPORT_COMMUNITY %in% route$communities) return(empty)
    rule <- applied_rule(simulation$policies, "EXPORT", owner, link, prefix, route$path, route$communities)
    if (rule_has(rule, "DENY")) return(list(content = NULL, rule = rule))
    allowed <- rule_has(rule, "ALLOW")
    if (!allowed && !route_local(route)) {
        learning_link <- simulation$network$links[[route$link]]
        if (link_role(
            learning_link,
            owner
        ) %in% c("peer", "provider") && link_role(link, owner) %in% c("peer", "provider")) return(list(
            content = NULL,
            rule = rule
        ))
    }
    prepend <- rule_value(rule, "PREPEND", 0L)
    med <- rule_value(rule, "MED", 0L)
    communities <- if (is.null(rule)) route$communities else edit_communities(route$communities, rule)
    list(
        content = bgp_attribute(c(rep(owner, 1L + prepend), route$path), route$origin, med, communities),
        rule = rule
    )
}

process_pending <- function(simulation, session) {
    sent <- 0L
    link <- simulation$network$links[[session$link]]
    for (prefix in prefix_order(session$pending)) {
        advertised <- advertised_content(simulation, session, prefix)
        content <- advertised$content
        rule <- advertised$rule
        if (identical(session$outgoing[[prefix]], content)) next
        if (is.null(content)) remove_key(session$outgoing, prefix) else session$outgoing[[prefix]] <- content
        message <- send_message(
            simulation$messages,
            simulation$time,
            session$owner,
            other_end(link, session$owner),
            link,
            prefix,
            content
        )
        suffix <- if (is.null(content)) "WITHDRAW" else paste("ANNOUNCE", attribute_text(content))
        log_update(simulation, paste("SEND", message_text(message, simulation$network), suffix))
        session$sent <- session$sent + 1L
        sent <- sent + 1L
        add_counter(simulation$period$counters, "updates")
        if (is.null(content)) add_counter(simulation$period$counters, "withdrawals")
        if (!is.null(rule)) rule$hits <- rule$hits + 1L
    }
    session$pending <- character()
    session$timer <- if (sent > 0L && link$mrai >= 1L) simulation$time + link$mrai else -1L
}

redecide <- function(simulation, owner, prefix) {
    router <- simulation$routers[[as.character(owner)]]
    route <- router$origination[[prefix]]
    if (is.null(route)) {
        candidates <- candidate_routes(simulation, owner, prefix)
        route <- if (length(candidates)) best_route(candidates, simulation$network)$route else NULL
    }
    if (identical(router$rib[[prefix]], route)) return(invisible(NULL))
    if (is.null(route)) remove_key(router$rib, prefix) else router$rib[[prefix]] <- route
    log_update(simulation, sprintf("BEST %d %s %s", owner, prefix, route_text(route, simulation$network)))
    router$changes <- router$changes + 1L
    add_counter(simulation$period$counters, "best_changes")
    add_counter(simulation$period$exploration, paste(owner, prefix))
    simulation$period$best_lines[[length(simulation$period$best_lines) + 1L]] <- list(
        time = simulation$time,
        owner = owner,
        prefix = prefix,
        route = route
    )
    simulation$changed_prefixes <- union(simulation$changed_prefixes, prefix)
    for (session in router$sessions) {
        if (simulation$network$links[[session$link]]$up) {
            session$pending <- union(session$pending, prefix)
            if (session$timer == -1L) process_pending(simulation, session)
        }
    }
}

receive_message <- function(simulation, message) {
    session <- simulation$by_session[[paste(message$receiver, message$link)]]
    prefix <- message$prefix
    content <- message$content
    session$received <- session$received + 1L
    simulation$period$convergence_time <- simulation$time - simulation$period$event$time
    if (is.null(content)) {
        remove_key(session$incoming, prefix)
        result <- "WITHDRAW"
    } else if (message$receiver %in% content$path) {
        remove_key(session$incoming, prefix)
        result <- "ANNOUNCE loop"
    } else {
        session$incoming[[prefix]] <- content
        evaluated <- import_route(simulation, session, prefix, content)
        rule <- evaluated$rule
        if (!is.null(rule)) rule$hits <- rule$hits + 1L
        result <- if (is.null(evaluated$route)) paste(
            "ANNOUNCE deny",
            rule$name
        ) else if (is.null(rule)) "ANNOUNCE accept" else paste(
            "ANNOUNCE accept",
            rule$name
        )
    }
    log_update(simulation, paste("RECV", message_text(message, simulation$network), result))
    redecide(simulation, message$receiver, prefix)
}

originate <- function(simulation, owner, prefix, origin, communities) {
    simulation$routers[[as.character(owner)]]$origination[[prefix]] <- originated_route(
        origin,
        parse_communities(communities)
    )
    redecide(simulation, owner, prefix)
}

link_down <- function(simulation, link) {
    link$up <- FALSE
    link$down_count <- link$down_count + 1L
    for (message in remove_link_messages(simulation$messages, link$number)) {
        log_update(simulation, paste("DROP", message_text(message, simulation$network)))
        add_counter(simulation$period$counters, "drops")
    }
    remembered <- list()
    endpoints <- sort(c(link$first, link$second))
    for (owner in endpoints) {
        session <- simulation$by_session[[paste(owner, link$number)]]
        remembered[[as.character(owner)]] <- prefix_order(map_keys(session$incoming))
        session$incoming <- new_map()
        session$outgoing <- new_map()
        session$pending <- character()
        session$timer <- -1L
    }
    for (owner in endpoints) for (prefix in remembered[[as.character(owner)]]) redecide(
        simulation,
        owner,
        prefix
    )
}

link_up <- function(simulation, link) {
    link$up <- TRUE
    for (owner in sort(c(link$first, link$second))) {
        session <- simulation$by_session[[paste(owner, link$number)]]
        session$pending <- map_keys(simulation$routers[[as.character(owner)]]$rib)
        process_pending(simulation, session)
    }
}

change_policy <- function(simulation, rule, active) {
    rule$active <- active
    router <- simulation$routers[[as.character(rule$owner)]]
    if (rule$direction == "IMPORT") {
        prefixes <- character()
        for (session in router$sessions) prefixes <- union(prefixes, map_keys(session$incoming))
        for (prefix in prefix_order(prefixes)) redecide(simulation, rule$owner, prefix)
    } else {
        for (session in router$sessions) {
            if (simulation$network$links[[session$link]]$up) {
                session$pending <- union(
                    session$pending,
                    union(map_keys(router$rib), map_keys(session$outgoing))
                )
                if (session$timer == -1L) process_pending(simulation, session)
            }
        }
    }
}

execute_event <- function(simulation, event) {
    log_update(simulation, sprintf("EVENT %d %s", simulation$period$number, event$text))
    fields <- event$fields
    if (event$kind == "INITIAL") {
        for (entry in simulation$network$initial) originate(
            simulation,
            entry$owner,
            entry$prefix,
            entry$origin,
            entry$communities
        )
    } else if (event$kind == "ANNOUNCE") {
        originate(simulation, as.integer(fields[2L]), fields[3L], fields[4L], fields[-(1:4)])
    } else if (event$kind == "WITHDRAW") {
        owner <- as.integer(fields[2L])
        prefix <- fields[3L]
        remove_key(simulation$routers[[as.character(owner)]]$origination, prefix)
        redecide(simulation, owner, prefix)
    } else if (event$kind %in% c("LINK_DOWN", "LINK_UP")) {
        link <- simulation$network$links[[simulation$network$by_name[[fields[3L]]]]]
        if (event$kind == "LINK_DOWN") link_down(simulation, link) else link_up(simulation, link)
    } else {
        change_policy(simulation, simulation$policies$rules[[fields[3L]]], event$kind == "POLICY_ON")
    }
}

global_state <- function(simulation) {
    table_state <- function(table) lapply(
        prefix_order(map_keys(table)),
        function(prefix) list(prefix = prefix, attribute = table[[prefix]])
    )
    sessions <- lapply(simulation$sessions, function(session) {
        list(
            incoming = table_state(session$incoming),
            outgoing = table_state(session$outgoing),
            pending = prefix_order(session$pending),
            timer = if (session$timer == -1L) -1L else session$timer - simulation$time
        )
    })
    messages <- lapply(ordered_messages(simulation$messages), function(message) {
        list(
            arrival = message$arrival - simulation$time,
            receiver = message$receiver,
            sender = message$sender,
            link = message$link,
            prefix = message$prefix,
            content = message$content
        )
    })
    serialize(list(sessions, messages), NULL, version = 2L)
}

detect_divergence <- function(simulation) {
    period <- simulation$period
    if (!is.null(period$divergence) || period$delivery_times > simulation$stepcap) return(invisible(NULL))
    state <- global_state(simulation)
    first_hash <- second_hash <- 0
    for (byte in as.integer(state)) {
        first_hash <- (257 * first_hash + byte) %% 2147483647
        second_hash <- (263 * second_hash + byte) %% 2147483629
    }
    key <- sprintf("%.0f:%.0f", first_hash, second_hash)
    bucket <- period$states[[key]]
    for (entry in bucket) {
        if (identical(entry$state, state)) {
            first <- entry$time
            cycle <- Filter(
                function(item) first < item$time && item$time <= simulation$time,
                period$best_lines
            )
            period$divergence <- list(first = first, repeat_time = simulation$time, cycle = cycle)
            return(invisible(NULL))
        }
    }
    period$states[[key]] <- c(bucket, list(list(state = state, time = simulation$time)))
}

quiet <- function(simulation) !length(simulation$messages$heap) && all(vapply(
    simulation$sessions,
    function(session) !length(session$pending),
    FALSE
))

run_period <- function(simulation, number, event, boundary) {
    period <- new.env(parent = emptyenv())
    period$number <- number
    period$event <- event
    period$before <- lapply(simulation$routers, function(router) as.list(router$rib))
    period$counters <- new_map()
    period$exploration <- new_map()
    period$best_lines <- list()
    period$convergence_time <- period$delivery_times <- 0L
    period$states <- new_map()
    period$divergence <- NULL
    period$status <- ""
    period$routes_changed <- 0L
    simulation$period <- period
    simulation$periods[[length(simulation$periods) + 1L]] <- period
    simulation$time <- event$time
    simulation$changed_prefixes <- character()
    execute_event(simulation, event)
    repeat {
        delivered <- FALSE
        repeat {
            arrival <- next_message_time(simulation$messages)
            if (is.null(arrival) || arrival != simulation$time) break
            receive_message(simulation, take_message(simulation$messages))
            delivered <- TRUE
        }
        for (session in simulation$sessions) {
            if (session$timer == simulation$time) {
                session$timer <- -1L
                if (length(session$pending)) process_pending(simulation, session)
            }
        }
        if (length(simulation$changed_prefixes)) forwarding_checks(simulation)
        if (delivered) {
            period$delivery_times <- period$delivery_times + 1L
            detect_divergence(simulation)
        }
        is_quiet <- quiet(simulation)
        if (is.null(boundary)) {
            if (is_quiet || !is.null(period$divergence) || period$delivery_times >= simulation$stepcap) break
        } else if (simulation$time == boundary) {
            break
        }
        moments <- vapply(simulation$sessions, function(session) session$timer, 0L)
        moments <- c(moments[moments >= 0L], next_message_time(simulation$messages), boundary)
        simulation$time <- min(moments)
        simulation$changed_prefixes <- character()
    }
    period$status <- if (!is.null(period$divergence)) "DIVERGENT" else if (quiet(simulation)) "CONVERGED" else if (is.null(boundary)) "CAPPED" else "UNSETTLED"
    for (owner in simulation$network$ases) {
        key <- as.character(owner)
        old <- period$before[[key]]
        current <- simulation$routers[[key]]$rib
        for (prefix in union(names(old), map_keys(current))) {
            if (!identical(
                old[[prefix]],
                current[[prefix]]
            )) period$routes_changed <- period$routes_changed + 1L
        }
    }
    period$states <- NULL
}

trace_path <- function(simulation, source, address) {
    visits <- source
    hops <- list()
    owner <- source
    finish <- function(result, arrival = 0L) list(
        result = result,
        visits = visits,
        hops = hops,
        count = sum(vapply(hops, function(hop) hop$link != 0L, FALSE)),
        arrival = arrival
    )
    repeat {
        router <- simulation$routers[[as.character(owner)]]
        matches <- Filter(
            function(prefix) prefix_contains(parse_prefix(prefix), address),
            map_keys(router$rib)
        )
        if (!length(matches)) return(finish(if (!length(hops)) "UNREACHABLE" else "BLACKHOLE"))
        prefix <- matches[which.max(vapply(matches, function(prefix) parse_prefix(prefix)$length, 0L))]
        route <- router$rib[[prefix]]
        if (route_local(route)) {
            hops[[length(hops) + 1L]] <- list(owner = owner, prefix = prefix, link = 0L)
            return(finish("DELIVERED", owner))
        }
        hops[[length(hops) + 1L]] <- list(owner = owner, prefix = prefix, link = route$link)
        owner <- other_end(simulation$network$links[[route$link]], owner)
        repeated <- owner %in% visits
        visits <- c(visits, owner)
        if (repeated) return(finish("LOOP"))
    }
}

prefix_loops <- function(simulation, prefix) {
    arrows <- new_map()
    for (owner in simulation$network$ases) {
        route <- simulation$routers[[as.character(owner)]]$rib[[prefix]]
        if (!is.null(route) && !route_local(route)) arrows[[as.character(owner)]] <- other_end(
            simulation$network$links[[route$link]],
            owner
        )
    }
    finished <- integer()
    loops <- list()
    for (start in simulation$network$ases) {
        if (start %in% finished) next
        path <- integer()
        current <- start
        while (exists(
            as.character(current),
            arrows,
            inherits = FALSE
        ) && !current %in% finished && !current %in% path) {
            path <- c(path, current)
            current <- arrows[[as.character(current)]]
        }
        if (current %in% path) {
            cycle <- path[match(current, path):length(path)]
            first <- which.min(cycle)
            cycle <- c(cycle[first:length(cycle)], if (first > 1L) cycle[seq_len(first - 1L)] else integer())
            loops[[path_text(cycle)]] <- cycle
        }
        finished <- union(finished, path)
    }
    loops
}

forwarding_checks <- function(simulation) {
    for (prefix in prefix_order(simulation$changed_prefixes)) {
        loops <- prefix_loops(simulation, prefix)
        for (key in map_keys(simulation$ongoing_rings)) {
            record <- simulation$ongoing_rings[[key]]
            if (record$prefix == prefix && !path_text(record$path) %in% names(loops)) {
                record$end_time <- simulation$time
                remove_key(simulation$ongoing_rings, key)
            }
        }
        if (length(loops)) loops <- loops[order(vapply(loops, function(loop) loop[1L], 0L))]
        for (loop in loops) {
            key <- paste(prefix, path_text(loop))
            if (!exists(key, simulation$ongoing_rings, inherits = FALSE)) {
                record <- new.env(parent = emptyenv())
                record$prefix <- prefix
                record$path <- loop
                record$start <- simulation$time
                record$end_time <- -1L
                simulation$ring_records[[length(simulation$ring_records) + 1L]] <- record
                simulation$ongoing_rings[[key]] <- record
            }
        }
    }
    for (index in seq_along(simulation$traces)) {
        trace <- simulation$traces[[index]]
        path <- trace_path(simulation, trace$source, trace$value)
        bad <- path$result %in% c("LOOP", "BLACKHOLE")
        key <- as.character(index)
        record <- simulation$ongoing_traces[[key]]
        if (!is.null(record) && (!bad || record$result != path$result || !identical(
            record$visits,
            path$visits
        ))) {
            record$end_time <- simulation$time
            remove_key(simulation$ongoing_traces, key)
        }
        if (bad && !exists(key, simulation$ongoing_traces, inherits = FALSE)) {
            record <- new.env(parent = emptyenv())
            record$index <- index
            record$result <- path$result
            record$visits <- path$visits
            record$start <- simulation$time
            record$end_time <- -1L
            simulation$trace_records[[length(simulation$trace_records) + 1L]] <- record
            simulation$ongoing_traces[[key]] <- record
        }
    }
}

period_csv <- function(period) {
    exploration <- unlist(as.list(period$exploration), use.names = FALSE)
    values <- c(
        period$number,
        period$event$time,
        period$event$kind,
        period$status,
        period$convergence_time,
        vapply(
            c("updates", "withdrawals", "drops", "best_changes"),
            function(name) get_counter(period$counters, name),
            0L
        ),
        period$routes_changed,
        if (length(exploration)) max(exploration) else 0L
    )
    paste(values, collapse = ",")
}

rib_lines <- function(simulation) {
    lines <- character()
    for (owner in simulation$network$ases) {
        router <- simulation$routers[[as.character(owner)]]
        local <- sum(vapply(as.list(router$rib), route_local, FALSE))
        sent <- sum(vapply(router$sessions, function(session) session$sent, 0L))
        received <- sum(vapply(router$sessions, function(session) session$received, 0L))
        lines <- c(
            lines,
            sprintf(
                "AS %d routes %d local %d sent %d received %d changes %d",
                owner,
                length(map_keys(router$rib)),
                local,
                sent,
                received,
                router$changes
            )
        )
        for (session in router$sessions) {
            accepted <- sum(vapply(
                map_keys(session$incoming),
                function(prefix) !is.null(import_route(
                    simulation,
                    session,
                    prefix,
                    session$incoming[[prefix]]
                )$route),
                FALSE
            ))
            link <- simulation$network$links[[session$link]]
            lines <- c(
                lines,
                sprintf(
                    "SESSION %s %d %s %s in %d accepted %d out %d sent %d received %d flaps %d",
                    link$name,
                    other_end(link, owner),
                    link_role(link, owner),
                    if (link$up) "UP" else "DOWN",
                    length(map_keys(session$incoming)),
                    accepted,
                    length(map_keys(session$outgoing)),
                    session$sent,
                    session$received,
                    link$down_count
                )
            )
        }
        for (prefix in prefix_order(map_keys(router$rib))) {
            route <- router$rib[[prefix]]
            candidates <- candidate_routes(simulation, owner, prefix)
            line <- sprintf(
                "%s %s candidates %d",
                prefix,
                route_text(route, simulation$network),
                length(candidates)
            )
            if (!route_local(route)) line <- paste(
                line,
                "reason",
                best_route(candidates, simulation$network)$reason
            )
            lines <- c(lines, line)
            remaining <- Filter(function(candidate) !identical(candidate, route), candidates)
            while (length(remaining)) {
                alternate <- best_route(remaining, simulation$network)$route
                lines <- c(lines, paste("ALT", route_text(alternate, simulation$network)))
                remove <- which(vapply(
                    remaining,
                    function(candidate) identical(candidate, alternate),
                    FALSE
                ))[1L]
                remaining <- remaining[-remove]
            }
        }
    }
    lines
}

trace_lines <- function(simulation, source, address, value) {
    path <- trace_path(simulation, source, value)
    lines <- sprintf("TRACE %d %s %s hops %d", source, address, path$result, path$count)
    for (hop in path$hops) {
        beginning <- sprintf("HOP %d %s", hop$owner, hop$prefix)
        if (hop$link == 0L) lines <- c(lines, paste(beginning, "LOCAL")) else {
            link <- simulation$network$links[[hop$link]]
            lines <- c(lines, sprintf("%s next %d link %s", beginning, other_end(link, hop$owner), link$name))
        }
    }
    if (path$result == "LOOP") lines <- c(lines, sprintf("HOP %d REVISIT", tail(path$visits, 1L)))
    if (path$result %in% c("BLACKHOLE", "UNREACHABLE")) lines <- c(
        lines,
        sprintf("HOP %d NOROUTE", tail(path$visits, 1L))
    )
    if (!length(path$hops)) {
        lines <- c(lines, "CONTROL NONE")
    } else {
        route <- simulation$routers[[as.character(source)]]$rib[[path$hops[[1L]]$prefix]]
        notation <- if (route_local(route)) "LOCAL" else path_text(route$path)
        match <- path$result == "DELIVERED" && identical(collapse_runs(route$path), path$visits[-1L])
        lines <- c(lines, paste("CONTROL", notation, if (match) "MATCH" else "MISMATCH"))
    }
    if (path$count > 0L) {
        pattern <- paste0(
            vapply(
                Filter(function(hop) hop$link != 0L, path$hops),
                function(hop) link_direction(simulation$network$links[[hop$link]], hop$owner),
                ""
            ),
            collapse = ""
        )
        lines <- c(
            lines,
            paste(
                "PATTERN",
                pattern,
                if (valley_position(pattern) == nchar(pattern)) "VALLEYFREE" else "VALLEY"
            )
        )
    }
    lines
}

path_lines <- function(simulation) {
    lines <- character()
    for (trace in simulation$traces) lines <- c(
        lines,
        trace_lines(simulation, trace$source, trace$address, trace$value)
    )
    originated <- character()
    for (router in simulation$routers) originated <- union(originated, map_keys(router$origination))
    prefixes <- prefix_order(originated)
    lines <- c(
        lines,
        paste0("PREFIXES", if (length(prefixes)) paste0(" ", paste(prefixes, collapse = ",")) else "")
    )
    for (source in simulation$network$ases) {
        symbols <- character()
        for (prefix in prefixes) {
            path <- trace_path(simulation, source, parse_prefix(prefix)$address)
            if (path$result == "DELIVERED") {
                symbol <- if (path$count == 0L) "*" else if (exists(
                    prefix,
                    simulation$routers[[as.character(path$arrival)]]$origination,
                    inherits = FALSE
                )) "+" else "X"
            } else {
                symbol <- c(LOOP = "L", BLACKHOLE = "B", UNREACHABLE = "U")[[path$result]]
            }
            symbols <- c(symbols, symbol)
        }
        lines <- c(
            lines,
            paste0("REACH ", source, if (length(symbols)) paste0(" ", paste0(symbols, collapse = "")) else "")
        )
    }
    lines
}

audit_lines <- function(simulation) {
    lines <- character()
    loops <- blackholes <- 0L
    records <- simulation$trace_records
    if (length(records)) records <- records[order(
        vapply(records, function(record) record$start, 0L),
        vapply(records, function(record) record$index, 0L)
    )]
    for (record in records) {
        trace <- simulation$traces[[record$index]]
        if (record$result == "LOOP") loops <- loops + 1L else blackholes <- blackholes + 1L
        endpoint <- if (record$end_time == -1L) "END" else as.character(record$end_time)
        line <- sprintf(
            "%s %d %s from %d to %s",
            record$result,
            trace$source,
            trace$address,
            record$start,
            endpoint
        )
        if (record$result == "BLACKHOLE") line <- paste(line, "at", tail(record$visits, 1L))
        lines <- c(lines, paste(line, "path", path_text(record$visits)))
    }
    rings <- simulation$ring_records
    if (length(rings)) {
        prefix_values <- lapply(rings, function(record) parse_prefix(record$prefix))
        rings <- rings[order(
            vapply(rings, function(record) record$start, 0L),
            vapply(prefix_values, function(prefix) prefix$address, 0),
            vapply(prefix_values, function(prefix) prefix$length, 0L),
            vapply(rings, function(record) record$path[1L], 0L)
        )]
    }
    for (record in rings) lines <- c(
        lines,
        sprintf(
            "RING %s from %d to %s path %s",
            record$prefix,
            record$start,
            if (record$end_time == -1L) "END" else as.character(record$end_time),
            path_text(record$path)
        )
    )
    route_count <- valleys <- 0L
    for (owner in simulation$network$ases) {
        router <- simulation$routers[[as.character(owner)]]
        for (prefix in prefix_order(map_keys(router$rib))) {
            route <- router$rib[[prefix]]
            if (route_local(route)) next
            route_count <- route_count + 1L
            path <- collapse_runs(c(owner, route$path))
            pattern <- paste0(vapply(seq_len(length(path) - 1L), function(index) {
                key <- paste(sort(path[index:(index + 1L)]), collapse = ":")
                link <- simulation$network$links[[simulation$network$between[[key]][1L]]]
                link_direction(link, path[index])
            }, ""), collapse = "")
            violation <- valley_position(pattern)
            if (violation != nchar(pattern)) {
                valleys <- valleys + 1L
                lines <- c(
                    lines,
                    sprintf(
                        "VALLEY %d %s path %s pattern %s leaker %d",
                        owner,
                        prefix,
                        path_text(route$path),
                        pattern,
                        path[violation + 1L]
                    )
                )
            }
        }
    }
    for (rule in simulation$policies$rules) lines <- c(
        lines,
        sprintf(
            "RULE %s %s %s hits %d",
            rule$name,
            rule$direction,
            if (rule$active) "ON" else "OFF",
            rule$hits
        )
    )
    divergent <- 0L
    for (period in simulation$periods) {
        divergence <- period$divergence
        if (is.null(divergence)) next
        divergent <- divergent + 1L
        lines <- c(
            lines,
            sprintf(
                "DIVERGENT event %d first %d repeat %d period %d",
                period$number,
                divergence$first,
                divergence$repeat_time,
                divergence$repeat_time - divergence$first
            )
        )
        oscillations <- new_map()
        pairs <- list()
        for (entry in divergence$cycle) {
            lines <- c(
                lines,
                sprintf(
                    "CYCLE %d %d %s %s",
                    entry$time,
                    entry$owner,
                    entry$prefix,
                    route_text(entry$route, simulation$network)
                )
            )
            key <- paste(entry$owner, entry$prefix)
            if (!exists(key, oscillations, inherits = FALSE)) pairs[[key]] <- list(
                owner = entry$owner,
                prefix = entry$prefix
            )
            add_counter(oscillations, key)
        }
        if (length(pairs)) {
            prefixes <- lapply(pairs, function(pair) parse_prefix(pair$prefix))
            pairs <- pairs[order(
                vapply(pairs, function(pair) pair$owner, 0L),
                vapply(prefixes, function(prefix) prefix$address, 0),
                vapply(prefixes, function(prefix) prefix$length, 0L)
            )]
        }
        for (pair in pairs) lines <- c(
            lines,
            sprintf(
                "OSCILLATE %d %s changes %d",
                pair$owner,
                pair$prefix,
                get_counter(oscillations, paste(pair$owner, pair$prefix))
            )
        )
    }
    c(
        lines,
        sprintf(
            "SUMMARY loops %d blackholes %d rings %d routes %d valleys %d divergent %d end %d",
            loops,
            blackholes,
            length(rings),
            route_count,
            valleys,
            divergent,
            simulation$time
        )
    )
}

main <- function() {
    network <- read_topology()
    policies <- read_policies()
    events <- read_events()
    params <- read_params()
    simulation <- new_simulation(network, policies, params$defaults, params$stepcap, params$traces)
    for (index in seq_along(events)) {
        boundary <- if (index < length(events)) events[[index + 1L]]$time - 1L else NULL
        run_period(simulation, index - 1L, events[[index]], boundary)
    }
    write_reports(list(
        updates.txt = simulation$logs,
        convergence.csv = c(CONVERGENCE_HEADER, vapply(simulation$periods, period_csv, "")),
        ribs.txt = rib_lines(simulation),
        paths.txt = path_lines(simulation),
        audit.txt = audit_lines(simulation)
    ))
}

main()
