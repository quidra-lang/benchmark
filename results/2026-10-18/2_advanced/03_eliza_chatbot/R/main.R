script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("script_loader", "matcher", "linter", "responder", "memory")) {
  source(file.path(source_dir, paste0(unit, ".R")))
}

SOURCES <- c("keyword", "memory", "question", "default", "repeat")
NO_ARGUMENT_COMMANDS <- c(":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo")
TEXT_COMMANDS <- c(":prepare", ":reflect", ":say", ":explain")
SINGLE_ARGUMENT_COMMANDS <- c(":groups", ":find", ":script", ":cycles", ":coverage")
KEYWORD_COMMANDS <- c(":script", ":cycles", ":coverage", ":test")

normalize <- function(text) {
  parts <- strsplit(tolower(text), "[,.?!;]")[[1L]]
  clauses <- lapply(parts, function(part) {
    words <- words_of(gsub("[^a-z0-9']", " ", part))
    words <- gsub("^'+|'+$", "", words)
    words[nzchar(words)]
  })
  clauses[lengths(clauses) > 0L]
}

all_words <- function(clauses) unlist(clauses, use.names = FALSE)

pre_substitute <- function(script, clauses) {
  lapply(clauses, function(clause) {
    unlist(lapply(clause, function(word) {
      replacement <- script$pre_table[[word]]
      if (is.null(replacement)) word else replacement
    }), use.names = FALSE)
  })
}

is_quit <- function(script, text) {
  words <- all_words(normalize(text))
  length(words) == 1L && words[1L] %in% script$quit_words
}

select_clause <- function(script, clauses) {
  for (i in seq_along(clauses)) if (any(clauses[[i]] %in% names(script$keyword_map))) return(i)
  0L
}

keyword_list <- function(script, words) {
  ids <- unique(unname(script$keyword_map[words[words %in% names(script$keyword_map)]]))
  ranks <- vapply(ids, function(id) script$keywords[[id]]$rank, integer(1L))
  ids[order(-ranks, seq_along(ids), method = "radix")]
}

rule_entries <- function(script, keyword) {
  entries <- list()
  for (field in c("memories", "decomps")) {
    ids <- keyword[[field]]
    for (number in seq_along(ids)) {
      entries[[length(entries) + 1L]] <- list(label = if (field == "memories") "memory" else "decomp", number = number, id = ids[number])
    }
  }
  entries
}

increment_count <- function(counts, word) {
  if (!word %in% names(counts)) counts[word] <- 0L
  counts[word] <- counts[word] + 1L
  counts
}

cycle_reset <- function(bot) {
  bot$state$positions[] <- 1L
  bot$state$list_positions[] <- 1L
  invisible(NULL)
}

take_text <- function(bot, name) {
  texts <- bot$script$texts[[name]]
  position <- bot$state$list_positions[[name]]
  bot$state$list_positions[[name]] <- position %% length(texts) + 1L
  texts[position]
}

take_item <- function(bot, rule_id) {
  items <- bot$script$rules[[rule_id]]$items
  position <- bot$state$positions[rule_id]
  id <- items[position]
  bot$state$item_uses[id] <- bot$state$item_uses[id] + 1L
  bot$state$positions[rule_id] <- position %% length(items) + 1L
  list(number = position, item = bot$script$items[[id]])
}

find_rule <- function(script, rules, words) {
  for (number in seq_along(rules)) {
    id <- rules[number]
    bindings <- match_pattern(script$rules[[id]]$pattern, words, script$group_words)
    if (!is.null(bindings)) return(list(number = number, id = id, bindings = bindings))
  }
  NULL
}

