script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("scoring", "substitution", "transposition", "playfair", "analysis")) {
  source(file.path(source_dir, paste0(unit, ".R")))
}

COMMANDS <- c("ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY")
NAMING_COMMANDS <- c("ENCRYPT", "DECRYPT", "BREAK")
CIPHERS <- c("caesar", "affine", "vigenere", "autokey", "playfair", "railfence", "columnar")
SUBSTITUTION_CIPHERS <- c("caesar", "affine", "vigenere", "autokey")
TOP_OPTION <- c(1L, 20L, 5L)
BREAK_OPTIONS <- list(
  caesar = list(TOP = TOP_OPTION),
  affine = list(TOP = TOP_OPTION),
  vigenere = list(TOP = TOP_OPTION, MAXLEN = c(2L, 20L, 10L),
                  IOC = c(1L, 100000L, 6000L), KASISKI = c(1L, 100L, 60L),
                  REFINE = c(0L, 10L, 5L)),
  autokey = list(TOP = TOP_OPTION, MAXLEN = c(1L, 20L, 8L)),
  railfence = list(TOP = TOP_OPTION, MAXRAILS = c(2L, 20L, 10L)),
  columnar = list(TOP = TOP_OPTION, MAXLEN = c(2L, 6L, 6L)),
  playfair = list(TOP = TOP_OPTION, KEYS = NULL)
)

job_error <- function(reason) {
  stop(structure(list(message = reason, call = NULL),
                 class = c("job_error", "error", "condition")))
}

valid_name <- function(text) {
  grepl("^[a-z0-9_]{1,16}$", text)
}

digit_string <- function(text, max_length) {
  nchar(text) >= 1L && nchar(text) <= max_length && grepl("^[0-9]+$", text)
}

parse_key <- function(cipher, word) {
  if (cipher %in% c("caesar", "railfence")) {
    minimum <- if (cipher == "caesar") 0L else 2L
    maximum <- if (cipher == "caesar") 25L else 20L
    if (digit_string(word, 2L)) {
      value <- as.integer(word)
      if (value >= minimum && value <= maximum) return(value)
    }
  } else if (cipher == "affine") {
    if (grepl("^[0-9]{1,2},[0-9]{1,2}$", word)) {
      values <- as.integer(strsplit(word, ",", fixed = TRUE)[[1L]])
      if (values[1L] %in% AFFINE_MULTIPLIERS && values[2L] <= 25L) return(values)
    }
  } else if (cipher == "columnar") {
    if (grepl("^[A-Za-z0-9]{2,9}$", word)) return(toupper(word))
  } else {
    maximum <- if (cipher == "playfair") 25L else 20L
    if (nchar(word) >= 1L && nchar(word) <= maximum && grepl("^[A-Za-z]+$", word)) {
      key <- toupper(word)
      return(if (cipher == "playfair") chartr("J", "I", key) else key)
    }
  }
  job_error(paste("bad key", word))
}

parse_options <- function(words, allowed) {
  options <- lapply(allowed, function(limits) if (is.null(limits)) NULL else limits[3L])
  seen <- character()
  for (word in words) {
    separator <- regexpr("=", word, fixed = TRUE)[1L]
    if (separator < 1L) job_error(paste("bad option", word))
    name <- substr(word, 1L, separator - 1L)
    value <- substring(word, separator + 1L)
    if (!name %in% names(allowed) || name %in% seen) job_error(paste("bad option", word))
    if (name == "KEYS") {
      if (!valid_name(value)) job_error(paste("bad option", word))
      options[[name]] <- value
    } else {
      limits <- allowed[[name]]
      if (!digit_string(value, 6L)) job_error(paste("bad option", word))
      number <- as.integer(value)
      if (number < limits[1L] || number > limits[2L]) job_error(paste("bad option", word))
      options[[name]] <- number
    }
    seen <- c(seen, name)
  }
  options
}

