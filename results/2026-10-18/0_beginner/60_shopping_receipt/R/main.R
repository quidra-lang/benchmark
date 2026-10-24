items <- data.frame(name=c("milk","notebook","bread","apple","detergent","eggs"),
    price=c(198L,165L,248L,128L,437L,268L), quantity=c(2L,3L,1L,4L,1L,1L),
    category=c("food","general","food","food","general","food"))
subtotals <- items$price * items$quantity
cat(sprintf("%s %d x %d = %d\n",items$name,items$price,items$quantity,subtotals),sep="")
categories <- c("food","general")
totals <- tapply(subtotals,items$category,sum)[categories]
taxes <- (totals * c(8L,10L)) %/% 100L
cat(sprintf("%s: %d yen, tax %d yen\n",categories,totals,taxes),sep="")
cat(sprintf("total: %d yen\n",sum(totals)+sum(taxes)))
