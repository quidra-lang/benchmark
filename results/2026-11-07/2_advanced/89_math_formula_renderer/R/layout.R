ELEMENT_TYPES <- c("ordinary", "operator", "binary", "relation", "open", "close", "punctuation")
SPACING <- list(list(0L,1L,"B","R",0L,0L,0L), list(1L,1L,NULL,"R",0L,0L,0L),
    list("B","B",NULL,NULL,"B",NULL,NULL), list("R","R",NULL,0L,"R",0L,0L),
    list(0L,0L,NULL,0L,0L,0L,0L), list(0L,1L,"B","R",0L,0L,0L), list("P","P",NULL,"P","P","P","P"))
element_types <- function(node) {
    kind <- node$kind
    if (kind == "symbol") {
        type <- if (node$value %in% names(SYMBOL_TYPES)) SYMBOL_TYPES[[node$value]] else "ordinary"
    } else if (kind == "command") {
        type <- COMMAND_TYPES[[node$value]]
    } else if (kind == "delim") {
        return(c("open", "close"))
    } else if (kind == "script") {
        return(element_types(node$children[[1]]))
    } else if (kind %in% c("overset", "underset")) {
        return(element_types(node$children[[2]]))
    } else type <- "ordinary"
    c(type,type)
}
converted_types <- function(nodes) {
    result <- lapply(nodes, element_types)
    for (i in seq_along(result)) {
        current <- result[[i]]
        if (current[1] == "binary" && (i == 1L || result[[i-1L]][2] %in% c("binary","operator","relation","open","punctuation"))) current <- c("ordinary","ordinary")
        result[[i]] <- current
        if (current[1] %in% c("relation","close","punctuation") && i > 1L && result[[i-1L]][2] == "binary") result[[i-1L]] <- c("ordinary","ordinary")
    }
    if (length(result) && result[[length(result)]][2] == "binary") result[[length(result)]] <- c("ordinary","ordinary")
    result
}
word_element <- function(node) {
    if (node$kind == "script") return(word_element(node$children[[1]]))
    node$kind == "command" && (substring(node$value,2L) %in% GREEK || node$value == "\\infty")
}
alphanumeric <- function(node) {
    if (node$kind %in% c("identifier","number") || word_element(node)) return(TRUE)
    if (node$kind == "script") return(alphanumeric(node$children[[1]]))
    node$kind == "accent" && node$value %in% c("overline","hat","vec","dot","tilde") && alphanumeric(node$children[[1]])
}
spacing <- function(nodes, style, parameters) {
    types <- converted_types(nodes)
    values <- c(B=if (style == "normal") parameters$bin_space else 0L,
        R=if (style == "normal") parameters$rel_space else 0L, P=if (style == "normal") parameters$punct_space else 0L)
    gaps <- integer()
    for (i in seq_len(max(0L,length(nodes)-1L))) {
        first <- nodes[[i]]
        second <- nodes[[i+1L]]
        if (alphanumeric(first) && alphanumeric(second) && (word_element(first) || word_element(second))) {
            gaps <- c(gaps, 1L)
        } else {
            row <- match(types[[i]][2], ELEMENT_TYPES)
            column <- match(types[[i+1L]][1], ELEMENT_TYPES)
            entry <- SPACING[[row]][[column]]
            gaps <- c(gaps, if (is.character(entry)) values[[entry]] else entry)
        }
    }
    list(types=types, gaps=gaps)
}
row_box <- function(children, gaps, description="row", roles=rep("",length(children))) {
    ascent <- max(c(0L, vapply(children, function(child) child$baseline, 0L)))
    depth <- max(c(0L, vapply(children, descent, 0L)))
    width <- sum(vapply(children, function(child) child$width, 0L))+sum(gaps)
    result <- new_box(width, ascent+depth+1L, ascent, description)
    x <- 0L
    for (i in seq_along(children)) {
        child <- children[[i]]
        add_child(result, child, x, ascent-child$baseline, roles[i])
        x <- x+child$width
        if (i <= length(gaps)) x <- x+gaps[i]
    }
    result
}
