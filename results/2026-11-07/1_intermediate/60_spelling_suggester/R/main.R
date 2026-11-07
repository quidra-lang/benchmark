ADJACENT_KEYS <- strsplit(c(
  a = "qswz", b = "ghnv", c = "dfvx", d = "cefrsx", e = "drsw",
  f = "cdgrtv", g = "bfhtvy", h = "bgjnuy", i = "jkou", j = "hikmnu",
  k = "ijlmo", l = "kop", m = "jkn", n = "bhjm", o = "iklp",
  p = "lo", q = "aw", r = "deft", s = "adewxz", t = "fgry",
  u = "hijy", v = "bcfg", w = "aeqs", x = "cdsz", y = "ghtu",
  z = "asx"
), "")
SOUNDEX_GROUPS <- strsplit(c(
  "1" = "bfpv", "2" = "cgjkqsxz", "3" = "dt", "4" = "l", "5" = "mn", "6" = "r", "0" = "aeiouy"
), "")
SOUNDEX_DIGITS <- setNames(
  rep(names(SOUNDEX_GROUPS), lengths(SOUNDEX_GROUPS)),
  unlist(SOUNDEX_GROUPS, use.names = FALSE)
)
FINDING_KINDS <- c("unknown", "case", "capital", "repeats")
COUNTER_NAMES <- c("checked", "unknown", "case", "capital", "repeats", "corrected")
OPTION_MAXIMUMS <- c(LIMIT = 3L, SUGGESTIONS = 10L)
KEYBOARD_MODES <- c("ON", "OFF")
MAX_WORD_LENGTH <- 30L
MAX_FREQUENCY <- 1000000L
MAX_LISTED <- 20L
REPORT_SIZE <- 10L

command_error <- function(message) {
  stop(errorCondition(message, class = "command_error", call = NULL))
}

word_argument <- function(text) {
  if (!grepl("^[[:alpha:]]{1,30}$", text)) command_error(paste("BAD WORD", text))
  tolower(text)
}

number_argument <- function(text, lower, upper) {
  if (!grepl("^[0-9]{1,7}$", text)) command_error(paste("BAD NUMBER", text))
  value <- as.integer(text)
  if (value < lower || value > upper) command_error(paste("BAD NUMBER", text))
  value
}

decimal_text <- function(numerator, denominator, digits) {
  scale <- 10^digits
  value <- (2 * numerator * scale + denominator) %/% (2 * denominator)
  sprintf("%d.%0*d", value %/% scale, digits, value %% scale)
}

emit <- function(...) {
  writeLines(paste(c(...), collapse = " "))
}

increment <- function(counts, key) {
  counts[key] <- if (key %in% names(counts)) counts[[key]] + 1L else 1L
  counts
}

split_letters <- function(word) strsplit(word, "")[[1]]

capitalize_first <- function(word) {
  paste0(toupper(substr(word, 1L, 1L)), substring(word, 2L))
}

apply_case <- function(token_text, word) {
  if (nchar(token_text) >= 2L && grepl("^[[:upper:]]+$", token_text)) {
    toupper(word)
  } else if (grepl("^[[:upper:]]", token_text)) {
    capitalize_first(word)
  } else {
    word
  }
}

is_mixed_case <- function(token_text) {
  grepl("[[:upper:]]", substring(token_text, 2L)) && grepl("[[:lower:]]", token_text)
}

tokenize <- function(text) {
  matches <- gregexpr("[[:alpha:]]+", text)[[1]]
  tokens <- list()
  if (matches[1] == -1L) {
    return(tokens)
  }
  match_lengths <- attr(matches, "match.length")
  position <- 1L
  for (index in seq_along(matches)) {
    start <- matches[[index]]
    last <- start + match_lengths[[index]] - 1L
    token_text <- substr(text, start, last)
    word <- tolower(token_text)
    gap <- substr(text, position, start - 1L)
    tokens[[index]] <- list(
      number = index,
      text = token_text,
      word = word,
      last = last,
      gap = gap,
      sentence_start = index == 1L || grepl("[.!?]", gap),
      is_repeat = index > 1L && word == tokens[[index - 1L]]$word && grepl("^ *$", gap)
    )
    position <- last + 1L
  }
  tokens
}

