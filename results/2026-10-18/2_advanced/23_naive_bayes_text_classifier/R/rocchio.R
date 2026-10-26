vector_length <- function(values) {
  total <- 0
  for (value in values) total <- total + value * value
  sqrt(total)
}
rocchio_vector <- function(model, sequence) {
  terms <- sort(unique(sequence), method = "radix")
  values <- vapply(terms, function(term) sum(sequence == term) * model$idf[term], numeric(1))
  list(terms = terms, values = values)
}
train_rocchio <- function(sequences, labels, class_count, frequencies) {
  model <- list(idf = log(length(sequences) / frequencies), centroids = matrix(0, class_count, length(frequencies)), lengths = numeric(class_count))
  documents <- integer(class_count)
  for (i in seq_along(sequences)) {
    label <- labels[i]
    documents[label] <- documents[label] + 1L
    vector <- rocchio_vector(model, sequences[[i]])
    length <- vector_length(vector$values)
    if (length > 0) for (position in seq_along(vector$terms)) {
      term <- vector$terms[position]
      model$centroids[label, term] <- model$centroids[label, term] + vector$values[position] / length
    }
  }
  for (label in seq_len(class_count)) {
    total <- 0
    for (term in seq_along(frequencies)) {
      model$centroids[label, term] <- model$centroids[label, term] / documents[label]
      total <- total + model$centroids[label, term] * model$centroids[label, term]
    }
    model$lengths[label] <- sqrt(total)
  }
  model
}
rocchio_predict <- function(model, sequence) {
  vector <- rocchio_vector(model, sequence)
  length <- vector_length(vector$values)
  similarities <- numeric(nrow(model$centroids))
  for (label in seq_along(similarities)) {
    if (length <= 0 || model$lengths[label] <= 0) next
    product <- 0
    for (position in seq_along(vector$terms)) product <- product + vector$values[position] * model$centroids[label, vector$terms[position]]
    similarities[label] <- product / (length * model$lengths[label])
  }
  ranking <- class_ranking(similarities)
  list(label = ranking[1L], score = similarities[ranking[1L]], ranking = ranking)
}
