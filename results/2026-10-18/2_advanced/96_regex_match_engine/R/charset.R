ASCII <- 0L:127L
DIGITS <- 48L:57L
LOWER <- 97L:122L
UPPER <- 65L:90L
WORD <- sort(unique(c(DIGITS, LOWER, UPPER, 95L)))
SPACE <- c(9L, 10L, 11L, 12L, 13L, 32L)
STANDARD <- list(d = DIGITS, w = WORD, s = SPACE)

has_flag <- function(flags, flag) flag %in% strsplit(flags, "", fixed = TRUE)[[1L]]
is_letter <- function(character) {
    character != "" && utf8ToInt(character) %in% c(LOWER, UPPER)
}
is_digit <- function(character) {
    character != "" && utf8ToInt(character) %in% DIGITS
}
switched_code <- function(code) {
    if (code %in% LOWER) return(code - 32L)
    if (code %in% UPPER) return(code + 32L)
    code
}
escaped_set <- function(character) {
    code <- utf8ToInt(character)
    lower <- intToUtf8(if (code %in% UPPER) code + 32L else code)
    base <- STANDARD[[lower]]
    if (code %in% UPPER) setdiff(ASCII, base) else base
}
characters_equal <- function(a, b, flags) {
    a == b || (has_flag(flags, "i") && is_letter(a) && switched_code(utf8ToInt(a)) == utf8ToInt(b))
}
test_char <- function(text, position, expected, flags) {
    position < nchar(text) && characters_equal(substr(text, position + 1L, position + 1L), expected, flags)
}
test_any <- function(text, position, flags) {
    position < nchar(text) && (has_flag(flags, "s") || substr(text, position + 1L, position + 1L) != "\n")
}
code_matches_class <- function(code, codes, negated, flags) {
    present <- code %in% codes || (has_flag(flags, "i") && code %in% c(LOWER, UPPER) && switched_code(code) %in% codes)
    present != negated
}
test_class <- function(text, position, codes, negated, flags) {
    position < nchar(text) && code_matches_class(utf8ToInt(substr(text, position + 1L, position + 1L)), codes, negated, flags)
}
is_word_at <- function(text, position) {
    position >= 0L && position < nchar(text) && utf8ToInt(substr(text, position + 1L, position + 1L)) %in% WORD
}
assertion <- function(kind, text, position, flags) {
    if (kind == "BOL") return(position == 0L || (has_flag(flags, "m") && substr(text, position, position) == "\n"))
    if (kind == "EOL") return(position == nchar(text) || (has_flag(flags, "m") && substr(text, position + 1L, position + 1L) == "\n"))
    edge <- is_word_at(text, position - 1L) != is_word_at(text, position)
    if (kind == "WORD") edge else !edge
}
