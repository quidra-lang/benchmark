channel_items <- function(mode,arguments) {
  items <- list()
  sign <- "+"
  position <- 1L
  for (c in strsplit(mode,"",fixed=TRUE)[[1L]]) {
    if (c %in% c("+","-")) {
      sign <- c
      next
    }
    argument <- NULL
    if (c %in% c("o","v","b","k") || (c == "l" && sign == "+")) {
      if (position <= length(arguments)) {
        argument <- arguments[position]
        position <- position+1L
      }
    }
    if (c == "k" && sign == "-") argument <- "*" else if (c == "l" && sign == "+") {
      if (is.null(argument) || !is_digits(argument) || nchar(argument) > 4L || as.integer(argument) < 1L) argument <- NULL
    }
    items[[length(items)+1L]] <- list(sign=sign,character=c,argument=argument)
  }
  items
}
change_string <- function(changes) {
  mode <- ""
  arguments <- character()
  previous <- ""
  for (change in changes) {
    if (change$sign != previous) {
      mode <- paste0(mode,change$sign)
      previous <- change$sign
    }
    mode <- paste0(mode,change$character)
    if (!is.null(change$argument)) arguments <- c(arguments,change$argument)
  }
  paste0(mode,if (length(arguments)) paste0(" ",arguments,collapse="") else "")
}
