COMMAND_DISPLAY <- vapply(SYMBOL_COMMANDS, function(entry) entry[1], "")
COMMAND_TYPES <- vapply(SYMBOL_COMMANDS, function(entry) entry[2], "")
SYMBOL_TYPES <- local({
    table <- character()
    groups <- list(binary="+-*", relation="=<>:", open="([", close=")]!", punctuation=",;")
    for (kind in names(groups)) for (character in strsplit(groups[[kind]], "", fixed=TRUE)[[1]]) table[character] <- kind
    table
})
LARGE_GLYPHS <- list("\\sum"=c("\\--", " > ", "/--"), "\\prod"=c("___", "| |", "| |"), "\\int"=c(" /", " |", "/ "))
new_box <- function(width, height, baseline, description) {
    box <- new.env(parent=emptyenv())
    box$width <- width
    box$height <- height
    box$baseline <- baseline
    box$description <- description
    box$children <- box$strings <- list()
    box
}
descent <- function(box) box$height-1L-box$baseline
add_child <- function(box, child, x, y, role="") box$children[[length(box$children)+1L]] <- list(box=child, x=x, y=y, role=role)
draw_string <- function(box, text, x=0L, y=0L) box$strings[[length(box$strings)+1L]] <- list(text=text, x=x, y=y)
delimiter_glyph <- function(delimiter, height) {
    if (delimiter == ".") return(character())
    character <- substring(delimiter, nchar(delimiter))
    if (height == 1L) return(character)
    if (delimiter %in% c("[", "]", "|")) return(rep(delimiter, height))
    left <- delimiter %in% c("(", "\\{")
    result <- c(if (left) "/" else "\\", rep("|", height-2L), if (left) "\\" else "/")
    if (delimiter %in% c("\\{", "\\}") && height >= 3L) result[(height-1L) %/% 2L+1L] <- if (left) "<" else ">"
    result
}
