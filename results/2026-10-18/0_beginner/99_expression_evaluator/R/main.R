evaluate_tokens <- function(tokens,variables,start) {
    position <- start
    factor <- function() {
        token <- tokens[position]
        position <<- position+1
        if (token == "-") return(-factor())
        if (token == "(") {
            value <- expression()
            position <<- position+1
            return(value)
        }
        if (grepl("^[0-9]",token)) return(as.numeric(token))
        if (!token %in% names(variables)) stop(paste("undefined variable",token),call.=FALSE)
        unname(variables[token])
    }
    term <- function() {
        value <- factor()
        while (position <= length(tokens) && tokens[position] %in% c("*","/")) {
            operation <- tokens[position]
            position <<- position+1
            right <- factor()
            if (operation == "/" && right == 0) stop("division by zero",call.=FALSE)
            value <- if (operation == "*") value*right else sign(value)*sign(right)*(abs(value) %/% abs(right))
        }
        value
    }
    expression <- function() {
        value <- term()
        while (position <= length(tokens) && tokens[position] %in% c("+","-")) {
            operation <- tokens[position]
            position <<- position+1
            right <- term()
            value <- if (operation == "+") value+right else value-right
        }
        value
    }
    expression()
}
lines <- c("width = 12","height = width - 5","area = width * height","(area + 6) / 4","shift = -area / 8 + 3","height = 100 / (height - 7) + bonus","volume = area * depth","width = (width+3)*-(2-4)","width * shift - height")
variables <- numeric(0)
for (line in lines) {
    tokens <- regmatches(line,gregexpr("[0-9]+|[a-z]+|[()+*/=-]",line,perl=TRUE))[[1]]
    assignment <- length(tokens) >= 2 && tokens[2] == "="
    result <- tryCatch(list(ok=TRUE,value=evaluate_tokens(tokens,variables,if (assignment) 3 else 1)),error=function(e) list(ok=FALSE,error=conditionMessage(e)))
    if (!result$ok) {
        cat("error: ",result$error,"\n",sep="")
    } else if (assignment) {
        variables[tokens[1]] <- result$value
        cat(sprintf("%s = %d\n",tokens[1],result$value))
    } else cat(sprintf("%d\n",result$value))
}
