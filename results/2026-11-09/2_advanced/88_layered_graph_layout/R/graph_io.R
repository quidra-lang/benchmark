SETTING_NAMES <- c("layering", "width", "promotion", "heuristic", "sweeps", "node_sep", "dummy_sep",
    "layer_gap", "direction", "sifting", "reduce", "restarts", "seed")
DEFAULTS <- setNames(list("longest", 4L, "off", "barycenter", 12L, 2L, 1L, 3L, "TB", "off", "off", 0L, 1L), SETTING_NAMES)
CHOICES <- list(layering=c("longest", "coffman"), promotion=c("on", "off"), heuristic=c("barycenter", "median"),
    direction=c("TB", "BT", "LR", "RL"), sifting=c("on", "off"), reduce=c("on", "off"))
RANGES <- list(width=c(1,40), sweeps=c(0,50), node_sep=c(1,9), dummy_sep=c(1,9),
    layer_gap=c(2,9), restarts=c(0,9), seed=c(1,2147483646))
setting_value <- function(name, word) {
    if (name %in% names(CHOICES)) return(if (word %in% CHOICES[[name]]) word else NULL)
    if (name %in% names(RANGES) && grepl("^[0-9]{1,10}$", word)) {
        value <- as.numeric(word)
        range <- RANGES[[name]]
        if (value >= range[1] && value <= range[2]) return(as.integer(value))
    }
    NULL
}
input_lines <- function(name) {
    lines <- readLines(file.path("input", name), warn=FALSE)
    indices <- which(nzchar(lines) & !startsWith(lines, "#"))
    lapply(indices, function(i) list(number=i, fields=strsplit(lines[i], " ", fixed=TRUE)[[1]]))
}
read_defaults <- function() {
    settings <- DEFAULTS
    for (record in input_lines("params.txt")) settings[[record$fields[1]]] <- setting_value(record$fields[1], record$fields[2])
    settings
}
new_input_graph <- function(name, defaults) {
    graph <- new.env(parent=emptyenv())
    graph$name <- name
    graph$settings <- defaults
    graph$nodes <- character()
    graph$edges <- list()
    graph$edge_set <- new.env(hash=TRUE, parent=emptyenv())
    graph$path <- NULL
    graph$self_loops <- graph$duplicates <- 0L
    graph$error <- NULL
    graph
}
accept_line <- function(graph, fields) {
    kind <- fields[1]
    if (kind == "OPTION") {
        value <- setting_value(fields[2], fields[3])
        if (is.null(value)) return("bad_option")
        graph$settings[[fields[2]]] <- value
    } else if (kind == "NODE") {
        id <- fields[2]
        if (id %in% names(graph$nodes)) return("duplicate_node")
        if (length(graph$nodes) == 40L) return("too_many_nodes")
        graph$nodes[id] <- fields[3]
    } else {
        a <- fields[2]
        b <- fields[3]
        if (!a %in% names(graph$nodes) || !b %in% names(graph$nodes)) return("unknown_node")
        key <- paste(a, b)
        if (kind == "PATH") {
            graph$path <- as.integer(c(a, b))
        } else if (a == b) {
            graph$self_loops <- graph$self_loops+1L
        } else if (exists(key, graph$edge_set, inherits=FALSE)) {
            graph$duplicates <- graph$duplicates+1L
        } else {
            graph$edge_set[[key]] <- TRUE
            graph$edges[[length(graph$edges)+1L]] <- as.integer(c(a, b))
        }
    }
    ""
}
read_graphs <- function(defaults) {
    graphs <- list()
    graph <- NULL
    for (record in input_lines("graphs.txt")) {
        fields <- record$fields
        if (fields[1] == "GRAPH") {
            graph <- new_input_graph(fields[2], defaults)
            graphs[[length(graphs)+1L]] <- graph
        } else if (fields[1] == "END") {
            if (is.null(graph$error) && !length(graph$nodes)) graph$error <- list(kind="no_nodes", line=record$number)
        } else if (is.null(graph$error)) {
            error <- accept_line(graph, fields)
            if (nzchar(error)) graph$error <- list(kind=error, line=record$number)
        }
    }
    graphs
}
