standard_costs <- function(data) {
  costs <- list()
  for (id in rev(data$planning_order)) {
    material <- data$items[[id]]$material
    labor <- data$items[[id]]$labor
    for (row in data$bom$children[[id]]) {
      child <- costs[[row$child]]
      material <- material + integer_divide(row$qty_per * (100 + row$scrap) * child$material + 50, 100)
      labor <- labor + integer_divide(row$qty_per * (100 + row$scrap) * child$labor + 50, 100)
    }
    costs[[id]] <- list(material = material, labor = labor, total = material + labor)
  }
  costs
}

abc_classes <- function(values) {
  ids <- names(values)[order(-values, names(values), method = "radix")]
  total <- sum(values)
  before <- 0
  classes <- character()
  for (id in ids) {
    value <- values[[id]]
    classes[id] <- if (value == 0) "C" else if (100 * before < 80 * total) "A" else if (100 * before < 95 * total) "B" else "C"
    before <- before + value
  }
  classes
}
