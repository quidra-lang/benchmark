query_tokens <- function(text) {
    pattern <- "'[a-z0-9_-]*'|[A-Za-z_][A-Za-z0-9_]*|-?[0-9]+|<=|>=|<>|[=<>(),*]"
    regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1L]]
}

peek_token <- function(parser) if (parser$position <= length(parser$tokens)) parser$tokens[parser$position] else ""
take_token <- function(parser) {
    token <- parser$tokens[parser$position]
    parser$position <- parser$position + 1L
    token
}
accept_token <- function(parser, token) {
    if (peek_token(parser) != token) return(FALSE)
    parser$position <- parser$position + 1L
    TRUE
}

parse_item <- function(parser) {
    name <- take_token(parser)
    if (grepl("^[a-z]", name)) return(list(operation = "COLUMN", name = name))
    take_token(parser)
    operation <- if (accept_token(parser, "DISTINCT")) "COUNT_DISTINCT" else name
    column <- if (accept_token(parser, "*")) NULL else take_token(parser)
    take_token(parser)
    list(operation = operation, name = column)
}

parse_literal <- function(parser) {
    token <- take_token(parser)
    if (startsWith(token, "'")) return(list(kind = "STRING", value = substr(token, 2L, nchar(token) - 1L)))
    if (token %in% c("TRUE", "FALSE")) return(list(kind = "BOOL", value = token == "TRUE"))
    list(kind = "INT", value = as.numeric(token))
}

parse_negation <- function(parser) {
    if (accept_token(parser, "NOT")) return(list(operation = "NOT", left = parse_negation(parser)))
    if (accept_token(parser, "(")) {
        tree <- parse_condition(parser)
        take_token(parser)
        return(tree)
    }
    column <- take_token(parser)
    operation <- take_token(parser)
    literals <- list()
    if (operation == "IS") {
        operation <- if (accept_token(parser, "NOT")) "IS_NOT_NULL" else "IS_NULL"
        take_token(parser)
    } else if (operation == "BETWEEN") {
        literals <- list(parse_literal(parser))
        take_token(parser)
        literals[[2L]] <- parse_literal(parser)
    } else if (operation == "IN") {
        take_token(parser)
        literals <- list(parse_literal(parser))
        while (accept_token(parser, ",")) literals[[length(literals) + 1L]] <- parse_literal(parser)
        take_token(parser)
    } else {
        literals <- list(parse_literal(parser))
    }
    list(operation = operation, column = column, literals = literals)
}

parse_conjunction <- function(parser) {
    tree <- parse_negation(parser)
    while (accept_token(parser, "AND")) tree <- list(
        operation = "AND",
        left = tree,
        right = parse_negation(parser)
    )
    tree
}

parse_condition <- function(parser) {
    tree <- parse_conjunction(parser)
    while (accept_token(parser, "OR")) tree <- list(
        operation = "OR",
        left = tree,
        right = parse_conjunction(parser)
    )
    tree
}

parse_query <- function(text) {
    parser <- new.env(parent = emptyenv())
    parser$tokens <- query_tokens(text)
    parser$position <- 1L
    take_token(parser)
    items <- NULL
    if (!accept_token(parser, "*")) {
        items <- list(parse_item(parser))
        while (accept_token(parser, ",")) items[[length(items) + 1L]] <- parse_item(parser)
    }
    condition <- if (accept_token(parser, "WHERE")) parse_condition(parser) else NULL
    group <- NULL
    if (accept_token(parser, "GROUP")) {
        take_token(parser)
        group <- take_token(parser)
    }
    order <- NULL
    descending <- FALSE
    if (accept_token(parser, "ORDER")) {
        take_token(parser)
        order <- take_token(parser)
        descending <- accept_token(parser, "DESC")
        if (!descending) accept_token(parser, "ASC")
    }
    limit <- if (accept_token(parser, "LIMIT")) as.integer(take_token(parser)) else NULL
    list(
        items = items,
        condition = condition,
        group = group,
        order = order,
        descending = descending,
        limit = limit
    )
}
