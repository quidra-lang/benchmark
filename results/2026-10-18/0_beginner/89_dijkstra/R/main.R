names <- LETTERS[1:7]
weights <- matrix(0,7,7)
for (edge in list(c("A","B",7),c("A","C",3),c("A","D",9),c("B","C",2),c("C","E",6),c("B","D",3),c("D","E",4),c("D","F",5),c("E","F",3),c("E","G",8),c("F","G",4))) {
    i <- match(edge[1],names); j <- match(edge[2],names)
    weights[i,j] <- weights[j,i] <- as.integer(edge[3])
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
