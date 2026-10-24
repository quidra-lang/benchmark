TOKEN_PATTERN <- "[A-Za-z]+"
WORD_PATTERN <- "^[A-Za-z]{1,30}$"
NUMBER_PATTERN <- "^[0-9]{1,7}$"
PREFIX_TERM_PATTERN <- "^[A-Za-z]{1,30}\\*$"
LEXEME_PATTERN <- "[()]|[^ ()]+"
OPERATORS <- c("AND", "OR", "NOT", "(", ")")
CONJUNCTION_CONTINUATIONS <- c("AND", "NOT", "(", "term", "prefix")
VOWELS <- c("a", "e", "i", "o", "u")
STEP_NAMES <- c("1a", "1b", "1c", "2", "3", "4", "5a", "5b")
STEP_4_SUFFIXES <- c(
  "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
  "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize"
)
KWIC_WIDTH <- 30
MAX_COUNT <- 100
MAX_DOCUMENT_NUMBER <- 999
MAX_LINE_NUMBER <- 999

command_error <- function(message) {
  stop(errorCondition(message, class = "command_error"))
}

last_letter <- function(word) {
  substring(word, nchar(word))
}

drop_last <- function(word) {
  substr(word, 1, nchar(word) - 1)
}

letter_pattern <- function(word) {
  indices <- seq_len(nchar(word))
  word_letters <- substring(word, indices, indices)
  kinds <- character(length(word_letters))
  for (index in indices) {
    letter <- word_letters[index]
    vowel <- letter %in% VOWELS ||
      (letter == "y" && index > 1 && kinds[index - 1] == "C")
    kinds[index] <- if (vowel) "V" else "C"
  }
  paste(kinds, collapse = "")
}

measure <- function(word) {
  sum(gregexpr("VC", letter_pattern(word), fixed = TRUE)[[1]] > 0)
}

has_vowel <- function(word) {
  grepl("V", letter_pattern(word), fixed = TRUE)
}

ends_double <- function(word) {
  size <- nchar(word)
  endsWith(letter_pattern(word), "CC") &&
    substr(word, size, size) == substr(word, size - 1, size - 1)
}

ends_cvc <- function(word) {
  endsWith(letter_pattern(word), "CVC") && !(last_letter(word) %in% c("w", "x", "y"))
}

always <- function(remainder) TRUE

measure_above_zero <- function(remainder) measure(remainder) > 0

measure_above_one <- function(remainder) measure(remainder) > 1

ion_condition <- function(remainder) {
  measure(remainder) > 1 && (endsWith(remainder, "s") || endsWith(remainder, "t"))
}

final_e_condition <- function(remainder) {
  value <- measure(remainder)
  value > 1 || (value == 1 && !ends_cvc(remainder))
}

rule <- function(suffix, replacement, condition) {
  list(suffix = suffix, replacement = replacement, condition = condition)
}

rules_with <- function(condition, replacements) {
  Map(rule, names(replacements), replacements, list(condition))
}

RULE_TABLES <- list(
  "1a" = rules_with(always, c(sses = "ss", ies = "i", ss = "ss", s = "")),
  "1b" = list(
    rule("eed", "ee", measure_above_zero),
    rule("ed", "", has_vowel),
    rule("ing", "", has_vowel)
  ),
  "1c" = list(rule("y", "i", has_vowel)),
  "2" = rules_with(measure_above_zero, c(
    ational = "ate", tional = "tion", enci = "ence", anci = "ance",
    izer = "ize", abli = "able", alli = "al", entli = "ent", eli = "e",
    ousli = "ous", ization = "ize", ation = "ate", ator = "ate",
    alism = "al", iveness = "ive", fulness = "ful", ousness = "ous",
    aliti = "al", iviti = "ive", biliti = "ble"
  )),
  "3" = rules_with(measure_above_zero, c(
    icate = "ic", ative = "", alize = "al", iciti = "ic",
    ical = "ic", ful = "", ness = ""
  )),
  "4" = lapply(STEP_4_SUFFIXES, function(suffix) {
    rule(suffix, "", if (suffix == "ion") ion_condition else measure_above_one)
  }),
  "5a" = list(rule("e", "", final_e_condition))
)

