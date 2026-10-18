text <- "she sells sea shells by the sea shore"
frequencies <- table(strsplit(text,"",fixed=TRUE)[[1]])
symbols <- names(frequencies)[order(vapply(names(frequencies),utf8ToInt,integer(1)))]
trees <- lapply(symbols,function(symbol) list(weight=as.numeric(frequencies[symbol]),smallest=utf8ToInt(symbol),symbol=symbol))
while (length(trees) > 1) {
    ordered <- order(vapply(trees,function(node) node$weight,numeric(1)),vapply(trees,function(node) node$smallest,integer(1)))
    trees <- trees[ordered]
    left <- trees[[1]]
    right <- trees[[2]]
    trees <- trees[-c(1,2)]
    node <- list(weight=left$weight+right$weight,smallest=min(left$smallest,right$smallest),left=left,right=right)
    trees[[length(trees)+1]] <- node
}
codes <- character(0)
visit <- function(node,prefix) {
    if (!is.null(node$symbol)) {
        codes[node$symbol] <<- prefix
    } else {
        visit(node$left,paste0(prefix,"0"))
        visit(node$right,paste0(prefix,"1"))
    }
}
invisible(visit(trees[[1]],""))
bits <- 0
for (symbol in symbols) {
    cat(sprintf("'%s' freq=%d code=%s\n",symbol,frequencies[symbol],codes[symbol]))
    bits <- bits+frequencies[symbol]*nchar(codes[symbol])
}
cat(sprintf("encoded bits: %d\nfixed 8-bit: %d\n",bits,nchar(text)*8))
