smallest_multiple <- function(quantity, factor) integer_divide(quantity + factor - 1, factor) * factor

lot_size <- function(item, week, projected, receipts, gross, horizon) {
  net <- item$safety_stock - projected
  if (item$rule == "LFL") return(net)
  if (item$rule == "FOQ") return(smallest_multiple(net, item$lot[1L]))
  if (item$rule == "MIN") return(smallest_multiple(max(net, item$lot[1L]), item$lot[2L]))
  quantity <- net
  last <- min(week + item$lot[1L] - 1, horizon)
  if (week < last) for (later in seq.int(week + 1L, last)) {
    projected <- projected + receipts[later] - gross[later]
    quantity <- max(quantity, item$safety_stock - projected)
  }
  quantity
}
