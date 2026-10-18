evaluate <- function(expression) {
    stack <- numeric(0)
    for (token in strsplit(expression," ",fixed=TRUE)[[1]]) {
        if (token %in% c("+","-","*","/")) {
            if (length(stack) < 2) return("error: stack underflow")
            b <- tail(stack,1)
            a <- stack[length(stack)-1]
            stack <- head(stack,-2)
            if (token == "/" && b == 0) return("error: division by zero")
            value <- switch(token,"+"=a+b,"-"=a-b,"*"=a*b,"/"=trunc(a/b))
            stack <- c(stack,value)
        } else stack <- c(stack,as.numeric(token))
    }
    if (length(stack) == 1) sprintf("%d",stack[1]) else "error: leftover operands"
}
expressions <- c("3 4 + 2 *","-17 5 / 4 -3 * -","1 2 + * 3","15 7 1 1 + - / 3 * 2 1 1 + + -","4 2 5 * + 1 3 2 * - 5 + /","2 3 4 + 5","46341 46339 * -2 /")
for (expression in expressions) cat(sprintf("%s => %s\n",expression,evaluate(expression)))
