program <- c("SET A 1","SET B 1","SET D 8","MUL A B","PRINT A","ADD B 1","SUB D 1","JNZ D -4","SET A 1071","SET B 462","SET C A","MOD C B","SET A B","SET B C","JNZ B -4","PRINT A","HALT")
registers <- c(A=0,B=0,C=0,D=0)
value <- function(token) if (token %in% names(registers)) unname(registers[token]) else as.numeric(token)
pc <- 0
executed <- 0
while (pc >= 0 && pc < length(program)) {
    parts <- strsplit(program[pc+1]," ",fixed=TRUE)[[1]]
    operation <- parts[1]
    executed <- executed+1
    if (operation == "HALT") break
    if (operation == "JNZ") {
        pc <- pc+(if (value(parts[2]) != 0) as.integer(parts[3]) else 1)
        next
    } else if (operation == "PRINT") {
        cat(sprintf("%d\n",value(parts[2])))
    } else {
        register <- parts[2]
        operand <- value(parts[3])
        registers[register] <- switch(operation,SET=operand,ADD=registers[register]+operand,SUB=registers[register]-operand,MUL=registers[register]*operand,MOD=registers[register] %% operand)
    }
    pc <- pc+1
}
cat(sprintf("executed: %d\n",executed))
