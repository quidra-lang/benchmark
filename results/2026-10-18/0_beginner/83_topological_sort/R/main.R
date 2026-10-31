topological <- function(courses, edges) {
  indegree <- setNames(rep(0, length(courses)), courses)
  adjacency <- setNames(replicate(length(courses), character(0), simplify = FALSE), courses)
  for (edge in edges) {
    adjacency[[edge[1]]] <- c(adjacency[[edge[1]]], edge[2])
    indegree[edge[2]] <- indegree[edge[2]] + 1
  }
  ordered <- character(0)
  alphabetical <- sort(courses, method = "radix")
  repeat {
    ready <- alphabetical[!alphabetical %in% ordered & indegree[alphabetical] == 0]
    if (length(ready) == 0) break
    course <- ready[1]
    ordered <- c(ordered, course)
    for (target in adjacency[[course]]) indegree[target] <- indegree[target] - 1
  }
  list(order = ordered, remaining = alphabetical[!alphabetical %in% ordered])
}

courses1 <- c("physics", "algebra", "graphics", "programming", "statistics", "calculus", "databases", "algorithms")
edges1 <- list(
  c("calculus", "physics"), c("algebra", "calculus"), c("programming", "algorithms"),
  c("algebra", "statistics"), c("algorithms", "databases"), c("statistics", "databases"),
  c("calculus", "graphics"), c("algorithms", "graphics"), c("physics", "graphics")
)
courses2 <- c("music", "ecology", "art", "geology", "biology", "chemistry")
edges2 <- list(
  c("music", "art"), c("art", "ecology"), c("biology", "chemistry"), c("chemistry", "ecology"),
  c("ecology", "geology"), c("geology", "chemistry")
)
first <- topological(courses1, edges1)
second <- topological(courses2, edges2)
cat("order: ", paste(first$order, collapse = " -> "), "\n", sep = "")
cat("order: ", paste(second$order, collapse = " -> "), "\n", sep = "")
cat("cycle: ", paste(second$remaining, collapse = " "), "\n", sep = "")
