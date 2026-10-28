irc_fold <- function(value) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ[]\\^","abcdefghijklmnopqrstuvwxyz{}|~",value)
is_digits <- function(value) nzchar(value) && all(strsplit(
    value,
    "",
    fixed=TRUE
)[[1L]] %in% as.character(0L:9L))
is_letter <- function(character) character %in% c(LETTERS,letters)
valid_nickname <- function(value) {
  characters <- strsplit(value,"",fixed=TRUE)[[1L]]
  special <- c("[","]","\\","`","_","^","{","|","}")
  length(characters) > 0L && (is_letter(characters[1L]) || characters[1L] %in% special) && all(characters[-1L] %in% c(
      LETTERS,
      letters,
      special,
      as.character(0L:9L),
      "-"
  ))
}
valid_channel <- function(
    value,
    maximum
) nchar(value) >= 2L && nchar(value) <= maximum && startsWith(value,"#") && !grepl(
    ":",
    value,
    fixed=TRUE
)
text_slice <- function(text,first,last=nchar(text)) if (first > last) "" else substr(text,first,last)
parse_message <- function(raw) {
  n <- nchar(raw)
  position <- 1L
  if (startsWith(raw,":")) {
    position <- regexpr(" ",raw,fixed=TRUE)[1L]
    if (position == -1L) return(list(command="",parameters=character()))
  }
  at <- function(i) substr(raw,i,i)
  while (position <= n && at(position) == " ") position <- position+1L
  start <- position
  while (position <= n && at(position) != " ") position <- position+1L
  command <- toupper(text_slice(raw,start,position-1L))
  parameters <- character()
  while (position <= n) {
    while (position <= n && at(position) == " ") position <- position+1L
    if (position > n) break
    if (at(position) == ":") {
      parameters <- c(parameters,text_slice(raw,position+1L))
      break
    }
    if (length(parameters) == 14L) {
      parameters <- c(parameters,text_slice(raw,position))
      break
    }
    start <- position
    while (position <= n && at(position) != " ") position <- position+1L
    parameters <- c(parameters,text_slice(raw,start,position-1L))
  }
  list(command=command,parameters=parameters)
}