keyword_reply <- function(bot, clauses) {
  script <- bot$script
  selected <- select_clause(script, clauses)
  if (!selected) return(list(reply = NULL, trace = "CLAUSE none"))
  original <- clauses[[selected]]
  keys <- keyword_list(script, original)
  trace <- c(paste("CLAUSE", selected, paste(original, collapse = " ")),
             paste("KEYS", paste(vapply(keys, function(id) script$keywords[[id]]$word, character(1L)), collapse = " ")))
  first <- script$keywords[[keys[1L]]]
  found <- find_rule(script, first$memories, original)
  if (!is.null(found)) {
    trace <- c(trace, paste("MEMORY", first$word, found$number))
    bot$state$hits[found$id] <- bot$state$hits[found$id] + 1L
    if (length(script$rules[[found$id]]$items)) {
      item <- take_item(bot, found$id)$item
      memory_store(bot, first$word, build_reply(item$text, found$bindings, script$post_table))
    }
  }
  entered <- integer()
  for (key_id in keys) {
    if (key_id %in% entered) next
    trace <- c(trace, paste("ENTER", script$keywords[[key_id]]$word))
    words <- original
    repeat {
      entered <- c(entered, key_id)
      keyword <- script$keywords[[key_id]]
      bot$state$keyword_uses[key_id] <- bot$state$keyword_uses[key_id] + 1L
      found <- find_rule(script, keyword$decomps, words)
      if (is.null(found)) {
        trace <- c(trace, paste("NOMATCH", keyword$word))
        break
      }
      bot$state$hits[found$id] <- bot$state$hits[found$id] + 1L
      if (!length(script$rules[[found$id]]$items)) {
        trace <- c(trace, paste("DECOMP", keyword$word, found$number, 0L))
        break
      }
      taken <- take_item(bot, found$id)
      item <- taken$item
      trace <- c(trace, paste("DECOMP", keyword$word, found$number, taken$number))
      if (item$kind == "REASM") {
        bot$state$keyword_replies[key_id] <- bot$state$keyword_replies[key_id] + 1L
        bot$state$session$topics <- increment_count(bot$state$session$topics, keyword$word)
        return(list(reply = build_reply(item$text, found$bindings, script$post_table), trace = trace))
      }
      if (item$kind == "NEWKEY") break
      target <- item$arguments[1L]
      if (!target %in% names(script$keyword_map) || script$keyword_map[[target]] %in% entered) {
        trace <- c(trace, paste("BLOCKED", target))
        break
      }
      if (item$kind == "RESTATE") {
        words <- restated_words(item$arguments[-1L], found$bindings)
        trace <- c(trace, paste(c("RESTATE", target, words), collapse = " "))
      } else trace <- c(trace, paste("GOTO", target))
      key_id <- script$keyword_map[[target]]
    }
  }
  list(reply = NULL, trace = trace)
}

decide <- function(bot, text) {
  clauses <- normalize(text)
  if (length(bot$script$texts$REPEAT) && length(clauses) && identical(clauses, bot$state$session$previous)) {
    trace <- "REPEAT"
    reply <- take_text(bot, "REPEAT")
    source <- "repeat"
  } else {
    result <- keyword_reply(bot, pre_substitute(bot$script, clauses))
    reply <- result$reply
    trace <- result$trace
    source <- "keyword"
    if (is.null(reply)) {
      if (length(bot$state$memory$texts)) {
        reply <- memory_recall(bot)
        source <- "memory"
      } else if (endsWith(text, "?") && length(bot$script$texts$QUESTION)) {
        reply <- take_text(bot, "QUESTION")
        source <- "question"
      } else {
        reply <- take_text(bot, "DEFAULT")
        source <- "default"
      }
    }
  }
  bot$state$session$previous <- clauses
  bot$state$session$sources[source] <- bot$state$session$sources[source] + 1L
  if (source %in% c("question", "default")) bot$state$session$unrecognized <- c(bot$state$session$unrecognized, bot$state$session$turns)
  list(reply = reply, trace = c(trace, paste("REPLY", source)))
}

source_line <- function(turns, sources) {
  paste0("turns=", turns, " ", paste(paste0(SOURCES, "=", sources[SOURCES]), collapse = " "))
}

grouped_lines <- function(values, size) {
  if (!length(values)) return(character())
  starts <- seq.int(1L, length(values), by = size)
  vapply(starts, function(start) paste(values[seq.int(start, min(start + size - 1L, length(values)))], collapse = " "), character(1L))
}

ranked_counts <- function(counts) {
  if (!length(counts)) return("none")
  keys <- sort(names(counts), method = "radix")
  keys <- head(keys[order(-counts[keys], seq_along(keys), method = "radix")], 5L)
  paste(paste(keys, counts[keys]), collapse = ", ")
}

arguments_fit <- function(name, text, args) {
  if (name %in% NO_ARGUMENT_COMMANDS) return(!length(args))
  if (name %in% TEXT_COMMANDS) return(nzchar(text))
  if (name %in% SINGLE_ARGUMENT_COMMANDS) return(length(args) == 1L)
  if (name == ":trace") return(length(args) == 1L && args[1L] %in% c("on", "off"))
  length(args) >= 2L
}

