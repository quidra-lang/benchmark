parse_transaction <- function(text) {
    parts <- strsplit(text, ";", fixed = TRUE)[[1L]]
    values <- function(part) substring(part, regexpr("=", part, fixed = TRUE) + 1L)
    outputs <- lapply(strsplit(values(parts[2L]), ",", fixed = TRUE)[[1L]], function(item) {
        pair <- strsplit(item, ":", fixed = TRUE)[[1L]]
        list(address = pair[1L], amount = as.integer(pair[2L]))
    })
    cb <- startsWith(parts[1L], "cb=")
    list(text = text, txid = digest(text), size = nchar(text, type = "bytes"),
         inputs = if (cb) character() else strsplit(values(parts[1L]), ",", fixed = TRUE)[[1L]],
         outputs = outputs,
         signatures = if (cb) character() else strsplit(values(parts[3L]), ",", fixed = TRUE)[[1L]],
         coinbase_height = if (cb) as.integer(values(parts[1L])) else NULL)
}
is_coinbase <- function(tx) !is.null(tx$coinbase_height)
output_total <- function(tx) sum(vapply(tx$outputs, function(output) output$amount, 0L))
transaction_body <- function(tx) strsplit(tx$text, ";sig=", fixed = TRUE)[[1L]][1L]
pairs_text <- function(outputs) paste(
    vapply(outputs, function(output) paste(output$address, output$amount, sep = ":"), ""),
    collapse = ","
)
create_transaction <- function(inputs, outputs, secret) {
    body <- paste0("in=", paste(inputs, collapse = ","), ";out=", pairs_text(outputs))
    signatures <- vapply(seq_along(inputs), function(i) signature(secret, i - 1L, body), "")
    parse_transaction(paste0(body, ";sig=", paste(signatures, collapse = ",")))
}
create_coinbase <- function(height, outputs) parse_transaction(paste0(
    "cb=",
    height,
    ";out=",
    pairs_text(outputs)
))
is_mature <- function(
    coin,
    height,
    maturity
) !coin$coinbase || coin$height == 0L || height >= coin$height + maturity
check_transaction <- function(tx, utxo, spent, height, owners, maturity) {
    failure <- function(reason) list(reason = reason, fee = 0L)
    for (output in tx$outputs) if (is.null(owners[[output$address]]) || output$amount == 0L) return(failure("bad-output"))
    seen <- character()
    total <- 0L
    for (i in seq_along(tx$inputs)) {
        ref <- tx$inputs[i]
        if (ref %in% spent || ref %in% seen) return(failure("double-spend"))
        coin <- utxo[[ref]]
        if (is.null(coin)) return(failure("missing-input"))
        if (!is_mature(coin, height, maturity)) return(failure("immature"))
        if (tx$signatures[i] != signature(
            owners[[coin$address]]$secret,
            i - 1L,
            transaction_body(tx)
        )) return(failure("bad-sig"))
        seen <- c(seen, ref)
        total <- total + coin$amount
    }
    if (total < output_total(tx)) return(failure("overspend"))
    list(reason = NULL, fee = total - output_total(tx))
}
apply_transaction <- function(utxo, tx, height) {
    utxo[tx$inputs] <- NULL
    for (i in seq_along(tx$outputs)) {
        output <- tx$outputs[[i]]
        utxo[[paste(tx$txid, i - 1L, sep = ":")]] <- list(
            address = output$address,
            amount = output$amount,
            height = height,
            coinbase = is_coinbase(tx)
        )
    }
    utxo
}