gap_cost <- function(keyboard) if (keyboard) 2L else 1L

substitution_cost <- function(x, y, keyboard) {
  if (x == y) {
    0L
  } else if (!keyboard) {
    1L
  } else if (y %in% ADJACENT_KEYS[[x]]) {
    1L
  } else {
    2L
  }
}

is_swap <- function(a, b, i, j) {
  i >= 2L && j >= 2L && a[i] == b[j - 1L] && a[i - 1L] == b[j]
}

distance_table <- function(a, b, keyboard) {
  gap <- gap_cost(keyboard)
  rows <- length(a)
  columns <- length(b)
  table <- matrix(0L, rows + 1L, columns + 1L)
  table[, 1] <- (0:rows) * gap
  table[1, ] <- (0:columns) * gap
  for (i in seq_len(rows)) {
    for (j in seq_len(columns)) {
      best <- min(
        table[i, j + 1L] + gap,
        table[i + 1L, j] + gap,
        table[i, j] + substitution_cost(a[i], b[j], keyboard)
      )
      if (is_swap(a, b, i, j)) {
        best <- min(best, table[i - 1L, j - 1L] + 1L)
      }
      table[i + 1L, j + 1L] <- best
    }
  }
  table
}

edit_distance <- function(a, b, keyboard) {
  table <- distance_table(a, b, keyboard)
  table[nrow(table), ncol(table)]
}

prefix_distance <- function(a, b, keyboard) {
  table <- distance_table(a, b, keyboard)
  min(table[nrow(table), ])
}

edit_operations <- function(a, b, keyboard) {
  table <- distance_table(a, b, keyboard)
  gap <- gap_cost(keyboard)
  operations <- character(0)
  i <- length(a)
  j <- length(b)
  while (i > 0L || j > 0L) {
    if (i >= 1L && j >= 1L &&
      table[i + 1L, j + 1L] == table[i, j] + substitution_cost(a[i], b[j], keyboard)) {
      if (a[i] != b[j]) {
        operations <- c(operations, paste0("sub:", a[i], ">", b[j]))
      }
      i <- i - 1L
      j <- j - 1L
    } else if (is_swap(a, b, i, j) && table[i + 1L, j + 1L] == table[i - 1L, j - 1L] + 1L) {
      operations <- c(operations, paste0("swap:", a[i - 1L], a[i]))
      i <- i - 2L
      j <- j - 2L
    } else if (i >= 1L && table[i + 1L, j + 1L] == table[i, j + 1L] + gap) {
      operations <- c(operations, paste0("del:", a[i]))
      i <- i - 1L
    } else {
      operations <- c(operations, paste0("ins:", b[j]))
      j <- j - 1L
    }
  }
  list(distance = table[nrow(table), ncol(table)], operations = rev(operations))
}

soundex <- function(word) {
  chars <- split_letters(word)
  code <- toupper(chars[1])
  previous <- if (chars[1] %in% c("h", "w")) "0" else SOUNDEX_DIGITS[[chars[1]]]
  for (letter in chars[-1]) {
    if (letter %in% c("h", "w")) next
    digit <- SOUNDEX_DIGITS[[letter]]
    if (digit != "0" && digit != previous) {
      code <- paste0(code, digit)
    }
    previous <- digit
  }
  substr(paste0(code, "000"), 1L, 4L)
}

precedes <- function(candidate, current) {
  if (length(candidate) != length(current)) {
    return(length(candidate) < length(current))
  }
  differs <- candidate != current
  any(differs) && candidate[differs][1] < current[differs][1]
}