parse_job <- function(words) {
  command <- words[1L]
  if (!command %in% COMMANDS) job_error("unknown command")
  new_name <- NULL
  count <- length(words)
  if (command %in% NAMING_COMMANDS && count >= 5L && words[count - 1L] == "AS") {
    new_name <- words[count]
    if (!valid_name(new_name)) job_error("bad syntax")
    words <- head(words, -2L)
  }
  count <- length(words)
  valid <- switch(command,
    ENCRYPT = count == 4L,
    DECRYPT = count == 4L,
    BREAK = count >= 3L,
    ANALYZE = count %in% c(2L, 3L),
    IDENTIFY = count %in% c(2L, 3L),
    COMPARE = count == 3L
  )
  if (!valid) job_error("bad syntax")
  job <- list(command = command, new_name = new_name, options = list())
  if (command %in% NAMING_COMMANDS) {
    job$cipher <- words[2L]
    if (!job$cipher %in% CIPHERS) job_error(paste("unknown cipher", job$cipher))
  }
  if (command %in% c("ENCRYPT", "DECRYPT")) {
    job$key <- parse_key(job$cipher, words[3L])
    job$source <- words[4L]
  } else if (command == "BREAK") {
    job$source <- words[3L]
    job$options <- parse_options(tail(words, -3L), BREAK_OPTIONS[[job$cipher]])
    if (job$cipher == "playfair" && is.null(job$options$KEYS)) job_error("missing option KEYS")
  } else if (command %in% c("ANALYZE", "IDENTIFY")) {
    job$source <- words[2L]
    allowed <- if (command == "ANALYZE") list(MAXLEN = c(2L, 20L, 10L)) else list(KEYS = NULL)
    job$options <- parse_options(tail(words, -2L), allowed)
  } else {
    job$source <- words[2L]
    job$second <- words[3L]
  }
  job
}

key_notation <- function(cipher, key) {
  if (cipher == "affine") paste(key, collapse = ",") else as.character(key)
}

transform_text <- function(cipher, key, text, decrypt = FALSE) {
  switch(cipher,
    caesar = caesar_transform(text, key, decrypt),
    affine = affine_transform(text, key, decrypt),
    vigenere = vigenere_transform(text, key, decrypt),
    autokey = autokey_transform(text, key, decrypt),
    railfence = rail_fence_transform(text, key, decrypt),
    columnar = columnar_transform(text, key, decrypt),
    playfair = playfair_transform(text, key, decrypt)
  )
}

split_body <- function(text) {
  strsplit(paste0(text, "\n"), "\n", fixed = TRUE)[[1L]]
}

group_form <- function(text) {
  starts <- seq.int(1L, nchar(text), by = 5L)
  groups <- substring(text, starts, starts + 4L)
  starts <- seq.int(1L, length(groups), by = 10L)
  vapply(starts, function(start) {
    paste(groups[seq.int(start, min(start + 9L, length(groups)))], collapse = " ")
  }, character(1L))
}

solution_lines <- function(cipher, key, text, letters) {
  if (cipher %in% SUBSTITUTION_CIPHERS) {
    split_body(transform_text(cipher, key, text, TRUE))
  } else {
    group_form(transform_text(cipher, key, letters, TRUE))
  }
}

as_suffix <- function(new_name) {
  if (is.null(new_name)) "" else paste0(" as=", new_name)
}

number_list <- function(numbers) {
  paste(numbers, collapse = ",")
}

count_list <- function(entries) {
  paste(paste0(names(entries), ":", entries), collapse = " ")
}

playfair_key_list <- function(text) {
  runs <- regmatches(text, gregexpr("[A-Za-z]+", text))[[1L]]
  unique(chartr("J", "I", toupper(runs)))
}

period_profile <- function(text, max_length) {
  repeats <- repeated_trigrams(text)
  gaps <- as.integer(unlist(lapply(repeats, function(entry) entry$gaps), use.names = FALSE))
  periods <- lapply(seq_len(max_length), function(length) {
    indices <- column_indices(text, length)
    list(length = length, indices = indices, average = sum(indices) %/% length,
         kasiski = sum(gaps %% length == 0L))
  })
  list(periods = periods, repeats = repeats, gap_count = length(gaps))
}

profile_lines <- function(profile) {
  lines <- vapply(profile$periods, function(period) {
    paste0("L=", period$length, " ioc=", period$average, " kasiski=", period$kasiski,
           " cols=", number_list(period$indices))
  }, character(1L))
  lines <- c(lines, paste0("kasiski repeats=", length(profile$repeats),
                           " spacings=", profile$gap_count))
  for (entry in profile$repeats) {
    lines <- c(lines, paste0(entry$trigram, " at=", number_list(entry$positions),
                             " gaps=", number_list(entry$gaps), " gcd=", entry$gcd))
  }
  lines
}

