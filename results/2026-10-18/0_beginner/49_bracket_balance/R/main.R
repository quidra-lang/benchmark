strings <- c("(a + b) * [c - d]","{x = [1, 2, (3 + 4)]}","f(a[i] + g(b)}","(1 + 2)) * 3","if (a < b) { c = d[0]; }","((a + b] * c","[{(x * y) - z}")
matching <- c(")"="(","]"="[","}"="{")
for (text in strings) {
    stack <- character(0)
    error_index <- -1
    characters <- strsplit(text,"",fixed=TRUE)[[1]]
    for (position in seq_along(characters)) {
        c_value <- characters[position]
        if (c_value %in% c("(","[","{")) {
            stack <- c(stack,c_value)
        } else if (c_value %in% names(matching)) {
            if (length(stack) == 0 || tail(stack,1) != matching[c_value]) {
                error_index <- position-1
                break
            }
            stack <- head(stack,-1)
        }
    }
    if (error_index < 0 && length(stack) > 0) error_index <- nchar(text)
    result <- if (error_index < 0) "balanced" else sprintf("error at index %d",error_index)
    cat(sprintf("%s -> %s\n",text,result))
}
