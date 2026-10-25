TEXT_DIRECTIVES <- c("INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT")
GLOBAL_DIRECTIVES <- c(TEXT_DIRECTIVES, "QUIT", "STOP", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON")
RULE_DIRECTIVES <- c("DECOMP", "MEMORY")
ITEM_DIRECTIVES <- c("REASM", "GOTO", "NEWKEY", "RESTATE")
MOVE_DIRECTIVES <- c("GOTO", "NEWKEY", "RESTATE")

words_of <- function(text) {
  parts <- strsplit(text, " ", fixed = TRUE)[[1L]]
  parts[nzchar(parts)]
}

is_word <- function(text) grepl("^[a-z0-9]([a-z0-9']*[a-z0-9])?$", text)
is_reference <- function(text) grepl("^\\([0-9]\\)$", text)
is_element <- function(text) text %in% c("*", "#") | is_word(text) | grepl("^@[a-z0-9]([a-z0-9']*[a-z0-9])?$", text)
is_number <- function(text) grepl("^[0-9]{1,2}$", text)

well_formed <- function(name, args) {
  count <- length(args)
  if (name %in% c(TEXT_DIRECTIVES, "REASM")) return(count >= 1L)
  if (name %in% c("QUIT", "STOP")) return(count >= 1L && all(is_word(args)))
  if (name == "MEMSIZE") return(count == 1L && is_number(args[1L]) && as.integer(args[1L]) %in% 1L:20L)
  if (name == "PERSIST") return(count == 1L && args[1L] %in% c("cycles", "memory"))
  if (name %in% c("PRE", "SYNON")) return(count >= 2L && all(is_word(args)))
  if (name == "POST") return(count >= 2L && is_word(args[1L]))
  if (name == "KEY") return(count == 2L && is_word(args[1L]) && is_number(args[2L]))
  if (name %in% RULE_DIRECTIVES) return(count >= 1L && all(is_element(args)))
  if (name == "GOTO") return(count == 1L && is_word(args[1L]))
  if (name == "NEWKEY") return(count == 0L)
  count >= 2L && is_word(args[1L]) && all(is_word(args[-1L]) | is_reference(args[-1L]))
}

load_script <- function(path) {
  lines <- readLines(path, warn = FALSE)
  script <- list(lines = lines, texts = setNames(rep(list(character()), length(TEXT_DIRECTIVES)), TEXT_DIRECTIVES),
                 quit_words = character(), stop_words = character(), memsize = 3L, persist = character(),
                 pres = list(), posts = list(), pre_table = list(), post_table = list(), groups = list(),
                 group_words = list(), keywords = list(), keyword_map = integer(), rules = list(),
                 items = list(), diagnostics = list())
  current_keyword <- current_rule <- 0L
  ignoring <- FALSE
  first_lines <- integer()
  for (line_number in seq_along(lines)) {
    line <- lines[line_number]
    if (!nzchar(line) || startsWith(line, "#")) next
    parts <- words_of(line)
    name <- parts[1L]
    args <- parts[-1L]
    text <- if (length(args)) substring(line, nchar(name) + 2L) else ""
    if (name %in% c(GLOBAL_DIRECTIVES, "KEY")) {
      current_keyword <- current_rule <- 0L
      ignoring <- FALSE
    } else if (name %in% c(RULE_DIRECTIVES, ITEM_DIRECTIVES)) {
      if (ignoring) next
      if (name %in% RULE_DIRECTIVES) current_rule <- 0L
    }
    unique_key <- if (name == "MEMSIZE") name else if (name %in% c("KEY", "SYNON", "PRE", "POST", "PERSIST")) paste(name, args[1L]) else NULL
    code <- message <- NULL
    if (!name %in% c(GLOBAL_DIRECTIVES, "KEY", RULE_DIRECTIVES, ITEM_DIRECTIVES)) {
      code <- "SYNTAX"
      message <- paste("unknown directive", name)
    } else if (!well_formed(name, args)) {
      code <- "SYNTAX"
      message <- paste("bad arguments for", name)
    } else if (name %in% RULE_DIRECTIVES && current_keyword == 0L) {
      code <- "ORPHAN"
      message <- paste(name, "without KEY")
    } else if (name == "REASM" && current_rule == 0L) {
      code <- "ORPHAN"
      message <- "REASM without DECOMP or MEMORY"
    } else if (name %in% MOVE_DIRECTIVES && (current_rule == 0L || script$rules[[current_rule]]$kind == "MEMORY")) {
      code <- "ORPHAN"
      message <- paste(name, "without DECOMP")
    } else if (!is.null(unique_key) && unique_key %in% names(first_lines)) {
      code <- "DUPLICATE"
      message <- paste(unique_key, "first defined at line", first_lines[[unique_key]])
      if (name == "KEY") ignoring <- TRUE
    }
    if (!is.null(code)) {
      script$diagnostics[[length(script$diagnostics) + 1L]] <- list(line = line_number, code = code, message = message)
      next
    }
    if (!is.null(unique_key)) first_lines[unique_key] <- line_number
    if (name %in% TEXT_DIRECTIVES) {
      script$texts[[name]] <- c(script$texts[[name]], text)
    } else if (name == "QUIT") {
      script$quit_words <- union(script$quit_words, args)
    } else if (name == "STOP") {
      script$stop_words <- union(script$stop_words, args)
    } else if (name == "MEMSIZE") {
      script$memsize <- as.integer(args[1L])
    } else if (name == "PERSIST") {
      script$persist <- c(script$persist, args[1L])
    } else if (name %in% c("PRE", "POST")) {
      substitution <- list(source = args[1L], replacement = args[-1L], line = line_number)
      if (name == "PRE") {
        script$pres[[length(script$pres) + 1L]] <- substitution
        script$pre_table[[args[1L]]] <- args[-1L]
      } else {
        script$posts[[length(script$posts) + 1L]] <- substitution
        script$post_table[[args[1L]]] <- args[-1L]
      }
    } else if (name == "SYNON") {
      script$groups[[length(script$groups) + 1L]] <- list(name = args[1L], members = unique(args), line = line_number)
      script$group_words[[args[1L]]] <- unique(args)
    } else if (name == "KEY") {
      current_keyword <- length(script$keywords) + 1L
      script$keyword_map[args[1L]] <- current_keyword
      script$keywords[[current_keyword]] <- list(word = args[1L], rank = as.integer(args[2L]), line = line_number,
                                                 memories = integer(), decomps = integer())
    } else if (name %in% RULE_DIRECTIVES) {
      current_rule <- length(script$rules) + 1L
      script$rules[[current_rule]] <- list(kind = name, pattern = args, line = line_number, items = integer())
      field <- if (name == "MEMORY") "memories" else "decomps"
      script$keywords[[current_keyword]][[field]] <- c(script$keywords[[current_keyword]][[field]], current_rule)
    } else {
      item_id <- length(script$items) + 1L
      script$items[[item_id]] <- list(kind = name, text = text, arguments = args, line = line_number)
      script$rules[[current_rule]]$items <- c(script$rules[[current_rule]]$items, item_id)
    }
  }
  script
}
