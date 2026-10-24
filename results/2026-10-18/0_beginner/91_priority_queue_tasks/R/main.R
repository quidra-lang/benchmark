before <- function(a,b) a$priority < b$priority || (a$priority == b$priority && a$sequence < b$sequence)
heap <- new.env(parent=emptyenv())
heap$items <- list()
heap_push <- function(task) {
    items <- heap$items
    items[[length(items)+1]] <- task
    child <- length(items)
    while (child > 1) {
        parent <- child %/% 2
        if (!before(items[[child]],items[[parent]])) break
        items[c(child,parent)] <- items[c(parent,child)]
        child <- parent
    }
    heap$items <- items
}
heap_pop <- function() {
    items <- heap$items
    task <- items[[1]]
    last <- tail(items,1)[[1]]
    items <- head(items,-1)
    if (length(items) > 0) {
        items[[1]] <- last
        parent <- 1
        while (2*parent <= length(items)) {
            child <- 2*parent
            if (child < length(items) && before(items[[child+1]],items[[child]])) child <- child+1
            if (!before(items[[child]],items[[parent]])) break
            items[c(child,parent)] <- items[c(parent,child)]
            parent <- child
        }
    }
    heap$items <- items
    task
}
operations <- c("add email 3","add backup 5","add deploy 1","run","add report 3","add test 2","add lint 3","run","run","add cleanup 5","add review 2","run","add build 1","add docs 4","run","run")
for (sequence in seq_along(operations)) {
    parts <- strsplit(operations[sequence]," ",fixed=TRUE)[[1]]
    if (parts[1] == "add") {
        heap_push(list(name=parts[2],priority=as.integer(parts[3]),sequence=sequence))
    } else {
        task <- heap_pop()
        cat(sprintf("run: %s (priority %d)\n",task$name,task$priority))
    }
}
remaining <- character(0)
while (length(heap$items) > 0) remaining <- c(remaining,heap_pop()$name)
cat("remaining: ",paste(remaining,collapse=" "),"\n",sep="")