# Apply the rule with the longest matching suffix; return the word and the applied suffix.
apply_rules <- function(word, rules) {
  matching <- Filter(function(candidate) endsWith(word, candidate$suffix), rules)
  if (length(matching) == 0) {
    return(list(word = word, suffix = NA_character_))
  }
  suffix_lengths <- vapply(matching, function(candidate) nchar(candidate$suffix), integer(1))
  selected <- matching[[which.max(suffix_lengths)]]
  remainder <- substr(word, 1, nchar(word) - nchar(selected$suffix))
  if (!selected$condition(remainder)) {
    return(list(word = word, suffix = NA_character_))
  }
  list(word = paste0(remainder, selected$replacement), suffix = selected$suffix)
}

tidy_step_1b <- function(word) {
  if (endsWith(word, "at") || endsWith(word, "bl") || endsWith(word, "iz")) {
    return(paste0(word, "e"))
  }
  if (ends_double(word) && !(last_letter(word) %in% c("l", "s", "z"))) {
    return(drop_last(word))
  }
  if (measure(word) == 1 && ends_cvc(word)) {
    return(paste0(word, "e"))
  }
  word
}

apply_step <- function(name, word) {
  if (name == "5b") {
    if (measure(word) > 1 && ends_double(word) && endsWith(word, "l")) {
      return(drop_last(word))
    }
    return(word)
  }
  outcome <- apply_rules(word, RULE_TABLES[[name]])
  if (name == "1b" && outcome$suffix %in% c("ed", "ing")) {
    return(tidy_step_1b(outcome$word))
  }
  outcome$word
}

stemming_steps <- function(word) {
  changes <- character(0)
  if (nchar(word) > 2) {
    for (name in STEP_NAMES) {
      result <- apply_step(name, word)
      if (result != word) {
        changes[name] <- result
      }
      word <- result
    }
  }
  list(stem = word, changes = changes)
}

stem_cache <- new.env()

porter_stem <- function(word) {
  stem <- stem_cache[[word]]
  if (is.null(stem)) {
    stem <- stemming_steps(word)$stem
    stem_cache[[word]] <- stem
  }
  stem
}

yes_no <- function(flag) if (flag) "YES" else "NO"

word_argument <- function(text) {
  if (!grepl(WORD_PATTERN, text)) {
    command_error(paste("BAD WORD", text))
  }
  tolower(text)
}

number_argument <- function(text, minimum, maximum) {
  if (!grepl(NUMBER_PATTERN, text)) {
    command_error(paste("BAD NUMBER", text))
  }
  value <- as.integer(text)
  if (value < minimum || value > maximum) {
    command_error(paste("BAD NUMBER", text))
  }
  value
}

split_arguments <- function(name, rest) {
  if (name == "SEARCH") {
    return(rest)
  }
  if (name == "APPEND") {
    space <- regexpr(" ", rest, fixed = TRUE)
    if (space < 0) {
      return(rest)
    }
    return(c(substr(rest, 1, space - 1), substring(rest, space + 1)))
  }
  strsplit(rest, " ", fixed = TRUE)[[1]]
}

count_values <- function(values) {
  keys <- sort(unique(values), method = "radix")
  setNames(tabulate(match(values, keys), nbins = length(keys)), keys)
}

count_of <- function(counts, key) {
  if (key %in% names(counts)) counts[[key]] else 0L
}

by_count <- function(counts) {
  if (length(counts) == 0) {
    return(counts)
  }
  counts[order(-counts, names(counts), method = "radix")]
}

closest_distance <- function(positions, others, same_stem) {
  if (same_stem) {
    gaps <- diff(positions)
  } else {
    # The closest pair of different stems is adjacent in the merged order.
    merged <- c(positions, others)
    sources <- rep(c(0, 1), c(length(positions), length(others)))
    ordering <- order(merged)
    merged <- merged[ordering]
    sources <- sources[ordering]
    adjacent <- which(diff(sources) != 0)
    gaps <- merged[adjacent + 1] - merged[adjacent]
  }
  if (length(gaps) == 0) NULL else min(gaps)
}

gcd <- function(first, second) {
  while (second != 0) {
    remainder <- first %% second
    first <- second
    second <- remainder
  }
  first
}

