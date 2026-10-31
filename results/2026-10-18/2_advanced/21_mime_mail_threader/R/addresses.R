dot_atom <- function(tokens) {
  if (length(tokens) %% 2L == 0L) return(FALSE)
  for (i in seq_along(tokens)) if (tokens[[i]]$kind != if (i %% 2L == 1L) "word" else ".") return(FALSE)
  TRUE
}

address_peek <- function(parser) {
  if (parser$position <= length(parser$tokens)) parser$tokens[[parser$position]]$kind else ""
}
address_expect <- function(parser, kind) {
  if (address_peek(parser) != kind) parser$failed <- TRUE else parser$position <- parser$position + 1L
}
address_run <- function(parser, phrase) {
  start <- parser$position
  kinds <- c("word", ".", if (phrase) "quoted")
  while (address_peek(parser) %in% kinds) parser$position <- parser$position + 1L
  if (start == parser$position) list() else parser$tokens[seq.int(start, parser$position - 1L)]
}

display_name <- function(parser, phrase) {
  output <- character()
  previous <- FALSE
  for (i in seq_along(phrase)) {
    token <- phrase[[i]]
    text <- token$text
    decoded <- FALSE
    if (token$kind == "word") {
      value <- decode_word(text)
      text <- value$text
      decoded <- value$decoded
      parser$encoding_error <- parser$encoding_error || value$error
    }
    if (i > 1L && token$spaced && !(decoded && previous)) output <- c(output, " ")
    output <- c(output, text)
    previous <- decoded
  }
  collapse_whitespace(paste0(output, collapse = ""))
}

address_mailbox <- function(parser, phrase, local, domain, named) {
  if (!dot_atom(local) || !dot_atom(domain)) {
    parser$failed <- TRUE
    return(NULL)
  }
  token_text <- function(tokens) paste0(vapply(tokens, function(token) token$text, character(1)), collapse = "")
  list(kind = "mailbox", name = if (named) display_name(parser, phrase) else "",
       address = ascii_lower(paste0(token_text(local), "@", token_text(domain))))
}

parse_address <- function(parser, in_group) {
  phrase <- address_run(parser, TRUE)
  following <- address_peek(parser)
  if (following == "<") {
    parser$position <- parser$position + 1L
    local <- address_run(parser, FALSE)
    address_expect(parser, "@")
    domain <- address_run(parser, FALSE)
    address_expect(parser, ">")
    return(address_mailbox(parser, phrase, local, domain, TRUE))
  }
  if (following == "@") {
    parser$position <- parser$position + 1L
    domain <- address_run(parser, FALSE)
    return(address_mailbox(parser, list(), phrase, domain, FALSE))
  }
  if (following == ":" && length(phrase) > 0L && !in_group) {
    parser$position <- parser$position + 1L
    mailboxes <- list()
    if (address_peek(parser) != ";") {
      repeat {
        entry <- parse_address(parser, TRUE)
        if (parser$failed || is.null(entry) || entry$kind != "mailbox") {
          parser$failed <- TRUE
          return(NULL)
        }
        mailboxes[[length(mailboxes) + 1L]] <- entry
        if (address_peek(parser) != ",") break
        parser$position <- parser$position + 1L
      }
    }
    address_expect(parser, ";")
    return(list(kind = "group", mailboxes = mailboxes))
  }
  parser$failed <- TRUE
  NULL
}

parse_address_list <- function(value) {
  tokens <- tokenize(value)
  if (is.null(tokens) || length(tokens) == 0L) return(NULL)
  parser <- new.env(parent = emptyenv())
  parser$tokens <- tokens
  parser$position <- 1L
  parser$encoding_error <- parser$failed <- FALSE
  addresses <- list()
  repeat {
    address <- parse_address(parser, FALSE)
    if (parser$failed || is.null(address)) return(NULL)
    addresses[[length(addresses) + 1L]] <- address
    if (address_peek(parser) != ",") break
    parser$position <- parser$position + 1L
  }
  if (parser$position <= length(tokens)) return(NULL)
  list(addresses = addresses, error = parser$encoding_error)
}
