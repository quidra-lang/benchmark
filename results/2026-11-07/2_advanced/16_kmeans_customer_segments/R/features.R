feature_names <- c("recency", "frequency", "monetary", "basket", "categories", "tenure")
sqrt_features <- c(FALSE, TRUE, TRUE, TRUE, FALSE, FALSE)

customer_values <- function(customer) c(customer$recency, customer$frequency, customer$monetary,
                                        customer$basket, customer$categories, customer$tenure)
transformed_values <- function(customer) {
  values <- customer_values(customer)
  values[sqrt_features] <- sqrt(values[sqrt_features])
  values
}

eligible_customers <- function(orders, day) {
  groups <- orders_by_customer(Filter(function(order) order$net > 0, orders))
  lapply(sort(names(groups), method = "radix"), function(id) {
    purchases <- groups[[id]]
    days <- vapply(purchases, function(order) order$day, numeric(1L))
    spend <- sum(vapply(purchases, function(order) order$net, numeric(1L)))
    category_spend <- numeric()
    for (order in purchases) {
      for (row in order$rows) {
        previous <- category_spend[row$category]
        category_spend[row$category] <- if (is.na(previous)) row$amount else previous + row$amount
      }
    }
    frequency <- length(purchases)
    monetary <- spend / 100
    list(id = id, orders = purchases, recency = day - max(days), frequency = frequency,
      spend = spend, monetary = monetary, basket = monetary / frequency,
      category_spend = category_spend, categories = sum(category_spend > 0), tenure = day - min(days))
  })
}

ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total + value
  total
}
mean_value <- function(values) ordered_sum(values) / length(values)
sample_sd <- function(values) {
  average <- mean_value(values)
  total <- 0
  for (value in values) {
    difference <- value - average
    total <- total + difference * difference
  }
  sqrt(total / (length(values) - 1L))
}

standardization <- function(rows) {
  columns <- lapply(seq_along(feature_names), function(feature) vapply(rows, function(row) row[feature], numeric(1L)))
  list(means = vapply(columns, mean_value, numeric(1L)), sds = vapply(columns, sample_sd, numeric(1L)))
}

standardize <- function(values, means, sds) {
  result <- numeric(length(values))
  nonzero <- sds != 0
  result[nonzero] <- (values[nonzero] - means[nonzero]) / sds[nonzero]
  result
}

correlation_value <- function(points, first, second) {
  ordered_sum(vapply(points, function(point) point[first] * point[second], numeric(1L))) / (length(points) - 1L)
}
