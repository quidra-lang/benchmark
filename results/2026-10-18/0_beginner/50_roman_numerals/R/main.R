to_roman <- function(number) {
    values <- c(1000,900,500,400,100,90,50,40,10,9,5,4,1)
    symbols <- c("M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I")
    result <- ""
    for (i in seq_along(values)) {
        while (number >= values[i]) {
            result <- paste0(result,symbols[i])
            number <- number-values[i]
        }
    }
    result
}
from_roman <- function(roman) {
    table <- c(I=1,V=5,X=10,L=50,C=100,D=500,M=1000)
    values <- unname(table[strsplit(roman,"",fixed=TRUE)[[1]]])
    total <- 0
    for (i in seq_along(values)) total <- total + if (i < length(values) && values[i] < values[i+1]) -values[i] else values[i]
    total
}
for (number in c(9,14,49,94,444,1994,2768,3999)) {
    roman <- to_roman(number)
    cat(sprintf("%d -> %s -> %d\n",number,roman,from_roman(roman)))
}