vigenere_decision <- function(profile, options) {
  averages <- vapply(profile$periods, function(period) period$average, integer(1L))
  if (profile$gap_count > 0L) {
    matches <- which(vapply(profile$periods, function(period) {
      period$length >= 2L && 100L * period$kasiski >= options$KASISKI * profile$gap_count
    }, logical(1L)))
    if (length(matches)) {
      length <- tail(matches, 1L)
      if (averages[length] >= options$IOC) return(list(length = length, method = "kasiski"))
    }
  }
  matches <- which(averages >= options$IOC)
  if (length(matches)) return(list(length = matches[1L], method = "ioc"))
  list(length = which.max(averages), method = "maxioc")
}

vigenere_shift <- function(column, weights) {
  counts <- letter_counts(column)
  scores <- vapply(0L:25L, function(shift) {
    sum(counts * weights$monograms[(0L:25L - shift) %% 26L + 1L])
  }, integer(1L))
  which.max(scores) - 1L
}

autokey_shift <- function(column, weights) {
  values <- letter_values(column)
  scores <- vapply(0L:25L, function(shift) {
    previous <- shift
    total <- 0L
    for (value in values) {
      previous <- (value - previous) %% 26L
      total <- total + weights$monograms[previous + 1L]
    }
    total
  }, integer(1L))
  which.max(scores) - 1L
}

column_key <- function(cipher, text, length, weights) {
  shift_function <- if (cipher == "vigenere") vigenere_shift else autokey_shift
  shifts <- vapply(period_columns(text, length), shift_function, integer(1L), weights = weights)
  intToUtf8(shifts + 65L)
}

permutation_keys <- function(digits) {
  if (length(digits) == 1L) return(as.character(digits))
  unlist(lapply(seq_along(digits), function(i) {
    paste0(digits[i], permutation_keys(digits[-i]))
  }), use.names = FALSE)
}

candidate_keys <- function(cipher, text, options, key_list, weights) {
  switch(cipher,
    caesar = as.list(0L:25L),
    affine = unlist(lapply(AFFINE_MULTIPLIERS, function(a) {
      lapply(0L:25L, function(b) c(a, b))
    }), recursive = FALSE),
    railfence = as.list(seq.int(2L, options$MAXRAILS)),
    columnar = as.list(unlist(lapply(seq.int(2L, options$MAXLEN), function(width) {
      permutation_keys(seq_len(width))
    }), use.names = FALSE)),
    playfair = as.list(key_list),
    lapply(seq_len(options$MAXLEN), function(length) column_key(cipher, text, length, weights))
  )
}

refine_vigenere <- function(result, text, candidates, options, weights) {
  profile <- period_profile(text, options$MAXLEN)
  decision <- vigenere_decision(profile, options)
  initial <- candidates[[decision$length]]
  key <- strsplit(initial$key, "", fixed = TRUE)[[1L]]
  reference <- initial$score
  passes <- 0L
  changes <- 0L
  for (pass in seq_len(options$REFINE)) {
    passes <- passes + 1L
    changed <- FALSE
    for (j in seq_along(key)) {
      scores <- vapply(LETTERS, function(letter) {
        trial <- key
        trial[j] <- letter
        plain <- vigenere_transform(text, paste(trial, collapse = ""), TRUE)
        bigram_fitness(plain, weights)
      }, integer(1L))
      best <- which.max(scores)
      if (scores[best] > reference) {
        key[j] <- LETTERS[best]
        reference <- scores[best]
        changes <- changes + 1L
        changed <- TRUE
      }
    }
    if (!changed) break
  }
  result$key <- paste(key, collapse = "")
  result$score <- reference
  result$profile <- profile
  result$length <- decision$length
  result$method <- decision$method
  result$passes <- passes
  result$changes <- changes
  result
}

