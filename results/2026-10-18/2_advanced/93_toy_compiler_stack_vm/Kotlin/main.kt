import java.io.File
fun reachableFrom(root: Int, calls: Map<Int, Set<Int>>): Set<Int> {
    val seen = mutableSetOf<Int>()
    val pending = mutableListOf(root)
    while (pending.isNotEmpty()) {
        val id = pending.removeAt(pending.lastIndex)
        if (seen.add(id)) pending.addAll(calls[id].orEmpty().sorted())
    }
    return seen
}
fun warningLines(program: Program, semantic: Semantic, reachable: Set<Int>): List<String> {
    val warnings = mutableListOf<Pair<Position, String>>()
    for (symbol in semantic.symbols) {
        if (symbol.variable != null && symbol.reads == 0) warnings.add(Pair(symbol.name.position, "unused ${if (symbol.parameter) "parameter" else "variable"} '${symbol.name.text}'"))
        if (symbol.function != null && symbol.function.id !in reachable) warnings.add(Pair(symbol.name.position, "function '${symbol.name.text}' is never called"))
    }
    fun walk(statement: Stmt) {
        when (val s = statement.kind) {
            is StmtKind.Block -> {
                val i = s.statements.indexOfFirst {
                    !canComplete(it)
                }
                if (i >= 0 && i + 1 < s.statements.size) warnings.add(Pair(s.statements[i + 1].position, "unreachable statement"))
                s.statements.forEach {
                    walk(it)
                }
            }
            is StmtKind.Conditional -> {
                walk(s.yes)
                s.no?.let {
                    walk(it)
                }
            }
            is StmtKind.WhileLoop -> walk(s.body)
            is StmtKind.ForLoop -> {
                s.initial?.let {
                    walk(it)
                }
                s.update?.let {
                    walk(it)
                }
                walk(s.body)
            }
            else -> Unit
        }
    }
    for (declaration in program.declarations) if (declaration is Top.FunctionDecl) walk(declaration.function.body)
    return warnings.sortedBy {
        it.first
    }.map {
        "warning ${it.first}: ${it.second}"
    }
}
class Folder {
    var count = 0
    fun literal(expression: Expr): Long? = when (val e = expression.kind) {
        is ExprKind.Integer -> e.value
        is ExprKind.BooleanValue -> if (e.value) 1L else 0L
        else -> null
    }
    fun boolean(expression: Expr, value: Boolean): Boolean = (expression.kind as? ExprKind.BooleanValue)?.value == value
    fun integer(expression: Expr, value: Long): Boolean = (expression.kind as? ExprKind.Integer)?.value == value
    fun made(old: Expr, value: Long, type: ToyType): Expr {
        val result = Expr(old.position, if (type == ToyType.BOOL) ExprKind.BooleanValue(value != 0L) else ExprKind.Integer(value))
        result.type = type
        count++
        return result
    }
    fun expression(original: Expr): Expr {
        when (val e = original.kind) {
            is ExprKind.Element -> original.kind = e.copy(index = expression(e.index))
            is ExprKind.Call -> original.kind = e.copy(arguments = e.arguments.map {
                expression(it)
            })
            is ExprKind.Unary -> {
                val value = expression(e.value)
                original.kind = e.copy(value = value)
                val v = literal(value)
                if (v != null) {
                    val result = if (e.op == "!") {
                        if (v == 0L) 1L else 0L
                    } else -v
                    if (result in -2147483648L..2147483647L) return made(original, result, original.type!!)
                }
            }
            is ExprKind.Binary -> {
                val a = expression(e.left)
                val b = expression(e.right)
                original.kind = e.copy(left = a, right = b)
                val x = literal(a)
                val y = literal(b)
                if (x != null && y != null) {
                    val value: Long? = when (e.op) {
                        "+" -> x + y
                        "-" -> x - y
                        "*" -> x * y
                        "/" -> if (y != 0L) x / y else null
                        "%" -> if (y != 0L) x - y * (x / y) else null
                        "<" -> if (x < y) 1L else 0L
                        "<=" -> if (x <= y) 1L else 0L
                        ">" -> if (x > y) 1L else 0L
                        ">=" -> if (x >= y) 1L else 0L
                        "==" -> if (x == y) 1L else 0L
                        "!=" -> if (x != y) 1L else 0L
                        "&&" -> if (x != 0L && y != 0L) 1L else 0L
                        "||" -> if (x != 0L || y != 0L) 1L else 0L
                        else -> null
                    }
                    if (value != null && value in -2147483648L..2147483647L) return made(original, value, original.type!!)
                }
                if (e.op == "&&" && boolean(a, false)) return made(original, 0, ToyType.BOOL)
                if (e.op == "||" && boolean(a, true)) return made(original, 1, ToyType.BOOL)
                if (e.op == "&&" && boolean(a, true) || e.op == "||" && boolean(a, false) || e.op == "+" && integer(a, 0) || e.op == "*" && integer(a, 1)) {
                    count++
                    return b
                }
                if (e.op in listOf("+", "-") && integer(b, 0) || e.op in listOf("*", "/") && integer(b, 1) || e.op == "&&" && boolean(b, true) || e.op == "||" && boolean(b, false)) {
                    count++
                    return a
                }
            }
            else -> Unit
        }
        return original
    }
    fun statement(original: Stmt): Stmt {
        when (val s = original.kind) {
            is StmtKind.Block -> original.kind = s.copy(statements = s.statements.map {
                statement(it)
            })
            is StmtKind.Declaration -> s.variable.initializer = s.variable.initializer?.let {
                expression(it)
            }
            is StmtKind.Assignment -> original.kind = s.copy(index = s.index?.let {
                expression(it)
            }, value = expression(s.value))
            is StmtKind.Call -> original.kind = s.copy(value = expression(s.value))
            is StmtKind.Print -> original.kind = s.copy(values = s.values.map {
                expression(it)
            })
            is StmtKind.ReturnValue -> original.kind = s.copy(value = s.value?.let {
                expression(it)
            })
            is StmtKind.Conditional -> {
                val condition = expression(s.condition)
                val kind = condition.kind
                if (kind is ExprKind.BooleanValue) {
                    count++
                    return if (kind.value) statement(s.yes) else s.no?.let {
                        statement(it)
                    } ?: Stmt(original.position, StmtKind.Empty)
                }
                original.kind = s.copy(condition = condition, yes = statement(s.yes), no = s.no?.let {
                    statement(it)
                })
            }
            is StmtKind.WhileLoop -> {
                val condition = expression(s.condition)
                if (boolean(condition, false)) {
                    count++
                    return Stmt(original.position, StmtKind.Empty)
                }
                original.kind = s.copy(condition = condition, body = statement(s.body))
            }
            is StmtKind.ForLoop -> original.kind = s.copy(initial = s.initial?.let {
                statement(it)
            }, condition = s.condition?.let {
                expression(it)
            }, update = s.update?.let {
                statement(it)
            }, body = statement(s.body))
            else -> Unit
        }
        return original
    }
    fun program(program: Program, reachable: Set<Int>) {
        for (declaration in program.declarations) {
            when (declaration) {
                is Top.VariableDecl -> declaration.variable.initializer = declaration.variable.initializer?.let {
                    expression(it)
                }
                is Top.FunctionDecl -> if (declaration.function.id in reachable) statement(declaration.function.body)
            }
        }
    }
}
val ruleNames = listOf("const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable")
fun isJump(op: String): Boolean = op in listOf("JUMP", "JUMPF", "JUMPT")
fun conditional(op: String): Boolean = op in listOf("JUMPF", "JUMPT")
fun transfer(op: String): Boolean = op in listOf("JUMP", "RET", "RETV", "HALT")
fun jumps(op: String, value: Long): Boolean = if (op == "JUMPF") value == 0L else value != 0L
fun inverse(op: String): String = if (op == "JUMPF") "JUMPT" else "JUMPF"
fun peephole(original: List<Instruction>): Pair<List<Instruction>, IntArray> {
    val code = original.map {
        it.snapshot()
    }.toMutableList()
    val counts = IntArray(7)
    fun delete(index: Int) {
        code.removeAt(index)
        for (instruction in code) if (isJump(instruction.op) && instruction.operands[0] > index.toLong()) instruction.operands[0]--
    }
    while (true) {
        val targets = code.filter {
            isJump(it.op)
        }.map {
            it.operands[0].toInt()
        }.toSet()
        var changed = false
        for (i in code.indices) {
            val a = code[i]
            val b = code.getOrNull(i + 1)
            val free = b != null && i + 1 !in targets
            if (b != null && free && a.op == "PUSH" && conditional(b.op)) {
                if (jumps(b.op, a.operands[0])) {
                    code[i] = Instruction("JUMP", b.operands.toMutableList(), b.position)
                    delete(i + 1)
                } else {
                    delete(i + 1)
                    delete(i)
                }
                counts[0]++
            }
            else if (b != null && free && b.op == "NOT" && a.op in listOf("LT", "LE", "GT", "GE", "EQ", "NE")) {
                a.op = mapOf("LT" to "GE", "LE" to "GT", "GT" to "LE", "GE" to "LT", "EQ" to "NE", "NE" to "EQ").getValue(a.op)
                delete(i + 1)
                counts[1]++
            }
            else if (b != null && free && a.op == "NOT" && conditional(b.op)) {
                code[i] = Instruction(inverse(b.op), b.operands.toMutableList(), b.position)
                delete(i + 1)
                counts[2]++
            }
            else if (b != null && free && conditional(a.op) && a.operands[0] == (i + 2).toLong() && b.op == "JUMP") {
                code[i] = Instruction(inverse(a.op), b.operands.toMutableList(), a.position)
                delete(i + 1)
                counts[3]++
            }
            else {
                var target: Long? = null
                if (isJump(a.op) && a.operands[0] < code.size.toLong()) {
                    val t = a.operands[0].toInt()
                    val at = code[t]
                    if (at.op == "JUMP") target = at.operands[0] else if (at.op == "PUSH" && t + 1 < code.size && conditional(code[t + 1].op)) target = if (jumps(code[t + 1].op, at.operands[0])) code[t + 1].operands[0] else (t + 2).toLong()
                }
                if (target != null && target != a.operands[0]) {
                    a.operands[0] = target
                    counts[4]++
                }
                else if (isJump(a.op) && a.operands[0] == (i + 1).toLong()) {
                    if (a.op == "JUMP") delete(i) else code[i] = Instruction("POP", mutableListOf(), a.position)
                    counts[5]++
                }
                else if (free && transfer(a.op)) {
                    delete(i + 1)
                    counts[6]++
                } else continue
            }
            changed = true
            break
        }
        if (!changed) return Pair(code, counts)
    }
}
fun successors(code: List<Instruction>, index: Int): List<Int> {
    val instruction = code[index]
    val result = mutableListOf<Int>()
    if (!transfer(instruction.op) && index + 1 < code.size) result.add(index + 1)
    if (isJump(instruction.op) && instruction.operands[0] < code.size.toLong() && instruction.operands[0].toInt() !in result) result.add(instruction.operands[0].toInt())
    return result
}
data class BasicBlock(val first: Int, val last: Int, val successors: List<Int>)
fun blocks(code: List<Instruction>): List<BasicBlock> {
    val leaders = mutableSetOf(0)
    for ((i, instruction) in code.withIndex()) {
        if (isJump(instruction.op) && instruction.operands[0] < code.size.toLong()) leaders.add(instruction.operands[0].toInt())
        if ((isJump(instruction.op) || transfer(instruction.op)) && i + 1 < code.size) leaders.add(i + 1)
    }
    val sorted = leaders.sorted()
    val index = sorted.withIndex().associate {
        it.value to it.index
    }
    return sorted.mapIndexed {
        k, first -> val last = if (k + 1 < sorted.size) sorted[k + 1] - 1 else code.lastIndex
        BasicBlock(first, last, successors(code, last).map {
            index.getValue(it)
        })
    }
}
fun stackDepth(code: List<Instruction>, semantic: Semantic): Int {
    fun effect(instruction: Instruction): Int = when (instruction.op) {
        "PUSH", "LOADG", "LOADL", "READ" -> 1
        "POP", "STOREG", "STOREL", "JUMPF", "JUMPT", "RETV", "ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE" -> -1
        "STOREA" -> -2
        "CALL" -> -instruction.operands[1].toInt() + if (semantic.symbols[instruction.callee!!].type == ToyType.VOID) 0 else 1
        "PRINT" -> -instruction.operands[0].toInt()
        else -> 0
    }
    val depth = mutableMapOf(0 to 0)
    val pending = mutableListOf(0)
    var maximum = 0
    while (pending.isNotEmpty()) {
        val i = pending.removeAt(pending.lastIndex)
        val next = depth.getValue(i) + effect(code[i])
        maximum = maxOf(maximum, next)
        for (j in successors(code, i)) if (j !in depth) {
            depth[j] = next
            pending.add(j)
        }
    }
    return maximum
}
data class FlatCode(val instructions: List<Instruction>, val owners: List<Int>, val starts: List<Int>)
fun flatten(units: List<CodeUnit>): FlatCode {
    val starts = mutableListOf<Int>()
    val functionStarts = mutableMapOf<Int, Int>()
    var address = 0
    for (unit in units) {
        starts.add(address)
        unit.function?.let {
            functionStarts[it.id] = address
        }
        address += unit.code.size
    }
    val instructions = mutableListOf<Instruction>()
    val owners = mutableListOf<Int>()
    for ((i, unit) in units.withIndex()) for (original in unit.code) {
        val instruction = original.snapshot()
        if (isJump(instruction.op)) instruction.operands[0] += starts[i].toLong()
        if (instruction.op == "CALL") instruction.operands[0] = functionStarts.getValue(instruction.callee!!).toLong()
        instructions.add(instruction)
        owners.add(i)
    }
    return FlatCode(instructions, owners, starts)
}
fun spelling(instruction: Instruction): String = instruction.op + instruction.operands.joinToString("") {
    " $it"
}
fun pad(text: String, width: Int, left: Boolean = false): String = if (left) text.padEnd(width) else text.padStart(width)
fun listingLines(program: Program, semantic: Semantic, before: List<CodeUnit>, after: List<CodeUnit>, old: FlatCode, new: FlatCode): List<String> {
    val globals = program.declarations.filterIsInstance<Top.VariableDecl>().map {
        it.variable
    }
    val lines = mutableListOf(if (globals.isEmpty()) "globals: none" else "globals:")
    for (variable in globals) lines.add("  ${variable.address} ${variable.name.text} " + (variable.size?.let {
        "int[$it]"
    } ?: variable.type.text))
    lines.add("functions:")
    for ((i, unit) in after.withIndex()) {
        val function = unit.function
        val signature = function?.let {
            " ${it.type.text}(${it.parameters.joinToString(",") { p -> p.type.text }})"
        } ?: ""
        val callees = function?.let {
            semantic.calls[it.id].orEmpty().map {
                id -> semantic.symbols[id].name.text
            }.sorted()
        } ?: listOf("main")
        val recursive = function?.let {
            f -> semantic.calls[f.id].orEmpty().any {
                f.id in reachableFrom(it, semantic.calls)
            }
        } ?: false
        lines.add("  ${unit.name}$signature address=${old.starts[i]}->${new.starts[i]} size=${before[i].code.size}->${unit.code.size} slots=${unit.slots.size} stack=${stackDepth(unit.code, semantic)} blocks=${blocks(unit.code).size} calls=${if (callees.isEmpty()) "-" else callees.joinToString(",")}" + if (recursive) " recursive" else "")
        for ((slot, variable) in unit.slots.withIndex()) lines.add("    slot $slot ${variable.name.text} ${variable.type.text}")
    }
    lines.add("references:")
    val referents = globals.map {
        it.id
    } + program.declarations.filterIsInstance<Top.FunctionDecl>().map {
        it.function.id
    }
    for (id in referents) {
        val symbol = semantic.symbols[id]
        val uses = symbol.references.map {
            it.line
        }.distinct().sorted()
        lines.add("  ${symbol.name.text} defined ${symbol.name.position.line} used ${if (uses.isEmpty()) "-" else uses.joinToString(" ")}")
    }
    for ((heading, units, flat) in listOf(Triple("before", before, old), Triple("after", after, new))) {
        lines.add("$heading peephole: ${flat.instructions.size} instructions")
        for ((i, unit) in units.withIndex()) {
            lines.add(unit.name + ":")
            for (j in unit.code.indices) {
                val pc = flat.starts[i] + j
                lines.add(pad(pc.toString(), 5) + "  " + spelling(flat.instructions[pc]))
            }
        }
    }
    lines.add("control flow:")
    for ((i, unit) in after.withIndex()) {
        lines.add("  " + unit.name)
        for ((k, block) in blocks(unit.code).withIndex()) lines.add("    B$k ${new.starts[i] + block.first}-${new.starts[i] + block.last}" + if (block.successors.isEmpty()) "" else " -> " + block.successors.joinToString(" ") {
            "B$it"
        })
    }
    return lines
}
fun statsLines(beforeCount: Int, after: List<CodeUnit>, code: FlatCode, main: VMResult, comparison: VMResult, folds: Int, rules: IntArray): List<String> {
    val lines = mutableListOf("code: $beforeCount -> ${code.instructions.size}", "folds: $folds", "peephole: ${rules.sum()}")
    for (i in ruleNames.indices) lines.add("  ${ruleNames[i]} ${rules[i]}")
    lines.addAll(listOf("executed: ${main.executed}", "executed before peephole: ${comparison.executed}", "behaviour: ${if (main.output == comparison.output && main.message == comparison.message) "same" else "different"}", "max call depth: ${main.maxDepth}", "max stack: ${main.maxStack}", "opcodes:"))
    val opcodes = mutableMapOf<String, Int>()
    val unitCounts = IntArray(after.size)
    val lineCounts = mutableMapOf<Int, Int>()
    for ((pc, instruction) in code.instructions.withIndex()) {
        val count = main.counts[pc]
        opcodes[instruction.op] = (opcodes[instruction.op] ?: 0) + count
        unitCounts[code.owners[pc]] += count
        lineCounts[instruction.position.line] = (lineCounts[instruction.position.line] ?: 0) + count
    }
    for ((op, count) in opcodes.entries.filter {
        it.value > 0
    }.sortedWith(compareByDescending<Map.Entry<String, Int>> {
        it.value
    }.thenBy {
        it.key
    })) lines.add("  $op $count")
    lines.add("functions:")
    for (i in after.indices.drop(1).sortedWith(compareByDescending<Int> {
        unitCounts[it]
    }.thenBy {
        after[it].name
    })) lines.add("  ${after[i].name} calls=${main.calls[i]} executed=${unitCounts[i]}")
    lines.add("calls:")
    for ((edge, count) in main.edges.entries.sortedWith(compareByDescending<Map.Entry<CallEdge, Int>> {
        it.value
    }.thenBy {
        after[it.key.caller].name
    }.thenBy {
        after[it.key.callee].name
    })) lines.add("  ${after[edge.caller].name} -> ${after[edge.callee].name} $count")
    lines.add("hot lines:")
    for ((line, count) in lineCounts.entries.filter {
        it.value > 0
    }.sortedWith(compareByDescending<Map.Entry<Int, Int>> {
        it.value
    }.thenBy {
        it.key
    }).take(5)) lines.add("  line $line: $count")
    val missing = lineCounts.filterValues {
        it == 0
    }.keys.sorted()
    lines.addAll(listOf("coverage: ${lineCounts.values.count { it > 0 }} of ${lineCounts.size} lines", "not executed: ${if (missing.isEmpty()) "none" else missing.joinToString(" ")}", "hot spots:"))
    for (pc in code.instructions.indices.filter {
        main.counts[it] > 0
    }.sortedWith(compareByDescending<Int> {
        main.counts[it]
    }.thenBy {
        it
    }).take(5)) lines.add("  pc=$pc count=${main.counts[pc]} ${spelling(code.instructions[pc])}")
    return lines
}
data class SourceProgram(val name: String, val lines: MutableList<Pair<Int, String>> = mutableListOf())
fun readPrograms(): Pair<List<SourceProgram>, List<String>> {
    val lines = File("input/program.src").readLines()
    val result = mutableListOf<SourceProgram>()
    for ((i, line) in lines.withIndex()) {
        if (line.startsWith("#program ")) result.add(SourceProgram(line.drop(9))) else result.last().lines.add(Pair(i + 1, line))
    }
    return Pair(result, lines)
}
fun readInput(): Map<String, List<Long>> {
    val result = mutableMapOf<String, MutableList<Long>>()
    var name = ""
    for (line in File("input/input.txt").readLines()) {
        if (line.startsWith("#input ")) {
            name = line.drop(7)
            result[name] = mutableListOf()
        } else result.getValue(name).addAll(line.split(' ').map {
            it.toLong()
        })
    }
    return result
}
fun display(position: Position, sources: List<String>): List<String> = listOf("  " + sources[position.line - 1], " ".repeat(position.column + 1) + "^")
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val (programs, sourceLines) = readPrograms()
    val inputs = readInput()
    val listing = mutableListOf<String>()
    val output = mutableListOf<String>()
    val diagnostics = mutableListOf<String>()
    val stats = mutableListOf<String>()
    val rows = mutableListOf(listOf("program", "status", "code", "executed", "output"))
    var compiled = 0
    val compileErrors = mutableMapOf("lexical" to 0, "syntax" to 0, "semantic" to 0)
    var runtimeErrors = 0
    var foldTotal = 0
    val ruleTotals = IntArray(7)
    var executedTotal = 0
    for (source in programs) {
        val heading = "== program ${source.name} =="
        listing.add(heading)
        output.add(heading)
        diagnostics.add(heading)
        stats.add(heading)
        val program: Program
        val semantic = Semantic()
        try {
            program = Parser(Lexer.lex(source.lines)).program()
            semantic.analyze(program)
        } catch (error: CompileError) {
            listing.add("not compiled")
            stats.add("not compiled")
            diagnostics.add("${error.kind} error ${error.position}: ${error.reason}")
            diagnostics.addAll(display(error.position, sourceLines))
            diagnostics.add("status: compile error")
            compileErrors[error.kind] = compileErrors.getValue(error.kind) + 1
            rows.add(listOf(source.name, error.kind + " error", "-", "-", "-"))
            continue
        }
        compiled++
        val reachable = reachableFrom(semantic.globals.getValue("main"), semantic.calls)
        diagnostics.addAll(warningLines(program, semantic, reachable))
        val folder = Folder()
        folder.program(program, reachable)
        foldTotal += folder.count
        val (before, area) = Codegen(semantic).generate(program, reachable)
        val after = mutableListOf<CodeUnit>()
        val rules = IntArray(7)
        for (unit in before) {
            val (code, counts) = peephole(unit.code)
            after.add(unit.copy(code = code))
            for (k in rules.indices) rules[k] += counts[k]
        }
        for (k in rules.indices) ruleTotals[k] += rules[k]
        val old = flatten(before)
        val new = flatten(after)
        val input = inputs[source.name].orEmpty()
        val main = VM.run(new.instructions, new.owners, new.starts, area, input)
        val comparison = VM.run(old.instructions, old.owners, old.starts, area, input)
        executedTotal += main.executed
        listing.addAll(listingLines(program, semantic, before, after, old, new))
        output.addAll(main.output)
        val pc = main.errorPC
        if (pc != null) {
            runtimeErrors++
            val instruction = new.instructions[pc]
            diagnostics.add("runtime error ${instruction.position}: ${main.message} in ${after[new.owners[pc]].name}")
            diagnostics.addAll(display(instruction.position, sourceLines))
            for (caller in main.callers.take(5)) diagnostics.add("  called from ${after[new.owners[caller]].name} at ${new.instructions[caller].position}")
            if (main.callers.size > 5) diagnostics.add("  ... ${main.callers.size - 5} more")
        }
        val status = if (main.message == null) "ok" else "runtime error"
        diagnostics.add("status: $status")
        stats.addAll(statsLines(old.instructions.size, after, new, main, comparison, folder.count, rules))
        rows.add(listOf(source.name, status, new.instructions.size.toString(), main.executed.toString(), main.output.size.toString()))
    }
    stats.addAll(listOf("== summary ==", "programs: ${programs.size}", "compiled: $compiled", "compile errors: lexical ${compileErrors.getValue("lexical")} syntax ${compileErrors.getValue("syntax")} semantic ${compileErrors.getValue("semantic")}", "runtime errors: $runtimeErrors", "folds: $foldTotal", "peephole: ${ruleTotals.sum()}"))
    for (i in ruleNames.indices) stats.add("  ${ruleNames[i]} ${ruleTotals[i]}")
    stats.add("executed: $executedTotal")
    val widths = (0..4).map {
        k -> rows.maxOf {
            it[k].length
        }
    }
    for (row in rows) stats.add("  " + row.mapIndexed {
        k, value -> pad(value, widths[k], k < 2)
    }.joinToString("  "))
    write("listing.txt", listing)
    write("output.txt", output)
    write("diagnostics.txt", diagnostics)
    write("stats.txt", stats)
}
