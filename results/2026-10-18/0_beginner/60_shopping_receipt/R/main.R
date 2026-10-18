items <- list(c("milk",198,2,"food"),c("notebook",165,3,"general"),c("bread",248,1,"food"),c("apple",128,4,"food"),c("detergent",437,1,"general"),c("eggs",268,1,"food"))
totals <- c(food=0,general=0)
for (item in items) {
    price <- as.integer(item[2])
    quantity <- as.integer(item[3])
    subtotal <- price*quantity
    totals[item[4]] <- totals[item[4]]+subtotal
    cat(sprintf("%s %d x %d = %d\n",item[1],price,quantity,subtotal))
}
payment <- 0
for (category in c("food","general")) {
    rate <- if (category == "food") 8 else 10
    tax <- (totals[category]*rate) %/% 100
    payment <- payment+totals[category]+tax
    cat(sprintf("%s: %d yen, tax %d yen\n",category,totals[category],tax))
}
cat(sprintf("total: %d yen\n",payment))
