# Task B: 97_toy_assembly_vm / R

Initialize registers/program counter, parse each of the seventeen instruction strings, resolve operands as register values or integer literals, execute the selected update and advance/jump the counter. Move executed increment behind an opcode-membership decision containing only SET,ADD,SUB,MUL,MOD,JNZ, before their execution; count both taken and non-taken JNZ. Factorial contributes 3 SET +8×(MUL,ADD,SUB,JNZ)=35. Euclid contributes 2 SET +3×(SET,MOD,SET,SET,JNZ)=17. Revised executed=52. PRINT still emits 1,2,6,24,120,720,5040,40320,21, and HALT still terminates; excluding them changes only counting.

The local operand helper and command dispatch resolve values; JNZ updates pc with next skipping the ordinary advance, and HALT breaks.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L8,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35.

- L1: `program <- c(`
- L2: `"SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1", "JNZ D -4",`
- L3: `"SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B", "SET B C", "JNZ B -4", "PRINT A",`
- L4: `"HALT"`
- L5: `)`
- L6: `registers <- c(A = 0, B = 0, C = 0, D = 0)`
- L8: `value <- function(token) if (token %in% names(registers)) unname(registers[token]) else as.numeric(token)`
- L10: `pc <- 0`
- L11: `executed <- 0`
- L12: `while (pc >= 0 && pc < length(program)) {`
- L13: `parts <- strsplit(program[pc + 1], " ", fixed = TRUE)[[1]]`
- L14: `operation <- parts[1]`
- L15: `executed <- executed + 1`
- L16: `if (operation == "HALT") break`
- L17: `if (operation == "JNZ") {`
- L18: `pc <- pc + (if (value(parts[2]) != 0) as.integer(parts[3]) else 1)`
- L19: `next`
- L20: `} else if (operation == "PRINT") {`
- L21: `cat(sprintf("%d\n", value(parts[2])))`
- L22: `} else {`
- L23: `register <- parts[2]`
- L24: `operand <- value(parts[3])`
- L25: `registers[register] <- switch(operation,`
- L26: `SET = operand,`
- L27: `ADD = registers[register] + operand,`
- L28: `SUB = registers[register] - operand,`
- L29: `MUL = registers[register] * operand,`
- L30: `MOD = registers[register] %% operand`
- L31: `)`
- L32: `}`
- L33: `pc <- pc + 1`
- L34: `}`
- L35: `cat(sprintf("executed: %d\n", executed))`

Minimization: The instruction data, resolver, complete dispatch/control flow, counter position and print/summary output are needed for the exact revised count. No unrelated program examples are included. The selected complete original lines, in source order, cost 593 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 595, and the complete source costs 595. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
