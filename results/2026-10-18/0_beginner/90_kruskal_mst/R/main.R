edges <- list(c("A","B",7),c("C","A",4),c("B","C",9),c("B","D",14),c("D","C",6),c("C","E",3),c("E","D",5),c("F","D",11),c("E","G",16),c("G","F",8),c("H","F",12),c("G","H",2),c("H","E",10))
edges <- edges[order(vapply(edges,function(edge) as.integer(edge[3]),integer(1)))]
parents <- setNames(LETTERS[1:8],LETTERS[1:8])
find_root <- function(vertex) {
    while (parents[vertex] != vertex) vertex <- unname(parents[vertex])
    vertex
}
accepted <- 0
skipped <- 0
total <- 0
for (edge in edges) {
    a <- edge[1]
    b <- edge[2]
    weight <- as.integer(edge[3])
    first_root <- find_root(a)
    second_root <- find_root(b)
    if (first_root == second_root) {
        skipped <- skipped+1
    } else {
        parents[second_root] <- first_root
        accepted <- accepted+1
        total <- total+weight
        endpoints <- sort(c(a,b),method="radix")
        cat(sprintf("%s-%s %d\n",endpoints[1],endpoints[2],weight))
        if (accepted == 7) break
    }
}
cat(sprintf("total weight: %d\nskipped: %d\n",total,skipped))
