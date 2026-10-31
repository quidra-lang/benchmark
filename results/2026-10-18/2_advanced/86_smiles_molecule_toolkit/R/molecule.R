ORGANIC <- c("B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I")
AROMATIC <- c("B", "C", "N", "O", "P", "S")
BOND_TYPES <- c("-"=1L, "/"=1L, "\\"=1L, "="=2L, "#"=3L, ":"=4L)
BASE_VALUES <- c(1L, 2L, 3L, 1L)
analysis_error <- function(reason, column) {
    stop(structure(list(message=reason, reason=reason, column=column, call=NULL),
        class=c("analysis_error", "error", "condition")))
}
new_atom <- function(element, aromatic=FALSE, mass=0L, charge=0L, hydrogens=0L, bracket=FALSE, column=0L) {
    atom <- new.env(parent=emptyenv())
    atom$element <- element
    atom$aromatic <- aromatic
    atom$mass <- mass
    atom$charge <- charge
    atom$hydrogens <- hydrogens
    atom$bracket <- bracket
    atom$column <- column
    atom
}
new_molecule <- function(elements) {
    molecule <- new.env(parent=emptyenv())
    molecule$elements <- elements
    molecule$atoms <- molecule$neighbors <- molecule$bonds <- molecule$rings <- list()
    molecule$ring_atoms <- integer()
    molecule$name <- ""
    molecule
}
add_atom <- function(m, atom) {
    number <- length(m$atoms)+1L
    m$atoms[[number]] <- atom
    m$neighbors[[number]] <- list()
    number
}
bond_key <- function(a, b) paste(sort(c(a, b)), collapse=",")
add_bond <- function(m, a, b, symbol) {
    bond <- new.env(parent=emptyenv())
    bond$ends <- sort(c(a, b))
    bond$symbol <- symbol
    bond$kind <- bond$multiplicity <- 0L
    bond$ring <- FALSE
    m$bonds[[bond_key(a, b)]] <- bond
    m$neighbors[[a]][[as.character(b)]] <- bond
    m$neighbors[[b]][[as.character(a)]] <- bond
    bond
}
ordered_bonds <- function(m) {
    values <- unname(m$bonds)
    values[order(vapply(values, function(b) b$ends[1], 0), vapply(values, function(b) b$ends[2], 0))]
}
neighbor_numbers <- function(m, a) sort(as.integer(names(m$neighbors[[a]])))
get_bond <- function(m, a, b) m$neighbors[[a]][[as.character(b)]]
degree <- function(m, a) length(m$neighbors[[a]])
base_total <- function(m, a) sum(vapply(m$neighbors[[a]], function(b) BASE_VALUES[b$kind], 0L))
bond_total <- function(m, a) sum(vapply(m$neighbors[[a]], function(b) b$multiplicity, 0L))
read_elements <- function() {
    elements <- list()
    for (text in readLines("input/elements.txt", warn=FALSE)) {
        if (!nzchar(text) || startsWith(text, "#")) next
        f <- strsplit(text, " ", fixed=TRUE)[[1]]
        elements[[f[1]]] <- list(symbol=f[1], number=as.integer(f[2]), weight=as.integer(f[3]),
            valences=as.integer(strsplit(f[4], ",", fixed=TRUE)[[1]]))
    }
    elements
}
needs_pi <- function(m, a, hydrogens=m$atoms[[a]]$hydrogens) {
    atom <- m$atoms[[a]]
    atom$aromatic && atom$element$valences[1]+atom$charge >= base_total(m, a)+hydrogens+1L
}
organic_hydrogens <- function(atom, total) {
    eligible <- atom$element$valences[atom$element$valences >= total]
    if (length(eligible)) eligible[1]-total else NULL
}
