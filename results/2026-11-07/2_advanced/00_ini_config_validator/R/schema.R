load_schema <- function(path) {
    specs <- list(); lines <- read_lines(path)
    for (number in seq_along(lines)) {
        line <- lines[number]
        if (trim_spaces(line) == "" || startsWith(line, "#")) next
        words <- split_keep(line, " ")
        pattern <- words[1L]; parts <- split_keep(section_of(pattern), ".")
        spec <- list(id = length(specs) + 1L, line = number, pattern = pattern, key = key_name(pattern), parts = parts,
                     wildcard = "*" %in% parts, kind = words[2L], required = FALSE, secret = FALSE,
                     unique = FALSE, fixed = FALSE, default = NULL, range = NULL, values = character(),
                     item = "string", aliases = character(), when = NULL, le = NULL)
        for (attribute in words[-c(1L, 2L)]) {
            pair <- cut_first(attribute, "="); name <- pair$before; argument <- pair$after
            if (name %in% c("required", "secret", "unique", "fixed")) {
                spec[[name]] <- TRUE
            } else if (name == "range") {
                spec$range <- split_keep(argument, "..")
            } else if (name == "values") {
                spec$values <- split_keep(argument, ",")
            } else if (name == "alias") {
                spec$aliases <- split_keep(argument, ",")
            } else {
                spec[[name]] <- argument
            }
        }
        specs[[length(specs) + 1L]] <- spec
    }
    specs
}

spec_matches <- function(spec, section) {
    parts <- split_keep(section, ".")
    length(parts) == length(spec$parts) && all(spec$parts == "*" | spec$parts == parts)
}

spec_for <- function(schema, key) {
    for (spec in schema) if (!spec$wildcard && spec$pattern == key) return(spec)
    for (spec in schema) if (spec$wildcard && spec$key == key_name(key) && spec_matches(spec, section_of(key))) return(spec)
    NULL
}

target_keys <- function(schema, spec, sections) {
    if (!spec$wildcard) return(spec$pattern)
    targets <- character()
    for (section in sort(sections, method = "radix")) {
        key <- paste0(section, ".", spec$key)
        if (spec_matches(spec, section) && identical(spec_for(schema, key)$id, spec$id)) targets <- c(targets, key)
    }
    targets
}
