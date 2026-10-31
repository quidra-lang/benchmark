product_record <- function(name, category, price) list(name = name, category = category, price = price)

transaction_record <- function(tid, customer, day) {
  transaction <- new.env(parent = emptyenv())
  transaction$tid <- tid
  transaction$customer <- customer
  transaction$day <- day
  transaction$counts <- numeric()
  transaction
}

add_product <- function(transaction, item) {
  duplicate <- item %in% names(transaction$counts)
  transaction$counts[item] <- if (duplicate) transaction$counts[item] + 1 else 1
  duplicate
}

read_records <- function(name) strsplit(readLines(file.path("input", name), warn = FALSE)[-1L], ",", fixed = TRUE)
basket_items <- function(basket) sort(names(basket$counts), method = "radix")
extended_basket <- function(items, taxonomy) sort(unique(c(items, unname(taxonomy[items]))), method = "radix")
contains <- function(items, itemset) all(itemset %in% items)
