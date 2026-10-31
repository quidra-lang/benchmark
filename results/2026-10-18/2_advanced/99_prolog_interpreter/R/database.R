new_database <- function() record(predicates = new_table(), order = character())
add_clause <- function(database, clause) {
    key <- indicator(clause$head)
    if (!exists(key, database$predicates, inherits = FALSE)) {
        database$predicates[[key]] <- list()
        database$order <- c(database$order, key)
    }
    clauses <- database$predicates[[key]]
    clauses[[length(clauses) + 1L]] <- clause
    database$predicates[[key]] <- clauses
}
candidate_clauses <- function(database, goal) {
    key <- indicator(goal)
    clauses <- database$predicates[[key]]
    if (indicator_parts(key)$arity == 0L) return(clauses)
    Filter(function(clause) same_kind(goal$arguments[[1L]], clause$head$arguments[[1L]]), clauses)
}
copy_clause <- function(clause) copy_terms(clause$head, clause$body)
