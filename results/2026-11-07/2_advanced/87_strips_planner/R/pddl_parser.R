expressions <- function(text) {
    cleaned <- paste(sub(";.*$", "", strsplit(text, "\n", fixed=TRUE)[[1]]), collapse="\n")
    tokens <- regmatches(cleaned, gregexpr("\\(|\\)|[^ ()\n]+", cleaned))[[1]]
    position <- 1L
    read_expression <- function() {
        token <- tokens[position]
        position <<- position+1L
        if (token != "(") return(token)
        items <- list()
        while (tokens[position] != ")") items[[length(items)+1L]] <- read_expression()
        position <<- position+1L
        items
    }
    roots <- list()
    while (position <= length(tokens)) roots[[length(roots)+1L]] <- read_expression()
    roots
}
typed_list <- function(words) {
    words <- unlist(words, use.names=FALSE)
    result <- list()
    pending <- character()
    position <- 1L
    while (position <= length(words)) {
        if (words[position] == "-") {
            for (name in pending) result[[length(result)+1L]] <- c(name, words[position+1L])
            pending <- character()
            position <- position+2L
        } else {
            pending <- c(pending, words[position])
            position <- position+1L
        }
    }
    for (name in pending) result[[length(result)+1L]] <- c(name, "object")
    result
}
parse_atom <- function(expression) unlist(expression, use.names=FALSE)
conjuncts <- function(expression, empty=TRUE) {
    conjunction <- identical(expression[[1]], "and") && all(vapply(expression[-1], is.list, FALSE))
    if (conjunction && (empty || length(expression) > 1L)) expression[-1] else list(expression)
}
parse_literal <- function(expression) {
    negative <- identical(expression[[1]], "not") && length(expression) == 2L && is.list(expression[[2]])
    list(sign=!negative, atom=parse_atom(if (negative) expression[[2]] else expression))
}
read_domain <- function(text) {
    expression <- expressions(text)[[1]]
    domain <- new.env(parent=emptyenv())
    domain$name <- expression[[2]][[2]]
    domain$parents <- list(object=NULL)
    domain$type_order <- "object"
    domain$predicates <- list()
    domain$predicate_order <- character()
    domain$actions <- list()
    for (section in expression[-c(1,2)]) {
        kind <- section[[1]]
        if (kind == ":types") {
            words <- unlist(section[-1], use.names=FALSE)
            for (name in words) if (name != "-" && !name %in% domain$type_order) {
                domain$parents[[name]] <- "object"
                domain$type_order <- c(domain$type_order, name)
            }
            for (entry in typed_list(words)) domain$parents[[entry[1]]] <- entry[2]
        } else if (kind == ":predicates") {
            for (declaration in section[-1]) {
                name <- declaration[[1]]
                domain$predicates[[name]] <- vapply(typed_list(declaration[-1]), function(p) p[2], "")
                domain$predicate_order <- c(domain$predicate_order, name)
            }
        } else if (kind == ":action") {
            indices <- seq.int(3L, length(section), by=2L)
            fields <- setNames(section[indices+1L], vapply(section[indices], identity, ""))
            condition <- if (is.null(fields[[":precondition"]])) list() else {
                lapply(conjuncts(fields[[":precondition"]]), parse_literal)
            }
            effects <- list()
            cost <- 1L
            for (item in conjuncts(fields[[":effect"]], empty=FALSE)) {
                if (identical(item[[1]], "increase") && length(item) == 3L && identical(item[[2]], list("total-cost"))) {
                    cost <- as.integer(item[[3]])
                } else effects[[length(effects)+1L]] <- parse_literal(item)
            }
            domain$actions[[length(domain$actions)+1L]] <- list(name=section[[2]],
                parameters=typed_list(fields[[":parameters"]]), condition=condition, effects=effects, cost=cost)
        }
    }
    domain
}
read_problems <- function(text) {
    lapply(expressions(text), function(expression) {
        entries <- expression[-c(1,2)]
        sections <- setNames(lapply(entries, function(s) s[-1]), vapply(entries, function(s) s[[1]], ""))
        typed <- typed_list(sections[[":objects"]])
        problem <- new.env(parent=emptyenv())
        problem$name <- expression[[2]][[2]]
        problem$object_order <- vapply(typed, function(p) p[1], "")
        problem$objects <- setNames(vapply(typed, function(p) p[2], ""), problem$object_order)
        problem$initial <- lapply(sections[[":init"]], parse_atom)
        problem$goals <- lapply(conjuncts(sections[[":goal"]][[1]], empty=FALSE), parse_atom)
        problem$diagnostics <- character()
        problem
    })
}