jaccard <- function(common, total) {
  if (total == 0) {
    return(c(0, 1))
  }
  c(common, total) / gcd(common, total)
}

classify <- function(lexeme) {
  if (lexeme %in% OPERATORS) {
    return(list(kind = lexeme, spelling = lexeme))
  }
  if (grepl(WORD_PATTERN, lexeme)) {
    return(list(kind = "term", spelling = tolower(lexeme)))
  }
  if (grepl(PREFIX_TERM_PATTERN, lexeme)) {
    return(list(kind = "prefix", spelling = tolower(drop_last(lexeme))))
  }
  command_error(paste("BAD TERM", lexeme))
}

empty_tokens <- function() {
  data.frame(
    document = integer(0), text = character(0), form = character(0),
    stem = character(0), line = integer(0), position = integer(0),
    start = integer(0)
  )
}

new_document <- function(number) {
  document <- new.env()
  document$number <- number
  document$lines <- character(0)
  document$tokens <- empty_tokens()
  document
}

add_line <- function(document, text) {
  document$lines <- c(document$lines, text)
  matches <- gregexpr(TOKEN_PATTERN, text)
  words <- regmatches(text, matches)[[1]]
  forms <- tolower(words)
  added <- data.frame(
    document = rep(document$number, length(words)),
    text = words,
    form = forms,
    stem = vapply(forms, porter_stem, character(1), USE.NAMES = FALSE),
    line = rep(length(document$lines), length(words)),
    position = nrow(document$tokens) + seq_along(words),
    start = as.integer(matches[[1]])[seq_along(words)]
  )
  document$tokens <- rbind(document$tokens, added)
  added
}

reference <- function(tokens) {
  sprintf("%d:%d:%d", tokens$document, tokens$line, tokens$position)
}

new_query_parser <- function(items, stem_sets) {
  parser <- new.env()
  parser$items <- items
  parser$position <- 1
  parser$stem_sets <- stem_sets
  parser
}

peek_kind <- function(parser) {
  if (parser$position > length(parser$items)) {
    return("")
  }
  parser$items[[parser$position]]$kind
}

take_item <- function(parser) {
  if (parser$position > length(parser$items)) {
    command_error("SYNTAX")
  }
  item <- parser$items[[parser$position]]
  parser$position <- parser$position + 1
  item
}

parse_query <- function(parser) {
  result <- parse_expression(parser)
  if (parser$position <= length(parser$items)) {
    command_error("SYNTAX")
  }
  result
}

parse_expression <- function(parser) {
  result <- parse_conjunction(parser)
  while (peek_kind(parser) == "OR") {
    parser$position <- parser$position + 1
    right <- parse_conjunction(parser)
    result <- list(
      canonical = sprintf("(%s OR %s)", result$canonical, right$canonical),
      documents = union(result$documents, right$documents)
    )
  }
  result
}

parse_conjunction <- function(parser) {
  result <- parse_negation(parser)
  while (peek_kind(parser) %in% CONJUNCTION_CONTINUATIONS) {
    if (peek_kind(parser) == "AND") {
      parser$position <- parser$position + 1
    }
    right <- parse_negation(parser)
    result <- list(
      canonical = sprintf("(%s AND %s)", result$canonical, right$canonical),
      documents = intersect(result$documents, right$documents)
    )
  }
  result
}

parse_negation <- function(parser) {
  if (peek_kind(parser) != "NOT") {
    return(parse_element(parser))
  }
  parser$position <- parser$position + 1
  inner <- parse_negation(parser)
  list(
    canonical = sprintf("(NOT %s)", inner$canonical),
    documents = setdiff(as.integer(names(parser$stem_sets)), inner$documents)
  )
}

parse_element <- function(parser) {
  item <- take_item(parser)
  if (item$kind == "(") {
    result <- parse_expression(parser)
    if (take_item(parser)$kind != ")") {
      command_error("SYNTAX")
    }
    return(result)
  }
  if (item$kind == "term") {
    stem <- porter_stem(item$spelling)
    return(list(canonical = stem, documents = documents_where(parser, \(stems) stem %in% stems)))
  }
  if (item$kind == "prefix") {
    matches <- documents_where(parser, \(stems) any(startsWith(stems, item$spelling)))
    return(list(canonical = paste0(item$spelling, "*"), documents = matches))
  }
  command_error("SYNTAX")
}