break_cipher <- function(cipher, text, options, key_list, weights) {
  keys <- candidate_keys(cipher, text, options, key_list, weights)
  candidates <- lapply(keys, function(key) {
    plain <- transform_text(cipher, key, text, TRUE)
    score <- if (cipher %in% c("caesar", "affine")) {
      monogram_fitness(plain, weights)
    } else {
      bigram_fitness(plain, weights)
    }
    list(key = key, plaintext = plain, score = score)
  })
  scores <- vapply(candidates, function(candidate) candidate$score, integer(1L))
  ranked <- candidates[order(-scores, seq_along(scores), method = "radix")]
  result <- list(cipher = cipher, candidates = ranked, key = ranked[[1L]]$key,
                 score = ranked[[1L]]$score)
  if (cipher == "vigenere") {
    result <- refine_vigenere(result, text, candidates, options, weights)
  }
  result
}

vigenere_report <- function(number, source, letters, result) {
  c(paste0("JOB ", number, " BREAK vigenere source=", source),
    paste0("letters=", nchar(letters)), profile_lines(result$profile),
    paste0("decision length=", result$length, " method=", result$method),
    paste0("refine passes=", result$passes, " changes=", result$changes, " key=", result$key))
}

playfair_report <- function(number, source, letters, result) {
  pairs <- playfair_pairs(letters)
  square <- build_square(result$key)
  rows <- substring(square, seq.int(1L, 21L, by = 5L), seq.int(5L, 25L, by = 5L))
  c(paste0("JOB ", number, " BREAK playfair source=", source),
    paste0("letters=", nchar(letters)),
    paste0("digraphs pairs=", length(pairs), " distinct=", length(unique(pairs))),
    paste0("top ", count_list(top_counts(pairs))), paste0("square ", paste(rows, collapse = " ")))
}

message_text <- function(desk, name) {
  if (!name %in% names(desk$messages)) job_error(paste("unknown message", name))
  paste(desk$messages[[name]], collapse = "\n")
}

store_message <- function(desk, new_name, lines) {
  if (!is.null(new_name)) desk$messages[[new_name]] <- lines
}

transform_job <- function(desk, number, job, text, letters) {
  if (!nchar(letters)) job_error("no letters")
  decrypt <- job$command == "DECRYPT"
  if (decrypt && job$cipher == "playfair" && !valid_playfair(letters)) job_error("bad playfair text")
  if (job$cipher %in% SUBSTITUTION_CIPHERS) {
    lines <- split_body(transform_text(job$cipher, job$key, text, decrypt))
  } else {
    lines <- group_form(transform_text(job$cipher, job$key, letters, decrypt))
  }
  count <- sum(vapply(lines, function(line) nchar(letter_string(line)), integer(1L)))
  header <- paste0("JOB ", number, " ", job$command, " ", job$cipher,
                   " key=", key_notation(job$cipher, job$key), " source=", job$source,
                   " letters=", count, " lines=", length(lines), as_suffix(job$new_name))
  desk$result_lines <- c(desk$result_lines, header, lines)
  store_message(desk, job$new_name, lines)
}

break_job <- function(desk, number, job, text, letters, key_list) {
  if (nchar(letters) < 40L) job_error("text too short")
  if (job$cipher == "playfair") {
    if (!valid_playfair(letters)) job_error("bad playfair text")
    if (!length(key_list)) job_error("empty key list")
  }
  result <- break_cipher(job$cipher, letters, job$options, key_list, desk$weights)
  lines <- solution_lines(job$cipher, result$key, text, letters)
  header <- paste0("JOB ", number, " BREAK ", job$cipher, " source=", job$source,
                   " key=", key_notation(job$cipher, result$key), " score=", result$score,
                   " lines=", length(lines), as_suffix(job$new_name))
  desk$result_lines <- c(desk$result_lines, header, lines)
  store_message(desk, job$new_name, lines)
  candidates <- result$candidates
  margin <- if (length(candidates) < 2L) 0L else candidates[[1L]]$score - candidates[[2L]]$score
  header <- paste0("JOB ", number, " BREAK ", job$cipher, " source=", job$source,
                   " tried=", length(candidates), " margin=", margin)
  report <- vapply(seq_len(min(job$options$TOP, length(candidates))), function(rank) {
    candidate <- candidates[[rank]]
    paste(rank, key_notation(job$cipher, candidate$key), candidate$score,
          substr(candidate$plaintext, 1L, 40L))
  }, character(1L))
  desk$candidate_lines <- c(desk$candidate_lines, header, report)
  if (job$cipher == "vigenere") {
    desk$analysis_lines <- c(desk$analysis_lines, vigenere_report(number, job$source, letters, result))
  } else if (job$cipher == "playfair") {
    desk$analysis_lines <- c(desk$analysis_lines, playfair_report(number, job$source, letters, result))
  }
}

