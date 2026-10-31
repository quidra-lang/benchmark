NO_EXPORT_COMMUNITY <- 65535 * 65536 + 65281
parse_community <- function(text) {
    if (text == "NO_EXPORT") return(NO_EXPORT_COMMUNITY)
    values <- as.numeric(strsplit(text, ":", fixed = TRUE)[[1L]])
    values[1L] * 65536 + values[2L]
}
parse_communities <- function(values) unname(sort(unique(vapply(values, parse_community, 0))))
community_text <- function(value) if (value == NO_EXPORT_COMMUNITY) "NO_EXPORT" else sprintf(
    "%.0f:%.0f",
    value %/% 65536,
    value %% 65536
)
communities_text <- function(values) if (length(values)) paste(
    vapply(values, community_text, ""),
    collapse = ","
) else "-"

edit_communities <- function(communities, rule) {
    edited <- communities
    for (entry in rule$actions) {
        if (entry$action == "ADD") edited <- union(edited, entry$value)
        if (entry$action == "REMOVE") edited <- setdiff(edited, entry$value)
    }
    unname(sort(edited))
}

read_policies <- function() {
    lists <- rules <- list()
    for (line in readLines("input/policies.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        if (fields[1L] == "PLIST") {
            prefix <- parse_prefix(fields[4L])
            bounds <- list()
            if (length(fields) > 4L) for (index in seq.int(
                5L,
                length(fields),
                by = 2L
            )) bounds[[fields[index]]] <- as.integer(fields[index + 1L])
            low <- if (is.null(bounds$GE)) prefix$length else bounds$GE
            high <- if (!is.null(bounds$LE)) bounds$LE else if (!is.null(bounds$GE)) 32L else prefix$length
            lists[[fields[2L]]] <- c(
                lists[[fields[2L]]],
                list(list(permit = fields[3L] == "PERMIT", prefix = prefix, low = low, high = high))
            )
            next
        }
        separator <- match("THEN", fields)
        conditions <- actions <- list()
        if (separator > 7L) for (index in seq.int(7L, separator - 1L, by = 2L)) {
            condition <- fields[index]
            token <- fields[index + 1L]
            value <- if (condition %in% c(
                "CONTAINS",
                "ORIGINAS"
            )) as.integer(token) else if (condition == "LENGTH") as.integer(strsplit(
                token,
                "-",
                fixed = TRUE
            )[[1L]]) else if (condition == "COMMUNITY") parse_community(token) else token
            conditions[[length(conditions) + 1L]] <- list(condition = condition, value = value)
        }
        settings <- list()
        index <- separator + 1L
        while (index <= length(fields)) {
            action <- fields[index]
            index <- index + 1L
            value <- NULL
            if (!action %in% c("DENY", "ALLOW")) {
                value <- if (action %in% c(
                    "ADD",
                    "REMOVE"
                )) parse_community(fields[index]) else as.integer(fields[index])
                index <- index + 1L
            }
            actions[[length(actions) + 1L]] <- list(action = action, value = value)
            settings[action] <- list(value)
        }
        rule <- new.env(parent = emptyenv())
        rule$name <- fields[2L]
        rule$active <- fields[3L] == "ON"
        rule$owner <- as.integer(fields[4L])
        rule$direction <- fields[5L]
        rule$target <- fields[6L]
        rule$conditions <- conditions
        rule$actions <- actions
        rule$settings <- settings
        rule$hits <- 0L
        rules[[rule$name]] <- rule
    }
    list(lists = lists, rules = rules)
}

prefix_permitted <- function(policies, name, prefix) {
    for (entry in policies$lists[[name]]) {
        if (entry$low <= prefix$length && prefix$length <= entry$high && prefix_contains(
            entry$prefix,
            prefix$address
        )) return(entry$permit)
    }
    FALSE
}

rule_matches <- function(policies, rule, owner, link, prefix, path, communities) {
    if (!rule$active || rule$owner != owner) return(FALSE)
    if (!rule$target %in% c("*", as.character(other_end(link, owner)), link$name)) return(FALSE)
    for (entry in rule$conditions) {
        condition <- entry$condition
        value <- entry$value
        if (condition == "PREFIX" && !prefix_permitted(policies, value, parse_prefix(prefix))) return(FALSE)
        if (condition == "CONTAINS" && !value %in% path) return(FALSE)
        if (condition == "ORIGINAS" && (if (length(path)) tail(path, 1L) else owner) != value) return(FALSE)
        if (condition == "LENGTH" && !(value[1L] <= length(path) && length(path) <= value[2L])) return(FALSE)
        if (condition == "COMMUNITY" && !value %in% communities) return(FALSE)
    }
    TRUE
}

applied_rule <- function(policies, direction, owner, link, prefix, path, communities) {
    for (rule in policies$rules) if (rule$direction == direction && rule_matches(
        policies,
        rule,
        owner,
        link,
        prefix,
        path,
        communities
    )) return(rule)
    NULL
}
rule_has <- function(rule, action) !is.null(rule) && action %in% names(rule$settings)
rule_value <- function(rule, action, default) if (rule_has(rule, action)) rule$settings[[action]] else default
