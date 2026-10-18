adjacency <- replicate(9,integer(0),simplify=FALSE)
for (edge in list(c(5,0),c(3,8),c(7,2),c(1,6),c(0,2),c(5,3),c(7,5),c(6,4),c(8,7))) {
    a <- edge[1]+1; b <- edge[2]+1
    adjacency[[a]] <- c(adjacency[[a]],b-1)
    adjacency[[b]] <- c(adjacency[[b]],a-1)
}
adjacency <- lapply(adjacency,sort)
walk <- function(start,seen) {
    order <- integer(0)
    visit <- function(vertex) {
        seen[vertex+1] <<- TRUE
        order <<- c(order,vertex)
        for (neighbor in adjacency[[vertex+1]]) {
            if (!seen[neighbor+1]) visit(neighbor)
        }
    }
    visit(start)
    list(seen=seen,order=order)
}
cat("DFS: ",paste(walk(0,rep(FALSE,9))$order,collapse=" "),"\n",sep="")
queue <- 0
seen <- rep(FALSE,9)
seen[1] <- TRUE
head_index <- 1
while (head_index <= length(queue)) {
    vertex <- queue[head_index]
    head_index <- head_index+1
    for (neighbor in adjacency[[vertex+1]]) {
        if (!seen[neighbor+1]) {
            seen[neighbor+1] <- TRUE
            queue <- c(queue,neighbor)
        }
    }
}
cat("BFS: ",paste(queue,collapse=" "),"\n",sep="")
seen <- rep(FALSE,9)
components <- list()
for (vertex in 0:8) {
    if (!seen[vertex+1]) {
        result <- walk(vertex,seen)
        seen <- result$seen
        components[[length(components)+1]] <- sort(result$order)
    }
}
cat(sprintf("components: %d\n",length(components)))
for (i in seq_along(components)) cat(sprintf("component %d: %s\n",i,paste(components[[i]],collapse=" ")))
