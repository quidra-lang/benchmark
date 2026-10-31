log_prefix <- function(bot) paste(bot$state$session$name, bot$state$session$turns)

memory_store <- function(bot, keyword, text) {
  prefix <- log_prefix(bot)
  if (text %in% bot$state$memory$texts) {
    bot$state$memory$log <- c(bot$state$memory$log, paste(prefix, "SKIP", keyword, text))
    return(invisible(NULL))
  }
  if (length(bot$state$memory$texts) == bot$state$memory$capacity) {
    bot$state$memory$log <- c(bot$state$memory$log, paste(prefix, "DROP", bot$state$memory$texts[1L]))
    bot$state$memory$texts <- bot$state$memory$texts[-1L]
  }
  bot$state$memory$texts <- c(bot$state$memory$texts, text)
  bot$state$memory$log <- c(bot$state$memory$log, paste(prefix, "STORE", keyword, text))
  bot$state$session$stored <- bot$state$session$stored + 1L
  invisible(NULL)
}

memory_recall <- function(bot) {
  text <- bot$state$memory$texts[1L]
  bot$state$memory$texts <- bot$state$memory$texts[-1L]
  bot$state$memory$log <- c(bot$state$memory$log, paste(log_prefix(bot), "RECALL", text))
  bot$state$session$recalled <- bot$state$session$recalled + 1L
  text
}

memory_clear <- function(bot, prefix = log_prefix(bot)) {
  count <- length(bot$state$memory$texts)
  if (count) {
    bot$state$memory$log <- c(bot$state$memory$log, paste(prefix, "CLEAR", count))
    bot$state$memory$texts <- character()
  }
  invisible(NULL)
}