analyze_job <- function(desk, number, job, letters) {
  count <- nchar(letters)
  if (count < 40L) job_error("text too short")
  codes <- utf8ToInt(letters)
  doubles <- which(head(codes, -1L) == tail(codes, -1L))
  counts <- letter_counts(letters)
  report <- c(paste0("JOB ", number, " ANALYZE source=", job$source),
              paste0("letters=", count),
              paste0("ioc=", index_of_coincidence(letters),
                     " mono=", monogram_fitness(letters, desk$weights),
                     " bigram=", bigram_fitness(letters, desk$weights)),
              paste0("doubles=", length(doubles), " pair_doubles=", sum(doubles %% 2L == 1L),
                     " distinct=", sum(counts > 0L)))
  rows <- vapply(seq_len(26L), function(i) {
    paste(LETTERS[i], counts[i], percentage(counts[i], count))
  }, character(1L))
  starts <- seq_len(count - 1L)
  bigrams <- substring(letters, starts, starts + 1L)
  report <- c(report, rows, paste0("bigrams ", count_list(top_counts(bigrams))),
              profile_lines(period_profile(letters, job$options$MAXLEN)))
  desk$result_lines <- c(desk$result_lines,
                         paste0("JOB ", number, " ANALYZE source=", job$source, " letters=", count))
  desk$analysis_lines <- c(desk$analysis_lines, report)
}

compare_job <- function(desk, number, job, first, second) {
  prefix <- paste("JOB", number, "COMPARE", job$source, job$second)
  if (first == second) {
    line <- paste0(prefix, " equal letters=", nchar(first))
  } else {
    shared <- min(nchar(first), nchar(second))
    mismatches <- which(utf8ToInt(first)[seq_len(shared)] != utf8ToInt(second)[seq_len(shared)])
    earliest <- if (length(mismatches)) mismatches[1L] else shared + 1L
    line <- paste0(prefix, " differ letters=", nchar(first), ",", nchar(second),
                   " first=", earliest, " mismatches=", length(mismatches))
  }
  desk$result_lines <- c(desk$result_lines, line)
}

cipher_family <- function(shape, ioc, mono_average) {
  if (shape) return("playfair")
  if (ioc >= 5500L && mono_average >= 44L) return("transposition")
  if (ioc >= 5500L) return("monoalphabetic")
  "polyalphabetic"
}

identify_job <- function(desk, number, job, text, letters, key_list) {
  count <- nchar(letters)
  if (count < 40L) job_error("text too short")
  ioc <- index_of_coincidence(letters)
  average <- monogram_fitness(letters, desk$weights) %/% count
  shape <- count %% 2L == 0L && !grepl("J", letters, fixed = TRUE) && valid_playfair(letters)
  family <- cipher_family(shape, ioc, average)
  if (family == "playfair" && !is.null(key_list) && !length(key_list)) job_error("empty key list")
  ciphers <- switch(family,
    playfair = if (is.null(key_list)) character() else "playfair",
    transposition = c("railfence", "columnar"),
    monoalphabetic = "affine",
    polyalphabetic = c("vigenere", "autokey")
  )
  tried <- lapply(ciphers, function(cipher) {
    options <- parse_options(character(), BREAK_OPTIONS[[cipher]])
    break_cipher(cipher, letters, options, key_list, desk$weights)
  })
  report <- c(paste0("JOB ", number, " IDENTIFY source=", job$source),
              paste0("letters=", count, " ioc=", ioc, " mono_avg=", average,
                     " distinct=", sum(letter_counts(letters) > 0L),
                     " shape=", if (shape) "yes" else "no"),
              paste0("family=", family))
  for (result in tried) {
    report <- c(report, paste0("try ", result$cipher,
                               " key=", key_notation(result$cipher, result$key),
                               " score=", result$score))
  }
  header <- paste0("JOB ", number, " IDENTIFY source=", job$source, " family=", family)
  if (!length(tried)) {
    desk$result_lines <- c(desk$result_lines, header)
  } else {
    scores <- vapply(tried, function(result) result$score, integer(1L))
    chosen <- tried[[which.max(scores)]]
    cipher <- chosen$cipher
    key <- chosen$key
    if (cipher == "affine" && key[1L] == 1L) {
      cipher <- "caesar"
      key <- key[2L]
    }
    lines <- solution_lines(cipher, key, text, letters)
    header <- paste0(header, " cipher=", cipher, " key=", key_notation(cipher, key),
                     " score=", chosen$score, " lines=", length(lines))
    desk$result_lines <- c(desk$result_lines, header, lines)
    report <- c(report, paste0("choice ", cipher))
  }
  desk$analysis_lines <- c(desk$analysis_lines, report)
}

