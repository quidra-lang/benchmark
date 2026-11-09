pattern_matches <- function(pattern, atom) {
    if (!is.null(pattern$choices)) {
        return(paste0(atom$element$symbol, ":", as.integer(atom$aromatic)) %in% pattern$choices)
    }
    is.null(pattern$aromatic) || atom$aromatic == pattern$aromatic
}
read_pattern_atom <- function(text, position, elements) {
    c <- character_at(text, position)
    if (c %in% c("*", "A", "a")) {
        return(list(atom=list(choices=NULL, aromatic=if (c == "*") NULL else c == "a"), next_position=position+1L))
    }
    if (c == "[") {
        closing <- regexpr("]", substring(text, position+1L), fixed=TRUE)[1]
        if (closing < 0L) analysis_error("unclosed bracket", position)
        last <- position+closing
        content <- text_slice(text, position+1L, last-1L)
        if (!nzchar(content) || endsWith(content, ",")) analysis_error("bad bracket atom", position)
        choices <- character()
        for (item in strsplit(content, ",", fixed=TRUE)[[1]]) {
            organic <- read_organic(item, 1L)
            if (is.null(organic) || organic$next_position != nchar(item)+1L) analysis_error("bad bracket atom", position)
            choices <- union(choices, paste0(organic$symbol, ":", as.integer(organic$aromatic)))
        }
        return(list(atom=list(choices=choices, aromatic=NULL), next_position=last+1L))
    }
    organic <- read_organic(text, position)
    if (is.null(organic)) analysis_error("unexpected character", position)
    list(atom=list(choices=paste0(organic$symbol, ":", as.integer(organic$aromatic)), aromatic=NULL),
        next_position=organic$next_position)
}
molecule_pattern <- function(m) {
    pattern <- new_molecule(m$elements)
    for (atom in m$atoms) {
        add_atom(pattern, list(choices=paste0(atom$element$symbol, ":", as.integer(atom$aromatic)), aromatic=NULL))
    }
    for (bond in ordered_bonds(m)) add_bond(pattern, bond$ends[1], bond$ends[2], bond$kind)
    pattern
}
bond_matches <- function(pattern, bond) {
    symbol <- pattern$symbol
    if (is.null(symbol)) return(bond$kind %in% c(1L, 4L))
    if (is.character(symbol) && symbol == "~") return(TRUE)
    kind <- if (is.numeric(symbol)) symbol else BOND_TYPES[[symbol]]
    bond$kind == kind
}
embeddings <- function(pattern, m) {
    n <- length(m$atoms)
    k <- length(pattern$atoms)
    if (k > n) return(list(count=0L, unique=0L, mapping=integer()))
    candidates <- lapply(seq_len(k), function(i) {
        which(vapply(seq_len(n), function(a) {
            pattern_matches(pattern$atoms[[i]], m$atoms[[a]]) && degree(m, a) >= degree(pattern, i)
        }, FALSE))
    })
    mapping <- used <- integer()
    sets <- new.env(hash=TRUE, parent=emptyenv())
    count_matches <- 0L
    first_mapping <- integer()
    assign_atom <- function(i) {
        if (i > k) {
            count_matches <<- count_matches+1L
            sets[[paste(sort(used), collapse=",")]] <- TRUE
            if (!length(first_mapping)) first_mapping <<- mapping
            return(invisible(NULL))
        }
        for (a in candidates[[i]]) {
            if (a %in% used) next
            feasible <- TRUE
            for (b in neighbor_numbers(pattern, i)) {
                if (b >= i) next
                target <- get_bond(m, a, mapping[b])
                if (is.null(target) || !bond_matches(get_bond(pattern, i, b), target)) {
                    feasible <- FALSE
                    break
                }
            }
            if (!feasible) next
            mapping <<- c(mapping, a)
            used <<- c(used, a)
            assign_atom(i+1L)
            used <<- setdiff(used, a)
            mapping <<- head(mapping, -1)
        }
    }
    assign_atom(1L)
    list(count=count_matches, unique=length(ls(sets, all.names=TRUE)), mapping=first_mapping)
}
fingerprint <- function(m) {
    codes <- vapply(seq_along(m$atoms), function(a) {
        16L*m$atoms[[a]]$element$number+8L*as.integer(m$atoms[[a]]$aromatic)+degree(m, a)
    }, 0L)
    bits <- rep(FALSE, 1024L)
    used <- integer()
    paths <- 0L
    extend_path <- function(a, depth, value) {
        paths <<- paths+1L
        bits[value %% 1024L+1L] <<- TRUE
        if (depth == 5L) return(invisible(NULL))
        for (b in neighbor_numbers(m, a)) {
            if (b %in% used) next
            next_value <- (value*31L+get_bond(m, a, b)$kind) %% 1000003L
            next_value <- (next_value*31L+codes[b]) %% 1000003L
            used <<- c(used, b)
            extend_path(b, depth+1L, next_value)
            used <<- setdiff(used, b)
        }
    }
    for (a in seq_along(codes)) {
        used <- a
        extend_path(a, 0L, codes[a])
    }
    list(bits=which(bits)-1L, paths=paths)
}
tanimoto <- function(a, b) {
    common <- length(intersect(a, b))
    c(common, length(a)+length(b)-common)
}
