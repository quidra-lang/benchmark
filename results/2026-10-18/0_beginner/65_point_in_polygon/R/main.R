polygon <- matrix(c(1,1,11,2,13,9,9,7,7,12,5,6,2,10,3,5),ncol=2,byrow=TRUE)
points <- list(c(4,8),c(6,4),c(10,8),c(7,11),c(14,3),c(12,8))
for (point in points) {
    px <- point[1]
    py <- point[2]
    crossings <- 0
    for (i in seq_len(nrow(polygon))) {
        j <- i %% nrow(polygon)+1
        x1 <- polygon[i,1]
        y1 <- polygon[i,2]
        x2 <- polygon[j,1]
        y2 <- polygon[j,2]
        if ((y1 > py) != (y2 > py)) {
            intersection <- x1+(x2-x1)*(py-y1)/(y2-y1)
            if (intersection > px) crossings <- crossings+1
        }
    }
    result <- if (crossings %% 2 == 1) "inside" else "outside"
    cat(sprintf("(%d, %d): %s\n",px,py,result))
}
