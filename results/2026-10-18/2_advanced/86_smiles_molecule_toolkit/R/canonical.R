dense_ranks <- function(values) {
    ordered <- list()
    for (value in values) {
        position <- 1L
        while (position <= length(ordered) && sequence_less(ordered[[position]], value)) position <- position+1L
        if (position > length(ordered) || !identical(ordered[[position]], value)) {
            ordered <- append(ordered, list(value), after=position-1L)
        }
    }
    vapply(values, function(value) which(vapply(ordered, function(v) identical(v, value), FALSE))[1], 0L)
}
refine_ranks <- function(m, ranks) {
    repeat {
        values <- lapply(seq_along(m$atoms), function(a) {
            neighbors <- neighbor_numbers(m, a)
            kinds <- vapply(neighbors, function(b) get_bond(m, a, b)$kind, 0L)
            indices <- order(ranks[neighbors], kinds)
            neighborhood <- unlist(lapply(indices, function(i) c(ranks[neighbors[i]], kinds[i])), use.names=FALSE)
            c(ranks[a], neighborhood)
        })
        new_ranks <- dense_ranks(values)
        if (length(unique(new_ranks)) == length(unique(ranks))) return(new_ranks)
        ranks <- new_ranks
    }
}
canonical_ranks <- function(m) {
    invariants <- lapply(seq_along(m$atoms), function(a) {
        atom <- m$atoms[[a]]
        c(degree(m, a), atom$element$number, atom$mass, atom$charge, atom$hydrogens, as.integer(atom$aromatic))
    })
    ranks <- refine_ranks(m, dense_ranks(invariants))
    classes <- length(unique(ranks))
    while (length(unique(ranks)) != length(ranks)) {
        counts <- table(ranks)
        tied <- min(as.integer(names(counts)[counts > 1L]))
        first_atom <- which(ranks == tied)[1]
        values <- 2L*ranks-as.integer(seq_along(ranks) == first_atom)
        ranks <- refine_ranks(m, dense_ranks(as.list(values)))
    }
    list(ranks=ranks, classes=classes)
}
atom_notation <- function(m, a) {
    atom <- m$atoms[[a]]
    symbol <- atom$element$symbol
    ordinary <- symbol %in% ORGANIC && (!atom$aromatic || symbol %in% AROMATIC) && atom$mass == 0L && atom$charge == 0L
    if (atom$aromatic) {
        ordinary <- ordinary && needs_pi(m, a) == needs_pi(m, a, 0L)
        symbol <- tolower(symbol)
    }
    hydrogens <- organic_hydrogens(atom, bond_total(m, a))
    if (ordinary && !is.null(hydrogens) && hydrogens == atom$hydrogens) return(symbol)
    text <- paste0("[", if (atom$mass == 0L) "" else atom$mass, symbol)
    if (atom$hydrogens != 0L) text <- paste0(text, "H", if (atom$hydrogens == 1L) "" else atom$hydrogens)
    if (atom$charge != 0L) {
        text <- paste0(text, if (atom$charge > 0L) "+" else "-",
            if (abs(atom$charge) == 1L) "" else abs(atom$charge))
    }
    paste0(text, "]")
}
canonical_bond_symbol <- function(m, bond) {
    in_ring <- bond$ring && m$atoms[[bond$ends[1]]]$aromatic && m$atoms[[bond$ends[2]]]$aromatic
    if (bond$kind == 1L) return(if (in_ring) "-" else "")
    if (bond$kind == 2L) return("=")
    if (bond$kind == 3L) return("#")
    if (in_ring) "" else ":"
}
canonical_smiles <- function(m, ranks) {
    visits <- integer(length(m$atoms))
    children <- rep(list(list()), length(m$atoms))
    closures <- character()
    visit_count <- 0L
    visit <- function(a, incoming=NULL) {
        visit_count <<- visit_count+1L
        visits[a] <<- visit_count
        neighbors <- neighbor_numbers(m, a)
        for (b in neighbors[order(ranks[neighbors])]) {
            bond <- get_bond(m, a, b)
            key <- bond_key(a, b)
            if (identical(bond, incoming) || key %in% closures) next
            if (visits[b] == 0L) {
                children[[a]][[length(children[[a]])+1L]] <<- list(atom=b, bond=bond)
                visit(b, bond)
            } else closures <<- union(closures, key)
        }
    }
    root <- which(ranks == 1L)[1]
    visit(root)
    assignments <- list()
    occupied <- integer()
    write_atom <- function(a) {
        parts <- atom_notation(m, a)
        neighbors <- neighbor_numbers(m, a)
        for (b in neighbors[order(visits[neighbors])]) {
            bond <- get_bond(m, a, b)
            key <- bond_key(a, b)
            if (!key %in% closures) next
            if (!is.null(assignments[[key]])) {
                number <- assignments[[key]]
                assignments[[key]] <<- NULL
                occupied <<- setdiff(occupied, number)
                symbol <- ""
            } else {
                number <- 1L
                while (number %in% occupied) number <- number+1L
                assignments[[key]] <<- number
                occupied <<- c(occupied, number)
                symbol <- canonical_bond_symbol(m, bond)
            }
            parts <- c(parts, paste0(symbol, if (number < 10L) number else sprintf("%%%02d", number)))
        }
        for (i in seq_along(children[[a]])) {
            child <- children[[a]][[i]]
            continuation <- paste0(canonical_bond_symbol(m, child$bond), write_atom(child$atom))
            parts <- c(parts, if (i < length(children[[a]])) paste0("(", continuation, ")") else continuation)
        }
        paste(parts, collapse="")
    }
    write_atom(root)
}
canonicalize <- function(m) {
    ranking <- canonical_ranks(m)
    list(smiles=canonical_smiles(m, ranking$ranks), classes=ranking$classes)
}