documents_where <- function(parser, condition) {
  as.integer(names(Filter(condition, parser$stem_sets)))
}

emit <- function(...) {
  writeLines(paste(c(...), collapse = " "))
}

new_engine <- function(stopwords) {
  engine <- new.env()
  engine$stopwords <- stopwords
  engine$documents <- list()
  engine
}

add_document <- function(engine, number) {
  document <- new_document(number)
  engine$documents[[as.character(number)]] <- document
  document
}

find_document <- function(engine, number) {
  engine$documents[[as.character(number)]]
}

ordered_documents <- function(engine) {
  documents <- engine$documents
  documents[order(as.integer(names(documents)))]
}

is_indexed <- function(engine, tokens) {
  !(tokens$form %in% engine$stopwords)
}

indexed_tokens <- function(engine, document) {
  tokens <- document$tokens
  tokens[is_indexed(engine, tokens), ]
}

term_frequencies <- function(engine, document) {
  count_values(indexed_tokens(engine, document)$stem)
}

stem_set <- function(engine, document) {
  unique(indexed_tokens(engine, document)$stem)
}

all_tokens <- function(engine) {
  token_tables <- lapply(ordered_documents(engine), function(document) document$tokens)
  do.call(rbind, c(list(empty_tokens()), unname(token_tables)))
}

occurrence_table <- function(engine) {
  tokens <- all_tokens(engine)
  tokens[is_indexed(engine, tokens), ]
}

total_frequencies <- function(engine) {
  count_values(occurrence_table(engine)$stem)
}

stem_positions <- function(engine, document, stem) {
  tokens <- indexed_tokens(engine, document)
  tokens$position[tokens$stem == stem]
}

form_count <- function(engine, form) {
  sum(all_tokens(engine)$form == form)
}

phrase_starts <- function(engine, tokens, targets) {
  count <- nrow(tokens) - length(targets) + 1
  if (count < 1) {
    return(integer(0))
  }
  starts <- seq_len(count)
  matched <- rep(TRUE, count)
  indexed <- is_indexed(engine, tokens)
  for (offset in seq_along(targets)) {
    if (targets[offset] != "?") {
      rows <- starts + offset - 1
      matched <- matched & indexed[rows] & tokens$stem[rows] == targets[offset]
    }
  }
  starts[matched]
}

term_argument <- function(engine, text) {
  word <- word_argument(text)
  if (word %in% engine$stopwords) {
    command_error(paste("STOPWORD", word))
  }
  porter_stem(word)
}

document_argument <- function(engine, text) {
  number <- number_argument(text, 1, MAX_DOCUMENT_NUMBER)
  document <- find_document(engine, number)
  if (is.null(document)) {
    command_error(paste("NO DOC", number))
  }
  document
}

stem_words <- function(engine, arguments) {
  words <- vapply(arguments, word_argument, character(1), USE.NAMES = FALSE)
  stems <- vapply(words, porter_stem, character(1), USE.NAMES = FALSE)
  emit("STEM", paste0(words, ":", stems))
}

show_steps <- function(engine, arguments) {
  word <- word_argument(arguments[1])
  changes <- stemming_steps(word)$changes
  if (length(changes) == 0) {
    emit("STEPS", word, "NONE")
  } else {
    emit("STEPS", word, paste0(names(changes), ":", changes))
  }
}

show_measure <- function(engine, arguments) {
  word <- word_argument(arguments[1])
  emit(
    "MEASURE", word, letter_pattern(word), paste0("m=", measure(word)),
    paste0("vowel=", yes_no(has_vowel(word))),
    paste0("double=", yes_no(ends_double(word))),
    paste0("cvc=", yes_no(ends_cvc(word)))
  )
}