segment <- function(word, words) {
  size <- nchar(word)
  ways <- integer(size + 1L)
  best <- vector("list", size + 1L)
  ways[size + 1L] <- 1L
  best[[size + 1L]] <- character(0)
  for (start in rev(seq_len(size))) {
    for (last in start:size) {
      piece <- substr(word, start, last)
      if (!(piece %in% words) || ways[last + 1L] == 0L) next
      ways[start] <- ways[start] + ways[last + 1L]
      candidate <- c(piece, best[[last + 1L]])
      if (is.null(best[[start]]) || precedes(candidate, best[[start]])) {
        best[[start]] <- candidate
      }
    }
  }
  list(ways = ways[1], best = best[[1]])
}

new_spell_checker <- function(dictionary) {
  list2env(list(
    dictionary = dictionary,
    ignored = character(0),
    rules = setNames(character(0), character(0)),
    keyboard = FALSE,
    base_limit = 2L,
    suggestion_count = 5L,
    undo_history = list(),
    unknown_log = setNames(integer(0), character(0)),
    correction_log = setNames(integer(0), character(0)),
    counters = setNames(integer(length(COUNTER_NAMES)), COUNTER_NAMES)
  ))
}

limit <- function(checker) {
  if (checker$keyboard) 2L * checker$base_limit else checker$base_limit
}

is_known <- function(checker, word) {
  word %in% names(checker$dictionary) || word %in% checker$ignored
}

frequency_order <- function(dictionary) {
  names(dictionary)[order(-dictionary, names(dictionary))]
}

require_entry <- function(checker, word) {
  if (!(word %in% names(checker$dictionary))) command_error(paste("NOT FOUND", word))
  checker$dictionary[[word]]
}

rank_by_distance <- function(checker, words, distances) {
  ordering <- order(distances, -checker$dictionary[words], words)
  setNames(distances[ordering], words[ordering])
}

candidates <- function(checker, word) {
  max_distance <- limit(checker)
  gap <- gap_cost(checker$keyboard)
  others <- names(checker$dictionary)
  others <- others[others != word & abs(nchar(others) - nchar(word)) * gap <= max_distance]
  word_letters <- split_letters(word)
  distances <- vapply(others, function(other) {
    edit_distance(word_letters, split_letters(other), checker$keyboard)
  }, integer(1), USE.NAMES = FALSE)
  keep <- distances <= max_distance
  rank_by_distance(checker, others[keep], distances[keep])
}

correction <- function(checker, word) {
  if (is_known(checker, word)) {
    return(NULL)
  }
  if (word %in% names(checker$rules)) {
    return(checker$rules[[word]])
  }
  found <- candidates(checker, word)
  if (length(found) == 0L) NULL else names(found)[1]
}

record_undo <- function(checker, name) {
  record <- list(
    name = name, dictionary = checker$dictionary, ignored = checker$ignored, rules = checker$rules
  )
  checker$undo_history <- c(checker$undo_history, list(record))
}

log_correction <- function(checker, word, replacement) {
  checker$correction_log <- increment(checker$correction_log, paste0(word, ">", replacement))
  checker$counters[["corrected"]] <- checker$counters[["corrected"]] + 1L
}

unknown_finding <- function(checker, token) {
  label <- paste("UNKNOWN", token$number, token$text)
  if (token$word %in% names(checker$rules)) {
    return(paste(label, "RULE", checker$rules[[token$word]]))
  }
  found <- candidates(checker, token$word)
  if (length(found) == 0L) {
    return(paste(label, "NONE"))
  }
  paste(c(label, "SUGGEST", head(names(found), checker$suggestion_count)), collapse = " ")
}

