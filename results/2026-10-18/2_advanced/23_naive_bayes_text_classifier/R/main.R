source("tokenizer.R")
source("vocabulary.R")
source("naive_bayes.R")
source("rocchio.R")
source("evaluation.R")

model_names <- c("multinomial", "bernoulli", "complement", "rocchio", "vote")
model_pairs <- list(c(1L, 2L), c(1L, 3L), c(1L, 4L), c(2L, 3L), c(2L, 4L), c(3L, 4L))
read_lines <- function(name) readLines(file.path("input", name), warn = FALSE)
write_lines <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
join_parts <- function(parts) {
  lines <- character()
  for (part in parts) {
    if (length(lines) > 0L) lines <- c(lines, "")
    lines <- c(lines, part)
  }
  lines
}
hundredths <- function(text) {
  parts <- strsplit(text, ".", fixed = TRUE)[[1L]]
  as.integer(parts[1L]) * 100L + as.integer(parts[2L])
}
hundredths_text <- function(value) sprintf("%d.%02d", as.integer(value %/% 100), as.integer(value %% 100))
class_counts_text <- function(names, counts) paste(paste(names, counts), collapse = " ")
bucket_of <- function(value, boundaries) 1L + sum(value >= boundaries)
rounded4 <- function(value) round(value * 10000)
evaluation_fields <- function(value) paste(value$correct, real_text(value$micro), real_text(value$macro), sep = ",")
rank_ratios <- function(entries) {
  comes_first <- function(a, b) {
    left <- a$p * b$q
    right <- b$p * a$q
    if (left != right) left > right else a$term < b$term
  }
  sort_part <- function(ids) {
    if (length(ids) < 2L) return(ids)
    midpoint <- length(ids) %/% 2L
    left <- sort_part(ids[seq_len(midpoint)])
    right <- sort_part(ids[seq.int(midpoint + 1L, length(ids))])
    output <- integer()
    i <- j <- 1L
    while (i <= length(left) && j <= length(right)) {
      if (comes_first(entries[[left[i]]], entries[[right[j]]])) {
        output <- c(output, left[i])
        i <- i + 1L
      } else {
        output <- c(output, right[j])
        j <- j + 1L
      }
    }
    if (i <= length(left)) output <- c(output, left[seq.int(i, length(left))])
    if (j <= length(right)) output <- c(output, right[seq.int(j, length(right))])
    output
  }
  entries[sort_part(seq_along(entries))]
}
load_settings <- function() {
  rows <- strsplit(read_lines("params.txt"), " ", fixed = TRUE)
  values <- setNames(lapply(rows, function(row) row[-1L]), vapply(rows, function(row) row[1L], character(1)))
  value <- function(key) as.integer(values[[key]])
  list(alphas = vapply(values$ALPHAS, hundredths, integer(1)), min_df = value("MIN_DF"), features = value("FEATURES"),
    bigrams = values$BIGRAMS[1L] == "yes", top = value("TOP"), curve = value("CURVE"), sizes = value("SIZES"),
    thresholds = vapply(values$THRESHOLDS, hundredths, integer(1)), lengths = value("LENGTHS"), iterations = value("EM_ITERATIONS"),
    weight = hundredths(values$EM_WEIGHT[1L]), resamples = value("BOOTSTRAP")[1L], seed = as.numeric(values$BOOTSTRAP[2L]))
}
load_experiment <- function() {
  e <- new.env(parent = emptyenv())
  e$settings <- load_settings()
  stopwords <- read_lines("stopwords.txt")
  rows <- strsplit(read_lines("train.txt"), "\t", fixed = TRUE)
  e$classes <- sort(unique(vapply(rows, function(row) row[1L], character(1))), method = "radix")
  e$training <- lapply(seq_along(rows), function(i) list(name = as.character(i), label = match(rows[[i]][1L], e$classes), tokens = tokenize(rows[[i]][2L], stopwords)))
  e$tests <- lapply(strsplit(read_lines("test.txt"), "\t", fixed = TRUE), function(row) {
    list(name = row[1L], label = if (row[2L] == "?") NA_integer_ else match(row[2L], e$classes), tokens = tokenize(row[3L], stopwords))
  })
  texts <- read_lines("unlabelled.txt")
  e$unlabelled <- lapply(seq_along(texts), function(i) list(name = as.character(i), label = NA_integer_, tokens = tokenize(texts[i], stopwords)))
  e$labelled <- which(!vapply(e$tests, function(document) is.na(document$label), logical(1)))
  e$truths <- vapply(e$tests[e$labelled], function(document) document$label, integer(1))
  e
}
make_training <- function(documents, bigrams, class_count, min_df, size) {
  sequences <- lapply(documents, function(document) term_sequence(document$tokens, bigrams))
  labels <- vapply(documents, function(document) document$label, integer(1))
  vocabulary <- build_vocabulary(sequences, labels, class_count, min_df, size)
  encoded <- lapply(sequences, function(sequence) encode(vocabulary, sequence))
  list(bigrams = bigrams, vocabulary = vocabulary, counts = count_training(encoded, labels, class_count, length(vocabulary$terms)),
    rocchio = train_rocchio(encoded, labels, class_count, vocabulary$frequencies), models = list())
}
train_all <- function(training, alphas) {
  training$models <- lapply(seq_len(3L), function(kind) train_model(kind, training$counts, alphas[kind]))
  training
}
encode_document <- function(training, document) encode(training$vocabulary, term_sequence(document$tokens, training$bigrams))
classify <- function(training, model, sequence) {
  if (model == 4L) rocchio_predict(training$rocchio, sequence) else nb_predict(training$models[[model]], sequence)
}
trained <- function(e, documents, bigrams, size) train_all(make_training(documents, bigrams, length(e$classes), e$settings$min_df, size), e$selected)
alpha_text <- function(e, model) if (model <= 3L) hundredths_text(e$selected[model]) else "-"
cv_run <- function(e, predicted) {
  truths <- vapply(e$training, function(document) document$label, integer(1))
  fold_correct <- integer(5L)
  for (i in seq_along(predicted)) if (truths[i] == predicted[i]) {
    fold <- (i - 1L) %% 5L + 1L
    fold_correct[fold] <- fold_correct[fold] + 1L
  }
  list(predictions = predicted, evaluation = evaluate(length(e$classes), truths, predicted), fold_correct = fold_correct)
}
cross_validate <- function(e) {
  count <- length(e$training)
  predictions <- lapply(seq_len(4L), function(model) lapply(seq_len(if (model == 4L) 1L else length(e$settings$alphas)), function(i) integer(count)))
  e$folds <- list()
  for (fold in seq_len(5L)) {
    ids <- seq_len(count)
    held_out <- ids[(ids - 1L) %% 5L + 1L == fold]
    members <- e$training[(ids - 1L) %% 5L + 1L != fold]
    training <- make_training(members, e$settings$bigrams, length(e$classes), e$settings$min_df, e$settings$features)
    e$folds[[fold]] <- list(train = length(members), validate = length(held_out), candidates = training$vocabulary$candidate_count, vocabulary = length(training$vocabulary$terms))
    sequences <- lapply(held_out, function(index) encode_document(training, e$training[[index]]))
    for (kind in seq_len(3L)) for (position in seq_along(e$settings$alphas)) {
      model <- train_model(kind, training$counts, e$settings$alphas[position])
      for (i in seq_along(held_out)) predictions[[kind]][[position]][held_out[i]] <- nb_predict(model, sequences[[i]])$label
    }
    for (i in seq_along(held_out)) predictions[[4L]][[1L]][held_out[i]] <- rocchio_predict(training$rocchio, sequences[[i]])$label
  }
  e$cv_runs <- lapply(predictions, function(runs) lapply(runs, function(labels) cv_run(e, labels)))
}
select_alphas <- function(e) {
  e$selected <- integer(3L)
  e$selected_runs <- list()
  for (kind in seq_len(3L)) {
    runs <- e$cv_runs[[kind]]
    best <- 1L
    if (length(runs) > 1L) for (position in seq.int(2L, length(runs))) {
      if (rounded4(runs[[position]]$evaluation$macro) > rounded4(runs[[best]]$evaluation$macro)) best <- position
    }
    e$selected[kind] <- e$settings$alphas[best]
    e$selected_runs[[kind]] <- runs[[best]]
  }
  e$selected_runs[[4L]] <- e$cv_runs[[4L]][[1L]]
}
train_final <- function(e) {
  e$final <- trained(e, e$training, e$settings$bigrams, e$settings$features)
  e$test_sequences <- lapply(e$tests, function(document) encode_document(e$final, document))
  e$predictions <- lapply(seq_len(4L), function(model) lapply(e$test_sequences, function(sequence) classify(e$final, model, sequence)))
  base_predictions <- e$predictions
  e$predictions[[5L]] <- lapply(seq_along(e$tests), function(index) {
    labels <- vapply(base_predictions, function(predictions) predictions[[index]]$label, integer(1))
    votes <- tabulate(labels, nbins = length(e$classes))
    winner <- labels[1L]
    for (label in labels) if (votes[label] > votes[winner]) winner <- label
    list(label = winner, score = votes[winner] / 4)
  })
  e$correct <- lapply(e$predictions, function(predictions) vapply(seq_along(e$labelled), function(position) {
    predictions[[e$labelled[position]]]$label == e$truths[position]
  }, logical(1)))
}
test_evaluations <- function(e, training) {
  sequences <- lapply(e$labelled, function(index) encode_document(training, e$tests[[index]]))
  lapply(seq_len(4L), function(model) evaluate(length(e$classes), e$truths,
    vapply(sequences, function(sequence) classify(training, model, sequence)$label, integer(1))))
}
vocabulary_lines <- function(e) {
  vocabulary <- e$final$vocabulary
  lines <- sprintf("documents %d terms %d candidates %d vocabulary %d", length(e$training), vocabulary$term_count, vocabulary$candidate_count, length(vocabulary$terms))
  for (i in seq_along(vocabulary$ranking)) {
    entry <- vocabulary$ranking[[i]]
    lines <- c(lines, sprintf("%d %s %.0f %s %s", i, entry$term, entry$frequency, real_text(entry$score), e$classes[entry$best_class]))
  }
  lines
}
cv_lines <- function(e) {
  lines <- "model,alpha,correct,accuracy,macro_f1,selected"
  for (kind in seq_len(3L)) for (i in seq_along(e$settings$alphas)) {
    alpha <- e$settings$alphas[i]
    selected <- if (alpha == e$selected[kind]) "yes" else "no"
    lines <- c(lines, paste(model_names[kind], hundredths_text(alpha), evaluation_fields(e$cv_runs[[kind]][[i]]$evaluation), selected, sep = ","))
  }
  c(lines, paste0("rocchio,-,", evaluation_fields(e$cv_runs[[4L]][[1L]]$evaluation), ",yes"))
}
prediction_lines <- function(e) {
  lines <- "id,model,label,score"
  for (index in seq_along(e$tests)) for (model in seq_len(5L)) {
    prediction <- e$predictions[[model]][[index]]
    lines <- c(lines, paste(e$tests[[index]]$name, model_names[model], e$classes[prediction$label], real_text(prediction$score), sep = ","))
  }
  lines
}
curve_lines <- function(e) {
  lines <- "size,vocabulary,model,correct,accuracy,macro_f1"
  for (size in e$settings$curve) {
    training <- trained(e, e$training[seq_len(size)], e$settings$bigrams, e$settings$features)
    evaluations <- test_evaluations(e, training)
    for (model in seq_len(4L)) lines <- c(lines, paste(size, length(training$vocabulary$terms), model_names[model], evaluation_fields(evaluations[[model]]), sep = ","))
  }
  lines
}
feature_lines <- function(e) {
  lines <- "terms,features,vocabulary,model,correct,accuracy,macro_f1"
  for (bigrams in c(FALSE, TRUE)) for (size in e$settings$sizes) {
    kind <- if (bigrams) "bigrams" else "unigrams"
    training <- trained(e, e$training, bigrams, size)
    evaluations <- test_evaluations(e, training)
    for (model in seq_len(4L)) lines <- c(lines, paste(kind, size, length(training$vocabulary$terms), model_names[model], evaluation_fields(evaluations[[model]]), sep = ","))
  }
  lines
}
data_part <- function(e) {
  vocabulary <- e$final$vocabulary
  lines <- sprintf("documents train %d test %d labelled %d unlabelled %d classes %d", length(e$training), length(e$tests), length(e$labelled), length(e$unlabelled), length(e$classes))
  train_counts <- tabulate(vapply(e$training, function(document) document$label, integer(1)), nbins = length(e$classes))
  test_counts <- tabulate(e$truths, nbins = length(e$classes))
  for (label in seq_along(e$classes)) lines <- c(lines, sprintf("class %s train %d test %d", e$classes[label], train_counts[label], test_counts[label]))
  raw <- stops <- short <- kept <- bigrams <- 0L
  terms <- character()
  for (document in e$training) {
    tokens <- document$tokens
    raw <- raw + tokens$raw
    stops <- stops + tokens$stopwords
    short <- short + tokens$short
    kept <- kept + length(tokens$words)
    if (e$settings$bigrams) bigrams <- bigrams + length(tokens$bigrams)
    terms <- union(terms, term_sequence(tokens, e$settings$bigrams))
  }
  distinct_bigrams <- sum(is_bigram(terms))
  lines <- c(lines, sprintf("train_tokens raw %d stopwords %d short %d unigrams %d bigrams %d", raw, stops, short, kept, bigrams),
    sprintf("train_terms unigrams %d bigrams %d candidates %d vocabulary %d", length(terms) - distinct_bigrams, distinct_bigrams, vocabulary$candidate_count, length(vocabulary$terms)))
  total <- sum(vapply(e$tests, function(document) length(term_sequence(document$tokens, e$settings$bigrams)), integer(1)))
  in_vocabulary <- sum(vapply(e$test_sequences, length, integer(1)))
  lines <- c(lines, sprintf("test_terms total %d in_vocabulary %d", total, in_vocabulary))
  words <- unlist(lapply(e$tests, function(document) document$tokens$words), use.names = FALSE)
  words <- words[!(words %in% vocabulary$terms)]
  names <- sort(unique(words), method = "radix")
  counts <- vapply(names, function(word) sum(words == word), integer(1))
  order <- order(-counts, names, method = "radix")
  parts <- "test_oov"
  for (i in head(order, e$settings$top)) parts <- c(parts, paste(names[i], counts[i]))
  c(lines, paste(parts, collapse = " "))
}
folds_part <- function(e) {
  lines <- "folds 5"
  for (fold in seq_len(5L)) {
    summary <- e$folds[[fold]]
    lines <- c(lines, sprintf("fold %d train %d validate %d candidates %d vocabulary %d", fold, summary$train, summary$validate, summary$candidates, summary$vocabulary))
  }
  lines
}
selection_part <- function(e) {
  lines <- "selection"
  for (model in seq_len(4L)) {
    run <- e$selected_runs[[model]]
    value <- run$evaluation
    lines <- c(lines, paste(model_names[model], "alpha", alpha_text(e, model), "correct", proportion_text(value$correct, value$total), "macro_f1", real_text(value$macro), "folds", paste(run$fold_correct, collapse = " ")))
  }
  lines
}
cross_validation_part <- function(e, model) c(paste("cross_validation", model_names[model], "alpha", alpha_text(e, model)), evaluation_lines(e$selected_runs[[model]]$evaluation, e$classes))
test_part <- function(e, model) {
  predictions <- e$predictions[[model]][e$labelled]
  value <- evaluate(length(e$classes), e$truths, vapply(predictions, function(prediction) prediction$label, integer(1)))
  lines <- c(paste("test", model_names[model], "alpha", alpha_text(e, model)), paste("labelled", length(e$labelled), "correct", proportion_text(value$correct, length(e$labelled))))
  if (model <= 4L) {
    top_two <- sum(vapply(seq_along(predictions), function(i) e$truths[i] %in% head(predictions[[i]]$ranking, 2L), logical(1)))
    lines <- c(lines, paste("top2", proportion_text(top_two, length(e$labelled))))
  }
  c(lines, evaluation_lines(value, e$classes))
}
probability_part <- function(e, model) {
  thresholds <- e$settings$thresholds
  limits <- thresholds / 100
  count <- length(e$labelled)
  bin_rows <- bin_correct <- integer(length(limits) + 1L)
  bin_sums <- numeric(length(limits) + 1L)
  accepted <- accepted_correct <- integer(length(limits))
  loss <- brier <- 0
  for (position in seq_along(e$labelled)) {
    prediction <- e$predictions[[model]][[e$labelled[position]]]
    truth <- e$truths[position]
    correct <- e$correct[[model]][position]
    gap <- prediction$scores[truth] - prediction$scores[prediction$label]
    loss <- loss + (log(prediction$normalizer) - gap)
    squares <- 0
    for (label in seq_along(e$classes)) {
      difference <- prediction$probabilities[label] - (if (label == truth) 1 else 0)
      squares <- squares + difference * difference
    }
    brier <- brier + squares
    bucket <- bucket_of(prediction$score, limits)
    bin_rows[bucket] <- bin_rows[bucket] + 1L
    bin_sums[bucket] <- bin_sums[bucket] + prediction$score
    if (correct) bin_correct[bucket] <- bin_correct[bucket] + 1L
    for (threshold in seq_along(limits)) if (prediction$score >= limits[threshold]) {
      accepted[threshold] <- accepted[threshold] + 1L
      if (correct) accepted_correct[threshold] <- accepted_correct[threshold] + 1L
    }
  }
  lines <- c(paste("probability", model_names[model], "alpha", alpha_text(e, model)), paste("log_loss", real_text(loss / count), "brier", real_text(brier / count)))
  bounds <- c(0L, thresholds)
  for (bucket in seq_along(bounds)) {
    rows <- bin_rows[bucket]
    line <- sprintf("bin %s rows %d", hundredths_text(bounds[bucket]), rows)
    if (rows > 0L) line <- paste(line, "correct", proportion_text(bin_correct[bucket], rows), "mean", real_text(bin_sums[bucket] / rows))
    lines <- c(lines, line)
  }
  for (i in seq_along(thresholds)) {
    precise <- if (accepted[i] > 0L) proportion_text(accepted_correct[i], accepted[i]) else "-"
    lines <- c(lines, paste("threshold", hundredths_text(thresholds[i]), "covered", proportion_text(accepted[i], count), "correct", precise))
  }
  lines
}
lengths_part <- function(e) {
  boundaries <- e$settings$lengths
  rows <- integer(length(boundaries) + 1L)
  correct <- matrix(0L, 5L, length(rows))
  for (position in seq_along(e$labelled)) {
    bucket <- bucket_of(length(e$test_sequences[[e$labelled[position]]]), boundaries)
    rows[bucket] <- rows[bucket] + 1L
    for (model in seq_len(5L)) if (e$correct[[model]][position]) correct[model, bucket] <- correct[model, bucket] + 1L
  }
  lines <- "lengths"
  bounds <- c(0L, boundaries)
  for (bucket in seq_along(bounds)) {
    line <- sprintf("length %d rows %d", bounds[bucket], rows[bucket])
    if (rows[bucket] > 0L) for (model in seq_len(5L)) line <- paste(line, model_names[model], proportion_text(correct[model, bucket], rows[bucket]))
    lines <- c(lines, line)
  }
  lines
}
comparison_part <- function(e) {
  lines <- "comparison"
  for (pair in model_pairs) {
    first <- pair[1L]
    second <- pair[2L]
    agree <- sum(vapply(seq_along(e$tests), function(i) e$predictions[[first]][[i]]$label == e$predictions[[second]][[i]]$label, logical(1)))
    b <- sum(e$correct[[first]] & !e$correct[[second]])
    c <- sum(e$correct[[second]] & !e$correct[[first]])
    statistic <- if (b + c > 0L) fraction_text(max(0, abs(b - c) - 1) ^ 2, b + c) else fraction_text(0, 1)
    lines <- c(lines, paste(model_names[first], model_names[second], "agree", proportion_text(agree, length(e$tests)), "b", b, "c", c, "statistic", statistic))
  }
  errors <- integer(5L)
  for (position in seq_along(e$labelled)) {
    wrong <- sum(vapply(e$correct[seq_len(4L)], function(flags) !flags[position], logical(1)))
    errors[wrong + 1L] <- errors[wrong + 1L] + 1L
  }
  c(lines, paste("errors", paste(paste(0:4, errors), collapse = " ")))
}
bootstrap_part <- function(e) {
  count <- length(e$labelled)
  state <- e$settings$seed
  totals <- matrix(0L, e$settings$resamples, 5L)
  for (repetition in seq_len(e$settings$resamples)) {
    for (draw in seq_len(count)) {
      state <- (48271 * state) %% 2147483647
      position <- state %% count + 1L
      for (model in seq_len(5L)) if (e$correct[[model]][position]) totals[repetition, model] <- totals[repetition, model] + 1L
    }
  }
  rank <- e$settings$resamples %/% 40L + 1L
  lines <- sprintf("bootstrap resamples %d seed %.0f", e$settings$resamples, e$settings$seed)
  for (model in seq_len(5L)) {
    ordered <- sort(totals[, model], method = "radix")
    mean <- sum(ordered) / (e$settings$resamples * count)
    lines <- c(lines, paste(model_names[model], "mean", real_text(mean), "low", proportion_text(ordered[rank], count),
      "high", proportion_text(ordered[length(ordered) + 1L - rank], count)))
  }
  for (pair in model_pairs) {
    first <- totals[, pair[1L]]
    second <- totals[, pair[2L]]
    lines <- c(lines, sprintf("pair %s %s wins %d ties %d losses %d", model_names[pair[1L]], model_names[pair[2L]], sum(first > second), sum(first == second), sum(first < second)))
  }
  lines
}
hard_part <- function(e) {
  hard <- integer()
  counts <- integer(length(e$classes))
  for (i in seq_along(e$training)) {
    predictions <- vapply(e$selected_runs, function(run) run$predictions[i], integer(1))
    if (all(predictions != e$training[[i]]$label)) {
      hard <- c(hard, i)
      counts[e$training[[i]]$label] <- counts[e$training[[i]]$label] + 1L
    }
  }
  lines <- paste("hard_documents", length(hard), class_counts_text(e$classes, counts))
  for (index in head(hard, e$settings$top)) {
    predictions <- vapply(e$selected_runs, function(run) e$classes[run$predictions[index]], character(1))
    lines <- c(lines, paste(e$training[[index]]$name, "true", e$classes[e$training[[index]]$label], "predicted", paste(predictions, collapse = " ")))
  }
  lines
}
uncertain_part <- function(e) {
  predictions <- e$predictions[[1L]]
  ordered <- order(vapply(predictions, function(prediction) rounded4(prediction$margin), numeric(1)), seq_along(predictions), method = "radix")
  shown <- head(ordered, e$settings$top)
  lines <- paste("uncertain multinomial", length(shown))
  for (index in shown) {
    document <- e$tests[[index]]
    prediction <- predictions[[index]]
    truth <- if (is.na(document$label)) "?" else e$classes[document$label]
    lines <- c(lines, paste(document$name, "predicted", e$classes[prediction$label], "runner_up", e$classes[prediction$runner_up],
      "margin", real_text(prediction$margin), "posterior", real_text(prediction$score), "true", truth))
  }
  lines
}
evidence_lines <- function(e, sequence, predicted, truth) {
  alpha <- e$selected[1L]
  counts <- e$final$counts$occurrences
  weights <- e$final$models[[1L]]$weights
  entries <- lapply(first_occurrences(sequence), function(term) list(p = 100 * counts[predicted, term] + alpha, q = 100 * counts[truth, term] + alpha, term = term))
  lines <- character()
  for (entry in head(rank_ratios(entries), 3L)) {
    term <- entry$term
    lines <- c(lines, sprintf("  %s count %d evidence %s", e$final$vocabulary$terms[term], sum(sequence == term), real_text(weights[predicted, term] - weights[truth, term])))
  }
  lines
}
misclassified_part <- function(e) {
  wrong <- e$labelled[vapply(e$labelled, function(index) e$predictions[[1L]][[index]]$label != e$tests[[index]]$label, logical(1))]
  lines <- paste("misclassified multinomial", length(wrong))
  for (index in wrong) {
    document <- e$tests[[index]]
    prediction <- e$predictions[[1L]][[index]]
    lines <- c(lines, paste(document$name, "true", e$classes[document$label], "predicted", e$classes[prediction$label], "posterior", real_text(prediction$score)),
      evidence_lines(e, e$test_sequences[[index]], prediction$label, document$label))
  }
  lines
}
maximization <- function(e, posteriors, sequences) {
  counts <- e$final$counts
  occurrences <- counts$occurrences + 0
  documents <- counts$documents + 0
  weight <- e$settings$weight / 100
  for (i in seq_along(sequences)) {
    frequencies <- tabulate(sequences[[i]], nbins = counts$size)
    terms <- first_occurrences(sequences[[i]])
    for (label in seq_along(e$classes)) {
      share <- weight * posteriors[[i]]$probabilities[label]
      documents[label] <- documents[label] + share
      for (term in terms) occurrences[label, term] <- occurrences[label, term] + share * frequencies[term]
    }
  }
  alpha <- e$selected[1L]
  size <- length(e$final$vocabulary$terms)
  weights <- matrix(0, length(e$classes), size)
  for (label in seq_along(e$classes)) {
    total <- 0
    for (term in seq_len(size)) total <- total + occurrences[label, term]
    for (term in seq_len(size)) weights[label, term] <- smoothed_log(occurrences[label, term], total, alpha, size)
  }
  scale <- length(e$training) + (e$settings$weight * length(e$unlabelled)) / 100
  list(kind = 1L, priors = log(documents / scale), base = numeric(length(e$classes)), weights = weights)
}
semi_supervised_part <- function(e) {
  sequences <- lapply(e$unlabelled, function(document) encode_document(e$final, document))
  model <- e$final$models[[1L]]
  lines <- paste("semi_supervised multinomial alpha", alpha_text(e, 1L), "weight", hundredths_text(e$settings$weight), "unlabelled", length(e$unlabelled))
  previous <- NULL
  for (iteration in seq.int(0L, e$settings$iterations)) {
    posteriors <- lapply(sequences, function(sequence) nb_predict(model, sequence))
    assignments <- vapply(posteriors, function(posterior) posterior$label, integer(1))
    predicted <- vapply(e$labelled, function(index) nb_predict(model, e$test_sequences[[index]])$label, integer(1))
    value <- evaluate(length(e$classes), e$truths, predicted)
    changed <- if (is.null(previous)) "-" else as.character(sum(previous != assignments))
    assigned <- tabulate(assignments, nbins = length(e$classes))
    lines <- c(lines, paste("iteration", iteration, "correct", proportion_text(value$correct, value$total), "macro_f1", real_text(value$macro),
      "changed", changed, "assigned", class_counts_text(e$classes, assigned)))
    if (iteration < e$settings$iterations) model <- maximization(e, posteriors, sequences)
    previous <- assignments
  }
  lines
}
metrics_parts <- function(e) {
  parts <- list(data_part(e), folds_part(e), selection_part(e))
  parts <- c(parts, lapply(seq_len(4L), function(model) cross_validation_part(e, model)))
  parts <- c(parts, lapply(seq_len(5L), function(model) test_part(e, model)))
  parts <- c(parts, lapply(seq_len(3L), function(model) probability_part(e, model)))
  c(parts, list(lengths_part(e), comparison_part(e), bootstrap_part(e), hard_part(e), uncertain_part(e), misclassified_part(e), semi_supervised_part(e)))
}
characteristic_parts <- function(e, kind) {
  counts <- e$final$counts
  terms <- e$final$vocabulary$terms
  size <- length(terms)
  alpha <- e$selected[kind]
  table <- if (kind == 1L) counts$occurrences else counts$containing
  totals <- if (kind == 1L) counts$totals else counts$documents
  overall <- if (kind == 1L) counts$total else counts$document_total
  outcomes <- if (kind == 1L) size else 2L
  term_totals <- colSums(table)
  parts <- list(sprintf("model %s alpha %s vocabulary %d top %d", model_names[kind], hundredths_text(alpha), size, e$settings$top))
  for (label in seq_along(e$classes)) {
    total <- totals[label]
    other <- overall - total
    lines <- sprintf("class %s total %.0f other %.0f", e$classes[label], total, other)
    entries <- lapply(seq_len(size), function(term) list(p = 100 * table[label, term] + alpha, q = 100 * (term_totals[term] - table[label, term]) + alpha, term = term))
    ordered <- head(rank_ratios(entries), e$settings$top)
    for (rank in seq_along(ordered)) {
      term <- ordered[[rank]]$term
      count <- table[label, term]
      other_count <- term_totals[term] - count
      odds <- smoothed_log(count, total, alpha, outcomes) - smoothed_log(other_count, other, alpha, outcomes)
      lines <- c(lines, sprintf("%d %s %.0f %.0f %s", rank, terms[term], count, other_count, real_text(odds)))
    }
    parts[[length(parts) + 1L]] <- lines
  }
  parts
}
top_feature_parts <- function(e) c(characteristic_parts(e, 1L), characteristic_parts(e, 2L))

main <- function() {
  experiment <- load_experiment()
  cross_validate(experiment)
  select_alphas(experiment)
  train_final(experiment)
  dir.create("output", showWarnings = FALSE)
  write_lines("vocabulary.txt", vocabulary_lines(experiment))
  write_lines("cv_results.csv", cv_lines(experiment))
  write_lines("predictions.csv", prediction_lines(experiment))
  write_lines("learning_curve.csv", curve_lines(experiment))
  write_lines("feature_study.csv", feature_lines(experiment))
  write_lines("metrics.txt", join_parts(metrics_parts(experiment)))
  write_lines("top_features.txt", join_parts(top_feature_parts(experiment)))
}

main()
