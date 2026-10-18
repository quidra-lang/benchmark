sets <- list(c(3,8,5),c(6,6,6),c(5,8,5),c(13,5,12),c(2,9,4),c(7,4,7),c(8,6,7),c(4,9,6))
for (sides in sets) {
    ordered <- sort(sides); a <- ordered[1]; b <- ordered[2]; c_value <- ordered[3]
    if (a+b <= c_value) {
        result <- "not a triangle"
    } else {
        side <- if (a == c_value) "equilateral" else if (a == b || b == c_value) "isosceles" else "scalene"
        square_sum <- a*a+b*b
        angle <- if (c_value*c_value < square_sum) "acute" else if (c_value*c_value == square_sum) "right" else "obtuse"
        result <- paste(side,angle)
    }
    cat(paste(sides,collapse=" "),": ",result,"\n",sep="")
}