check_text <- function(checker, text) {
  tokens <- tokenize(text)
  counts <- setNames(integer(length(FINDING_KINDS)), FINDING_KINDS)
  findings <- character(0)
  add_finding <- function(kind, line) {
    counts[[kind]] <<- counts[[kind]] + 1L
    findings <<- c(findings, line)
  }
  for (token in tokens) {
    if (!is_known(checker, token$word)) {
      add_finding("unknown", unknown_finding(checker, token))
      checker$unknown_log <- increment(checker$unknown_log, token$word)
    }
    if (is_mixed_case(token$text)) {
      add_finding("case", paste("CASE", token$number, token$text))
    }
    if (token$sentence_start && grepl("^[[:lower:]]", token$text)) {
      add_finding("capital", paste("CAPITAL", token$number, token$text))
    }
    if (token$is_repeat) {
      add_finding("repeats", paste("REPEAT", token$number, token$text))
    }
  }
  checker$counters[["checked"]] <- checker$counters[["checked"]] + length(tokens)
  checker$counters[FINDING_KINDS] <- checker$counters[FINDING_KINDS] + counts
  emit("CHECK", paste0("words=", length(tokens)), paste0(FINDING_KINDS, "=", counts))
  writeLines(findings)
}

correct_text <- function(checker, text) {
  pieces <- character(0)
  position <- 0L
  changed <- 0L
  for (token in tokenize(text)) {
    replacement <- correction(checker, token$word)
    if (is.null(replacement)) {
      pieces <- c(pieces, token$gap, token$text)
    } else {
      pieces <- c(pieces, token$gap, apply_case(token$text, replacement))
      log_correction(checker, token$word, replacement)
      changed <- changed + 1L
    }
    position <- token$last
  }
  pieces <- c(pieces, substring(text, position + 1L))
  emit(paste0("CORRECT changed=", changed, ":"), paste(pieces, collapse = ""))
}

fix_text <- function(checker, text) {
  pieces <- character(0)
  position <- 0L
  removed <- 0L
  replaced <- 0L
  recased <- 0L
  for (token in tokenize(text)) {
    position <- token$last
    if (token$is_repeat) {
      removed <- removed + 1L
      next
    }
    replacement <- correction(checker, token$word)
    result <- apply_case(token$text, replacement %||% token$word)
    if (token$sentence_start && grepl("^[[:lower:]]", result)) {
      result <- capitalize_first(result)
    }
    if (!is.null(replacement)) {
      log_correction(checker, token$word, replacement)
      replaced <- replaced + 1L
    } else if (result != token$text) {
      recased <- recased + 1L
    }
    pieces <- c(pieces, token$gap, result)
  }
  pieces <- c(pieces, substring(text, position + 1L))
  emit(
    "FIX", paste0("removed=", removed), paste0("replaced=", replaced),
    paste0("recased=", recased, ":"), paste(pieces, collapse = "")
  )
}

profile_text <- function(checker, text) {
  tokens <- tokenize(text)
  words <- vapply(tokens, function(token) token$word, character(1))
  unknown <- sum(!vapply(words, function(word) is_known(checker, word), logical(1)))
  sentences <- sum(vapply(tokens, function(token) token$sentence_start, logical(1)))
  if (length(tokens) == 0L) {
    rate <- "0.0"
    average <- "0.00"
    longest <- "-"
  } else {
    rate <- decimal_text(100 * unknown, length(tokens), 1L)
    average <- decimal_text(sum(nchar(words)), length(tokens), 2L)
    longest <- words[which.max(nchar(words))]
  }
  emit(
    "PROFILE", paste0("words=", length(tokens)), paste0("distinct=", length(unique(words))),
    paste0("unknown=", unknown), paste0("rate=", rate), paste0("avglen=", average),
    paste0("longest=", longest), paste0("sentences=", sentences)
  )
}