show_index <- function(engine, arguments) {
  prefix <- if (length(arguments) == 0) "" else word_argument(arguments[1])
  occurrences <- occurrence_table(engine)
  stems <- sort(unique(occurrences$stem), method = "radix")
  stems <- stems[startsWith(stems, prefix)]
  emit("INDEX", paste0("stems=", length(stems)))
  for (stem in stems) {
    found <- occurrences[occurrences$stem == stem, ]
    emit(stem, paste0("df=", length(unique(found$document))), reference(found))
  }
}

search_documents <- function(engine, arguments) {
  query <- arguments[1]
  lexemes <- regmatches(query, gregexpr(LEXEME_PATTERN, query))[[1]]
  items <- lapply(lexemes, classify)
  stem_sets <- lapply(ordered_documents(engine), \(document) stem_set(engine, document))
  result <- parse_query(new_query_parser(items, stem_sets))
  for (item in items) {
    if (item$kind == "term" && item$spelling %in% engine$stopwords) {
      command_error(paste("STOPWORD", item$spelling))
    }
  }
  documents <- sort(result$documents)
  emit("SEARCH", result$canonical, paste0("count=", length(documents)), documents)
}

phrase <- function(engine, arguments) {
  words <- vapply(arguments, word_argument, character(1), USE.NAMES = FALSE)
  if (all(words %in% engine$stopwords)) {
    command_error("STOPWORDS ONLY")
  }
  targets <- vapply(
    words, \(word) if (word %in% engine$stopwords) "?" else porter_stem(word),
    character(1),
    USE.NAMES = FALSE
  )
  matches <- character(0)
  for (document in ordered_documents(engine)) {
    tokens <- document$tokens
    matches <- c(matches, reference(tokens[phrase_starts(engine, tokens, targets), ]))
  }
  emit(
    sprintf("PHRASE \"%s\"", paste(targets, collapse = " ")),
    paste0("matches=", length(matches)), matches
  )
}

near <- function(engine, arguments) {
  first <- term_argument(engine, arguments[1])
  second <- term_argument(engine, arguments[2])
  limit <- number_argument(arguments[3], 1, MAX_COUNT)
  found <- character(0)
  for (document in ordered_documents(engine)) {
    distance <- closest_distance(
      stem_positions(engine, document, first),
      stem_positions(engine, document, second),
      first == second
    )
    if (!is.null(distance) && distance <= limit) {
      found <- c(found, sprintf("%d:%d", document$number, distance))
    }
  }
  emit("NEAR", first, second, limit, paste0("count=", length(found)), found)
}

top <- function(engine, arguments) {
  limit <- number_argument(arguments[1], 1, MAX_COUNT)
  if (length(arguments) == 2) {
    document <- document_argument(engine, arguments[2])
    counts <- term_frequencies(engine, document)
    header <- c("TOP", limit, paste0("doc=", document$number))
  } else {
    counts <- total_frequencies(engine)
    header <- c("TOP", limit)
  }
  ranked <- head(by_count(counts), limit)
  emit(header, sprintf("%s:%d", names(ranked), ranked))
}

kwic <- function(engine, arguments) {
  stem <- term_argument(engine, arguments[1])
  occurrences <- occurrence_table(engine)
  found <- occurrences[occurrences$stem == stem, ]
  emit("KWIC", stem, paste0("count=", nrow(found)))
  for (row in seq_len(nrow(found))) {
    occurrence <- found[row, ]
    text <- find_document(engine, occurrence$document)$lines[occurrence$line]
    after_start <- occurrence$start + nchar(occurrence$text)
    before <- substr(text, max(1, occurrence$start - KWIC_WIDTH), occurrence$start - 1)
    after <- substr(text, after_start, after_start + KWIC_WIDTH - 1)
    context <- paste0(
      "|", formatC(before, width = KWIC_WIDTH), "[", occurrence$text, "]",
      formatC(after, width = KWIC_WIDTH, flag = "-"), "|"
    )
    emit(context, reference(occurrence))
  }
}

term_frequency <- function(engine, arguments) {
  document <- document_argument(engine, arguments[1])
  stem <- term_argument(engine, arguments[2])
  emit("TF", document$number, stem, count_of(term_frequencies(engine, document), stem))
}

document_frequency <- function(engine, arguments) {
  stem <- term_argument(engine, arguments[1])
  occurrences <- occurrence_table(engine)
  emit("DF", stem, length(unique(occurrences$document[occurrences$stem == stem])))
}

