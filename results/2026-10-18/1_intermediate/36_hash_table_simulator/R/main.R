modes <- c("CHAIN", "LINEAR", "QUADRATIC", "DOUBLE", "ROBINHOOD", "CUCKOO")
commands <- c("CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "PUT", "ADD", "GET",
              "DEL", "PROBE", "GEN", "GENDEL", "RESIZE", "CONVERT", "CLEAR", "DUMP",
              "MAP", "STATS", "KEYS", "TOP", "SCAN", "CLUSTERS", "DIST", "COMPARE", "BENCH")
fail <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("command_error", "error", "condition")))
}
next_prime <- function(value) {
  value <- max(2L, value)
  repeat {
    divisor <- 2L
    while (divisor * divisor <= value && value %% divisor != 0L) divisor <- divisor + 1L
    if (divisor * divisor > value) return(value)
    value <- value + 1L
  }
}
hash <- function(key, base, modulus) {
  value <- 0L
  for (code in utf8ToInt(key)) value <- (value * base + code) %% modulus
  value
}
decimal <- function(numerator, denominator) {
  if (denominator == 0L) return("0.00")
  scaled <- as.integer((gmp::as.bigz(numerator) * 100L) %/% denominator)
  sprintf("%d.%02d", scaled %/% 100L, scaled %% 100L)
}
slot_count <- function(table) table$cap * if (table$mode == "CUCKOO") 2L else 1L
position_text <- function(table, position) {
  if (table$mode == "CUCKOO") {
    sprintf("T%d.%d", (position - 1L) %/% table$cap + 1L, (position - 1L) %% table$cap)
  } else as.character(position - 1L)
}
distance <- function(table, key, position) {
  (position - 1L - hash(key, 31L, table$cap) + table$cap) %% table$cap
}
new_table <- function(mode, cap) {
  table <- new.env(parent = emptyenv())
  table$mode <- mode
  table$cap <- cap
  table$size <- table$tomb <- 0L
  table$buckets <- vector("list", if (mode == "CHAIN") cap else 0L)
  count <- if (mode == "CHAIN") 0L else slot_count(table)
  table$state <- integer(count) # 0 empty, 1 item, 2 tombstone.
  table$keys <- rep("", count)
  table$values <- integer(count)
  table$counters <- setNames(integer(8L), c("probes", "rehashes", "inserts", "updates",
                                           "hits", "misses", "deletes", "absent"))
  table
}
adopt <- function(table, replacement) {
  for (name in c("mode", "cap", "size", "tomb", "buckets", "state", "keys", "values")) {
    table[[name]] <- replacement[[name]]
  }
}
increment <- function(table, name, amount = 1L) table$counters[name] <- table$counters[name] + amount
item_keys <- function(items) vapply(items, function(item) item$key, character(1), USE.NAMES = FALSE)
table_items <- function(table) {
  if (table$mode == "CHAIN") return(unlist(table$buckets, recursive = FALSE, use.names = FALSE))
  lapply(which(table$state == 1L), function(position) list(key = table$keys[position], value = table$values[position]))
}
content <- function(table, position) {
  if (table$state[position] == 1L) table$keys[position] else if (table$state[position] == 2L) "D" else "-"
}
pair_text <- function(item) paste0(item$key, "=", item$value)
put_slot <- function(table, position, item) {
  table$state[position] <- 1L
  table$keys[position] <- item$key
  table$values[position] <- item$value
}
slot_item <- function(table, position) list(key = table$keys[position], value = table$values[position])