learn_text <- function(checker, text) {
  record_undo(checker, "LEARN")
  updated <- 0L
  added <- 0L
  skipped <- 0L
  for (token in tokenize(text)) {
    if (nchar(token$word) > MAX_WORD_LENGTH) {
      skipped <- skipped + 1L
    } else if (token$word %in% names(checker$dictionary)) {
      checker$dictionary[[token$word]] <- checker$dictionary[[token$word]] + 1L
      updated <- updated + 1L
    } else {
      checker$dictionary[[token$word]] <- 1L
      checker$ignored <- setdiff(checker$ignored, token$word)
      added <- added + 1L
    }
  }
  emit(
    "LEARN", paste0("updated=", updated), paste0("added=", added), paste0("skipped=", skipped)
  )
}

suggest_word <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  if (is_known(checker, word)) {
    emit("SUGGEST", word, "KNOWN")
  } else if (word %in% names(checker$rules)) {
    emit("SUGGEST", word, "RULE", checker$rules[[word]])
  } else {
    found <- candidates(checker, word)
    shown <- head(found, checker$suggestion_count)
    emit("SUGGEST", word, paste0("found=", length(found)), sprintf("%s:%d", names(shown), shown))
  }
}

show_distance <- function(checker, arguments) {
  first_word <- word_argument(arguments[1])
  second_word <- word_argument(arguments[2])
  result <- edit_operations(
    split_letters(first_word), split_letters(second_word), checker$keyboard
  )
  emit("DIST", first_word, second_word, result$distance, result$operations)
}

show_soundex <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  emit("SOUNDEX", word, soundex(word))
}

sounds_like <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  code <- soundex(word)
  others <- frequency_order(checker$dictionary)
  matches <- others[others != word & vapply(others, soundex, character(1)) == code]
  emit("SOUNDS", word, code, paste0("count=", length(matches)), head(matches, REPORT_SIZE))
}

split_word <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  result <- segment(word, names(checker$dictionary))
  if (result$ways == 0L) {
    emit("SPLIT", word, "ways=0", "->", "NONE")
  } else {
    emit("SPLIT", word, paste0("ways=", result$ways), "->", result$best)
  }
}

prefix_words <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  shown <- number_argument(arguments[2], 1L, MAX_LISTED)
  others <- frequency_order(checker$dictionary)
  matches <- others[startsWith(others, word)]
  listed <- head(matches, shown)
  emit(
    "PREFIX", word, paste0("count=", length(matches)),
    sprintf("%s:%d", listed, checker$dictionary[listed])
  )
}

complete_word <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  shown <- number_argument(arguments[2], 1L, MAX_LISTED)
  word_letters <- split_letters(word)
  others <- names(checker$dictionary)
  distances <- vapply(others, function(other) {
    prefix_distance(word_letters, split_letters(other), checker$keyboard)
  }, integer(1), USE.NAMES = FALSE)
  keep <- distances <= limit(checker) %/% 2L
  matches <- rank_by_distance(checker, others[keep], distances[keep])
  listed <- head(matches, shown)
  emit(
    "COMPLETE", word, paste0("count=", length(matches)),
    sprintf("%s:%d", names(listed), listed)
  )
}

list_words <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  shown <- number_argument(arguments[2], 1L, MAX_LISTED)
  others <- sort(names(checker$dictionary))
  matches <- others[others >= word]
  listed <- head(matches, shown)
  emit(
    "LIST", word, paste0("count=", length(matches)),
    sprintf("%s:%d", listed, checker$dictionary[listed])
  )
}

word_info <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  frequency <- require_entry(checker, word)
  emit(
    "WORD", word, paste0("freq=", frequency),
    paste0("rank=", match(word, frequency_order(checker$dictionary))),
    paste0("soundex=", soundex(word)),
    paste0("neighbors=", length(candidates(checker, word)))
  )
}

add_word <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  frequency <- number_argument(arguments[2], 1L, MAX_FREQUENCY)
  if (word %in% names(checker$dictionary)) command_error(paste("DUPLICATE", word))
  record_undo(checker, "ADD")
  checker$dictionary[[word]] <- frequency
  checker$ignored <- setdiff(checker$ignored, word)
  emit("ADD", word, frequency)
}