execute_job <- function(desk, number, words) {
  job <- parse_job(words)
  text <- message_text(desk, job$source)
  if (job$command == "COMPARE") {
    second <- message_text(desk, job$second)
    compare_job(desk, number, job, letter_string(text), letter_string(second))
    return(invisible(NULL))
  }
  key_list <- if (is.null(job$options$KEYS)) NULL else {
    playfair_key_list(message_text(desk, job$options$KEYS))
  }
  if (!is.null(job$new_name) && job$new_name %in% names(desk$messages)) {
    job_error(paste("duplicate message", job$new_name))
  }
  letters <- letter_string(text)
  switch(job$command,
    ENCRYPT = transform_job(desk, number, job, text, letters),
    DECRYPT = transform_job(desk, number, job, text, letters),
    BREAK = break_job(desk, number, job, text, letters, key_list),
    ANALYZE = analyze_job(desk, number, job, letters),
    IDENTIFY = identify_job(desk, number, job, text, letters, key_list)
  )
}

run_job <- function(desk, line) {
  desk$job_count <- desk$job_count + 1L
  number <- desk$job_count
  words <- strsplit(line, " ", fixed = TRUE)[[1L]]
  command <- words[1L]
  tryCatch({
    execute_job(desk, number, words)
    desk$ok_counts[command] <- desk$ok_counts[command] + 1L
  }, job_error = function(error) {
    desk$result_lines <- c(desk$result_lines, paste("JOB", number, "ERROR", conditionMessage(error)))
    if (command %in% COMMANDS) desk$error_counts[command] <- desk$error_counts[command] + 1L
  })
  invisible(NULL)
}

parse_messages <- function(lines) {
  messages <- list()
  name <- NULL
  body <- character()
  for (line in lines) {
    if (is.null(name)) {
      if (startsWith(line, "MESSAGE ")) {
        name <- substring(line, 9L)
        body <- character()
      }
    } else if (line == "END") {
      messages[[name]] <- body
      name <- NULL
    } else {
      body <- c(body, line)
    }
  }
  messages
}

main <- function() {
  desk <- new.env(parent = emptyenv())
  desk$weights <- parse_weights(readLines("input/weights.txt", warn = FALSE))
  desk$messages <- parse_messages(readLines("input/messages.txt", warn = FALSE))
  desk$job_count <- 0L
  desk$ok_counts <- setNames(integer(length(COMMANDS)), COMMANDS)
  desk$error_counts <- setNames(integer(length(COMMANDS)), COMMANDS)
  desk$result_lines <- character()
  desk$candidate_lines <- character()
  desk$analysis_lines <- character()
  jobs <- readLines("input/jobs.txt", warn = FALSE)
  for (line in jobs[nzchar(jobs) & !startsWith(jobs, "#")]) run_job(desk, line)
  totals <- vapply(COMMANDS, function(command) {
    paste0("TOTAL ", command, " ok=", desk$ok_counts[command], " errors=", desk$error_counts[command])
  }, character(1L))
  ok <- sum(desk$ok_counts)
  summary <- paste0("SUMMARY jobs=", desk$job_count, " ok=", ok,
                    " errors=", desk$job_count - ok, " messages=", length(desk$messages))
  desk$result_lines <- c(desk$result_lines, totals, summary)
  dir.create("output", showWarnings = FALSE)
  writeLines(desk$result_lines, "output/results.txt", useBytes = TRUE)
  writeLines(desk$candidate_lines, "output/candidates.txt", useBytes = TRUE)
  writeLines(desk$analysis_lines, "output/analysis.txt", useBytes = TRUE)
}

main()
