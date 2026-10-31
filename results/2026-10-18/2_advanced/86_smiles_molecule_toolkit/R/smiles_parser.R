character_at <- function(text, position) {
    if (position >= 1L && position <= nchar(text)) substr(text, position, position) else ""
}
text_slice <- function(text, a, b) if (a <= b) substr(text, a, b) else ""
ascii_digit <- function(c) grepl("^[0-9]$", c)
read_organic <- function(text, position) {
    pair <- substr(text, position, position+1L)
    if (pair %in% c("Cl", "Br")) return(list(symbol=pair, aromatic=FALSE, next_position=position+2L))
    c <- character_at(text, position)
    if (grepl("^[BCNOPSFI]$", c)) return(list(symbol=c, aromatic=FALSE, next_position=position+1L))
    if (grepl("^[bcnops]$", c)) return(list(symbol=toupper(c), aromatic=TRUE, next_position=position+1L))
    NULL
}
read_bracket <- function(content, elements, column) {
    position <- 1L
    while (ascii_digit(character_at(content, position))) position <- position+1L
    if (position >= 5L || (position > 1L && character_at(content, 1L) == "0")) {
        analysis_error("bad bracket atom", column)
    }
    mass <- if (position == 1L) 0L else as.integer(substr(content, 1L, position-1L))
    c <- character_at(content, position)
    if (!nzchar(c)) analysis_error("bad bracket atom", column)
    aromatic <- grepl("^[bcnops]$", c)
    if (aromatic) {
        symbol <- toupper(c)
        position <- position+1L
    } else if (grepl("^[A-Z]$", c)) {
        pair <- substr(content, position, position+1L)
        if (grepl("^[A-Z][a-z]$", pair) && pair %in% names(elements)) {
            symbol <- pair
            position <- position+2L
        } else if (c %in% names(elements)) {
            symbol <- c
            position <- position+1L
        } else {
            analysis_error("unknown element", column)
        }
    } else {
        analysis_error("bad bracket atom", column)
    }
    if (character_at(content, position) == "@") {
        position <- position+1L
        if (character_at(content, position) == "@") position <- position+1L
    }
    hydrogens <- charge <- 0L
    if (character_at(content, position) == "H") {
        hydrogens <- 1L
        position <- position+1L
        if (ascii_digit(character_at(content, position))) {
            hydrogens <- as.integer(character_at(content, position))
            position <- position+1L
        }
    }
    c <- character_at(content, position)
    if (c %in% c("+", "-")) {
        charge <- if (c == "+") 1L else -1L
        position <- position+1L
        c <- character_at(content, position)
        if (c %in% as.character(1:9)) {
            charge <- charge*as.integer(c)
            position <- position+1L
        }
    }
    if (position != nchar(content)+1L) analysis_error("bad bracket atom", column)
    new_atom(elements[[symbol]], aromatic, mass, charge, hydrogens, TRUE, column)
}
read_atom <- function(text, position, elements) {
    if (character_at(text, position) == "[") {
        closing <- regexpr("]", substring(text, position+1L), fixed=TRUE)[1]
        if (closing < 0L) analysis_error("unclosed bracket", position)
        last <- position+closing
        return(list(atom=read_bracket(text_slice(text, position+1L, last-1L), elements, position),
            next_position=last+1L))
    }
    organic <- read_organic(text, position)
    if (is.null(organic)) analysis_error("unexpected character", position)
    list(atom=new_atom(elements[[organic$symbol]], organic$aromatic, column=position),
        next_position=organic$next_position)
}
parse_smiles <- function(text, elements, pattern=FALSE) {
    molecule <- new_molecule(elements)
    symbols <- if (pattern) c("-"=1L, "="=2L, "#"=3L, ":"=4L, "~"=5L) else BOND_TYPES
    current <- 0L
    pending <- NULL
    position <- 1L
    branches <- open_rings <- list()
    while (position <= nchar(text)) {
        c <- character_at(text, position)
        column <- position
        if (c %in% names(symbols)) {
            if (current == 0L || !is.null(pending)) analysis_error("misplaced bond", column)
            pending <- list(symbol=c, column=column)
            position <- position+1L
        } else if (c == "(") {
            if (current == 0L || !is.null(pending) || character_at(text, position-1L) == "(") {
                analysis_error("misplaced branch", column)
            }
            branches[[length(branches)+1L]] <- c(current, column)
            position <- position+1L
        } else if (c == ")") {
            if (!length(branches)) analysis_error("unmatched parenthesis", column)
            if (!is.null(pending)) analysis_error("dangling bond", pending$column)
            if (character_at(text, position-1L) == "(") analysis_error("empty branch", column)
            current <- branches[[length(branches)]][1]
            branches <- head(branches, -1)
            position <- position+1L
        } else if (ascii_digit(c) || c == "%") {
            if (current == 0L) analysis_error("misplaced ring closure", column)
            if (c == "%") {
                if (!ascii_digit(character_at(text, position+1L)) || !ascii_digit(character_at(text, position+2L))) {
                    analysis_error("bad ring number", column)
                }
                ring <- as.integer(substr(text, position+1L, position+2L))
                position <- position+3L
            } else {
                ring <- as.integer(c)
                position <- position+1L
            }
            symbol <- if (is.null(pending)) NULL else pending$symbol
            pending <- NULL
            key <- as.character(ring)
            opened <- open_rings[[key]]
            if (is.null(opened)) {
                open_rings[[key]] <- list(atom=current, symbol=symbol, column=column)
                next
            }
            if (opened$atom == current) analysis_error("self bond", column)
            if (!is.null(opened$symbol) && !is.null(symbol) && symbols[[opened$symbol]] != symbols[[symbol]]) {
                analysis_error("ring bond mismatch", column)
            }
            if (!is.null(get_bond(molecule, opened$atom, current))) analysis_error("duplicate bond", column)
            add_bond(molecule, opened$atom, current, if (is.null(symbol)) opened$symbol else symbol)
            open_rings[[key]] <- NULL
        } else {
            read <- if (pattern) read_pattern_atom(text, position, elements) else read_atom(text, position, elements)
            number <- add_atom(molecule, read$atom)
            if (current != 0L) add_bond(molecule, current, number, if (is.null(pending)) NULL else pending$symbol)
            current <- number
            pending <- NULL
            position <- read$next_position
        }
    }
    if (!is.null(pending)) analysis_error("dangling bond", pending$column)
    if (length(branches)) analysis_error("unmatched parenthesis", branches[[1]][2])
    if (length(open_rings)) analysis_error("unclosed ring", min(vapply(open_rings, function(r) r$column, 0L)))
    molecule
}
