BODY_KINDS <- c("paragraph", "item", "enum", "quote", "term")
SETTING_NAMES <- c("width", "indent", "align")
PREAMBLE_NAMES <- c("page", "header", "footer")
BLOCK_NAMES <- c(
    "title",
    "author",
    "h1",
    "h2",
    "item",
    "enum",
    "quote",
    "term",
    "table",
    "verbatim",
    "toc",
    "lot",
    "index",
    "bibliography"
)
DIRECTIVE_NAMES <- c(SETTING_NAMES, PREAMBLE_NAMES, BLOCK_NAMES, "newpage", "hyphenation", "bib")
EMPTY_ARGUMENT_NAMES <- c("newpage", "verbatim", "toc", "lot", "index", "bibliography")
record <- function(...) list2env(list(...), parent = emptyenv())
split_all <- function(text, separator) {
  parts <- strsplit(text, separator, fixed = TRUE)[[1L]]
  if (!nzchar(text)) return("")
  if (endsWith(text, separator)) parts <- c(parts, "")
  parts
}
partition_text <- function(text, separator) {
  index <- regexpr(separator, text, fixed = TRUE)[[1L]]
  if (index == -1L) list(left = text, found = FALSE, right = "") else list(
      left = substr(text, 1L, index - 1L),
      found = TRUE,
      right = substring(text, index + nchar(separator))
  )
}
valid_argument <- function(name, argument) {
  if (name %in% c("width", "indent", "page")) {
    if (!grepl("^[0-9]{1,9}$", argument)) return(FALSE)
    limits <- switch(name, width = c(20L, 80L), indent = c(0L, 8L), page = c(10L, 100L))
    value <- as.integer(argument)
    return(limits[[1L]] <= value && value <= limits[[2L]])
  }
  if (name == "align") return(argument %in% c("left", "right", "center", "justify"))
  if (name %in% c("header", "footer")) return(length(split_all(argument, "|")) == 3L)
  if (name %in% EMPTY_ARGUMENT_NAMES) return(!nzchar(argument))
  if (name == "hyphenation") return(nzchar(argument) && all(grepl(
      "^[a-z]+(-[a-z]+)*$",
      split_all(argument, " ")
  )))
  if (name == "bib") {
    key <- partition_text(argument, " ")
    if (!key$found || !grepl("^[a-z0-9]+$", key$left)) return(FALSE)
    parts <- split_all(key$right, "|")
    return(length(parts) == 3L && nzchar(parts[[1L]]) && nzchar(parts[[3L]]) && grepl(
        "^[0-9]{4}$",
        parts[[2L]]
    ))
  }
  if (name == "term") {
    term <- partition_text(argument, "|")
    return(term$found && nzchar(term$left) && nzchar(term$right))
  }
  if (name == "table") return(grepl("^[lrc]+$", partition_text(argument, " ")$left))
  nzchar(argument)
}
parse_document <- function(lines) {
  document <- record(
      blocks = list(),
      warnings = list(),
      height = 40L,
      page_width = 60L,
      header = c("", "", ""),
      footer = c("", "", ""),
      hyphenation_words = character(),
      bibliography = list()
  )
  settings <- list(width = 60L, indent = 0L, align = "left")
  accepted <- character()
  open_body <- inner_block <- NULL
  pending <- FALSE
  create_block <- function(kind, line_number, argument = "") {
    if (!length(document$blocks)) document$page_width <- settings$width
    block <- record(
        kind = kind,
        line_number = line_number,
        argument = argument,
        page_break = pending,
        width = settings$width,
        indent = settings$indent,
        align = settings$align
    )
    pending <<- FALSE
    document$blocks[[length(document$blocks) + 1L]] <- block
    if (kind %in% BODY_KINDS) block$body_lines <- list()
    if (kind %in% c("table", "verbatim")) block$inner_lines <- list()
    block
  }
  for (line_number in seq_along(lines)) {
    line <- lines[[line_number]]
    if (!is.null(inner_block)) {
      if (line == ".end") inner_block <- NULL else inner_block$inner_lines[[length(inner_block$inner_lines) + 1L]] <- list(
          line_number,
          line
      )
      next
    }
    if (!nzchar(line)) {
      open_body <- NULL
      next
    }
    if (!startsWith(line, ".")) {
      if (is.null(open_body)) open_body <- create_block("paragraph", line_number)
      open_body$body_lines[[length(open_body$body_lines) + 1L]] <- list(line_number, line)
      next
    }
    open_body <- NULL
    directive <- partition_text(substring(line, 2L), " ")
    name <- directive$left
    argument <- directive$right
    warning <- if (!(name %in% DIRECTIVE_NAMES)) paste0("unknown directive .", name) else if (!valid_argument(name, argument)) paste0("bad argument for .", name) else if (name %in% PREAMBLE_NAMES && length(document$blocks)) paste0(
        ".",
        name,
        " ignored after the preamble"
    ) else if (name %in% PREAMBLE_NAMES && name %in% accepted) paste0("duplicate .", name) else NULL
    if (!is.null(warning)) {
      document$warnings[[length(document$warnings) + 1L]] <- list(line_number, warning)
      next
    }
    if (name %in% SETTING_NAMES) settings[[name]] <- if (name == "align") argument else as.integer(argument) else if (name %in% PREAMBLE_NAMES) {
      accepted <- c(accepted, name)
      if (name == "page") document$height <- as.integer(argument) else document[[name]] <- split_all(
          argument,
          "|"
      )
    } else if (name == "newpage") pending <- TRUE else if (name == "hyphenation") document$hyphenation_words <- c(
        document$hyphenation_words,
        split_all(argument, " ")
    ) else if (name == "bib") {
      key <- partition_text(argument, " ")
      fields <- split_all(key$right, "|")
      document$bibliography[[length(document$bibliography) + 1L]] <- record(
          line_number = line_number,
          key = key$left,
          author = fields[[1L]],
          year = fields[[2L]],
          title = fields[[3L]]
      )
    } else {
      block <- create_block(name, line_number, argument)
      if (name %in% c("item", "enum", "quote")) {
        block$body_lines[[1L]] <- list(line_number, argument)
        open_body <- block
      } else if (name == "term") {
        term <- partition_text(argument, "|")
        block$term <- term$left
        block$body_lines[[1L]] <- list(line_number, term$right)
        open_body <- block
      } else if (name == "table") {
        table <- partition_text(argument, " ")
        block$columns <- table$left
        block$caption <- table$right
        inner_block <- block
      } else if (name == "verbatim") inner_block <- block
    }
  }
  if (!is.null(inner_block)) document$warnings[[length(document$warnings) + 1L]] <- list(
      inner_block$line_number,
      paste("unterminated", inner_block$kind)
  )
  document
}
