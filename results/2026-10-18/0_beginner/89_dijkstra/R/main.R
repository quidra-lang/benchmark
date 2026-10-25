names <- LETTERS[1:7]
weights <- matrix(0,7,7)
edges <- data.frame(from=c("A","A","A","B","C","B","D","D","E","E","F"),
    to=c("B","C","D","C","E","D","E","F","F","G","G"), weight=c(7,3,9,2,6,3,4,5,3,8,4))
for (edge in seq_len(nrow(edges))) {
    i <- match(edges$from[edge],names)
    j <- match(edges$to[edge],names)
    weights[i,j] <- weights[j,i] <- edges$weight[edge]
}
distance <- rep(Inf,7)
previous <- integer(7)
finalized <- rep(FALSE,7)
distance[1] <- 0
for (step in 1:7) {
    candidates <- which(!finalized)
    vertex <- candidates[which.min(distance[candidates])]
    finalized[vertex] <- TRUE
    for (neighbor in 1:7) {
        if (weights[vertex,neighbor] > 0 && distance[vertex]+weights[vertex,neighbor] < distance[neighbor]) {
            distance[neighbor] <- distance[vertex]+weights[vertex,neighbor]
            previous[neighbor] <- vertex
        }
    }
}
for (i in 1:7) {
    path <- character(0)
    vertex <- i
    while (vertex != 0) {
        path <- c(names[vertex],path)
        vertex <- previous[vertex]
    }
    cat(sprintf("%s: distance=%d path=%s\n",names[i],distance[i],paste(path,collapse="-")))
}