remove_word <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  frequency <- require_entry(checker, word)
  record_undo(checker, "REMOVE")
  checker$dictionary <- checker$dictionary[names(checker$dictionary) != word]
  emit("REMOVE", word, frequency)
}

ignore_word <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  if (word %in% names(checker$dictionary)) command_error(paste("IN DICTIONARY", word))
  if (word %in% checker$ignored) command_error(paste("ALREADY IGNORED", word))
  record_undo(checker, "IGNORE")
  checker$ignored <- c(checker$ignored, word)
  emit("IGNORE", word)
}

unignore_word <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  if (!(word %in% checker$ignored)) command_error(paste("NOT IGNORED", word))
  record_undo(checker, "UNIGNORE")
  checker$ignored <- setdiff(checker$ignored, word)
  emit("UNIGNORE", word)
}

add_rule <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  target <- word_argument(arguments[2])
  if (word %in% names(checker$dictionary)) command_error(paste("IN DICTIONARY", word))
  if (!(target %in% names(checker$dictionary))) command_error(paste("NOT FOUND", target))
  record_undo(checker, "RULE")
  previous <- if (word %in% names(checker$rules)) checker$rules[[word]]
  checker$rules[[word]] <- target
  if (is.null(previous)) {
    emit("RULE", word, target)
  } else {
    emit("RULE", word, target, "REPLACED", previous)
  }
}

remove_rule <- function(checker, arguments) {
  word <- word_argument(arguments[1])
  if (!(word %in% names(checker$rules))) command_error(paste("NO RULE", word))
  record_undo(checker, "UNRULE")
  target <- checker$rules[[word]]
  checker$rules <- checker$rules[names(checker$rules) != word]
  emit("UNRULE", word, target)
}

show_rules <- function(checker, ...) {
  rules <- checker$rules[order(names(checker$rules))]
  emit("RULES", paste0("count=", length(rules)), sprintf("%s>%s", names(rules), rules))
}

set_keyboard <- function(checker, arguments) {
  keyboard_mode <- arguments[1]
  if (!(keyboard_mode %in% KEYBOARD_MODES)) command_error(paste("BAD MODE", keyboard_mode))
  checker$keyboard <- keyboard_mode == "ON"
  emit("KEYBOARD", keyboard_mode)
}

set_option <- function(checker, arguments) {
  option <- arguments[1]
  if (!(option %in% names(OPTION_MAXIMUMS))) command_error(paste("BAD OPTION", option))
  value <- number_argument(arguments[2], 1L, OPTION_MAXIMUMS[[option]])
  if (option == "LIMIT") {
    checker$base_limit <- value
  } else {
    checker$suggestion_count <- value
  }
  emit("SET", option, value)
}

undo_change <- function(checker, ...) {
  history_size <- length(checker$undo_history)
  if (history_size == 0L) command_error("NOTHING TO UNDO")
  record <- checker$undo_history[[history_size]]
  checker$undo_history <- checker$undo_history[-history_size]
  checker$dictionary <- record$dictionary
  checker$ignored <- record$ignored
  checker$rules <- record$rules
  emit("UNDO", record$name)
}

report_unknown <- function(checker, ...) {
  counts <- checker$unknown_log
  entries <- head(counts[order(-counts, names(counts))], REPORT_SIZE)
  emit("REPORT", paste0("distinct=", length(counts)), sprintf("%s:%d", names(entries), entries))
}

report_corrections <- function(checker, ...) {
  counts <- checker$correction_log
  entries <- head(counts[order(-counts, names(counts))], REPORT_SIZE)
  emit("HISTORY", paste0("distinct=", length(counts)), sprintf("%s:%d", names(entries), entries))
}