variants <- function(engine, arguments) {
  stem <- term_argument(engine, arguments[1])
  occurrences <- occurrence_table(engine)
  forms <- count_values(occurrences$form[occurrences$stem == stem])
  emit("VARIANTS", stem, paste0("count=", length(forms)), sprintf("%s:%d", names(forms), forms))
}

similar <- function(engine, arguments) {
  document <- document_argument(engine, arguments[1])
  limit <- number_argument(arguments[2], 1, MAX_COUNT)
  stems <- stem_set(engine, document)
  others <- Filter(\(other) other$number != document$number, ordered_documents(engine))
  numbers <- vapply(others, \(other) other$number, integer(1))
  scores <- vapply(others, function(other) {
    other_stems <- stem_set(engine, other)
    jaccard(length(intersect(stems, other_stems)), length(union(stems, other_stems)))
  }, numeric(2))
  shown <- head(order(-scores[1, ] / scores[2, ], numbers), limit)
  emit(
    "SIMILAR", document$number,
    sprintf("%d:%d/%d", numbers[shown], scores[1, shown], scores[2, shown])
  )
}

rank_documents <- function(engine, arguments) {
  limit <- number_argument(arguments[1], 1, MAX_COUNT)
  query <- unique(vapply(arguments[-1], \(argument) term_argument(engine, argument), character(1)))
  documents <- ordered_documents(engine)
  counts <- lapply(documents, \(document) term_frequencies(engine, document))
  ranked <- data.frame(
    number = vapply(documents, \(document) document$number, integer(1)),
    matched = vapply(counts, \(count) sum(query %in% names(count)), integer(1)),
    total = vapply(counts, \(count) sum(count[intersect(query, names(count))]), integer(1))
  )
  ranked <- ranked[ranked$matched > 0, ]
  ranked <- ranked[order(-ranked$matched, -ranked$total, ranked$number), ]
  shown <- head(ranked, limit)
  emit(
    paste0("RANK count=", nrow(ranked)),
    sprintf("%d:%d:%d", shown$number, shown$matched, shown$total)
  )
}

info <- function(engine, arguments) {
  document <- document_argument(engine, arguments[1])
  counts <- by_count(term_frequencies(engine, document))
  top_stem <- if (length(counts) == 0) "-" else sprintf("%s:%d", names(counts)[1], counts[[1]])
  emit(
    "INFO", document$number, paste0("lines=", length(document$lines)),
    paste0("tokens=", nrow(document$tokens)), paste0("indexed=", sum(counts)),
    paste0("stems=", length(counts)), paste0("top=", top_stem)
  )
}

show_line <- function(engine, arguments) {
  document <- document_argument(engine, arguments[1])
  line_number <- number_argument(arguments[2], 1, MAX_LINE_NUMBER)
  if (line_number > length(document$lines)) {
    command_error(sprintf("NO LINE %d:%d", document$number, line_number))
  }
  tokens <- document$tokens[document$tokens$line == line_number, ]
  stems <- ifelse(is_indexed(engine, tokens), tokens$stem, "-")
  emit(
    sprintf("LINE %d:%d", document$number, line_number),
    paste0("tokens=", nrow(tokens)), sprintf("%s/%s", tokens$form, stems)
  )
}

show_stats <- function(engine, arguments) {
  tokens <- all_tokens(engine)
  line_counts <- vapply(engine$documents, \(document) length(document$lines), integer(1))
  emit(
    "STATS", paste0("docs=", length(engine$documents)),
    paste0("lines=", sum(line_counts)), paste0("tokens=", nrow(tokens)),
    paste0("indexed=", sum(is_indexed(engine, tokens))),
    paste0("stems=", length(total_frequencies(engine))),
    paste0("stopwords=", length(engine$stopwords))
  )
}

stop_word <- function(engine, arguments) {
  word <- word_argument(arguments[1])
  if (word %in% engine$stopwords) {
    command_error(paste("ALREADY STOPWORD", word))
  }
  engine$stopwords <- c(engine$stopwords, word)
  emit("STOP", word, paste0("unindexed=", form_count(engine, word)))
}