# Search positions are one-based internally; paths always describe the old table.
search <- function(table, key, tracing = FALSE) {
  result <- list(found = FALSE, position = 0L, chain = 0L, probes = 0L, available = 0L,
                 item = NULL, path = character())
  home <- hash(key, 31L, table$cap) + 1L
  if (table$mode == "CHAIN") {
    bucket <- table$buckets[[home]]
    for (index in seq_along(bucket)) {
      item <- bucket[[index]]
      result$probes <- result$probes + 1L
      if (tracing) result$path <- c(result$path, paste0(home - 1L, ":", item$key))
      if (item$key == key) {
        result$found <- TRUE
        result$position <- home
        result$chain <- index
        result$item <- item
        return(result)
      }
    }
  } else if (table$mode == "CUCKOO") {
    for (position in c(home, table$cap + hash(key, 37L, table$cap) + 1L)) {
      result$probes <- result$probes + 1L
      if (tracing) result$path <- c(result$path, paste0(position_text(table, position), ":", content(table, position)))
      if (table$state[position] == 1L && table$keys[position] == key) {
        result$found <- TRUE
        result$position <- position
        result$item <- slot_item(table, position)
        return(result)
      }
    }
  } else {
    step <- 1L + hash(key, 37L, table$cap - 1L)
    for (index in seq_len(table$cap) - 1L) {
      offset <- switch(table$mode, QUADRATIC = index * index, DOUBLE = index * step, index)
      position <- (home - 1L + offset) %% table$cap + 1L
      result$probes <- result$probes + 1L
      if (tracing) result$path <- c(result$path, paste0(position - 1L, ":", content(table, position)))
      if (table$state[position] == 0L) {
        if (result$available == 0L) result$available <- position
        return(result)
      }
      if (table$state[position] == 2L) {
        if (result$available == 0L) result$available <- position
      } else {
        if (table$keys[position] == key) {
          result$found <- TRUE
          result$position <- position
          result$item <- slot_item(table, position)
          return(result)
        }
        if (table$mode == "ROBINHOOD" && distance(table, table$keys[position], position) < index) return(result)
      }
    }
  }
  result
}
place <- function(table, item, initial = NULL, tracing = FALSE) {
  result <- list(success = TRUE, position = 0L, reused = FALSE, shifted = 0L,
                 kicks = 0L, homeless = NULL, moves = character())
  original <- item$key
  if (table$mode == "CHAIN") {
    result$position <- hash(item$key, 31L, table$cap) + 1L
    table$buckets[[result$position]] <- c(table$buckets[[result$position]], list(item))
  } else if (table$mode %in% c("LINEAR", "QUADRATIC", "DOUBLE")) {
    if (is.null(initial)) initial <- search(table, item$key)
    position <- initial$available
    result$position <- position
    if (position == 0L) {
      result$success <- FALSE
      result$homeless <- item
    } else {
      result$reused <- table$state[position] == 2L
      if (result$reused) table$tomb <- table$tomb - 1L
      put_slot(table, position, item)
    }
  } else if (table$mode == "ROBINHOOD") {
    position <- hash(item$key, 31L, table$cap) + 1L
    travelled <- 0L
    origin <- 0L
    repeat {
      if (table$state[position] == 0L) {
        put_slot(table, position, item)
        if (result$position == 0L) result$position <- position
        if (tracing && origin > 0L) result$moves <- c(result$moves, sprintf("SHIFT %s %d -> %d", item$key, origin - 1L, position - 1L))
        break
      }
      other <- slot_item(table, position)
      old_distance <- distance(table, other$key, position)
      if (old_distance < travelled) {
        put_slot(table, position, item)
        if (result$position == 0L) result$position <- position
        if (tracing && origin > 0L) result$moves <- c(result$moves, sprintf("SHIFT %s %d -> %d", item$key, origin - 1L, position - 1L))
        item <- other
        origin <- position
        travelled <- old_distance
        result$shifted <- result$shifted + 1L
      }
      position <- position %% table$cap + 1L
      travelled <- travelled + 1L
    }
  } else {
    part <- 0L
    repeat {
      position <- part * table$cap + hash(item$key, 31L + 6L * part, table$cap) + 1L
      if (table$state[position] == 0L) {
        put_slot(table, position, item)
        result$position <- search(table, original)$position
        break
      }
      if (result$kicks == table$cap) {
        result$success <- FALSE
        result$homeless <- item
        break
      }
      other <- slot_item(table, position)
      put_slot(table, position, item)
      result$kicks <- result$kicks + 1L
      if (tracing) result$moves <- c(result$moves, paste("KICK", other$key, position_text(table, position)))
      item <- other
      part <- 1L - part
    }
  }
  result
}
remove_item <- function(table, found, tracing) {
  shifted <- 0L
  moves <- character()
  position <- found$position
  if (table$mode == "CHAIN") {
    table$buckets[[position]] <- table$buckets[[position]][-found$chain]
  } else if (table$mode %in% c("LINEAR", "QUADRATIC", "DOUBLE")) {
    table$state[position] <- 2L
    table$tomb <- table$tomb + 1L
  } else {
    table$state[position] <- 0L
    if (table$mode == "ROBINHOOD") {
      following <- position %% table$cap + 1L
      while (table$state[following] == 1L && distance(table, table$keys[following], following) > 0L) {
        destination <- (following - 2L + table$cap) %% table$cap + 1L
        item <- slot_item(table, following)
        put_slot(table, destination, item)
        table$state[following] <- 0L
        shifted <- shifted + 1L
        if (tracing) moves <- c(moves, sprintf("SHIFT %s %d -> %d", item$key, following - 1L, destination - 1L))
        following <- following %% table$cap + 1L
      }
    }
  }
  table$size <- table$size - 1L
  list(shifted = shifted, moves = moves)
}

