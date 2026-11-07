new_bid <- function(number, bidder, bundle, amount, xor) {
    list(number=number, bidder=bidder, bundle=bundle, amount=amount, xor=xor)
}
records <- function(name) strsplit(readLines(file.path("input", name), warn=FALSE), " ", fixed=TRUE)
read_inputs <- function() {
    reserves <- numeric()
    for (row in records("items.txt")) reserves[row[1]] <- as.numeric(row[2])
    raw <- list()
    current <- NULL
    for (fields in records("bids.txt")) {
        if (fields[1] == "auction") {
            if (!is.null(current)) raw[[current$name]] <- current
            current <- list(name=fields[2], items=fields[-c(1,2)], lines=list())
        } else {
            current$lines[[length(current$lines)+1L]] <- list(
                name=fields[2],
                language=fields[3],
                texts=fields[-c(1,2,3)]
            )
        }
    }
    if (!is.null(current)) raw[[current$name]] <- current
    groups <- list()
    current <- NULL
    for (fields in records("single_item.txt")) {
        if (fields[1] %in% c("lot", "slots")) {
            if (!is.null(current)) groups[[length(groups)+1L]] <- current
            current <- list(kind=fields[1], name=fields[2], arguments=fields[-c(1,2)], participants=list())
        } else {
            current$participants[[length(current$participants)+1L]] <- list(
                name=fields[2],
                value=as.numeric(fields[3]),
                bid=as.numeric(fields[4])
            )
        }
    }
    if (!is.null(current)) groups[[length(groups)+1L]] <- current
    parameters <- list()
    for (fields in records("params.txt")) parameters[[fields[1]]] <- if (fields[1] == "run") fields[-1] else as.numeric(fields[2])
    list(reserves=reserves, raw=raw, groups=groups, parameters=parameters)
}
