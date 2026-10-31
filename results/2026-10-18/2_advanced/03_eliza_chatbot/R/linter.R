CODE_ORDER <- c("SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED",
                "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE")
ERROR_CODES <- c("SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE")

unknown_groups <- function(pattern, groups) {
  names <- substring(pattern[startsWith(pattern, "@")], 2L)
  names[!names %in% names(groups)]
}

item_references <- function(item) {
  if (item$kind == "REASM") {
    starts <- seq_len(nchar(item$text))
    chunks <- substring(item$text, starts, starts + 2L)
    return(as.integer(substr(chunks[is_reference(chunks)], 2L, 2L)))
  }
  if (item$kind == "RESTATE") {
    args <- item$arguments[-1L]
    return(as.integer(substr(args[is_reference(args)], 2L, 2L)))
  }
  integer()
}

lint <- function(script) {
  found <- script$diagnostics
  add <- function(line, code, message) {
    found[[length(found) + 1L]] <<- list(line = line, code = code, message = message)
  }
  replacement_words <- unlist(lapply(script$pres, function(pre) pre$replacement), use.names = FALSE)
  targets <- unlist(lapply(script$items, function(item) if (item$kind %in% c("GOTO", "RESTATE")) item$arguments[1L]), use.names = FALSE)
  used_groups <- unlist(lapply(script$rules, function(rule) substring(rule$pattern[startsWith(rule$pattern, "@")], 2L)), use.names = FALSE)
  graph <- lapply(script$keywords, function(keyword) {
    unique(unlist(lapply(keyword$decomps, function(id) {
      unlist(lapply(script$rules[[id]]$items, function(item_id) {
        item <- script$items[[item_id]]
        if (item$kind %in% c("GOTO", "RESTATE") && item$arguments[1L] %in% names(script$keyword_map)) item$arguments[1L]
      }), use.names = FALSE)
    }), use.names = FALSE))
  })
  names(graph) <- names(script$keyword_map)
  reaches <- function(start, goal) {
    pending <- start
    seen <- character()
    while (length(pending)) {
      word <- pending[1L]
      pending <- pending[-1L]
      if (word == goal) return(TRUE)
      if (word %in% seen) next
      seen <- c(seen, word)
      pending <- c(pending, graph[[word]])
    }
    FALSE
  }
  for (keyword in script$keywords) {
    word <- keyword$word
    if (!length(keyword$decomps)) add(keyword$line, "KEY_NO_DECOMP", paste("keyword", word, "has no DECOMP"))
    if (word %in% names(script$pre_table) && !word %in% replacement_words && !word %in% targets) {
      add(keyword$line, "KEY_UNREACHABLE", paste("keyword", word, "is replaced by PRE"))
    }
  }
  for (group in script$groups) if (!group$name %in% used_groups) add(group$line, "SYNON_UNUSED", paste("group", group$name, "is never used"))
  for (pre in script$pres) for (word in pre$replacement) {
    if (word %in% names(script$pre_table)) add(pre$line, "PRE_CHAIN", paste("replacement", word, "is itself replaced by PRE"))
  }
  for (keyword in script$keywords) {
    for (ids in list(keyword$memories, keyword$decomps)) {
      for (position in seq_along(ids)) {
        rule <- script$rules[[ids[position]]]
        unknown <- unknown_groups(rule$pattern, script$group_words)
        for (name in unknown) add(rule$line, "SYNON_UNKNOWN", paste("unknown group", name))
        if (!length(rule$items)) add(rule$line, "RULE_NO_REASM", "rule has no reassembly")
        if (!length(unknown)) for (prior in head(ids, position - 1L)) {
          earlier <- script$rules[[prior]]
          if (!length(unknown_groups(earlier$pattern, script$group_words)) && pattern_covers(earlier$pattern, rule$pattern, script$group_words)) {
            add(rule$line, "RULE_SHADOWED", paste("pattern is shadowed by line", earlier$line))
            break
          }
        }
        wildcards <- sum(is_wildcard(rule$pattern))
        for (id in rule$items) {
          item <- script$items[[id]]
          for (number in item_references(item)) if (number == 0L || number > wildcards) {
            add(item$line, "REF_UNBOUND", paste0("reference (", number, ") is not bound"))
          }
          if (!item$kind %in% c("GOTO", "RESTATE")) next
          target <- item$arguments[1L]
          if (!target %in% names(script$keyword_map)) add(item$line, "TARGET_UNDEFINED", paste("target", target, "is not a keyword"))
          else if (reaches(target, keyword$word)) add(item$line, "TARGET_CYCLE", paste("edge", keyword$word, "->", target, "is on a cycle"))
        }
      }
    }
  }
  if (!length(found)) return(found)
  lines <- vapply(found, function(diagnostic) diagnostic$line, integer(1L))
  codes <- vapply(found, function(diagnostic) match(diagnostic$code, CODE_ORDER), integer(1L))
  found[order(lines, codes, seq_along(found), method = "radix")]
}
