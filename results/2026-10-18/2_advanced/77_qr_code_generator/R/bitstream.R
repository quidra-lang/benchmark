QR_ALPHANUMERIC <- strsplit("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:", "", fixed = TRUE)[[1]]
QR_ALPHA_VALUES <- setNames(seq_along(QR_ALPHANUMERIC) - 1L, QR_ALPHANUMERIC)

binary_digits <- function(value, width) {
    paste0(as.integer(intToBits(as.integer(value)))[seq_len(width)][width:1L], collapse = "")
}

codeword_bits <- function(words) paste0(vapply(words, binary_digits, "", width = 8L), collapse = "")
hex_words <- function(words) paste0(sprintf("%02x", as.integer(words)), collapse = "")

bits_codewords <- function(bits) {
    if (!nzchar(bits)) return(integer())
    vapply(seq.int(1L, nchar(bits), by = 8L), function(index) {
        strtoi(substr(bits, index, index + 7L), base = 2L)
    }, 0L)
}

new_bit_reader <- function(bits) {
    reader <- new.env(parent = emptyenv())
    reader$bits <- bits
    reader$position <- 0L
    reader
}

remaining_bits <- function(reader) nchar(reader$bits) - reader$position

read_bits <- function(reader, width) {
    start <- reader$position + 1L
    reader$position <- reader$position + width
    strtoi(substr(reader$bits, start, reader$position), base = 2L)
}

new_bit_writer <- function() {
    writer <- new.env(parent = emptyenv())
    writer$parts <- character()
    writer
}

write_bits <- function(writer, value, width) {
    writer$parts <- c(writer$parts, binary_digits(value, width))
}

bit_value <- function(writer) paste0(writer$parts, collapse = "")
