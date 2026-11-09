expand_values <- function(configuration, report) {
    results <- new.env(parent = emptyenv())
    progress <- character(); cycle_keys <- character()
    expand <- function(key) {
        if (exists(key, results, inherits = FALSE)) return(get(key, results, inherits = FALSE))
        progress <<- c(progress, key)
        value <- evaluate(key)
        progress <<- head(progress, -1L)
        assign(key, value, results)
        value
    }
    evaluate <- function(key) {
        definition <- configuration[[key]]; text <- definition$value
        position <- 1L; pieces <- character()
        while (position <= nchar(text)) {
            char <- substr(text, position, position)
            if (substr(text, position, position + 1L) != "${") {
                pieces <- c(pieces, if (char == LITERAL_DOLLAR) "$" else char)
                position <- position + 1L
                next
            }
            tail <- substring(text, position + 2L)
            close <- regexpr("}", tail, fixed = TRUE)[1L]
            reference <- if (close < 0L) "" else substr(tail, 1L, close - 1L)
            if (close < 0L || !is_section_name(reference)) {
                report(definition$origin, "E_BAD_REF", paste0(key, ": invalid reference")); return(NULL)
            }
            target <- if (grepl(".", reference, fixed = TRUE)) reference else paste0(section_of(key), ".", reference)
            if (is.null(configuration[[target]])) {
                report(definition$origin, "E_UNDEFINED", paste0(key, ": undefined reference ", target)); return(NULL)
            }
            if (target %in% progress) {
                path <- c(progress[seq.int(match(target, progress), length(progress))], target)
                report(configuration[[target]]$origin, "E_CYCLE", paste0("interpolation cycle ", paste(path, collapse = " -> ")))
                cycle_keys <<- union(cycle_keys, path)
                expanded <- NULL
            } else expanded <- expand(target)
            if (is.null(expanded)) {
                if (!(key %in% cycle_keys)) report(definition$origin, "E_DEPENDENCY", paste0(key, ": depends on failed key ", target))
                return(NULL)
            }
            pieces <- c(pieces, expanded)
            position <- position + close + 2L
        }
        paste(pieces, collapse = "")
    }
    for (key in key_order(names(configuration))) expand(key)
    as.list(results, all.names = TRUE)
}
