header_text <- function(height, previous, merkle, timestamp, difficulty, nonce) paste(
    height,
    previous,
    merkle,
    timestamp,
    difficulty,
    nonce,
    sep = "|"
)
block <- function(height, previous, merkle, timestamp, difficulty, nonce, transactions) {
    list(height = height, previous = previous, merkle = merkle, timestamp = timestamp, difficulty = difficulty, nonce = nonce, transactions = transactions,
         hash = digest(header_text(height, previous, merkle, timestamp, difficulty, nonce)))
}
block_size <- function(block) sum(vapply(block$transactions[-1L], function(tx) tx$size, 0L))
meets_difficulty <- function(hash, difficulty) startsWith(hash, paste(rep("0", difficulty), collapse = ""))
parse_block_event <- function(fields, texts) block(
    as.integer(fields[4L]),
    fields[5L],
    fields[6L],
    as.integer(fields[7L]),
    as.integer(fields[8L]),
    as.integer(fields[9L]),
    lapply(texts, parse_transaction)
)
mine_block <- function(height, previous, transactions, timestamp, difficulty) {
    root <- merkle_root(vapply(transactions, function(tx) tx$txid, ""))
    nonce <- 0L
    while (!meets_difficulty(
        digest(header_text(height, previous, root, timestamp, difficulty, nonce)),
        difficulty
    )) nonce <- nonce + 1L
    block(height, previous, root, timestamp, difficulty, nonce, transactions)
}
context_free_error <- function(block, max_size) {
    if (!meets_difficulty(block$hash, block$difficulty)) return("bad-pow")
    if (merkle_root(vapply(
        block$transactions,
        function(tx) tx$txid,
        ""
    )) != block$merkle) return("bad-merkle")
    first <- block$transactions[[1L]]
    if (!is_coinbase(first) || first$coinbase_height != block$height || any(vapply(
        block$transactions[-1L],
        is_coinbase,
        FALSE
    ))) return("bad-structure")
    if (block_size(block) > max_size) return("too-large")
    NULL
}