debug_command <- function(bot, line) {
  parts <- words_of(line)
  name <- parts[1L]
  args <- parts[-1L]
  text <- if (length(args)) substring(line, nchar(name) + 2L) else ""
  if (!name %in% c(NO_ARGUMENT_COMMANDS, TEXT_COMMANDS, SINGLE_ARGUMENT_COMMANDS, ":trace", ":test")) return(paste("unknown command", name))
  if (!arguments_fit(name, text, args)) return("bad arguments")
  script <- bot$script
  if (name %in% KEYWORD_COMMANDS && !args[1L] %in% names(script$keyword_map)) return(paste("unknown keyword", args[1L]))
  if (name == ":prepare") {
    clauses <- pre_substitute(script, normalize(text))
    output <- vapply(seq_along(clauses), function(i) paste0("clause ", i, ": ", paste(clauses[[i]], collapse = " ")), character(1L))
    if (!length(clauses)) output <- "no words"
    selected <- select_clause(script, clauses)
    if (!selected) return(c(output, "selected none"))
    keys <- keyword_list(script, clauses[[selected]])
    labels <- vapply(keys, function(id) paste0(script$keywords[[id]]$word, "/", script$keywords[[id]]$rank), character(1L))
    return(c(output, paste("selected", selected), paste("keys", paste(labels, collapse = " "))))
  }
  if (name == ":reflect") {
    clauses <- pre_substitute(script, normalize(text))
    if (!length(clauses)) return("no words")
    return(vapply(clauses, function(clause) paste(reflect_words(clause, script$post_table), collapse = " "), character(1L)))
  }
  if (name == ":keys") {
    keys <- sort(names(script$keyword_map), method = "radix")
    if (!length(keys)) return(character())
    ids <- unname(script$keyword_map[keys])
    ranks <- vapply(ids, function(id) script$keywords[[id]]$rank, integer(1L))
    order <- order(-ranks, seq_along(keys), method = "radix")
    return(grouped_lines(paste0(keys[order], "/", ranks[order]), 8L))
  }
  if (name == ":groups") {
    groups <- vapply(script$groups, function(group) if (args[1L] %in% group$members) group$name else "", character(1L))
    groups <- sort(groups[nzchar(groups)], method = "radix")
    return(if (length(groups)) paste(groups, collapse = " ") else "none")
  }
  if (name == ":find") {
    word <- args[1L]
    output <- character()
    if (word %in% names(script$keyword_map)) output <- paste("keyword rank", script$keywords[[script$keyword_map[[word]]]]$rank)
    for (label in c("pre", "post")) {
      substitutions <- if (label == "pre") script$pres else script$posts
      for (substitution in substitutions) if (word == substitution$source || word %in% substitution$replacement) {
        output <- c(output, paste0(label, " ", substitution$line, ": ", substitution$source, " -> ", paste(substitution$replacement, collapse = " ")))
      }
    }
    for (group in script$groups) if (word %in% group$members) output <- c(output, paste("group", group$name, "line", group$line))
    for (keyword in script$keywords) for (entry in rule_entries(script, keyword)) {
      if (word %in% script$rules[[entry$id]]$pattern) output <- c(output, paste("pattern", keyword$word, entry$label, entry$number))
    }
    if (word %in% script$stop_words) output <- c(output, "stop word")
    if (word %in% script$quit_words) output <- c(output, "quit word")
    return(if (length(output)) output else "not found")
  }
  if (name %in% KEYWORD_COMMANDS) {
    keyword <- script$keywords[[script$keyword_map[[args[1L]]]]]
    entries <- rule_entries(script, keyword)
    if (name == ":script") {
      numbers <- c(keyword$line, unlist(lapply(entries, function(entry) {
        rule <- script$rules[[entry$id]]
        c(rule$line, vapply(rule$items, function(id) script$items[[id]]$line, integer(1L)))
      }), use.names = FALSE))
      numbers <- sort(numbers)
      return(paste(numbers, script$lines[numbers]))
    }
    output <- character()
    words <- if (name == ":test") all_words(pre_substitute(script, normalize(substring(text, nchar(args[1L]) + 2L)))) else character()
    for (entry in entries) {
      rule <- script$rules[[entry$id]]
      prefix <- paste0(entry$label, " ", entry$number, ": ")
      if (name == ":test") {
        bindings <- match_pattern(rule$pattern, words, script$group_words)
        result <- if (is.null(bindings)) "no match" else if (!length(bindings)) "match" else {
          paste(vapply(bindings, function(bound) paste0("[", paste(bound, collapse = " "), "]"), character(1L)), collapse = " ")
        }
      } else if (name == ":cycles") {
        result <- if (!length(rule$items)) "empty" else paste0("next ", bot$state$positions[entry$id], "/", length(rule$items))
      } else {
        uses <- if (!length(rule$items)) "-" else paste(bot$state$item_uses[rule$items], collapse = " ")
        result <- paste("hits", bot$state$hits[entry$id], "entries", uses)
      }
      output <- c(output, paste0(prefix, result))
    }
    return(if (length(output)) output else "no rules")
  }
  if (name == ":why") return(if (is.null(bot$state$session$last_trace)) "no reply yet" else bot$state$session$last_trace)
  if (name == ":trace") {
    bot$state$session$trace_on <- args[1L] == "on"
    return(paste("trace", args[1L]))
  }
  if (name == ":history") return(if (length(bot$state$session$history)) tail(bot$state$session$history, 5L) else "no turns yet")
  if (name == ":memory") {
    memory <- bot$state$memory
    return(c(paste0("memory ", length(memory$texts), "/", memory$capacity),
             vapply(seq_along(memory$texts), function(i) paste0(i, ": ", memory$texts[i]), character(1L))))
  }
  if (name == ":forget") {
    count <- length(bot$state$memory$texts)
    memory_clear(bot)
    return(paste("forgot", count))
  }
  if (name == ":reset") {
    cycle_reset(bot)
    return("cycles reset")
  }
  if (name == ":unused") {
    ids <- which(bot$state$item_uses == 0L)
    numbers <- sort(vapply(ids, function(id) script$items[[id]]$line, integer(1L)))
    return(c(paste("unused", length(numbers)), grouped_lines(as.character(numbers), 12L)))
  }
  if (name == ":stats") return(source_line(bot$state$session$turns, bot$state$session$sources))
  if (name == ":undo") {
    snapshot <- bot$state$session$undo
    if (is.null(snapshot)) return("nothing to undo")
    bot$state <- snapshot
    return(paste("undone turn", bot$state$session$turns + 1L))
  }
  if (is_quit(script, text)) return("would quit")
  saved <- bot$state
  result <- decide(bot, text)
  bot$state <- saved
  if (name == ":say") result$reply else result$trace
}

