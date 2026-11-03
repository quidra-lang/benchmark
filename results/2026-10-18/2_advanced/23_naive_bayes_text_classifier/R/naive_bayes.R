count_training <- function(sequences, labels, class_count, size) {
  documents <- numeric(class_count)
  occurrences <- containing <- matrix(0, class_count, size)
  for (i in seq_along(sequences)) {
    label <- labels[i]
    documents[label] <- documents[label] + 1
    for (term in sequences[[i]]) occurrences[label, term] <- occurrences[label, term] + 1
    for (term in first_occurrences(sequences[[i]])) containing[label, term] <- containing[label, term] + 1
  }
  totals <- rowSums(occurrences)
  list(class_count = class_count, size = size, document_total = length(sequences), documents = documents,
       occurrences = occurrences, containing = containing, totals = totals, total = sum(totals), term_totals = colSums(occurrences))
}
smoothed_log <- function(count, total, alpha, outcomes) log((100 * count + alpha) / (100 * total + alpha * outcomes))
class_ranking <- function(scores) order(-scores, seq_along(scores), method = "radix")
posterior <- function(scores) {
  ranking <- class_ranking(scores)
  label <- ranking[1L]
  best <- scores[label]
  exponentials <- exp(scores - best)
  normalizer <- 0
  for (value in exponentials) normalizer <- normalizer + value
  probabilities <- exponentials / normalizer
  list(label = label, score = probabilities[label], ranking = ranking, scores = scores, probabilities = probabilities,
       normalizer = normalizer, margin = best - scores[ranking[2L]], runner_up = ranking[2L])
}
nb_predict <- function(model, sequence) {
  terms <- if (model$kind == 2L) first_occurrences(sequence) else sequence
  scores <- numeric(length(model$priors))
  for (label in seq_along(scores)) {
    score <- model$base[label]
    for (term in terms) score <- score + model$weights[label, term]
    scores[label] <- score + model$priors[label]
  }
  posterior(scores)
}
train_model <- function(kind, counts, alpha) {
  priors <- log(counts$documents / counts$document_total)
  base <- numeric(counts$class_count)
  weights <- matrix(0, counts$class_count, counts$size)
  for (label in seq_len(counts$class_count)) for (term in seq_len(counts$size)) {
    if (kind == 1L) {
      weights[label, term] <- smoothed_log(counts$occurrences[label, term], counts$totals[label], alpha, counts$size)
    } else if (kind == 2L) {
      present <- smoothed_log(counts$containing[label, term], counts$documents[label], alpha, 2L)
      absent <- smoothed_log(counts$documents[label] - counts$containing[label, term], counts$documents[label], alpha, 2L)
      base[label] <- base[label] + absent
      weights[label, term] <- present - absent
    } else {
      weights[label, term] <- -smoothed_log(counts$term_totals[term] - counts$occurrences[label, term], counts$total - counts$totals[label], alpha, counts$size)
    }
  }
  list(kind = kind, priors = priors, base = base, weights = weights)
}
