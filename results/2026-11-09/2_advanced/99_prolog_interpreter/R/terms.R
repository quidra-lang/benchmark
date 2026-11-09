record <- function(...) list2env(list(...), parent = emptyenv())
new_table <- function() new.env(hash = TRUE, parent = emptyenv())
TERM_SERIAL <- record(value = 0L)
integer_term <- function(value) list(kind = "integer", value = if (inherits(value, "bigz")) value else gmp::as.bigz(value))
atom_term <- function(name) list(kind = "atom", name = name)
variable_term <- function() {
    TERM_SERIAL$value <- TERM_SERIAL$value + 1L
    record(kind = "variable", id = TERM_SERIAL$value, binding = NULL)
}
compound_term <- function(name, arguments) list(kind = "compound", name = name, arguments = arguments)
compound <- function(name, ...) compound_term(name, list(...))
NIL <- atom_term("[]")
is_variable <- function(term) !is.null(term) && is.environment(term) && identical(term$kind, "variable")
is_integer <- function(term) !is.null(term) && identical(term$kind, "integer")
is_compound <- function(term) !is.null(term) && identical(term$kind, "compound")
is_atom <- function(term, name = NULL) {
    !is.null(term) && identical(term$kind, "atom") && (is.null(name) || identical(term$name, name))
}
variable_key <- function(variable) paste0("v", variable$id)
dereference <- function(term) {
    while (is_variable(term) && !is.null(term$binding)) term <- term$binding
    term
}
indicator_key <- function(name, arity) paste0(nchar(name), ":", name, ":", arity)
indicator <- function(term) {
    term <- dereference(term)
    indicator_key(term$name, if (is_compound(term)) length(term$arguments) else 0L)
}
indicator_parts <- function(key) {
    colon <- which(strsplit(key, "", fixed = TRUE)[[1L]] == ":")[1L]
    size <- as.integer(substr(key, 1L, colon - 1L))
    list(name = if (size == 0L) "" else substr(key, colon + 1L, colon + size), arity = as.integer(substring(key, colon + size + 2L)))
}
indicator_term <- function(key) {
    parts <- indicator_parts(key)
    compound("/", atom_term(parts$name), integer_term(parts$arity))
}
predicate_keys <- function(names, arity) vapply(names, indicator_key, character(1L), arity = arity)
make_list <- function(elements, tail = NIL) {
    for (element in rev(elements)) tail <- compound(".", element, tail)
    tail
}
list_parts <- function(term) {
    elements <- list()
    term <- dereference(term)
    while (is_compound(term) && term$name == "." && length(term$arguments) == 2L) {
        elements[[length(elements) + 1L]] <- term$arguments[[1L]]
        term <- dereference(term$arguments[[2L]])
    }
    list(elements = elements, tail = term)
}
copy_terms <- function(...) {
    variables <- new_table()
    duplicate <- function(term) {
        if (is.null(term)) return(NULL)
        term <- dereference(term)
        if (is_variable(term)) {
            key <- variable_key(term)
            if (!exists(key, variables, inherits = FALSE)) variables[[key]] <- variable_term()
            return(variables[[key]])
        }
        if (is_compound(term)) return(compound_term(term$name, lapply(term$arguments, duplicate)))
        term
    }
    lapply(list(...), duplicate)
}
copy_term <- function(term) copy_terms(term)[[1L]]
variables_in <- function(...) {
    result <- list()
    pending <- rev(list(...))
    while (length(pending)) {
        term <- dereference(pending[[length(pending)]])
        pending[[length(pending)]] <- NULL
        if (is_variable(term)) result[[length(result) + 1L]] <- term else if (is_compound(term)) pending <- c(pending, rev(term$arguments))
    }
    result
}
same_kind <- function(left, right) {
    left <- dereference(left)
    right <- dereference(right)
    if (is_variable(left) || is_variable(right)) return(TRUE)
    if (is_compound(left) && is_compound(right)) return(left$name == right$name && length(left$arguments) == length(right$arguments))
    if (is_integer(left) && is_integer(right)) return(left$value == right$value)
    is_atom(left) && is_atom(right) && left$name == right$name
}
type_error <- function(kind, term) compound("type_error", atom_term(kind), term)
domain_error <- function(kind, term) compound("domain_error", atom_term(kind), term)
prolog_fault <- function(term) {
    stop(structure(list(message = "Prolog error", term = term), class = c("prolog_fault", "error", "condition")))
}
prolog_ball <- function(term) {
    stop(structure(list(message = "Prolog throw", term = term), class = c("prolog_ball", "error", "condition")))
}
