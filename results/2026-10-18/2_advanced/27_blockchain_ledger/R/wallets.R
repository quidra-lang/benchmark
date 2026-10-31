wallet <- function(name, secret) list(
    name = name,
    secret = secret,
    address = substr(digest(paste0("addr:", secret)), 1L, 16L)
)
signature <- function(secret, index, body) substr(digest(paste(secret, index, body, sep = ":")), 1L, 16L)
read_wallets <- function(path) lapply(
    strsplit(readLines(path), " ", fixed = TRUE),
    function(fields) wallet(fields[1L], fields[2L])
)
