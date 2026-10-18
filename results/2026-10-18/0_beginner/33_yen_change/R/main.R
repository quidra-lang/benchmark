for (amount in c(3780,15420,99999,506,48263)) {
    remaining <- amount
    total <- 0
    pieces <- character(0)
    for (face in c(10000,5000,1000,500,100,50,10,5,1)) {
        quantity <- remaining %/% face
        remaining <- remaining %% face
        if (quantity > 0) {
            pieces <- c(pieces, sprintf("%dx%d", face, quantity))
            total <- total + quantity
        }
    }
    cat(sprintf("%d yen: %s (%d pieces)\n", amount, paste(pieces, collapse = " "), total))
}
