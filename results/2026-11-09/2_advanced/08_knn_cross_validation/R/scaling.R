real_sum <- function(values) {
  total <- 0
  for (value in values) total <- total + value
  total
}

compute_scaling <- function(rows, method) {
  centers <- scales <- numeric(length(rows[[1L]]$values))
  for (feature in seq_along(centers)) {
    values <- vapply(rows, function(row) row$values[feature], numeric(1L))
    if (method == "standard") {
      center <- real_sum(values) / length(values)
      scale <- if (length(values) == 1L) 0 else sqrt(real_sum((values - center) * (values - center)) / (length(values) - 1L))
    } else {
      center <- min(values)
      scale <- max(values) - center
    }
    centers[feature] <- center
    scales[feature] <- scale
  }
  list(centers = centers, scales = scales)
}

transform_values <- function(scaling, values, features) {
  result <- numeric(length(features))
  for (index in seq_along(features)) {
    feature <- features[index]
    if (scaling$scales[feature] > 0) result[index] <- (values[feature] - scaling$centers[feature]) / scaling$scales[feature]
  }
  result
}
