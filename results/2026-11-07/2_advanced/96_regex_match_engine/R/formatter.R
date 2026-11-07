character_display <- function(code) {
    if (code >= 33L && code <= 126L && !code %in% c(92L, 93L, 94L, 45L)) return(intToUtf8(code))
    paste0("\\x", sprintf("%02X", code))
}
set_notation <- function(codes, negated = FALSE) {
    codes <- sort(unique(codes))
    pieces <- character()
    index <- 1L
    while (index <= length(codes)) {
        last <- index
        while (last < length(codes) && codes[last + 1L] == codes[last] + 1L) last <- last + 1L
        a <- character_display(codes[index])
        b <- character_display(codes[last])
        run <- last - index + 1L
        pieces <- c(pieces, if (run == 1L) a else if (run == 2L) paste0(a, b) else paste0(a, "-", b))
        index <- last + 1L
    }
    paste0("[", if (negated) "^" else "", paste0(pieces, collapse = ""), "]")
}
instruction_notation <- function(entry) {
    switch(entry$op,
        CHAR = paste("CHAR", character_display(utf8ToInt(entry$character))),
        CLASS = paste("CLASS", set_notation(entry$codes, entry$negated)),
        SPLIT = paste0("SPLIT ", entry$x, ", ", entry$y),
        JMP = paste("JMP", entry$x),
        SAVE = paste("SAVE", entry$slot),
        ASSERT = paste("ASSERT", entry$kind),
        BACKREF = paste("BACKREF", entry$group),
        LOOK = paste("LOOK", entry$kind, entry$x),
        entry$op)
}
quoted <- function(text) {
    characters <- strsplit(text, "", fixed = TRUE)[[1L]]
    encoded <- vapply(characters, function(character) {
        if (character == "\\") "\\\\" else if (character == "\"") "\\\"" else if (character == "\n") "\\n" else if (character == "\t") "\\t" else character
    }, character(1L))
    paste0("\"", paste0(encoded, collapse = ""), "\"")
}
