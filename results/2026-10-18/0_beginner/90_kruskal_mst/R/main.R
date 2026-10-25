edges <- data.frame(from=c("A","C","B","B","D","C","E","F","E","G","H","G","H"),
    to=c("B","A","C","D","C","E","D","D","G","F","F","H","E"), weight=c(7,4,9,14,6,3,5,11,16,8,12,2,10))
edges <- edges[order(edges$weight),]
parents <- setNames(LETTERS[1:8],LETTERS[1:8])
find_root <- function(vertex) {
    while (parents[vertex] != vertex) vertex <- unname(parents[vertex])
    vertex
}
accepted <- 0
skipped <- 0
total <- 0
for (edge in seq_len(nrow(edges))) {
    a <- edges$from[edge]
    b <- edges$to[edge]
    weight <- edges$weight[edge]
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
