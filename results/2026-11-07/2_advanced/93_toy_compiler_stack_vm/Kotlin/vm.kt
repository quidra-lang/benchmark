data class CallEdge(val caller: Int, val callee: Int)
data class Frame(val locals: MutableList<Long>, val returnAddress: Int)
data class VMResult(val output: List<String>, val counts: IntArray, val calls: IntArray, val edges: Map<CallEdge, Int>, val executed: Int, val maxStack: Int, val maxDepth: Int, val errorPC: Int?, val message: String?, val callers: List<Int>)
object VM {
    fun run(code: List<Instruction>, owners: List<Int>, starts: List<Int>, area: Int, input: List<Long>): VMResult {
        val unitAt = starts.withIndex().associate {
            it.value to it.index
        };
        val global = LongArray(area);
        val stack = mutableListOf<Long>();
        val frames = mutableListOf<Frame>();
        val counts = IntArray(code.size);
        val calls = IntArray(starts.size);
        val edges = mutableMapOf<CallEdge, Int>();
        val output = mutableListOf<String>()
        var pc = 0;
        var read = 0;
        var executed = 0;
        var maxStack = 0;
        var maxDepth = 0;
        var message: String? = null;
        var errorPC: Int? = null
        fun pop(): Long = stack.removeAt(stack.lastIndex)
        execution@ while (true) {
            if (executed == 100000) {
                message = "instruction limit exceeded";
                errorPC = pc;
                break
            }
            val instruction = code[pc];
            val op = instruction.op;
            val args = instruction.operands;
            counts[pc]++;
            executed++;
            var next = pc + 1
            when (op) {
                "PUSH" -> stack.add(args[0])
                "POP" -> pop()
                "LOADG" -> stack.add(global[args[0].toInt()])
                "STOREG" -> global[args[0].toInt()] = pop()
                "LOADL" -> stack.add(frames.last().locals[args[0].toInt()])
                "STOREL" -> frames.last().locals[args[0].toInt()] = pop()
                "LOADA", "STOREA" -> {
                    val value = if (op == "STOREA") pop() else 0L;
                    val index = pop();
                    if (index < 0 || index >= args[1]) message = "index $index out of bounds for array of size ${args[1]}" else if (op == "LOADA") stack.add(global[(args[0] + index).toInt()]) else global[(args[0] + index).toInt()] = value
                }
                "ADD", "SUB", "MUL", "DIV", "MOD" -> {
                    val b = pop();
                    val a = pop();
                    if (op in listOf("DIV", "MOD") && b == 0L) message = "division by zero" else {
                        val value = when (op) {
                            "ADD" -> a + b;
                            "SUB" -> a - b;
                            "MUL" -> a * b;
                            "DIV" -> a / b;
                            else -> a - b * (a / b)
                        };
                        if (value in -2147483648L..2147483647L) stack.add(value) else message = "integer overflow"
                    }
                }
                "NEG" -> {
                    val value = -pop();
                    if (value in -2147483648L..2147483647L) stack.add(value) else message = "integer overflow"
                }
                "NOT" -> {
                    val value = pop();
                    stack.add(if (value == 0L) 1L else 0L)
                }
                "LT", "LE", "GT", "GE", "EQ", "NE" -> {
                    val b = pop();
                    val a = pop();
                    val value = when (op) {
                        "LT" -> a < b;
                        "LE" -> a <= b;
                        "GT" -> a > b;
                        "GE" -> a >= b;
                        "EQ" -> a == b;
                        else -> a != b
                    };
                    stack.add(if (value) 1L else 0L)
                }
                "JUMP" -> next = args[0].toInt()
                "JUMPF", "JUMPT" -> {
                    val value = pop();
                    if (if (op == "JUMPF") value == 0L else value != 0L) next = args[0].toInt()
                }
                "CALL" -> if (frames.size == 100) message = "call depth limit exceeded" else {
                    val n = args[1].toInt();
                    val values = stack.takeLast(n).toMutableList();
                    repeat(n) {
                        pop()
                    };
                    frames.add(Frame(values, pc + 1));
                    next = args[0].toInt();
                    val unit = unitAt.getValue(next);
                    calls[unit]++;
                    val edge = CallEdge(owners[pc], unit);
                    edges[edge] = (edges[edge] ?: 0) + 1
                }
                "ENTER" -> {
                    val locals = frames.last().locals;
                    repeat(args[0].toInt() - locals.size) {
                        locals.add(0)
                    }
                }
                "RET", "RETV" -> next = frames.removeAt(frames.lastIndex).returnAddress
                "READ" -> if (read == input.size) message = "read past end of input" else stack.add(input[read++])
                "PRINT" -> {
                    val n = args[0].toInt();
                    val values = stack.takeLast(n);
                    repeat(n) {
                        pop()
                    };
                    output.add(values.joinToString(" "))
                }
                "HALT" -> {
                    maxStack = maxOf(maxStack, stack.size);
                    maxDepth = maxOf(maxDepth, frames.size);
                    break@execution
                }
            }
            if (message != null) {
                errorPC = pc;
                break
            }
            maxStack = maxOf(maxStack, stack.size);
            maxDepth = maxOf(maxDepth, frames.size);
            pc = next
        }
        return VMResult(output, counts, calls, edges, executed, maxStack, maxDepth, errorPC, message, frames.drop(1).asReversed().map {
            it.returnAddress - 1
        })
    }
}
