sealed interface FoldResult {
    data object Unchanged : FoldResult
    data object Deleted : FoldResult
    data class Replacement(val instruction: Instruction) : FoldResult
}
object Optimizations {
    fun fold(instruction: Instruction): FoldResult {
        if (instruction.kind !in listOf("bin", "if")) return FoldResult.Unchanged
        val a = instruction.a!!
        val b = instruction.b!!
        val x = a.constant
        val y = b.constant
        if (x != null && y != null) {
            if (instruction.operation in listOf("/", "%") && y == 0L) return FoldResult.Unchanged
            val value = TacParser.operation(instruction.operation, x, y)
            if (instruction.kind == "if") return if (value == 0L) FoldResult.Deleted else FoldResult.Replacement(Instruction("goto", target = instruction.target))
            return if (value in -2147483648L..2147483647L) FoldResult.Replacement(Instruction.move(instruction.destination!!, Operand.Constant(value))) else FoldResult.Unchanged
        }
        if (instruction.kind != "bin") return FoldResult.Unchanged
        val value = if (instruction.operation == "+" && x == 0L) b else if (instruction.operation in listOf("+", "-") && y == 0L) a else if (instruction.operation == "*" && x == 1L) b else if (instruction.operation in listOf("*", "/") && y == 1L) a else if (instruction.operation == "*" && (x == 0L || y == 0L)) Operand.Constant(0) else null
        return if (value == null) FoldResult.Unchanged else FoldResult.Replacement(Instruction.move(instruction.destination!!, value))
    }
    fun rewrite(function: Function, replacements: Map<Int, List<Instruction>>) {
        val code = mutableListOf<CodeLine>()
        var number = 0
        for (line in function.code) {
            if (line is CodeLine.Label) code.add(line) else {
                val replacement = replacements[number++]
                if (replacement == null) code.add(line) else code.addAll(replacement.map {
                    CodeLine.Code(it)
                })
            }
        }
        function.code = code
    }
    fun temporary(function: Function): String {
        function.temporary++
        return "_t${function.temporary}"
    }
    fun cseRewrite(instruction: Instruction, temporary: String, source: Boolean): List<Instruction> {
        val copy = Instruction.move(instruction.destination!!, Operand.Variable(temporary))
        return if (source) listOf(instruction.copy(destination = temporary), copy) else listOf(copy)
    }
    fun hoist(function: Function, graph: Graph, loop: NaturalLoop, moved: List<Int>): String {
        val h = loop.header
        val outside = graph.blocks[h].predecessors.filter {
            it !in loop.blocks
        }
        val preheader = if (h != 0 && outside.size == 1 && graph.blocks[outside[0]].successors == listOf(h)) outside[0] else null
        val moving = moved.toSet()
        val instructions = graph.instructions
        val insertion = mutableListOf<CodeLine>()
        val codeBefore = function.code.toMutableList()
        val position: Int
        val target: String
        if (preheader != null) {
            val last = graph.blocks[preheader].last
            position = graph.positions[last] + if (instructions[last].kind in listOf("goto", "if")) 0 else 1
            target = "B${preheader + 1}"
        }
        else {
            function.preheader++
            val label = "_p${function.preheader}"
            target = "new $label"
            insertion.add(CodeLine.Label(label))
            var first = graph.positions[graph.blocks[h].first]
            while (first > 0 && function.code[first - 1] is CodeLine.Label) first--
            position = first
            for (p in outside) {
                val index = graph.blocks[p].last
                if (instructions[index].kind in listOf("goto", "if") && instructions[index].target in graph.blocks[h].labels) codeBefore[graph.positions[index]] = CodeLine.Code(instructions[index].copy(target = label))
            }
        }
        insertion.addAll(moved.map {
            CodeLine.Code(instructions[it])
        })
        val code = mutableListOf<CodeLine>()
        var number = 0
        for ((i, line) in codeBefore.withIndex()) {
            if (i == position) code.addAll(insertion)
            if (line is CodeLine.Label) code.add(line) else {
                if (number !in moving) code.add(line)
                number++
            }
        }
        if (position == codeBefore.size) code.addAll(insertion)
        function.code = code
        return target
    }
    fun unreachable(function: Function, graph: Graph): List<String> {
        val records = graph.blocks.indices.filter {
            it !in graph.reachable
        }.map {
            "remove block B${it + 1}"
        }.toMutableList()
        var code = mutableListOf<CodeLine>()
        val labels = mutableListOf<CodeLine>()
        var number = 0
        for (line in function.code) {
            if (line is CodeLine.Label) labels.add(line) else {
                if (graph.owners[number] in graph.reachable) {
                    code.addAll(labels)
                    code.add(line)
                }
                labels.clear()
                number++
            }
        }
        val deleted = mutableSetOf<Int>()
        number = 0
        for ((i, line) in code.withIndex()) {
            if (line is CodeLine.Code) {
                number++
                if (line.instruction.kind in listOf("goto", "if")) {
                    var j = i + 1
                    while (j < code.size && code[j] is CodeLine.Label) {
                        if ((code[j] as CodeLine.Label).name == line.instruction.target) {
                            deleted.add(i)
                            records.add("remove jump #$number")
                            break
                        }
                        j++
                    }
                }
            }
        }
        code = code.filterIndexed {
            i, _ -> i !in deleted
        }.toMutableList()
        val targets = code.mapNotNull {
            if (it is CodeLine.Code && it.instruction.kind in listOf("goto", "if")) it.instruction.target else null
        }.toSet()
        function.code = code.filter {
            if (it is CodeLine.Label && it.name !in targets) {
                records.add("remove label " + it.name)
                false
            } else true
        }
        return records
    }
}