new_session <- function(name) {
  list(name = name, turns = 0L, sources = setNames(integer(length(SOURCES)), SOURCES),
       previous = NULL, history = character(), last_trace = NULL, trace_on = FALSE,
       topics = integer(), words = integer(), stored = 0L, recalled = 0L,
       unrecognized = integer(), undo = NULL)
}

write_notes <- function(bot) {
  session <- bot$state$session
  unrecognized <- if (length(session$unrecognized)) paste(session$unrecognized, collapse = " ") else "none"
  notes <- c(source_line(session$turns, session$sources), paste0("topics: ", ranked_counts(session$topics)),
             paste0("words: ", ranked_counts(session$words)),
             paste0("memory: stored=", session$stored, " recalled=", session$recalled, " pending=", length(bot$state$memory$texts)),
             paste0("unrecognized: ", unrecognized))
  bot$transcript <- c(bot$transcript, paste("NOTES", session$name), paste0("  ", notes))
  bot$total_turns <- bot$total_turns + session$turns
  bot$total_sources <- bot$total_sources + session$sources
}

run_session <- function(bot, number, name, lines) {
  script <- bot$script
  if (number >= 2L) {
    bot$transcript <- c(bot$transcript, "")
    if (!"cycles" %in% script$persist) cycle_reset(bot)
    if (!"memory" %in% script$persist) memory_clear(bot, paste(name, 0L))
  }
  bot$state$session <- new_session(name)
  greeting <- script$texts$INITIAL[(number - 1L) %% length(script$texts$INITIAL) + 1L]
  bot$transcript <- c(bot$transcript, paste("SESSION", name), eliza_lines(greeting))
  for (line in lines) {
    if (startsWith(line, ":")) {
      bot$transcript <- c(bot$transcript, line)
      output <- debug_command(bot, line)
      if (length(output)) bot$transcript <- c(bot$transcript, paste0("  ", output))
      next
    }
    bot$transcript <- c(bot$transcript, paste0("YOU: ", line))
    if (is_quit(script, line)) {
      farewell <- script$texts$FINAL[(number - 1L) %% length(script$texts$FINAL) + 1L]
      bot$transcript <- c(bot$transcript, eliza_lines(farewell))
      break
    }
    snapshot <- bot$state
    snapshot$session$undo <- NULL
    bot$state$session$undo <- snapshot
    bot$state$session$turns <- bot$state$session$turns + 1L
    for (word in all_words(normalize(line))) if (!word %in% script$stop_words) {
      bot$state$session$words <- increment_count(bot$state$session$words, word)
    }
    bot$state$session$history <- c(bot$state$session$history, paste0(bot$state$session$turns, ": ", line))
    result <- decide(bot, line)
    bot$transcript <- c(bot$transcript, eliza_lines(result$reply))
    bot$state$session$last_trace <- result$trace
    if (bot$state$session$trace_on) bot$transcript <- c(bot$transcript, paste0("  ", result$trace))
  }
  write_notes(bot)
}

