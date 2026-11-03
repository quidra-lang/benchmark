digest <- function(text) {
    bases <- c(1000003, 1500007, 2750159, 4194301)
    initials <- c(11, 23, 37, 53)
    codes <- c(as.integer(charToRaw(text)), nchar(text, type = "bytes"), 0, 0)
    lanes <- vapply(seq_along(bases), function(k) {
        h <- initials[k]
        for (code in codes) h <- (h * bases[k] + code) %% 2147483647
        sprintf("%08x", as.integer(h))
    }, "")
    paste0(lanes, collapse = "")
}
merkle_root <- function(hashes) {
    while (length(hashes) > 1L) {
        if (length(hashes) %% 2L) hashes <- c(hashes, tail(hashes, 1L))
        hashes <- vapply(
            seq.int(1L, length(hashes), 2L),
            function(i) digest(paste0(hashes[i], hashes[i + 1L])),
            ""
        )
    }
    hashes[[1L]]
}
short_hash <- function(text) substr(text, 1L, 8L)