# Environment replacement happens only after the complete trial succeeds.
rebuild <- function(table, mode, capacity, items) {
  trial <- new_table(mode, capacity)
  for (item in items) {
    if (!place(trial, item)$success) return(FALSE)
  }
  trial$size <- length(items)
  adopt(table, trial)
  TRUE
}
automatic <- function(table, capacity, reason, pending = NULL) {
  old <- table$cap
  items <- table_items(table)
  if (!is.null(pending)) items <- c(items, list(pending))
  while (!rebuild(table, table$mode, capacity, items)) capacity <- next_prime(2L * capacity)
  increment(table, "rehashes")
  sprintf("REHASH %s %d -> %d", reason, old, table$cap)
}
load_check <- function(table, maximum) {
  if ((table$size + table$tomb) * 100L <= maximum * slot_count(table)) return(character())
  grow <- table$size * 200L > maximum * slot_count(table)
  automatic(table, if (grow) next_prime(2L * table$cap) else table$cap, if (grow) "load" else "tomb")
}
shrink_check <- function(table, minimum, maximum) {
  capacity <- next_prime(table$cap %/% 2L)
  slots <- capacity * if (table$mode == "CUCKOO") 2L else 1L
  if (table$size * 100L >= minimum * slot_count(table) || capacity >= table$cap || table$size * 100L > maximum * slots) return(character())
  old <- table$cap
  if (!rebuild(table, table$mode, capacity, table_items(table))) return(character())
  increment(table, "rehashes")
  sprintf("REHASH shrink %d -> %d", old, capacity)
}
trace_path <- function(found, tracing) {
  if (tracing) paste("PATH", if (length(found$path)) paste(found$path, collapse = " ") else "none") else character()
}
put <- function(table, key, value, command, maximum, tracing = FALSE) {
  found <- search(table, key, tracing)
  increment(table, "probes", found$probes)
  trace <- trace_path(found, tracing)
  if (found$found) {
    old <- found$item$value
    if (command == "ADD") value <- old + value
    item <- list(key = key, value = value)
    if (table$mode == "CHAIN") table$buckets[[found$position]][[found$chain]] <- item else put_slot(table, found$position, item)
    increment(table, "updates")
    row <- sprintf("%s %s=%d UPDATED old=%d at=%s probes=%d", command, key, value, old, position_text(table, found$position), found$probes)
    return(list(changed = FALSE, rehashes = character(), rows = c(row, trace)))
  }
  placed <- place(table, list(key = key, value = value), found, tracing)
  table$size <- table$size + 1L
  increment(table, "inserts")
  row <- sprintf("%s %s=%d NEW", command, key, value)
  rehashes <- character()
  if (placed$success) {
    row <- paste0(row, sprintf(" at=%s probes=%d", position_text(table, placed$position), found$probes))
    if (placed$reused) row <- paste0(row, " reused")
    if (table$mode == "ROBINHOOD") row <- paste0(row, " shifted=", placed$shifted)
    if (table$mode == "CUCKOO") row <- paste0(row, " kicks=", placed$kicks)
  } else {
    row <- paste0(row, " probes=", found$probes)
    cuckoo <- table$mode == "CUCKOO"
    row <- paste0(row, if (cuckoo) paste0(" kicks=", placed$kicks, " failed") else " full")
    rehashes <- automatic(table, next_prime(2L * table$cap), if (cuckoo) "kicks" else "full", placed$homeless)
  }
  rehashes <- c(rehashes, load_check(table, maximum))
  list(changed = TRUE, rehashes = rehashes, rows = c(row, trace, placed$moves, rehashes))
}
get_item <- function(table, key, tracing) {
  found <- search(table, key, tracing)
  increment(table, "probes", found$probes)
  if (found$found) {
    increment(table, "hits")
    row <- sprintf("GET %s=%d at=%s probes=%d", key, found$item$value, position_text(table, found$position), found$probes)
  } else {
    increment(table, "misses")
    row <- sprintf("GET %s NOT FOUND probes=%d", key, found$probes)
  }
  c(row, trace_path(found, tracing))
}
delete_item <- function(table, key, minimum, maximum, tracing = FALSE) {
  found <- search(table, key, tracing)
  increment(table, "probes", found$probes)
  trace <- trace_path(found, tracing)
  if (!found$found) {
    increment(table, "absent")
    return(list(changed = FALSE, rehashes = character(), rows = c(sprintf("DEL %s NOT FOUND probes=%d", key, found$probes), trace)))
  }
  removed <- remove_item(table, found, tracing)
  increment(table, "deletes")
  row <- sprintf("DEL %s OK at=%s probes=%d", key, position_text(table, found$position), found$probes)
  if (table$mode == "ROBINHOOD") row <- paste0(row, " shifted=", removed$shifted)
  rehashes <- shrink_check(table, minimum, maximum)
  list(changed = TRUE, rehashes = rehashes, rows = c(row, trace, removed$moves, rehashes))
}

