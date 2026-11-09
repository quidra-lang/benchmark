address_value <- function(text) sum(as.numeric(strsplit(text, ".", fixed = TRUE)[[1L]]) * c(
    16777216,
    65536,
    256,
    1
))
address_text <- function(value) paste((value %/% c(16777216, 65536, 256, 1)) %% 256, collapse = ".")
parse_prefix <- function(text) {
    fields <- strsplit(text, "/", fixed = TRUE)[[1L]]
    list(address = address_value(fields[1L]), length = as.integer(fields[2L]))
}
prefix_text <- function(prefix) paste0(address_text(prefix$address), "/", prefix$length)
prefix_contains <- function(
    prefix,
    address
) (address %/% 2^(32L - prefix$length)) == (prefix$address %/% 2^(32L - prefix$length))
prefix_order <- function(prefixes) {
    if (!length(prefixes)) return(character())
    parsed <- lapply(prefixes, parse_prefix)
    prefixes[order(
        vapply(parsed, function(prefix) prefix$address, 0),
        vapply(parsed, function(prefix) prefix$length, 0L)
    )]
}
other_end <- function(link, owner) if (owner == link$first) link$second else link$first
link_role <- function(
    link,
    owner
) if (link$relationship == "P2P") "peer" else if (owner == link$first) "customer" else "provider"
link_direction <- function(link, owner) c(
    customer = "D",
    peer = "P",
    provider = "U"
)[[link_role(link, owner)]]

read_topology <- function() {
    router_ids <- list()
    links <- initial <- list()
    for (line in readLines("input/topology.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        if (fields[1L] == "AS") {
            router_ids[[fields[2L]]] <- address_value(fields[3L])
        } else if (fields[1L] == "LINK") {
            link <- new.env(parent = emptyenv())
            link$number <- length(links) + 1L
            link$name <- fields[2L]
            link$first <- as.integer(fields[3L])
            link$second <- as.integer(fields[4L])
            link$relationship <- fields[5L]
            link$delay <- as.integer(fields[6L])
            link$mrai <- as.integer(fields[7L])
            link$up <- TRUE
            link$down_count <- 0L
            links[[length(links) + 1L]] <- link
        } else {
            initial[[length(initial) + 1L]] <- list(
                owner = as.integer(fields[2L]),
                prefix = fields[3L],
                origin = fields[4L],
                communities = fields[-(1:4)]
            )
        }
    }
    ases <- sort(as.integer(names(router_ids)))
    at_as <- setNames(
        lapply(
            ases,
            function(owner) which(vapply(links, function(link) owner %in% c(link$first, link$second), FALSE))
        ),
        as.character(ases)
    )
    by_name <- setNames(seq_along(links), vapply(links, function(link) link$name, ""))
    between <- new.env(parent = emptyenv())
    for (link in links) {
        key <- paste(sort(c(link$first, link$second)), collapse = ":")
        between[[key]] <- c(between[[key]], link$number)
    }
    list(
        router_ids = router_ids,
        ases = ases,
        links = links,
        initial = initial,
        at_as = at_as,
        by_name = by_name,
        between = between
    )
}
