decode_component <- function(source) {
    output <- ""
    i <- 1
    while (i <= nchar(source)) {
        character <- substr(source,i,i)
        if (character == "+") {
            output <- paste0(output," ")
            i <- i+1
        } else if (character == "%") {
            output <- paste0(output,intToUtf8(strtoi(substr(source,i+1,i+2),base=16)))
            i <- i+3
        } else {
            output <- paste0(output,character)
            i <- i+1
        }
    }
    output
}
queries <- c("name=Alice+Smith&age=30&city=New%20York","q=c%2B%2B+tutorial&page=2&sort=desc&page=3","msg=50%25+off%21&debug&lang=en&ref=&lang=ja","redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips")
for (number in seq_along(queries)) {
    parameters <- list()
    for (item in strsplit(queries[number],"&",fixed=TRUE)[[1]]) {
        position <- regexpr("=",item,fixed=TRUE)[1]
        key <- decode_component(if (position < 0) item else substr(item,1,position-1))
        value <- if (position < 0) "" else decode_component(substring(item,position+1))
        parameters[[key]] <- c(parameters[[key]],value)
    }
    cat(sprintf("query %d:\n",number))
    for (key in sort(names(parameters),method="radix")) {
        quoted <- paste0('"',parameters[[key]],'"')
        cat("  ",key,": ",paste(quoted,collapse=", "),"\n",sep="")
    }
}
