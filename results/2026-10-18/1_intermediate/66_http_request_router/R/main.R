object <- function(...) list2env(list(...), parent = emptyenv())
routes <- list()
ordered_routes <- list()
tokens <- list()
redirects <- list()
origins <- character()
rate_limit <- NULL
config_errors <- 0
clients <- list()
statuses <- integer()
request_count <- 0
url_ok <- 0
url_error <- 0
name_pattern <- "^[a-z][a-z0-9_]{0,19}$"
role_pattern <- "^[a-z]{1,16}$"
media_pattern <- "^[a-z0-9.+-]+/[a-z0-9.+-]+$"
reasons <- c("200" = "OK", "204" = "No Content", "301" = "Moved Permanently", "302" = "Found", "304" = "Not Modified", "307" = "Temporary Redirect", "308" = "Permanent Redirect", "400" = "Bad Request", "401" = "Unauthorized", "403" = "Forbidden", "404" = "Not Found", "405" = "Method Not Allowed", "406" = "Not Acceptable", "412" = "Precondition Failed", "429" = "Too Many Requests", "501" = "Not Implemented")
header_order <- c("Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length")
emit <- function(...) cat(paste0(...), "\n", sep = "")
strip_spaces <- function(text) gsub("^ +| +$", "", text)
text_slice <- function(text, start, end = nchar(text)) if (start > end) "" else substr(text, start, end)
chars <- function(text) strsplit(text, "", fixed = TRUE)[[1]]
split_keep <- function(text, separator) {
    parts <- strsplit(paste0(text, "\001"), separator, fixed = TRUE)[[1]]
    last <- length(parts)
    parts[last] <- text_slice(parts[last], 1, nchar(parts[last]) - 1)
    parts
}
first_pair <- function(text, separator) {
    at <- regexpr(separator, text, fixed = TRUE)[1]
    if (at < 0) return(list(left = text, right = "", present = FALSE))
    list(left = text_slice(text, 1, at - 1), right = text_slice(text, at + nchar(separator)), present = TRUE)
}
fail_config <- function(message) stop(structure(list(message = message, call = NULL), class = c("configuration_error", "error", "condition")))
fail_url <- function(message) stop(structure(list(message = message, call = NULL), class = c("url_error", "error", "condition")))
find_route <- function(name) {
    for (route in routes) if (route$name == name) return(route)
    NULL
}
segment <- function(text) grepl("^[A-Za-z0-9._~-]+$", text) && !(text %in% c(".", ".."))
canonical <- function(text) {
    text == "/" || (startsWith(text, "/") && all(vapply(split_keep(substring(text, 2), "/"), segment, logical(1))))
}
parse_pattern <- function(text) {
    if (text == "/") return(list())
    if (!startsWith(text, "/")) return(NULL)
    parts <- split_keep(substring(text, 2), "/")
    pieces <- list()
    names <- character()
    for (index in seq_along(parts)) {
        part <- parts[index]
        if (segment(part)) {
            pieces[[length(pieces) + 1]] <- list(kind = "literal", name = part)
            next
        }
        match <- regmatches(part, regexec("^\\{(\\*?)([a-z][a-z0-9_]{0,19})(:(int|slug))?\\}$", part))[[1]]
        if (!length(match)) return(NULL)
        star <- match[2] == "*"
        name <- match[3]
        type <- match[5]
        if (name %in% names || (star && (type != "" || index != length(parts)))) return(NULL)
        names <- c(names, name)
        pieces[[length(pieces) + 1]] <- list(kind = if (star) "wildcard" else if (type == "") "parameter" else type, name = name)
    }
    pieces
}
configure <- function(line, number) {
    words <- split_keep(line, " ")
    command <- words[1]
    args <- words[-1]
    tryCatch({
        counts <- list(ROUTE = c(3, 5), TOKEN = 2, REDIRECT = 3, ORIGIN = 1, LIMIT = 2)
        if (!(command %in% c(names(counts), "TYPES"))) fail_config(paste0("unknown command ", command))
        if (if (command == "TYPES") length(args) < 2 else !(length(args) %in% counts[[command]])) fail_config("wrong number of arguments")
        if (command == "ROUTE") {
            name <- args[1]
            methods <- args[2]
            path <- args[3]
            if (!grepl(name_pattern, name)) fail_config(paste0("bad route name ", name))
            if (!is.null(find_route(name))) fail_config(paste0("duplicate route ", name))
            method_list <- split_keep(methods, ",")
            if (any(!(method_list %in% c("GET", "POST", "PUT", "PATCH", "DELETE"))) || anyDuplicated(method_list)) fail_config(paste0("bad methods ", methods))
            pieces <- parse_pattern(path)
            if (is.null(pieces)) fail_config(paste0("bad pattern ", path))
            if (length(args) == 5 && args[4] != "ROLE") fail_config(paste0("unknown option ", args[4]))
            if (length(args) == 5 && !grepl(role_pattern, args[5])) fail_config(paste0("bad role ", args[5]))
            routes[[length(routes) + 1]] <<- object(name = name, methods = method_list, pattern = path, pieces = pieces,
                                                  role = if (length(args) == 5) args[5] else "none", types = NULL, hits = 0, number = length(routes))
        } else if (command == "TOKEN") {
            token <- args[1]
            role <- args[2]
            if (!grepl("^[A-Za-z0-9._-]{1,32}$", token)) fail_config(paste0("bad token ", token))
            if (token %in% names(tokens)) fail_config(paste0("duplicate token ", token))
            if (!grepl(role_pattern, role)) fail_config(paste0("bad role ", role))
            tokens[token] <<- list(role)
        } else if (command == "REDIRECT") {
            from <- args[1]
            to <- args[2]
            code <- args[3]
            for (path in c(from, to)) {
                star <- endsWith(path, "/*")
                base <- if (star) text_slice(path, 1, nchar(path) - 2) else path
                if (!canonical(base) || (star && base == "/")) fail_config(paste0("bad path ", path))
            }
            star <- endsWith(from, "/*")
            if (star != endsWith(to, "/*")) fail_config("wildcard mismatch")
            if (!(code %in% c("301", "302", "307", "308"))) fail_config(paste0("bad redirect code ", code))
            if (any(vapply(redirects, function(rule) rule$from == from, logical(1)))) fail_config(paste0("duplicate redirect ", from))
            redirects[[length(redirects) + 1]] <<- list(from = from, base = if (star) text_slice(from, 1, nchar(from) - 2) else from,
                                                       to = if (star) text_slice(to, 1, nchar(to) - 2) else to, wildcard = star, code = as.integer(code))
        } else if (command == "ORIGIN") {
            origin <- args[1]
            if (!grepl("^https?://[a-z0-9.:-]+$", origin)) fail_config(paste0("bad origin ", origin))
            if (origin %in% origins) fail_config(paste0("duplicate origin ", origin))
            origins <<- c(origins, origin)
        } else if (command == "LIMIT") {
            if (!all(grepl("^[1-9][0-9]*$", args)) || as.numeric(args[1]) > 100 || as.numeric(args[2]) > 3600) fail_config("bad limit")
            if (!is.null(rate_limit)) fail_config("duplicate limit")
            rate_limit <<- as.numeric(args)
        } else if (command == "TYPES") {
            name <- args[1]
            route <- find_route(name)
            if (is.null(route)) fail_config(paste0("unknown route ", name))
            if (!is.null(route$types)) fail_config(paste0("duplicate types ", name))
            seen <- character()
            for (type in args[-1]) {
                if (!grepl(media_pattern, type)) fail_config(paste0("bad media type ", type))
                if (type %in% seen) fail_config(paste0("duplicate media type ", type))
                seen <- c(seen, type)
            }
            route$types <- args[-1]
        }
    }, configuration_error = function(e) {
        config_errors <<- config_errors + 1
        emit("CONFIG ERROR ", number, ": ", e$message)
    })
}
priority <- function(route) {
    kinds <- vapply(route$pieces, function(piece) piece$kind, character(1))
    c(-sum(kinds == "literal"), -sum(kinds %in% c("int", "slug")), as.integer("wildcard" %in% kinds), route$number)
}
decode <- function(text) {
    output <- character()
    position <- 1
    while (position <= nchar(text)) {
        char <- substr(text, position, position)
        if (char == "%") {
            output <- c(output, intToUtf8(strtoi(substr(text, position + 1, position + 2), 16)))
            position <- position + 3
        } else {
            output <- c(output, char)
            position <- position + 1
        }
    }
    paste(output, collapse = "")
}
encode <- function(text) {
    paste(vapply(chars(text), function(char) if (grepl("^[A-Za-z0-9._~-]$", char)) char else sprintf("%%%02X", utf8ToInt(char)), character(1)), collapse = "")
}
normalize <- function(path) {
    output <- character()
    position <- 1
    while (position <= nchar(path)) {
        char <- substr(path, position, position)
        if (char == "%") {
            number <- strtoi(substr(path, position + 1, position + 2), 16)
            char <- intToUtf8(number)
            if (!grepl("^[A-Za-z0-9._~-]$", char)) char <- sprintf("%%%02X", number)
            position <- position + 3
        } else position <- position + 1
        output <- c(output, char)
    }
    parts <- character()
    for (part in split_keep(substring(paste(output, collapse = ""), 2), "/")) {
        if (part == "..") {
            if (length(parts)) parts <- parts[-length(parts)]
        } else if (!(part %in% c("", "."))) parts <- c(parts, part)
    }
    paste0("/", paste(parts, collapse = "/"))
}
match_route <- function(route, segments) {
    pieces <- route$pieces
    wildcard <- length(pieces) > 0 && pieces[[length(pieces)]]$kind == "wildcard"
    count <- length(pieces) - as.integer(wildcard)
    if (if (wildcard) length(segments) < count else length(segments) != count) return(NULL)
    parameters <- list()
    for (index in seq_along(pieces)) {
        piece <- pieces[[index]]
        kind <- piece$kind
        name <- piece$name
        text <- if (index <= length(segments)) segments[index] else ""
        if (kind == "literal") {
            if (text != name) return(NULL)
        } else if (kind == "parameter") {
            parameters[name] <- list(decode(text))
        } else if (kind == "int") {
            if (!grepl("^[0-9]{1,9}$", text)) return(NULL)
            parameters[name] <- list(sprintf("%.0f", as.numeric(text)))
        } else if (kind == "slug") {
            if (!grepl("^[a-z0-9-]+$", text)) return(NULL)
            parameters[name] <- list(text)
        } else {
            rest <- if (length(segments) > count) segments[seq.int(count + 1, length(segments))] else character()
            parameters[name] <- list(paste(vapply(rest, decode, character(1)), collapse = "/"))
        }
    }
    parameters
}
selected_type <- function(types, accept) {
    if (is.null(accept)) return(types[1])
    elements <- list()
    for (element in split_keep(accept, ",")) {
        parts <- vapply(split_keep(element, ";"), strip_spaces, character(1))
        range <- tolower(parts[1])
        if (!(range == "*/*" || grepl("^[a-z0-9.+-]+/\\*$", range) || grepl(media_pattern, range))) next
        q <- NULL
        for (parameter in parts[-1]) {
            pair <- first_pair(parameter, "=")
            if (pair$present && tolower(strip_spaces(pair$left)) == "q") {
                q <- strip_spaces(pair$right)
                break
            }
        }
        if (!is.null(q) && !grepl("^(0(\\.[0-9]{0,3})?|1(\\.0{0,3})?)$", q)) next
        weight <- if (is.null(q)) 1000 else round(as.numeric(q) * 1000)
        specificity <- if (range == "*/*") 1 else if (endsWith(range, "/*")) 2 else 3
        elements[[length(elements) + 1]] <- list(range = range, specificity = specificity, weight = weight)
    }
    best <- NULL
    best_weight <- 0
    for (type in types) {
        specificity <- 0
        weight <- 0
        for (element in elements) {
            range <- element$range
            fits <- range == "*/*" || range == type || (element$specificity == 2 && first_pair(range, "/")$left == first_pair(type, "/")$left)
            if (fits && element$specificity > specificity) {
                specificity <- element$specificity
                weight <- element$weight
            }
        }
        if (weight > best_weight) {
            best_weight <- weight
            best <- type
        }
    }
    best
}
json_string <- function(text) {
    escaped <- vapply(chars(text), function(char) if (char %in% c("\\", '"')) paste0("\\", char) else char, character(1))
    paste0('"', paste(escaped, collapse = ""), '"')
}
html <- function(text) {
    replacements <- c("&" = "&amp;", "<" = "&lt;", ">" = "&gt;", '"' = "&quot;")
    paste(vapply(chars(text), function(char) if (char %in% names(replacements)) replacements[[char]] else char, character(1)), collapse = "")
}
body_for <- function(route, parameters, query, headers, type) {
    params <- lapply(sort(names(parameters), method = "radix"), function(name) c(name, parameters[[name]]))
    queries <- list()
    if (!is.null(query)) {
        for (part in split_keep(query, "&")) {
            if (part == "") next
            pair <- first_pair(part, "=")
            queries[[length(queries) + 1]] <- c(decode(chartr("+", " ", pair$left)), decode(chartr("+", " ", pair$right)))
        }
    }
    cookies <- list()
    if ("cookie" %in% names(headers)) {
        for (part in split_keep(headers[["cookie"]], ";")) {
            pair <- first_pair(strip_spaces(part), "=")
            if (pair$present && pair$left != "" && !(pair$left %in% names(cookies))) cookies[pair$left] <- list(pair$right)
        }
    }
    cookie_pairs <- lapply(sort(names(cookies), method = "radix"), function(name) c(name, cookies[[name]]))
    if (type == "application/json") {
        pairs <- function(list) paste(vapply(list, function(pair) paste0(json_string(pair[1]), ":", json_string(pair[2])), character(1)), collapse = ",")
        query_json <- paste(vapply(queries, function(pair) paste0("[", json_string(pair[1]), ",", json_string(pair[2]), "]"), character(1)), collapse = ",")
        return(paste0('{"route":', json_string(route$name), ',"params":{', pairs(params), '},"query":[', query_json, '],"cookies":{', pairs(cookie_pairs), "}}"))
    }
    if (type == "text/html") {
        output <- paste0("<dl><dt>route</dt><dd>", html(route$name), "</dd>")
        lists <- list(param = params, query = queries, cookie = cookie_pairs)
        for (label in names(lists)) for (pair in lists[[label]]) output <- paste0(output, "<dt>", label, " ", html(pair[1]), "</dt><dd>", html(pair[2]), "</dd>")
        return(paste0(output, "</dl>"))
    }
    pairs <- function(list) {
        if (!length(list)) return("-")
        paste(vapply(list, function(pair) paste0(encode(pair[1]), "=", encode(pair[2])), character(1)), collapse = "&")
    }
    paste0("route=", route$name, " params=", pairs(params), " query=", pairs(queries), " cookies=", pairs(cookie_pairs))
}
etag <- function(body) {
    a <- 1
    b <- 0
    for (char in utf8ToInt(body)) {
        a <- (a + char) %% 65521
        b <- (b + a) %% 65521
    }
    sprintf('"%04x%04x"', as.integer(b), as.integer(a))
}
response <- function(status, body = "", headers = list(), type = NULL) list(status = status, body = body, headers = headers, type = type)
handle <- function(method, target, headers) {
    if (!(method %in% c("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"))) return(response(501, paste0("not implemented: ", method)))
    if (!("host" %in% names(headers)) || headers[["host"]] == "") return(response(400, "bad request: missing host"))
    effective <- method
    if ("x-http-method-override" %in% names(headers)) {
        override <- headers[["x-http-method-override"]]
        if (method != "POST" || !(override %in% c("PUT", "PATCH", "DELETE"))) return(response(400, "bad request: method override"))
        effective <- override
    }
    client <- headers[["x-client"]]
    if (!is.null(client) && client != "") {
        time <- as.numeric(headers[["x-time"]])
        if (!(client %in% names(clients))) clients[[client]] <<- object(allowed = 0, limited = 0, level = if (is.null(rate_limit)) 0 else prod(rate_limit), last = time)
        record <- clients[[client]]
        if (!is.null(rate_limit)) {
            capacity <- rate_limit[1]
            period <- rate_limit[2]
            record$level <- min(capacity * period, record$level + (time - record$last) * capacity)
            record$last <- time
            if (record$level < period) {
                record$limited <- record$limited + 1
                wait <- ceiling((period - record$level) / capacity)
                return(response(429, paste0("too many requests: client ", client), list("Retry-After" = as.character(wait))))
            }
            record$level <- record$level - period
        }
        record$allowed <- record$allowed + 1
    }
    target_parts <- first_pair(target, "?")
    path <- target_parts$left
    query <- if (target_parts$present) target_parts$right else NULL
    suffix <- if (target_parts$present) paste0("?", query) else ""
    normalized <- normalize(path)
    if (normalized != path) return(response(308, paste0("redirect to ", normalized, suffix), list(Location = paste0(normalized, suffix))))
    for (rule in redirects) {
        if (path == rule$base || (rule$wildcard && startsWith(path, paste0(rule$base, "/")))) {
            destination <- paste0(rule$to, text_slice(path, nchar(rule$base) + 1), suffix)
            return(response(rule$code, paste0("redirect to ", destination), list(Location = destination)))
        }
    }
    segments <- if (path == "/") character() else split_keep(substring(path, 2), "/")
    matches <- list()
    allowed <- "OPTIONS"
    for (route in ordered_routes) {
        parameters <- match_route(route, segments)
        if (!is.null(parameters)) {
            matches[[length(matches) + 1]] <- list(route = route, parameters = parameters)
            allowed <- c(allowed, route$methods)
        }
    }
    if (!length(matches)) return(response(404, paste0("not found: ", path)))
    if ("GET" %in% allowed) allowed <- c(allowed, "HEAD")
    allow <- paste(sort(unique(allowed), method = "radix"), collapse = ", ")
    if (effective == "OPTIONS") return(response(204, headers = list(Allow = allow)))
    lookup <- if (effective == "HEAD") "GET" else effective
    selected <- NULL
    for (candidate in matches) {
        if (lookup %in% candidate$route$methods) {
            selected <- candidate
            break
        }
    }
    if (is.null(selected)) return(response(405, paste0("method not allowed: ", effective), list(Allow = allow)))
    route <- selected$route
    parameters <- selected$parameters
    route$hits <- route$hits + 1
    if (route$role != "none") {
        if (!("authorization" %in% names(headers))) return(response(401, "unauthorized: missing token", list("WWW-Authenticate" = 'Bearer realm="api"')))
        authorization <- first_pair(headers[["authorization"]], " ")
        token <- authorization$right
        if (tolower(authorization$left) != "bearer" || !(token %in% names(tokens))) return(response(401, "unauthorized: invalid token", list("WWW-Authenticate" = 'Bearer realm="api", error="invalid_token"')))
        if (!(tokens[[token]] %in% c(route$role, "admin"))) return(response(403, paste0("forbidden: requires role ", route$role)))
    }
    extra <- if (length(route$types) >= 2) list(Vary = "Accept") else list()
    type <- selected_type(route$types, headers[["accept"]])
    if (is.null(type)) return(response(406, paste0("not acceptable: ", paste(route$types, collapse = ", ")), extra))
    body <- body_for(route, parameters, query, headers, type)
    tag <- etag(body)
    if ("if-none-match" %in% names(headers)) {
        for (part in split_keep(headers[["if-none-match"]], ",")) {
            part <- strip_spaces(part)
            if (startsWith(part, "W/")) part <- substring(part, 3)
            if (part == "*" || part == tag) {
                if (lookup == "GET") return(response(304, headers = c(extra, list(ETag = tag))))
                return(response(412, paste0("precondition failed: ", tag), extra))
            }
        }
    }
    response(200, body, c(extra, list(ETag = tag)), type)
}
request <- function(line, header_lines) {
    request_count <<- request_count + 1
    head <- FALSE
    cors <- FALSE
    headers <- list()
    match <- regmatches(line, regexec("^([A-Z]{1,16}) (/[^ #]*) HTTP/1\\.1$", line))[[1]]
    if (!length(match)) {
        result <- response(400, "bad request: request line")
    } else {
        method <- match[2]
        target <- match[3]
        head <- method == "HEAD"
        valid_escapes <- TRUE
        position <- 1
        while (position <= nchar(target)) {
            if (substr(target, position, position) == "%") {
                hex <- substr(target, position + 1, position + 2)
                if (!grepl("^[0-9A-Fa-f]{2}$", hex) || strtoi(hex, 16) < 32 || strtoi(hex, 16) > 126) {
                    valid_escapes <- FALSE
                    break
                }
                position <- position + 3
            } else position <- position + 1
        }
        if (!valid_escapes) {
            result <- response(400, "bad request: percent escape")
        } else {
            result <- NULL
            for (index in seq_along(header_lines)) {
                pair <- first_pair(header_lines[index], ":")
                if (!pair$present || !grepl("^[A-Za-z0-9-]+$", pair$left)) {
                    result <- response(400, paste0("bad request: header line ", index))
                    break
                }
                name <- tolower(pair$left)
                if (name %in% names(headers)) {
                    result <- response(400, paste0("bad request: duplicate header ", name))
                    break
                }
                headers[name] <- list(strip_spaces(pair$right))
            }
            if (is.null(result)) {
                cors <- TRUE
                result <- handle(method, target, headers)
            }
        }
    }
    if (cors && "origin" %in% names(headers) && headers[["origin"]] %in% origins) {
        result$headers[["Access-Control-Allow-Origin"]] <- headers[["origin"]]
        if (result$status == 204 && "access-control-request-method" %in% names(headers)) result$headers[["Access-Control-Allow-Methods"]] <- result$headers[["Allow"]]
    }
    status <- result$status
    key <- as.character(status)
    statuses[key] <<- if (key %in% names(statuses)) statuses[key] + 1 else 1
    if (!(status %in% c(204, 304))) {
        result$headers[["Content-Type"]] <- if (status == 200) result$type else "text/plain"
        result$headers[["Content-Length"]] <- as.character(nchar(result$body))
    }
    emit("REQUEST ", request_count)
    emit("HTTP/1.1 ", status, " ", reasons[key])
    for (name in header_order) if (name %in% names(result$headers)) emit(name, ": ", result$headers[[name]])
    if (!head && !(status %in% c(204, 304))) emit(result$body)
}
urlfor <- function(line) {
    words <- split_keep(line, " ")
    name <- words[2]
    arguments <- if (length(words) > 2) words[seq.int(3, length(words))] else character()
    tryCatch({
        route <- find_route(name)
        if (is.null(route)) fail_url(paste0("unknown route ", name))
        parameter_names <- vapply(Filter(function(piece) piece$kind != "literal", route$pieces), function(piece) piece$name, character(1))
        values <- list()
        queries <- list()
        for (argument in arguments) {
            pair <- first_pair(argument, "=")
            key <- pair$left
            if (!pair$present || key == "") fail_url(paste0("bad argument ", argument))
            if (key %in% parameter_names) {
                if (key %in% names(values)) fail_url(paste0("duplicate parameter ", key))
                values[key] <- list(pair$right)
            } else queries[[length(queries) + 1]] <- c(key, pair$right)
        }
        for (piece in route$pieces) {
            kind <- piece$kind
            key <- piece$name
            if (kind == "literal") next
            if (kind != "wildcard" && !(key %in% names(values))) fail_url(paste0("missing parameter ", key))
            text <- if (key %in% names(values)) values[[key]] else ""
            valid <- switch(kind, parameter = text != "" && !(text %in% c(".", "..")), int = grepl("^[0-9]{1,9}$", text), slug = grepl("^[a-z0-9-]+$", text),
                            wildcard = text == "" || all(vapply(split_keep(text, "/"), function(part) !(part %in% c("", ".", "..")), logical(1))))
            if (!valid) fail_url(paste0("bad value for ", key))
        }
        parts <- character()
        for (piece in route$pieces) {
            kind <- piece$kind
            key <- piece$name
            if (kind == "literal") {
                parts <- c(parts, key)
            } else if (kind == "wildcard") {
                text <- if (key %in% names(values)) values[[key]] else ""
                if (text != "") parts <- c(parts, vapply(split_keep(text, "/"), encode, character(1)))
            } else parts <- c(parts, encode(values[[key]]))
        }
        url <- paste0("/", paste(parts, collapse = "/"))
        if (length(queries)) url <- paste0(url, "?", paste(vapply(queries, function(pair) paste0(encode(pair[1]), "=", encode(pair[2])), character(1)), collapse = "&"))
        url_ok <<- url_ok + 1
        emit("URLFOR ", name, " ", url)
    }, url_error = function(e) {
        url_error <<- url_error + 1
        emit("URLFOR ERROR ", e$message)
    })
}
input <- readLines(file("stdin"), warn = FALSE)
position <- 1
while (input[position] != "REQUESTS") {
    configure(input[position], position)
    position <- position + 1
}
position <- position + 1
emit("CONFIG routes=", length(routes), " tokens=", length(tokens), " redirects=", length(redirects), " origins=", length(origins), " limit=", if (is.null(rate_limit)) "none" else paste(rate_limit, collapse = "/"), " errors=", config_errors)
for (route in routes) if (is.null(route$types)) route$types <- "application/json"
if (length(routes)) {
    priorities <- do.call(rbind, lapply(routes, priority))
    ordering <- order(priorities[, 1], priorities[, 2], priorities[, 3], priorities[, 4])
    ordered_routes <- routes[ordering]
}
for (index in seq_along(ordered_routes)) {
    route <- ordered_routes[[index]]
    methods <- route$methods
    if ("GET" %in% methods) methods <- c(methods, "HEAD")
    emit("TABLE ", index, " ", route$name, " ", paste(sort(methods, method = "radix"), collapse = ","), " ", route$pattern, " role=", if (route$role == "none") "-" else route$role, " types=", paste(route$types, collapse = ","))
}
while (input[position] != "END") {
    line <- input[position]
    position <- position + 1
    if (startsWith(line, "URLFOR ")) {
        urlfor(line)
    } else {
        headers <- character()
        while (input[position] != "") {
            headers <- c(headers, input[position])
            position <- position + 1
        }
        position <- position + 1
        request(line, headers)
    }
}
emit("SUMMARY requests=", request_count, " urlfor_ok=", url_ok, " urlfor_error=", url_error)
for (status in names(statuses)[order(as.numeric(names(statuses)))]) emit("STATUS ", status, " ", statuses[status])
for (route in routes) emit("ROUTE ", route$name, " ", route$hits)
for (client in sort(names(clients), method = "radix")) {
    record <- clients[[client]]
    emit("CLIENT ", client, " allowed=", record$allowed, " limited=", record$limited)
}
