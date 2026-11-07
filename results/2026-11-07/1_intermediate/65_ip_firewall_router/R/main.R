object <- function(...) list2env(list(...), parent = emptyenv())
interfaces <- list()
routes <- list()
static_nat <- list()
forwards <- list()
pat <- list()
connections <- list()
timeouts <- c(TCP = 300, UDP = 60, ICMP = 30)
clock <- 0
packet_number <- 0
connection_number <- 0
drop_reasons <- c("down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted")
counts <- setNames(rep(0, length(drop_reasons) + 3), c(drop_reasons, "forwarded", "local", "errors"))
emit <- function(...) cat(paste0(...), "\n", sep = "")
fmt <- function(number) sprintf("%.0f", number)
fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("router_error", "error", "condition")))
find_item <- function(items, predicate) {
    for (item in items) if (predicate(item)) return(item)
    NULL
}
tuple_equal <- function(left, right) {
    length(left) == length(right) && all(mapply(function(a, b) a == b, left, right))
}
address <- function(word) {
    if (!grepl("^(0|[1-9][0-9]{0,2})(\\.(0|[1-9][0-9]{0,2})){3}$", word)) fail(paste0("bad address ", word))
    parts <- as.numeric(strsplit(word, ".", fixed = TRUE)[[1]])
    if (any(parts > 255)) fail(paste0("bad address ", word))
    sum(parts * 256^(3:0))
}
ip <- function(number) paste(floor(number / 256^(3:0)) %% 256, collapse = ".")
network <- function(number, length) floor(number / 2^(32 - length)) * 2^(32 - length)
parse_prefix <- function(word, hosts = FALSE) {
    parts <- strsplit(paste0(word, "!"), "/", fixed = TRUE)[[1]]
    parts[length(parts)] <- sub("!$", "", parts[length(parts)])
    parsed <- tryCatch({
        if (length(parts) != 2 || !grepl("^(0|[1-9][0-9]?)$", parts[2]) || as.numeric(parts[2]) > 32) fail("invalid")
        c(address(parts[1]), as.numeric(parts[2]))
    }, router_error = function(e) NULL)
    if (is.null(parsed)) fail(paste0("bad prefix ", word))
    if (!hosts && parsed[1] != network(parsed[1], parsed[2])) fail(paste0("host bits set in ", word))
    parsed
}
contains <- function(prefix, number) network(prefix[1], prefix[2]) == network(number, prefix[2])
iface <- function(name) {
    if (!(name %in% names(interfaces))) fail(paste0("no interface ", name))
    interfaces[[name]]
}
local_name <- function(number) {
    for (name in names(interfaces)) if (interfaces[[name]]$address == number) return(name)
    NULL
}
select_route <- function(number) {
    best <- NULL
    for (item in routes) {
        if (interfaces[[item$dev]]$up && contains(item$prefix, number) &&
            (is.null(best) || item$prefix[2] > best$prefix[2] || (item$prefix[2] == best$prefix[2] && item$metric < best$metric))) best <- item
    }
    best
}
route_text <- function(item) {
    paste0(item$type, " ", ip(item$prefix[1]), "/", item$prefix[2],
           if (!is.null(item$hop)) paste0(" via ", ip(item$hop)) else "", " dev ", item$dev, " metric ", item$metric)
}
port_range <- function(word) {
    if (word == "ANY") return(list(low = 0, high = 65535, any = TRUE))
    parts <- as.numeric(strsplit(word, "-", fixed = TRUE)[[1]])
    low <- parts[1]
    high <- parts[length(parts)]
    if (low > 65535 || high > 65535 || low > high) fail(paste0("bad port range ", word))
    list(low = low, high = high, any = FALSE)
}
range_text <- function(range) {
    if (range$any) "any" else if (range$low == range$high) fmt(range$low) else paste0(range$low, "-", range$high)
}
acl_prefix <- function(word) if (word == "ANY") c(0, 0) else parse_prefix(word)
prefix_text <- function(prefix) if (prefix[2] == 0) "any" else paste0(ip(prefix[1]), "/", prefix[2])
evaluate_acl <- function(name, direction, protocol, source, sport, destination, dport, established) {
    pair <- interfaces[[name]]$acl[[direction]]
    if (!length(pair$rules)) return(NULL)
    rules <- pair$rules[order(vapply(pair$rules, function(rule) rule$seq, numeric(1)))]
    for (rule in rules) {
        if (!(rule$proto %in% c("ANY", protocol)) || !contains(rule$src, source) || !contains(rule$dst, destination) ||
            (rule$proto %in% c("TCP", "UDP") && (sport < rule$sports$low || sport > rule$sports$high || dport < rule$dports$low || dport > rule$dports$high)) ||
            (rule$established && !established)) next
        rule$hits <- rule$hits + 1
        if (rule$action == "PERMIT") return(NULL)
        if (rule$action == "DENY") return(paste0("DROP acl ", name, " ", direction, " ", rule$seq))
        return(paste0("REJECT acl ", name, " ", direction, " ", rule$seq, " ", if (protocol == "TCP") "tcp-reset" else "icmp-prohibited"))
    }
    pair$default <- pair$default + 1
    paste0("DROP acl ", name, " ", direction, " default")
}
packet <- function(name, protocol, flags, source, sport, destination, dport, ttl) {
    input <- interfaces[[name]]
    if (!input$up) return(c("DROP down", "down"))
    for (number in c(source, destination)) {
        if (contains(c(0, 8), number) || contains(c(127 * 2^24, 8), number) || contains(c(224 * 2^24, 3), number)) return(c("DROP martian", "martian"))
    }
    if (!is.null(local_name(source))) return(c("DROP martian", "martian"))
    if (input$rpf != "off") {
        reverse <- select_route(source)
        if (is.null(reverse) || (input$rpf == "strict" && reverse$dev != name)) return(c("DROP rpf", "rpf"))
    }
    tuple <- list(protocol, source, sport, destination, dport)
    pure_syn <- protocol == "TCP" && flags == "S"
    connection <- find_item(connections, function(item) tuple_equal(item$orig, tuple) || tuple_equal(item$reply, tuple))
    direction <- if (is.null(connection)) NULL else if (tuple_equal(connection$orig, tuple)) "orig" else "reply"
    if (!is.null(connection) && connection$state == "CLOSED" && pure_syn) {
        connections <<- Filter(function(item) !identical(item, connection), connections)
        connection <- NULL
    }
    if (protocol == "TCP" && is.null(connection) && !pure_syn) return(c("DROP invalid", "invalid"))
    verdict <- evaluate_acl(name, "in", protocol, source, sport, destination, dport, !is.null(connection))
    if (!is.null(verdict)) return(c(verdict, "acl_in"))
    translated_destination <- destination
    translated_dport <- dport
    mapping <- NULL
    if (input$role == "outside") {
        static <- find_item(static_nat, function(item) item$outside == destination)
        forward <- if (destination == input$address) find_item(forwards, function(item) item$dev == name && item$proto == protocol && item$port == dport) else NULL
        if (!is.null(static)) {
            translated_destination <- static$inside
        } else if (!is.null(forward)) {
            translated_destination <- forward$inside
            translated_dport <- forward$inport
        } else if (destination == input$address) {
            mapping <- find_item(pat, function(item) item$dev == name && item$proto == protocol && item$port == dport)
            if (!is.null(mapping)) {
                translated_destination <- mapping$inside
                translated_dport <- mapping$inport
            }
        }
    }
    local <- local_name(translated_destination)
    if (!is.null(local)) return(c(paste0("LOCAL ", local), "local"))
    if (ttl == 1) return(c("DROP ttl", "ttl"))
    selected <- select_route(translated_destination)
    if (is.null(selected)) return(c("DROP noroute", "noroute"))
    output_name <- selected$dev
    output <- interfaces[[output_name]]
    verdict <- evaluate_acl(output_name, "out", protocol, source, sport, translated_destination, translated_dport, !is.null(connection))
    if (!is.null(verdict)) return(c(verdict, "acl_out"))
    translated_source <- source
    translated_sport <- sport
    if (input$role == "inside" && output$role == "outside") {
        static <- find_item(static_nat, function(item) item$inside == source)
        forward <- find_item(forwards, function(item) item$dev == output_name && item$proto == protocol && item$inside == source && item$inport == sport)
        if (!is.null(static)) {
            translated_source <- static$outside
        } else if (!is.null(forward)) {
            translated_source <- output$address
            translated_sport <- forward$port
        } else if (!is.null(output$pool)) {
            mapping <- find_item(pat, function(item) item$dev == output_name && item$proto == protocol && item$inside == source && item$inport == sport)
            if (is.null(mapping)) {
                used <- vapply(Filter(function(item) item$dev == output_name, c(pat, forwards)), function(item) item$port, numeric(1))
                available <- setdiff(seq(20000, 19999 + output$pool), used)
                if (!length(available)) return(c("DROP exhausted", "exhausted"))
                mapping <- object(dev = output_name, proto = protocol, inside = source, inport = sport, port = available[1], last = clock)
                pat[[length(pat) + 1]] <<- mapping
            }
            translated_source <- output$address
            translated_sport <- mapping$port
        }
    }
    if (!is.null(mapping)) mapping$last <- clock
    if (is.null(connection)) {
        connection_number <<- connection_number + 1
        connection <- object(number = connection_number, proto = protocol, orig = tuple,
                             reply = list(protocol, translated_destination, translated_dport, translated_source, translated_sport),
                             input = name, output = output_name, state = if (protocol == "TCP") "SYN_SENT" else "UNREPLIED",
                             orig_packets = 0, reply_packets = 0, orig_fin = FALSE, reply_fin = FALSE, last = clock)
        connections[[length(connections) + 1]] <<- connection
        direction <- "new"
    }
    side <- if (direction == "reply") "reply" else "orig"
    packet_field <- paste0(side, "_packets")
    connection[[packet_field]] <- connection[[packet_field]] + 1
    connection$last <- clock
    if (protocol != "TCP") {
        if (direction == "reply") connection$state <- "REPLIED"
    } else if (grepl("R", flags, fixed = TRUE)) {
        connection$state <- "CLOSED"
    } else {
        if (connection$state == "SYN_SENT" && direction == "reply" && grepl("S", flags, fixed = TRUE) && grepl("A", flags, fixed = TRUE)) connection$state <- "ESTABLISHED"
        if (grepl("F", flags, fixed = TRUE) && connection$state %in% c("ESTABLISHED", "FIN_WAIT")) {
            connection[[paste0(side, "_fin")]] <- TRUE
            connection$state <- if (connection$orig_fin && connection$reply_fin) "CLOSED" else "FIN_WAIT"
        }
    }
    output$tx <- output$tx + 1
    selected$hits <- selected$hits + 1
    next_hop <- if (is.null(selected$hop)) "direct" else paste0("via ", ip(selected$hop))
    text <- paste0("FORWARD ", output_name, " ", next_hop, " ttl=", ttl - 1)
    if (translated_destination != destination || translated_dport != dport) text <- paste0(text, " dnat=", ip(translated_destination), ":", translated_dport)
    if (translated_source != source || translated_sport != sport) text <- paste0(text, " snat=", ip(translated_source), ":", translated_sport)
    c(paste0(text, " conn=", connection$number, " ", direction), "forwarded")
}
reset_counters <- function() {
    counts[] <<- 0
    for (item in interfaces) {
        item$rx <- 0
        item$tx <- 0
        item$drop <- 0
        for (pair in item$acl) {
            pair$default <- 0
            for (rule in pair$rules) rule$hits <- 0
        }
    }
    for (item in routes) item$hits <- 0
}
show_state <- function(what) {
    sorted_names <- sort(names(interfaces), method = "radix")
    if (what == "IFACES") {
        emit("show ifaces count=", length(interfaces))
        for (name in sorted_names) {
            item <- interfaces[[name]]
            text <- paste0(name, " ", ip(item$address), "/", item$length, " ", if (item$up) "up" else "down", " ", item$role, " rpf=", item$rpf)
            if (!is.null(item$pool)) text <- paste0(text, " pat=", sum(vapply(pat, function(mapping) mapping$dev == name, logical(1))), "/", item$pool)
            emit(text)
        }
    } else if (what == "ROUTES") {
        emit("show routes count=", length(routes))
        ordering <- order(vapply(routes, function(item) item$prefix[1], numeric(1)), vapply(routes, function(item) item$prefix[2], numeric(1)), vapply(routes, function(item) item$metric, numeric(1)), seq_along(routes), method = "radix")
        for (item in routes[ordering]) emit(route_text(item), " hits=", item$hits, if (!interfaces[[item$dev]]$up) " inactive" else "")
    } else if (what == "ACL") {
        total <- sum(vapply(interfaces, function(item) sum(vapply(item$acl, function(pair) length(pair$rules), integer(1))), numeric(1)))
        emit("show acl count=", total)
        for (name in sorted_names) {
            for (direction in c("in", "out")) {
                pair <- interfaces[[name]]$acl[[direction]]
                if (!length(pair$rules)) next
                ordering <- order(vapply(pair$rules, function(rule) rule$seq, numeric(1)))
                for (rule in pair$rules[ordering]) emit("acl ", name, " ", direction, " ", rule$seq, " ", rule$action, " ", rule$proto, " ", prefix_text(rule$src), " ", range_text(rule$sports), " ", prefix_text(rule$dst), " ", range_text(rule$dports), if (rule$established) " established" else "", " hits=", rule$hits)
                emit("acl ", name, " ", direction, " default DENY hits=", pair$default)
            }
        }
    } else if (what == "NAT") {
        emit("show nat static=", length(static_nat), " forward=", length(forwards), " pat=", length(pat))
        for (item in static_nat[order(vapply(static_nat, function(item) item$inside, numeric(1)))]) emit("static ", ip(item$inside), " ", ip(item$outside))
        ordering <- order(vapply(forwards, function(item) item$dev, character(1)), vapply(forwards, function(item) item$port, numeric(1)), vapply(forwards, function(item) item$proto, character(1)), method = "radix")
        for (item in forwards[ordering]) emit("forward ", item$dev, " ", item$proto, " ", item$port, " ", ip(item$inside), ":", item$inport)
        ordering <- order(vapply(pat, function(item) item$dev, character(1)), vapply(pat, function(item) item$port, numeric(1)), method = "radix")
        for (item in pat[ordering]) emit("pat ", item$dev, " ", item$port, " ", item$proto, " ", ip(item$inside), ":", item$inport, " idle=", fmt(clock - item$last))
    } else if (what == "CONNS") {
        emit("show conns count=", length(connections))
        for (item in connections) {
            original <- item$orig
            reply <- item$reply
            emit("conn ", item$number, " ", item$proto, " ", ip(original[[2]]), ":", original[[3]], " > ", ip(original[[4]]), ":", original[[5]], " reply ", ip(reply[[2]]), ":", reply[[3]], " > ", ip(reply[[4]]), ":", reply[[5]], " in=", item$input, " out=", item$output, " state=", item$state, " pkts=", item$orig_packets, "/", item$reply_packets, " idle=", fmt(clock - item$last))
        }
    } else if (what == "COUNTERS") {
        dropped <- sum(counts[drop_reasons])
        emit("show counters packets=", counts["forwarded"] + counts["local"] + dropped, " forwarded=", counts["forwarded"], " local=", counts["local"], " dropped=", dropped, " errors=", counts["errors"])
        emit("drops ", paste(paste0(drop_reasons, "=", counts[drop_reasons]), collapse = " "))
        for (name in sorted_names) {
            item <- interfaces[[name]]
            emit("iface ", name, " rx=", item$rx, " tx=", item$tx, " drop=", item$drop)
        }
    }
}
command <- function(words) {
    kind <- words[1]
    a <- words[-1]
    name <- a[1]
    if (kind == "IFACE") {
        if (name %in% names(interfaces)) fail(paste0("duplicate interface ", name))
        prefix <- parse_prefix(a[2], TRUE)
        number <- prefix[1]
        length <- prefix[2]
        if (length < 8 || length > 30) fail(paste0("bad prefix ", a[2]))
        base <- network(number, length)
        if (number == base || number == base + 2^(32 - length) - 1) fail(paste0("bad host address ", a[2]))
        for (other in names(interfaces)) {
            item <- interfaces[[other]]
            common <- min(length, item$length)
            if (network(number, common) == network(item$address, common)) fail(paste0("subnet overlaps ", other))
        }
        interfaces[[name]] <<- object(address = number, length = length, up = TRUE, role = "inside", pool = NULL, rpf = "off", rx = 0, tx = 0, drop = 0,
                                     acl = list("in" = object(rules = list(), default = 0), "out" = object(rules = list(), default = 0)))
        routes[[length(routes) + 1]] <<- object(type = "C", prefix = c(base, length), dev = name, hop = NULL, metric = 0, hits = 0)
        emit("ok iface ", name, " ", a[2], " network ", ip(base), "/", length)
    } else if (kind %in% c("UP", "DOWN")) {
        item <- iface(name)
        state <- kind == "UP"
        if (item$up == state) fail(paste0("interface ", name, " already ", if (state) "up" else "down"))
        item$up <- state
        emit("ok ", tolower(kind), " ", name)
    } else if (kind == "ROUTE") {
        prefix <- parse_prefix(name)
        via <- a[2] == "VIA"
        hop <- if (via) address(a[3]) else NULL
        if (!via) iface(a[3])
        metric <- as.numeric(a[4])
        if (metric < 1 || metric > 255) fail(paste0("bad metric ", a[4]))
        output <- a[3]
        if (via) {
            if (!is.null(local_name(hop))) fail(paste0("nexthop ", a[3], " is local"))
            output <- NULL
            for (key in names(interfaces)) {
                item <- interfaces[[key]]
                if (contains(c(item$address, item$length), hop)) output <- key
            }
            if (is.null(output)) fail(paste0("nexthop ", a[3], " unreachable"))
        }
        if (!is.null(find_item(routes, function(item) item$type == "S" && identical(item$prefix, prefix) && item$dev == output && identical(item$hop, hop)))) fail(paste0("duplicate route ", name))
        item <- object(type = "S", prefix = prefix, dev = output, hop = hop, metric = metric, hits = 0)
        routes[[length(routes) + 1]] <<- item
        emit("ok route ", route_text(item))
    } else if (kind == "NOROUTE") {
        prefix <- parse_prefix(name)
        remaining <- Filter(function(item) !(item$type == "S" && identical(item$prefix, prefix)), routes)
        removed <- length(routes) - length(remaining)
        if (removed == 0) fail(paste0("no static route ", name))
        routes <<- remaining
        emit("ok noroute ", name, " removed=", removed)
    } else if (kind == "LOOKUP") {
        selected <- select_route(address(name))
        emit("lookup ", name, " ", if (is.null(selected)) "none" else route_text(selected))
    } else if (kind == "ACL") {
        item <- iface(name)
        direction <- tolower(a[2])
        sequence <- as.numeric(a[3])
        if (sequence < 1 || sequence > 9999) fail(paste0("bad sequence ", a[3]))
        source <- acl_prefix(a[6])
        sports <- port_range(a[7])
        destination <- acl_prefix(a[8])
        dports <- port_range(a[9])
        if (a[5] %in% c("ICMP", "ANY") && (a[7] != "ANY" || a[9] != "ANY")) fail(paste0("ports not allowed for ", a[5]))
        pair <- item$acl[[direction]]
        if (!is.null(find_item(pair$rules, function(rule) rule$seq == sequence))) fail(paste0("duplicate sequence ", a[3]))
        pair$rules[[length(pair$rules) + 1]] <- object(seq = sequence, action = a[4], proto = a[5], src = source, sports = sports, dst = destination, dports = dports, established = length(a) == 10, hits = 0)
        emit("ok acl ", name, " ", direction, " ", sequence)
    } else if (kind == "NOACL") {
        pair <- iface(name)$acl[[tolower(a[2])]]
        rule <- find_item(pair$rules, function(item) item$seq == as.numeric(a[3]))
        direction <- tolower(a[2])
        if (is.null(rule)) fail(paste0("no rule ", a[3], " on ", name, " ", direction))
        pair$rules <- Filter(function(item) !identical(item, rule), pair$rules)
        emit("ok noacl ", name, " ", direction, " ", a[3], " hits=", rule$hits)
    } else if (kind == "NAT") {
        if (name == "STATIC") {
            inside <- address(a[2])
            outside <- address(a[3])
            if (!is.null(local_name(inside))) fail(paste0("address ", a[2], " is local"))
            if (!is.null(local_name(outside))) fail(paste0("address ", a[3], " is local"))
            if (!is.null(find_item(static_nat, function(item) item$inside == inside))) fail(paste0("duplicate static ", a[2]))
            if (!is.null(find_item(static_nat, function(item) item$outside == outside))) fail(paste0("duplicate static ", a[3]))
            static_nat[[length(static_nat) + 1]] <<- object(inside = inside, outside = outside)
            emit("ok nat static ", a[2], " ", a[3])
        } else if (name == "OUTSIDE") {
            item <- iface(a[2])
            if (item$role == "outside") fail(paste0("interface ", a[2], " already outside"))
            item$role <- "outside"
            emit("ok nat outside ", a[2])
        } else if (name == "PAT") {
            item <- iface(a[2])
            count <- as.numeric(a[3])
            if (count < 1 || count > 1000) fail(paste0("bad pool size ", a[3]))
            if (!is.null(item$pool)) fail(paste0("pat already on ", a[2]))
            item$pool <- count
            item$role <- "outside"
            emit("ok nat pat ", a[2], " ", ip(item$address), " 20000-", 19999 + count)
        } else {
            item <- iface(a[2])
            port <- as.numeric(a[4])
            if (port < 1 || port > 65535) fail(paste0("bad port ", a[4]))
            inside <- address(a[5])
            inport <- as.numeric(a[6])
            if (inport < 1 || inport > 65535) fail(paste0("bad port ", a[6]))
            if (item$role != "outside") fail(paste0("interface ", a[2], " not outside"))
            if (!is.null(local_name(inside))) fail(paste0("address ", a[5], " is local"))
            if (!is.null(find_item(forwards, function(rule) rule$dev == a[2] && rule$proto == a[3] && rule$port == port))) fail(paste0("duplicate forward ", a[2], " ", a[3], " ", a[4]))
            forwards[[length(forwards) + 1]] <<- object(dev = a[2], proto = a[3], port = port, inside = inside, inport = inport)
            emit("ok nat forward ", a[2], " ", a[3], " ", port, " ", a[5], ":", inport)
        }
    } else if (kind == "RPF") {
        item <- iface(name)
        item$rpf <- tolower(a[2])
        emit("ok rpf ", name, " ", item$rpf)
    } else if (kind == "TIMEOUT") {
        seconds <- as.numeric(a[2])
        if (seconds < 1 || seconds > 86400) fail(paste0("bad timeout ", a[2]))
        timeouts[name] <<- seconds
        emit("ok timeout ", name, " ", seconds)
    } else if (kind == "TICK") {
        seconds <- as.numeric(name)
        if (seconds < 1 || seconds > 86400) fail(paste0("bad tick ", name))
        clock <<- clock + seconds
        conns <- length(connections)
        mappings <- length(pat)
        connections <<- Filter(function(item) {
            timeout <- if (item$proto == "TCP") switch(item$state, SYN_SENT = 60, FIN_WAIT = 60, CLOSED = 10, timeouts["TCP"]) else timeouts[item$proto]
            clock - item$last < timeout
        }, connections)
        pat <<- Filter(function(item) clock - item$last < timeouts[item$proto], pat)
        emit("ok tick time=", fmt(clock), " expired conns=", conns - length(connections), " nat=", mappings - length(pat))
    } else if (kind == "PACKET") {
        item <- iface(name)
        protocol <- a[2]
        flags <- a[3]
        if (protocol != "TCP" && flags != "-") fail(paste0("flags not allowed for ", protocol))
        if (protocol == "TCP" && flags != "-" && (!grepl("^[SAFR]+$", flags) || length(unique(strsplit(flags, "", fixed = TRUE)[[1]])) != nchar(flags))) fail(paste0("bad flags ", flags))
        source <- address(a[4])
        sport <- as.numeric(a[5])
        if (sport > 65535) fail(paste0("bad port ", a[5]))
        destination <- address(a[6])
        dport <- as.numeric(a[7])
        if (dport > 65535) fail(paste0("bad port ", a[7]))
        ttl <- as.numeric(a[8])
        if (ttl < 1 || ttl > 255) fail(paste0("bad ttl ", a[8]))
        packet_number <<- packet_number + 1
        item$rx <- item$rx + 1
        result <- packet(name, protocol, flags, source, sport, destination, dport, ttl)
        counts[result[2]] <<- counts[result[2]] + 1
        if (result[2] %in% drop_reasons) item$drop <- item$drop + 1
        emit("#", packet_number, " ", protocol, " ", flags, " ", a[4], ":", a[5], " > ", a[6], ":", a[7], " ", result[1])
    } else if (kind == "SHOW") {
        show_state(name)
    } else if (kind == "CLEAR") {
        if (name == "COUNTERS") {
            reset_counters()
            emit("ok clear counters")
        } else {
            emit("ok clear conns=", length(connections), " nat=", length(pat))
            connections <<- list()
            pat <<- list()
        }
    }
}
input <- readLines(file("stdin"), warn = FALSE)
number <- as.integer(input[1])
for (index in seq_len(number)) {
    tryCatch(command(strsplit(input[index + 1], " ", fixed = TRUE)[[1]]), router_error = function(e) {
        counts["errors"] <<- counts["errors"] + 1
        emit("error: ", e$message)
    })
}
