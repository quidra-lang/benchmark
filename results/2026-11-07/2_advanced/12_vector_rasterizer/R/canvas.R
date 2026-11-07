round_ratio <- function(numerator, denominator) {
  if (denominator < 0L) {
    numerator <- -numerator
    denominator <- -denominator
  }
  (2L * numerator + denominator) %/% (2L * denominator)
}
layer_record <- function(width, height, name, opacity, mode, body) list2env(list(width = width, height = height, name = name, opacity = opacity, mode = mode, body = body,
  painted = rep(FALSE, width * height), colors = matrix(0L, width * height, 4L), lines = integer(width * height), commands = 0L, errors = 0L), parent = emptyenv())
effective_alpha <- function(layer) {
  result <- integer(length(layer$painted))
  result[layer$painted] <- round_ratio(layer$colors[layer$painted, 4L] * layer$opacity, 255L)
  result
}
composite <- function(layers, background, width, height) {
  image <- matrix(rep(background[1:3], each = width * height), width * height, 3L)
  for (layer in layers) {
    indices <- which(layer$painted)
    alpha <- effective_alpha(layer)[indices]
    for (channel in 1:3) {
      source <- layer$colors[indices, channel]
      value <- image[indices, channel]
      if (layer$mode == "multiply") source <- round_ratio(source * value, 255L)
      else if (layer$mode == "screen") source <- 255L - round_ratio((255L - source) * (255L - value), 255L)
      image[indices, channel] <- round_ratio(alpha * source + (255L - alpha) * value, 255L)
    }
  }
  image
}