unstop_word <- function(engine, arguments) {
  word <- word_argument(arguments[1])
  if (!(word %in% engine$stopwords)) {
    command_error(paste("NOT STOPWORD", word))
  }
  engine$stopwords <- setdiff(engine$stopwords, word)
  emit("UNSTOP", word, paste0("indexed=", form_count(engine, word)))
}

append_text <- function(engine, arguments) {
  number <- number_argument(arguments[1], 1, MAX_DOCUMENT_NUMBER)
  document <- find_document(engine, number)
  created <- is.null(document)
  if (created) {
    document <- add_document(engine, number)
  }
  tokens <- add_line(document, arguments[2])
  emit(
    "APPEND", number, paste0("line=", length(document$lines)),
    paste0("tokens=", nrow(tokens)),
    paste0("indexed=", sum(is_indexed(engine, tokens))),
    paste0("new=", yes_no(created))
  )
}

delete_document <- function(engine, arguments) {
  document <- document_argument(engine, arguments[1])
  engine$documents[[as.character(document$number)]] <- NULL
  emit(
    "DELETE", document$number, paste0("lines=", length(document$lines)),
    paste0("tokens=", nrow(document$tokens))
  )
}

COMMANDS <- list(
  STEM = list(minimum = 1, maximum = 10, handler = stem_words),
  STEPS = list(minimum = 1, maximum = 1, handler = show_steps),
  MEASURE = list(minimum = 1, maximum = 1, handler = show_measure),
  INDEX = list(minimum = 0, maximum = 1, handler = show_index),
  SEARCH = list(minimum = 1, maximum = 1, handler = search_documents),
  PHRASE = list(minimum = 2, maximum = 10, handler = phrase),
  NEAR = list(minimum = 3, maximum = 3, handler = near),
  TOP = list(minimum = 1, maximum = 2, handler = top),
  KWIC = list(minimum = 1, maximum = 1, handler = kwic),
  TF = list(minimum = 2, maximum = 2, handler = term_frequency),
  DF = list(minimum = 1, maximum = 1, handler = document_frequency),
  VARIANTS = list(minimum = 1, maximum = 1, handler = variants),
  SIMILAR = list(minimum = 2, maximum = 2, handler = similar),
  RANK = list(minimum = 2, maximum = 11, handler = rank_documents),
  INFO = list(minimum = 1, maximum = 1, handler = info),
  LINE = list(minimum = 2, maximum = 2, handler = show_line),
  STATS = list(minimum = 0, maximum = 0, handler = show_stats),
  STOP = list(minimum = 1, maximum = 1, handler = stop_word),
  UNSTOP = list(minimum = 1, maximum = 1, handler = unstop_word),
  APPEND = list(minimum = 2, maximum = 2, handler = append_text),
  DELETE = list(minimum = 1, maximum = 1, handler = delete_document)
)

execute <- function(engine, line) {
  space <- regexpr(" ", line, fixed = TRUE)
  name <- if (space > 0) substr(line, 1, space - 1) else line
  tryCatch(
    {
      command <- COMMANDS[[name]]
      if (is.null(command)) {
        command_error(paste("UNKNOWN COMMAND", name))
      }
      arguments <- character(0)
      if (space > 0) {
        arguments <- split_arguments(name, substring(line, space + 1))
      }
      if (length(arguments) < command$minimum || length(arguments) > command$maximum) {
        command_error(paste("BAD ARGUMENTS", name))
      }
      command$handler(engine, arguments)
    },
    command_error = function(error) emit("ERROR", conditionMessage(error))
  )
}

main <- function() {
  lines <- readLines(file("stdin"), warn = FALSE)
  engine <- new_engine(strsplit(lines[1], " ", fixed = TRUE)[[1]][-1])
  index <- 2
  while (startsWith(lines[index], "DOC ")) {
    document <- add_document(engine, as.integer(substring(lines[index], 5)))
    index <- index + 1
    while (lines[index] != "ENDDOC") {
      add_line(document, lines[index])
      index <- index + 1
    }
    index <- index + 1
  }
  for (line in lines[index:length(lines)]) {
    if (line == "END") {
      break
    }
    execute(engine, line)
  }
}

main()