costs <- function(table) {
  keys <- character()
  values <- positions <- integer()
  if (table$mode == "CHAIN") {
    for (position in seq_len(table$cap)) {
      bucket <- table$buckets[[position]]
      keys <- c(keys, item_keys(bucket))
      values <- c(values, seq_along(bucket))
      positions <- c(positions, rep.int(position, length(bucket)))
    }
  } else {
    positions <- which(table$state == 1L)
    keys <- table$keys[positions]
    values <- vapply(positions, function(position) {
      if (table$mode == "CUCKOO") return((position - 1L) %/% table$cap + 1L)
      if (table$mode %in% c("LINEAR", "ROBINHOOD")) return(distance(table, table$keys[position], position) + 1L)
      search(table, table$keys[position])$probes
    }, integer(1), USE.NAMES = FALSE)
  }
  list(keys = keys, values = values, positions = positions)
}
metrics <- function(table) {
  values <- costs(table)$values
  list(longest = max(0L, values), average = decimal(sum(values), table$size))
}
dump <- function(table) {
  rows <- sprintf("DUMP %s cap=%d size=%d tomb=%d", table$mode, table$cap, table$size, table$tomb)
  if (table$mode == "CHAIN") {
    detail <- vapply(seq_len(table$cap), function(position) {
      bucket <- table$buckets[[position]]
      text <- if (length(bucket)) paste(vapply(bucket, pair_text, character(1)), collapse = " ") else "-"
      paste(position - 1L, text)
    }, character(1))
  } else {
    detail <- vapply(seq_along(table$state), function(position) {
      prefix <- if (table$mode == "CUCKOO") sprintf("T%d %d", (position - 1L) %/% table$cap + 1L, (position - 1L) %% table$cap) else as.character(position - 1L)
      text <- content(table, position)
      if (table$state[position] == 1L) {
        text <- pair_text(slot_item(table, position))
        if (table$mode == "ROBINHOOD") text <- paste0(text, " d=", distance(table, table$keys[position], position))
      }
      paste(prefix, text)
    }, character(1))
  }
  c(rows, detail)
}
gauge <- function(value) ifelse(value >= 10L, "+", as.character(value))
map_report <- function(table) {
  marks <- rep(".", slot_count(table))
  if (table$mode == "CHAIN") {
    counts <- lengths(table$buckets)
    marks[counts > 0L] <- gauge(counts[counts > 0L])
  } else {
    marks[table$state == 2L] <- "D"
    records <- costs(table)
    marks[records$positions] <- if (table$mode == "CUCKOO") "#" else gauge(records$values - 1L)
  }
  rows <- sprintf("MAP %s cap=%d", table$mode, table$cap)
  for (part in seq_len(if (table$mode == "CUCKOO") 2L else 1L) - 1L) {
    prefix <- if (table$mode == "CUCKOO") paste0("T", part + 1L, " ") else ""
    for (start in seq.int(0L, table$cap - 1L, by = 40L)) {
      indices <- part * table$cap + seq.int(start + 1L, min(start + 40L, table$cap))
      rows <- c(rows, paste0(prefix, sprintf("%05d ", start), paste(marks[indices], collapse = "")))
    }
  }
  rows
}
statistics <- function(table) {
  values <- metrics(table)
  counts <- table$counters
  c(sprintf("STATS %s size=%d cap=%d slots=%d tomb=%d load=%s%% longest=%d avg=%s probes=%d rehashes=%d",
            table$mode, table$size, table$cap, slot_count(table), table$tomb,
            decimal(100L * table$size, slot_count(table)), values$longest, values$average, counts["probes"], counts["rehashes"]),
    paste("OPS", paste(paste0(names(counts)[3:8], "=", counts[3:8]), collapse = " ")))
}
scan_table <- function(table, cursor, limit) {
  keys <- character()
  while (cursor < slot_count(table) && length(keys) < limit) {
    position <- cursor + 1L
    if (table$mode == "CHAIN") keys <- c(keys, item_keys(table$buckets[[position]])) else if (table$state[position] == 1L) keys <- c(keys, table$keys[position])
    cursor <- cursor + 1L
  }
  if (cursor == slot_count(table)) cursor <- 0L
  paste(c(paste0("SCAN next=", cursor), keys), collapse = " ")
}
circular_runs <- function(occupied) {
  size <- length(occupied)
  if (!size) return(integer())
  empty <- match(FALSE, occupied, nomatch = 0L)
  if (empty == 0L) return(size)
  order <- c(if (empty < size) seq.int(empty + 1L, size) else integer(), seq_len(empty))
  runs <- rle(occupied[order])
  runs$lengths[runs$values]
}
histogram <- function(values) {
  counts <- tabulate(values)
  values <- which(counts > 0L)
  counts <- counts[values]
  bars <- paste0(strrep("#", pmin.int(50L, counts)), ifelse(counts > 50L, "+", ""))
  sprintf("%d %d %s", values, counts, bars)
}
clusters <- function(table) {
  if (table$mode == "CHAIN") {
    values <- lengths(table$buckets)
    values <- values[values > 0L]
  } else if (table$mode == "CUCKOO") {
    values <- c(circular_runs(table$state[seq_len(table$cap)] != 0L),
                circular_runs(table$state[table$cap + seq_len(table$cap)] != 0L))
  } else values <- circular_runs(table$state != 0L)
  c(sprintf("CLUSTERS runs=%d longest=%d", length(values), max(0L, values)), histogram(values))
}
generated_keys <- function(count, length, seed) {
  state <- gmp::as.bigz(seed)
  result <- character(count)
  for (index in seq_len(count)) {
    codes <- integer(length)
    for (letter in seq_len(length)) {
      state <- (48271L * state) %% 2147483647L
      codes[letter] <- 97L + as.integer(state %% 26L)
    }
    result[index] <- intToUtf8(codes)
  }
  result
}
compare <- function(table, capacity, maximum) {
  items <- table_items(table)
  items <- items[order(item_keys(items), method = "radix")]
  rows <- sprintf("COMPARE keys=%d cap=%d", length(items), capacity)
  for (mode in modes) {
    trial <- new_table(mode, capacity)
    for (item in items) put(trial, item$key, item$value, "PUT", maximum)
    values <- metrics(trial)
    rows <- c(rows, sprintf("%s cap=%d longest=%d avg=%s probes=%d rehashes=%d", mode, trial$cap,
                            values$longest, values$average, trial$counters["probes"], trial$counters["rehashes"]))
  }
  rows
}
bench <- function(capacity, count, length, seed, maximum) {
  keys <- generated_keys(2L * count, length, seed)
  rows <- sprintf("BENCH cap=%d count=%d len=%d seed=%d", capacity, count, length, seed)
  for (mode in modes) {
    trial <- new_table(mode, capacity)
    for (index in seq_len(count)) put(trial, keys[index], index, "PUT", maximum)
    misses <- probes <- 0L
    for (key in keys[count + seq_len(count)]) {
      found <- search(trial, key)
      if (!found$found) {
        misses <- misses + 1L
        probes <- probes + found$probes
      }
    }
    rows <- c(rows, sprintf("%s cap=%d keys=%d hit=%s misses=%d miss=%s rehashes=%d", mode, trial$cap,
                            trial$size, metrics(trial)$average, misses, decimal(probes, misses), trial$counters["rehashes"]))
  }
  rows
}
check_capacity <- function(capacity) {
  if (capacity < 2L || capacity > 10000L) fail("BAD CAPACITY")
  capacity
}
check_mode <- function(mode) {
  if (!mode %in% modes) fail(paste("BAD MODE", mode))
  mode
}
check_generation <- function(args) {
  if (any(args < 1L | args > c(500L, 10L, 2147483646L))) fail("BAD ARGUMENT")
  args
}
execute <- function(simulator, line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1L]]
  command <- words[1L]
  if (!command %in% commands) fail(paste("UNKNOWN COMMAND", command))
  if (command == "CREATE") {
    mode <- check_mode(words[2L])
    capacity <- next_prime(check_capacity(as.integer(words[3L])))
    simulator$current <- new_table(mode, capacity)
    return(sprintf("CREATE %s cap=%d", mode, capacity))
  }
  if (command == "MAXLOAD" || command == "MINLOAD") {
    value <- as.integer(words[2L])
    limits <- if (command == "MAXLOAD") c(10L, 95L) else c(0L, 40L)
    if (value < limits[1L] || value > limits[2L]) fail("BAD LOAD")
    if (command == "MAXLOAD") simulator$max_load <- value else simulator$min_load <- value
    return(line)
  }
  if (command == "TRACE") {
    if (!words[2L] %in% c("ON", "OFF")) fail("BAD ARGUMENT")
    simulator$tracing <- words[2L] == "ON"
    return(line)
  }
  if (command == "HASH") {
    capacity <- check_capacity(as.integer(words[3L]))
    key <- words[2L]
    return(sprintf("HASH %s m=%d h31=%d h37=%d step=%d", key, capacity, hash(key, 31L, capacity),
                   hash(key, 37L, capacity), 1L + hash(key, 37L, capacity - 1L)))
  }
  if (command == "BENCH") {
    capacity <- next_prime(check_capacity(as.integer(words[2L])))
    args <- check_generation(as.integer(words[3:5]))
    return(bench(capacity, args[1L], args[2L], args[3L], simulator$max_load))
  }
  table <- simulator$current
  if (is.null(table)) fail("NO TABLE")
  switch(command,
    PUT =, ADD = put(table, words[2L], as.integer(words[3L]), command, simulator$max_load, simulator$tracing)$rows,
    GET = get_item(table, words[2L], simulator$tracing),
    DEL = delete_item(table, words[2L], simulator$min_load, simulator$max_load, simulator$tracing)$rows,
    PROBE = {
      found <- search(table, words[2L], TRUE)
      ending <- paste0(if (found$found) "FOUND" else "MISS", " probes=", found$probes)
      paste(c(paste("PROBE", words[2L]), found$path, ending), collapse = " ")
    },
    GEN =, GENDEL = {
      args <- check_generation(as.integer(words[2:4]))
      keys <- generated_keys(args[1L], args[2L], args[3L])
      successes <- 0L
      rows <- character()
      for (index in seq_along(keys)) {
        result <- if (command == "GEN") put(table, keys[index], index, "PUT", simulator$max_load) else
          delete_item(table, keys[index], simulator$min_load, simulator$max_load)
        if (result$changed) successes <- successes + 1L
        rows <- c(rows, result$rehashes)
      }
      summary <- if (command == "GEN") sprintf("GEN %d new=%d updated=%d", args[1L], successes, args[1L] - successes) else
        sprintf("GENDEL %d deleted=%d missing=%d", args[1L], successes, args[1L] - successes)
      c(rows, summary)
    },
    RESIZE =, CONVERT = {
      mode <- table$mode
      capacity <- table$cap
      if (command == "RESIZE") capacity <- next_prime(check_capacity(as.integer(words[2L]))) else mode <- check_mode(words[2L])
      slots <- capacity * if (mode == "CUCKOO") 2L else 1L
      if (table$size * 100L > simulator$max_load * slots) fail("TOO SMALL")
      row <- if (command == "RESIZE") sprintf("RESIZE %d -> %d", table$cap, capacity) else
        sprintf("CONVERT %s -> %s cap=%d", table$mode, mode, capacity)
      if (!rebuild(table, mode, capacity, table_items(table))) fail("REBUILD FAILED")
      row
    },
    CLEAR = {
      row <- paste("CLEAR", table$size)
      adopt(table, new_table(table$mode, table$cap))
      row
    },
    DUMP = dump(table),
    MAP = map_report(table),
    STATS = statistics(table),
    KEYS = paste(c(paste("KEYS", table$size), sort(item_keys(table_items(table)), method = "radix")), collapse = " "),
    TOP = {
      limit <- as.integer(words[2L])
      if (limit < 1L || limit > 100L) fail("BAD ARGUMENT")
      records <- costs(table)
      selected <- head(order(-records$values, records$keys, method = "radix"), limit)
      c(paste("TOP", length(selected)), sprintf("%s cost=%d at=%s", records$keys[selected],
                                                records$values[selected], position_text(table, records$positions[selected])))
    },
    SCAN = {
      cursor <- as.integer(words[2L])
      limit <- as.integer(words[3L])
      if (limit < 1L || limit > 100L) fail("BAD ARGUMENT")
      if (cursor >= slot_count(table)) fail("BAD CURSOR")
      scan_table(table, cursor, limit)
    },
    CLUSTERS = clusters(table),
    DIST = {
      values <- costs(table)$values
      c(sprintf("DIST keys=%d longest=%d", table$size, max(0L, values)), histogram(values))
    },
    COMPARE = compare(table, next_prime(check_capacity(as.integer(words[2L]))), simulator$max_load)
  )
}
main <- function() {
  input <- readLines(file("stdin"), warn = FALSE)
  simulator <- new.env(parent = emptyenv())
  simulator$current <- NULL
  simulator$max_load <- 75L
  simulator$min_load <- 0L
  simulator$tracing <- FALSE
  for (index in seq_len(as.integer(input[1L]))) {
    rows <- tryCatch(execute(simulator, input[index + 1L]),
                     command_error = function(problem) paste("ERROR", conditionMessage(problem)))
    cat(paste(rows, collapse = "\n"), "\n", sep = "")
  }
}
main()
