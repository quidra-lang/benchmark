# Task B: 97_toy_assembly_vm / Julia

Initialize registers/program counter, parse each of the seventeen instruction strings, resolve operands as register values or integer literals, execute the selected update and advance/jump the counter. Move executed increment behind an opcode-membership decision containing only SET,ADD,SUB,MUL,MOD,JNZ, before their execution; count both taken and non-taken JNZ. Factorial contributes 3 SET +8×(MUL,ADD,SUB,JNZ)=35. Euclid contributes 2 SET +3×(SET,MOD,SET,SET,JNZ)=17. Revised executed=52. PRINT still emits 1,2,6,24,120,720,5040,40320,21, and HALT still terminates; excluding them changes only counting.

Operand resolution and dispatch are in the selected main block; JNZ sets pc and continue prevents a second increment, while HALT breaks.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50.

- L2: `program = [`
- L3: `"SET A 1",`
- L4: `"SET B 1",`
- L5: `"SET D 8",`
- L6: `"MUL A B",`
- L7: `"PRINT A",`
- L8: `"ADD B 1",`
- L9: `"SUB D 1",`
- L10: `"JNZ D -4",`
- L11: `"SET A 1071",`
- L12: `"SET B 462",`
- L13: `"SET C A",`
- L14: `"MOD C B",`
- L15: `"SET A B",`
- L16: `"SET B C",`
- L17: `"JNZ B -4",`
- L18: `"PRINT A",`
- L19: `"HALT",`
- L20: `]`
- L21: `registers = Dict("A"=>0, "B"=>0, "C"=>0, "D"=>0)`
- L22: `value(token) = haskey(registers, token) ? registers[token] : parse(Int, token)`
- L23: `pc, executed = 0, 0`
- L24: `while 0 <= pc < length(program)`
- L25: `parts = split(program[pc+1])`
- L26: `operation = parts[1]`
- L27: `executed += 1`
- L28: `operation == "HALT" && break`
- L29: `if operation == "JNZ"`
- L30: `pc += value(parts[2]) != 0 ? parse(Int, parts[3]) : 1`
- L31: `continue`
- L32: `elseif operation == "PRINT"`
- L33: `println(value(parts[2]))`
- L34: `else`
- L35: `register, operand = parts[2], value(parts[3])`
- L36: `if operation == "SET"`
- L37: `registers[register] = operand`
- L38: `elseif operation == "ADD"`
- L39: `registers[register] += operand`
- L40: `elseif operation == "SUB"`
- L41: `registers[register] -= operand`
- L42: `elseif operation == "MUL"`
- L43: `registers[register] *= operand`
- L44: `elseif operation == "MOD"`
- L45: `registers[register] %= operand`
- L46: `end`
- L47: `end`
- L48: `pc += 1`
- L49: `end`
- L50: `println("executed: ", executed)`

Minimization: The instruction data, resolver, complete dispatch/control flow, counter position and print/summary output are needed for the exact revised count. No unrelated program examples are included. The selected complete original lines, in source order, cost 612 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 612, and the complete source costs 623. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