keyword_stats <- function(bot) {
  script <- bot$script
  keys <- sort(names(script$keyword_map), method = "radix")
  ids <- unname(script$keyword_map[keys])
  ids <- ids[order(-bot$state$keyword_uses[ids], seq_along(ids), method = "radix")]
  rows <- vapply(ids, function(id) {
    keyword <- script$keywords[[id]]
    hits <- if (length(keyword$decomps)) paste(bot$state$hits[keyword$decomps], collapse = "/") else "-"
    paste(keyword$word, keyword$rank, bot$state$keyword_uses[id], bot$state$keyword_replies[id], hits, sep = ",")
  }, character(1L))
  c("keyword,rank,uses,replies,decomposition_hits", rows)
}

main <- function() {
  script <- load_script("input/script.txt")
  diagnostics <- lint(script)
  lint_output <- "OK"
  if (length(diagnostics)) {
    lint_output <- vapply(diagnostics, function(diagnostic) paste(diagnostic$line, diagnostic$code, diagnostic$message), character(1L))
    errors <- sum(vapply(diagnostics, function(diagnostic) diagnostic$code %in% ERROR_CODES, logical(1L)))
    lint_output <- c(lint_output, paste0("TOTAL ", length(diagnostics), " errors=", errors, " warnings=", length(diagnostics) - errors))
  }
  bot <- new.env(parent = emptyenv())
  bot$script <- script
  bot$state <- list(positions = rep.int(1L, length(script$rules)), hits = integer(length(script$rules)),
                    item_uses = integer(length(script$items)), keyword_uses = integer(length(script$keywords)),
                    keyword_replies = integer(length(script$keywords)),
                    list_positions = setNames(rep.int(1L, 3L), c("DEFAULT", "QUESTION", "REPEAT")),
                    memory = list(capacity = script$memsize, texts = character(), log = character()), session = NULL)
  bot$transcript <- character()
  bot$total_turns <- 0L
  bot$total_sources <- setNames(integer(length(SOURCES)), SOURCES)
  lines <- readLines("input/dialogue.txt", warn = FALSE)
  starts <- which(startsWith(lines, "SESSION "))
  ends <- c(starts[-1L] - 1L, length(lines))
  for (number in seq_along(starts)) {
    start <- starts[number]
    run_session(bot, number, substring(lines[start], 9L), lines[seq.int(start + 1L, ends[number])])
  }
  bot$transcript <- c(bot$transcript, "", paste("SUMMARY", paste0("sessions=", length(starts)), source_line(bot$total_turns, bot$total_sources)))
  dir.create("output", showWarnings = FALSE)
  writeLines(lint_output, "output/lint.txt", useBytes = TRUE)
  writeLines(bot$transcript, "output/transcript.txt", useBytes = TRUE)
  writeLines(keyword_stats(bot), "output/keyword_stats.csv", useBytes = TRUE)
  writeLines(bot$state$memory$log, "output/memory_log.txt", useBytes = TRUE)
}

main()