show_stats <- function(checker, ...) {
  dictionary <- checker$dictionary
  top <- frequency_order(dictionary)[1]
  emit(
    "STATS", paste0("words=", length(dictionary)), paste0("total=", sum(dictionary)),
    paste0("avglen=", decimal_text(sum(nchar(names(dictionary))), length(dictionary), 2L)),
    paste0("top=", top, ":", dictionary[[top]]), paste0("ignored=", length(checker$ignored)),
    paste0("rules=", length(checker$rules)),
    paste0("keyboard=", if (checker$keyboard) "ON" else "OFF"),
    paste0("limit=", limit(checker)), paste0("suggestions=", checker$suggestion_count),
    paste0("undo=", length(checker$undo_history))
  )
  emit("SESSION", paste0(COUNTER_NAMES, "=", checker$counters[COUNTER_NAMES]))
}

COMMANDS <- list(
  CHECK = list(arity = NA, handler = check_text),
  CORRECT = list(arity = NA, handler = correct_text),
  FIX = list(arity = NA, handler = fix_text),
  PROFILE = list(arity = NA, handler = profile_text),
  LEARN = list(arity = NA, handler = learn_text),
  SUGGEST = list(arity = 1L, handler = suggest_word),
  DIST = list(arity = 2L, handler = show_distance),
  SOUNDEX = list(arity = 1L, handler = show_soundex),
  SOUNDS = list(arity = 1L, handler = sounds_like),
  SPLIT = list(arity = 1L, handler = split_word),
  PREFIX = list(arity = 2L, handler = prefix_words),
  COMPLETE = list(arity = 2L, handler = complete_word),
  LIST = list(arity = 2L, handler = list_words),
  WORD = list(arity = 1L, handler = word_info),
  ADD = list(arity = 2L, handler = add_word),
  REMOVE = list(arity = 1L, handler = remove_word),
  IGNORE = list(arity = 1L, handler = ignore_word),
  UNIGNORE = list(arity = 1L, handler = unignore_word),
  RULE = list(arity = 2L, handler = add_rule),
  UNRULE = list(arity = 1L, handler = remove_rule),
  RULES = list(arity = 0L, handler = show_rules),
  KEYBOARD = list(arity = 1L, handler = set_keyboard),
  SET = list(arity = 2L, handler = set_option),
  UNDO = list(arity = 0L, handler = undo_change),
  REPORT = list(arity = 0L, handler = report_unknown),
  HISTORY = list(arity = 0L, handler = report_corrections),
  STATS = list(arity = 0L, handler = show_stats)
)

execute <- function(checker, line) {
  name <- sub(" .*", "", line)
  rest <- if (grepl(" ", line, fixed = TRUE)) sub("^[^ ]* ", "", line)
  tryCatch(
    {
      if (!(name %in% names(COMMANDS))) command_error(paste("UNKNOWN COMMAND", name))
      command <- COMMANDS[[name]]
      if (is.na(command$arity)) {
        if (is.null(rest)) command_error(paste("BAD ARGUMENTS", name))
        command$handler(checker, rest)
      } else {
        arguments <- if (is.null(rest)) character(0) else strsplit(rest, " ", fixed = TRUE)[[1]]
        if (length(arguments) != command$arity) command_error(paste("BAD ARGUMENTS", name))
        command$handler(checker, arguments)
      }
    },
    command_error = function(condition) emit("ERROR", conditionMessage(condition))
  )
}

main <- function() {
  Sys.setlocale("LC_COLLATE", "C")
  lines <- readLines(file("stdin"))
  word_count <- as.integer(lines[1])
  entries <- lines[seq_len(word_count) + 1L]
  dictionary <- setNames(as.integer(sub(".* ", "", entries)), sub(" .*", "", entries))
  checker <- new_spell_checker(dictionary)
  command_count <- as.integer(lines[word_count + 2L])
  for (line in lines[seq_len(command_count) + word_count + 2L]) {
    execute(checker, line)
  }
}

main()
