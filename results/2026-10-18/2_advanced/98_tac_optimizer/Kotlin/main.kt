import java.io.File
val passNames = listOf("constprop", "copyprop", "cse", "dce", "licm", "unreachable")
val kinds = listOf("copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print")
fun list(values: List<String>): String = if (values.isEmpty()) "-" else values.joinToString(",")
fun blockList(values: List<Int>): String = list(values.map {
    "B${it + 1}"
})
fun numbers(values: List<Int>): String = list(values.map {
    "#${it + 1}"
})
fun constant(instructions: List<Instruction>, definitions: Set<DefinitionKey>, variable: String): Long? {
    val numbers = definitions.filter {
        it.variable == variable
    }.map {
        it.number
    }
    if (numbers.isEmpty() || 0 in numbers) return null
    var value: Long? = null
    for (number in numbers) {
        val instruction = instructions[number - 1]
        if (instruction.kind != "copy") return null
        val current = instruction.a?.constant ?: return null
        if (value != null && value != current) return null
        value = current
    }
    return value
}
fun propagate(function: Function, graph: Graph, analysis: Analysis, constants: Boolean): Pair<Int, List<String>> {
    val instructions = graph.instructions
    val replacements = mutableMapOf<Int, List<Instruction>>()
    val records = mutableListOf<String>()
    for ((i, original) in instructions.withIndex()) {
        if (graph.owners[i] !in graph.reachable) continue
        val instruction = original.copy()
        for (field in 0..1) {
            val operand = if (field == 0) instruction.a else instruction.b
            val variable = operand?.variable ?: continue
            val replacement = if (constants) constant(instructions, analysis.beforeDefinitions[i], variable)?.let {
                Operand.Constant(it)
            } else analysis.beforeCopies[i].firstOrNull {
                it.destination == variable
            }?.let {
                Operand.Variable(it.source)
            }
            if (replacement != null) {
                records.add("#${i + 1}: $variable -> ${replacement.text}")
                if (field == 0) instruction.a = replacement else instruction.b = replacement
            }
        }
        if (constants) {
            when (val folded = Optimizations.fold(instruction)) {
                FoldResult.Deleted -> {
                    records.add("#${i + 1}: delete ${instruction.text}")
                    replacements[i] = emptyList()
                    continue
                }
                is FoldResult.Replacement -> {
                    records.add("#${i + 1}: fold ${folded.instruction.text}")
                    replacements[i] = listOf(folded.instruction)
                    continue
                }
                FoldResult.Unchanged -> Unit
            }
        }
        replacements[i] = listOf(instruction)
    }
    Optimizations.rewrite(function, replacements)
    return records.size to records
}
fun cse(function: Function, graph: Graph, analysis: Analysis): Pair<Int, List<String>> {
    val instructions = graph.instructions
    val groups = mutableMapOf<TacExpression, MutableList<Int>>()
    for ((i, instruction) in instructions.withIndex()) {
        if (graph.owners[i] in graph.reachable) {
            val expression = instruction.expression
            if (expression != null && expression in analysis.beforeExpressions[i]) groups.getOrPut(expression) {
                mutableListOf()
            }.add(i)
        }
    }
    val replacements = mutableMapOf<Int, List<Instruction>>()
    val records = mutableListOf<String>()
    var count = 0
    for ((expression, candidates) in groups.entries.sortedBy {
        it.value[0]
    }) {
        val sources = mutableSetOf<Int>()
        for (candidate in candidates) {
            val block = graph.owners[candidate]
            val first = graph.blocks[block].first
            val source = (candidate - 1 downTo first).firstOrNull {
                instructions[it].expression == expression
            }
            if (source != null) {
                sources.add(source)
                continue
            }
            val pending = graph.blocks[block].predecessors.filter {
                it in graph.reachable
            }.toMutableList()
            val seen = mutableSetOf<Int>()
            while (pending.isNotEmpty()) {
                val current = pending.removeAt(pending.lastIndex)
                if (!seen.add(current)) continue
                val found = (graph.blocks[current].last downTo graph.blocks[current].first).firstOrNull {
                    instructions[it].expression == expression
                }
                if (found != null) sources.add(found) else pending.addAll(graph.blocks[current].predecessors.filter {
                    it in graph.reachable
                })
            }
        }
        sources.removeAll(candidates.toSet())
        val temporary = Optimizations.temporary(function)
        for (source in sources) replacements[source] = Optimizations.cseRewrite(instructions[source], temporary, true)
        for (candidate in candidates) replacements[candidate] = Optimizations.cseRewrite(instructions[candidate], temporary, false)
        records.add("${expression.text}: $temporary sources=${numbers(sources.sorted())} replaced=${numbers(candidates)}")
        count += candidates.size
    }
    Optimizations.rewrite(function, replacements)
    return count to records
}
fun dce(function: Function, graph: Graph, analysis: Analysis): Pair<Int, List<String>> {
    val replacements = mutableMapOf<Int, List<Instruction>>()
    val records = mutableMapOf<Int, String>()
    for (b in graph.reachable.sorted()) {
        var live = analysis.live.output[b]
        for (i in graph.blocks[b].last downTo graph.blocks[b].first) {
            val instruction = graph.instructions[i].copy()
            val selfCopy = instruction.kind == "copy" && instruction.destination == instruction.a?.variable
            val dead = instruction.kind in listOf("copy", "bin", "load") && instruction.destination?.let {
                it !in live
            } == true
            if (selfCopy || dead) {
                replacements[i] = emptyList()
                records[i] = "#${i + 1}: delete ${instruction.text}"
                continue
            }
            val x = instruction.destination
            if (instruction.kind == "call" && x != null && x !in live) {
                records[i] = "#${i + 1}: unused result ${instruction.text}"
                instruction.destination = null
                replacements[i] = listOf(instruction)
            }
            live = Transfer.live(live, instruction)
        }
    }
    Optimizations.rewrite(function, replacements)
    val lines = records.keys.sorted().map {
        records.getValue(it)
    }
    return lines.size to lines
}
fun licm(function: Function, graph: Graph, analysis: Analysis): Pair<Int, List<String>> {
    val instructions = graph.instructions
    for (loop in graph.loops.sortedWith(compareBy<NaturalLoop> {
        it.blocks.size
    }.thenBy {
        it.header
    })) {
        fun inside(number: Int): Boolean = number != 0 && graph.owners[number - 1] in loop.blocks
        val indices = instructions.indices.filter {
            graph.owners[it] in loop.blocks
        }
        val marked = mutableSetOf<Int>()
        val order = mutableListOf<Int>()
        while (true) {
            var changed = false
            for (i in indices) {
                val instruction = instructions[i]
                if (i in marked || instruction.kind !in listOf("copy", "bin", "load")) continue
                if (instruction.kind == "load" && indices.any {
                    instructions[it].kind == "call" || instructions[it].kind == "store" && instructions[it].array == instruction.array
                }) continue
                val invariant = instruction.used.all {
                    variable -> val definitions = analysis.beforeDefinitions[i].filter {
                        it.variable == variable
                    }.map {
                        it.number
                    }
                    definitions.all {
                        !inside(it)
                    } || definitions.size == 1 && inside(definitions[0]) && definitions[0] - 1 in marked
                }
                if (invariant) {
                    marked.add(i)
                    order.add(i)
                    changed = true
                }
            }
            if (!changed) break
        }
        val moved = mutableListOf<Int>()
        val movedSet = mutableSetOf<Int>()
        for (i in order) {
            val instruction = instructions[i]
            val destination = instruction.destination!!
            if (indices.count {
                instructions[it].destination == destination
            } != 1 || destination in analysis.live.input[loop.header]) continue
            val block = graph.owners[i]
            val dominatesExits = loop.exits.all {
                block in graph.dominators[it]
            }
            val dangerous = instruction.kind == "load" || instruction.kind == "bin" && instruction.operation in listOf("/", "%") && (instruction.b?.constant == null || instruction.b?.constant == 0L)
            val safe = !dangerous && loop.outside.all {
                destination !in analysis.live.input[it]
            }
            if (!dominatesExits && !safe) continue
            if (!instruction.used.all {
                variable -> analysis.beforeDefinitions[i].filter {
                    it.variable == variable && inside(it.number)
                }.all {
                    it.number - 1 in movedSet
                }
            }) continue
            moved.add(i)
            movedSet.add(i)
        }
        if (moved.isNotEmpty()) {
            val target = Optimizations.hoist(function, graph, loop, moved)
            return moved.size to listOf("B${loop.header + 1}: hoist ${numbers(moved)} to $target")
        }
    }
    return 0 to emptyList()
}
fun pass(name: String, function: Function): Pair<Int, List<String>> {
    val graph = Graph(function)
    val analysis = Analysis(function, graph)
    return when (name) {
        "constprop" -> propagate(function, graph, analysis, true)
        "copyprop" -> propagate(function, graph, analysis, false)
        "cse" -> cse(function, graph, analysis)
        "dce" -> dce(function, graph, analysis)
        "licm" -> licm(function, graph, analysis)
        else -> {
            val records = Optimizations.unreachable(function, graph)
            records.size to records
        }
    }
}
fun reach(start: Int, edges: List<List<Int>>): Set<Int> {
    val pending = mutableListOf(start)
    val seen = mutableSetOf<Int>()
    while (pending.isNotEmpty()) {
        val i = pending.removeAt(pending.lastIndex)
        if (seen.add(i)) pending.addAll(edges[i])
    }
    return seen
}
data class Calls(val edges: List<List<Int>>, val reachable: Set<Int>)
fun callGraph(program: Program): Calls {
    val indices = program.functions.mapIndexed {
        i, f -> f.name to i
    }.toMap()
    val edges = program.functions.map {
        function -> function.instructions.filter {
            it.kind == "call"
        }.map {
            indices.getValue(it.function)
        }.toSet().sorted()
    }
    return Calls(edges, reach(indices.getValue("main"), edges))
}
fun graphReport(program: Program, graph: Calls, label: String): List<String> {
    val lines = mutableListOf("== call graph ($label) ==")
    for ((i, function) in program.functions.withIndex()) {
        val recursive = graph.edges[i].any {
            i in reach(it, graph.edges)
        }
        lines.add("${function.name} -> ${list(graph.edges[i].map { program.functions[it].name })}" + if (recursive) " (recursive)" else "")
    }
    lines.add("unreachable functions: " + list(program.functions.indices.filter {
        it !in graph.reachable
    }.map {
        program.functions[it].name
    }))
    return lines
}
fun definitionList(set: Set<DefinitionKey>): String = list(set.sortedWith(compareBy<DefinitionKey> {
    it.number
}.thenBy {
    it.variable
}).map {
    "${it.variable}:${it.number}"
})
fun analysisReport(function: Function, label: String): List<String> {
    val graph = Graph(function)
    val analysis = Analysis(function, graph)
    val lines = mutableListOf("== ${function.name} ($label) ==", "code:")
    var number = 0
    for (line in function.code) {
        when (line) {
            is CodeLine.Label -> lines.add(line.name + ":")
            is CodeLine.Code -> {
                val instruction = line.instruction
                var text = "  #${number + 1} ${instruction.text}"
                if (graph.owners[number] in graph.reachable) {
                    val chains = instruction.used.distinct().map {
                        variable -> variable + ":" + list(analysis.beforeDefinitions[number].filter {
                            it.variable == variable
                        }.map {
                            it.number
                        }.sorted().map(Int::toString))
                    }
                    if (chains.isNotEmpty()) text += " | " + chains.joinToString(" ")
                }
                lines.add(text)
                number++
            }
        }
    }
    lines.add("blocks: ${graph.blocks.size}")
    for ((b, block) in graph.blocks.withIndex()) lines.add("B${b + 1} ${block.first + 1}-${block.last + 1} labels=${list(block.labels)} preds=${blockList(block.predecessors)} succs=${blockList(block.successors)}")
    lines.addAll(listOf("unreachable: " + blockList(graph.blocks.indices.filter {
        it !in graph.reachable
    }), "order: " + blockList(graph.order), "dominators:"))
    for (b in graph.reachable.sorted()) lines.add("B${b + 1} idom=${graph.idom[b]?.let { "B${
        it + 1
    }" } ?: "-"} dom=${blockList(graph.dominators[b].sorted())}")
    lines.add("dominator tree:")
    fun tree(block: Int, depth: Int) {
        lines.add(" ".repeat(depth * 2) + "B${block + 1}")
        for (b in graph.blocks.indices) if (graph.idom[b] == block) tree(b, depth + 1)
    }
    tree(0, 0)
    lines.add("loops: ${graph.loops.size}")
    for (loop in graph.loops) lines.add("header=B${loop.header + 1} latches=${blockList(loop.latches)} depth=${loop.depth} blocks=${blockList(loop.blocks.sorted())} exits=${blockList(loop.exits.sorted())}")
    lines.add("reaching definitions: iterations=${analysis.definitions.iterations}")
    for (b in graph.reachable.sorted()) lines.add("B${b + 1} in=${definitionList(analysis.definitions.input[b])} out=${definitionList(analysis.definitions.output[b])}")
    lines.add("liveness: iterations=${analysis.live.iterations}")
    for (b in graph.reachable.sorted()) lines.add("B${b + 1} in=${list(analysis.live.input[b].sorted())} out=${list(analysis.live.output[b].sorted())}")
    lines.add("available expressions: iterations=${analysis.expressions.iterations}")
    for (b in graph.reachable.sorted()) lines.add("B${b + 1} in=${list(analysis.expressions.input[b].map { it.text }.sorted())} out=${list(analysis.expressions.output[b].map { it.text }.sorted())}")
    return lines
}
fun allocate(function: Function, registers: Int, output: MutableList<String>): Function {
    val graph = Graph(function)
    val analysis = Analysis(function, graph)
    val allocation = Regalloc.allocate(function, graph, analysis, registers)
    fun rewrite(name: String): String = allocation.registers[name]?.let {
        "R$it"
    } ?: name
    fun operand(value: Operand?): Operand? = value?.let {
        if (it.variable != null) Operand.Variable(rewrite(it.variable!!)) else it
    }
    var moves = 0
    val allocated = function.copy(parameters = function.parameters.map(::rewrite), code = function.code.mapNotNull {
        line ->
        if (line is CodeLine.Label) line else {
            val original = (line as CodeLine.Code).instruction
            val instruction = original.copy(destination = original.destination?.let(::rewrite), a = operand(original.a), b = operand(original.b))
            if (instruction.kind == "copy" && instruction.destination == instruction.a?.variable) {
                moves++
                null
            } else CodeLine.Code(instruction)
        }
    })
    val spillUses = graph.instructions.sumOf {
        instruction -> instruction.used.count {
            it in allocation.spills
        }
    }
    val spillDefinitions = function.parameters.count {
        it in allocation.spills
    } + graph.instructions.count {
        instruction -> instruction.destination?.let {
            it in allocation.spills
        } == true
    }
    val pressure = graph.instructions.indices.filter {
        graph.owners[it] in graph.reachable
    }.maxOfOrNull {
        maxOf(analysis.beforeLive[it].size, analysis.afterLive[it].size)
    } ?: 0
    output.addAll(listOf("== ${function.name} ==", "nodes=${allocation.nodes.size} edges=${allocation.neighbors.values.sumOf { it.size } / 2} registers=$registers"))
    for (node in allocation.nodes) {
        val neighbors = allocation.neighbors.getValue(node)
        output.add("$node degree=${neighbors.size} cost=${allocation.costs.getValue(node)} neighbors=${list(neighbors.sorted())}")
    }
    output.addAll(listOf("simplify: " + list(allocation.order), "potential spills: " + list(allocation.potential.map {
        "${it.first}(${allocation.costs.getValue(it.first)}/${it.second})"
    })))
    for (node in allocation.nodes) output.add("$node -> " + (allocation.registers[node]?.let {
        "R$it"
    } ?: "spill"))
    output.add("summary: pressure=$pressure used=${allocation.registers.values.toSet().size} spilled=${allocation.spills.size} moves=$moves spill_uses=$spillUses spill_defs=$spillDefinitions")
    output.addAll(allocated.text)
    return allocated
}
class Execution(val program: Program, val input: List<Long>) {
    val arrays = program.arrays.associate {
        it.first to LongArray(it.second)
    }
    var position = 0
    val output = mutableListOf<Long>()
    val steps = mutableMapOf<String, Int>()
    val calls = mutableMapOf<String, Int>()
    val counts = kinds.associateWith {
        0
    }.toMutableMap()
    fun call(name: String, arguments: List<Long>): Long? {
        calls[name] = (calls[name] ?: 0) + 1
        val function = program.functions.first {
            it.name == name
        }
        val instructions = function.instructions
        val labels = TacParser.labels(function)
        val values = function.parameters.zip(arguments).toMap().toMutableMap()
        val pushed = mutableListOf<Long>()
        var pc = 0
        fun value(operand: Operand): Long = operand.constant ?: values.getValue(operand.variable!!)
        while (true) {
            val instruction = instructions[pc]
            steps[name] = (steps[name] ?: 0) + 1
            counts[instruction.kind] = counts.getValue(instruction.kind) + 1
            var next = pc + 1
            var result: Long? = null
            val a = instruction.a?.let(::value)
            val b = instruction.b?.let(::value)
            when (instruction.kind) {
                "copy" -> result = a
                "bin" -> result = TacParser.operation(instruction.operation, a!!, b!!)
                "load" -> result = arrays.getValue(instruction.array)[a!!.toInt()]
                "store" -> arrays.getValue(instruction.array)[a!!.toInt()] = b!!
                "goto" -> next = labels.getValue(instruction.target)
                "if" -> if (TacParser.operation(instruction.operation, a!!, b!!) != 0L) next = labels.getValue(instruction.target)
                "param" -> pushed.add(a!!)
                "call" -> {
                    val arguments = pushed.takeLast(instruction.count)
                    pushed.subList(pushed.size - instruction.count, pushed.size).clear()
                    result = call(instruction.function, arguments)
                }
                "return" -> return a
                "read" -> result = input[position++]
                else -> output.add(a!!)
            }
            if (instruction.destination != null && result != null) values[instruction.destination!!] = result
            pc = next
        }
    }
}
fun kindCounts(program: Program): Map<String, Int> {
    val counts = kinds.associateWith {
        0
    }.toMutableMap()
    for (function in program.functions) for (instruction in function.instructions) counts[instruction.kind] = counts.getValue(instruction.kind) + 1
    return counts
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val original = TacParser.parse(File("input/program.tac").readText())
    val settings = File("input/params.txt").readLines().map {
        it.split(' ')
    }
    val registers = settings[0][1].toInt()
    val enabled = passNames.filter {
        it in settings[1].drop(1)
    }
    val maxRounds = settings[2][1].toInt()
    val optimized = Program(original.arrays, original.functions.map {
        it.deepCopy()
    })
    val passes = mutableListOf<String>()
    val totals = enabled.associateWith {
        0
    }.toMutableMap()
    for (function in optimized.functions) {
        val before = function.instructions.size
        passes.add("== ${function.name} ==")
        var performed = 0
        for (round in 1..maxRounds) {
            performed = round
            val changes = mutableListOf<String>()
            val records = mutableListOf<String>()
            var changed = false
            for (name in enabled) {
                val (count, entries) = pass(name, function)
                if (count > 0) changed = true
                changes.add("$name=$count")
                totals[name] = totals.getValue(name) + count
                records.addAll(entries.map {
                    "  $name $it"
                })
            }
            passes.add("round $round: " + changes.joinToString(" "))
            passes.addAll(records)
            if (!changed) break
        }
        passes.add("result: rounds=$performed instructions=$before->${function.instructions.size}")
    }
    val optimizedGraph = callGraph(optimized)
    val analysisLines = graphReport(original, callGraph(original), "original").toMutableList()
    for (function in original.functions) analysisLines.addAll(analysisReport(function, "original"))
    analysisLines.addAll(graphReport(optimized, optimizedGraph, "optimized"))
    val removed = if ("unreachable" in enabled) optimized.functions.indices.filter {
        it !in optimizedGraph.reachable
    }.map {
        optimized.functions[it].name
    } else emptyList()
    optimized.functions = optimized.functions.filter {
        it.name !in removed
    }
    for (function in optimized.functions) analysisLines.addAll(analysisReport(function, "optimized"))
    passes.addAll(listOf("== program ==", "removed functions: " + list(removed), "== total ==", enabled.joinToString(" ") {
        "$it=${totals.getValue(it)}"
    }))
    val allocationLines = mutableListOf<String>()
    val allocated = Program(optimized.arrays, optimized.functions.map {
        allocate(it, registers, allocationLines)
    })
    val runs = File("input/input.txt").readLines().drop(1).map {
        line -> line.split(' ').drop(1).map(String::toLong)
    }
    val programs = listOf(original, optimized, allocated)
    val labels = listOf("original", "optimized", "allocated")
    val comparison = mutableListOf<String>()
    var same = 0
    val totalSteps = IntArray(3)
    val profileSteps = List(3) {
        mutableMapOf<String, Int>()
    }
    val profileCalls = mutableMapOf<String, Int>()
    val dynamicCounts = List(3) {
        kinds.associateWith {
            0
        }.toMutableMap()
    }
    for ((i, input) in runs.withIndex()) {
        comparison.add("run ${i + 1}: inputs=${input.size}")
        val outputs = mutableListOf<List<Long>>()
        for (p in 0..2) {
            val execution = Execution(programs[p], input)
            execution.call("main", emptyList())
            val steps = execution.steps.values.sum()
            val calls = execution.calls.values.sum()
            comparison.add("  ${labels[p]}: steps=$steps calls=$calls output=${list(execution.output.map(Long::toString))}")
            outputs.add(execution.output.toList())
            totalSteps[p] += steps
            for ((name, count) in execution.steps) profileSteps[p][name] = (profileSteps[p][name] ?: 0) + count
            if (p == 0) {
                for ((name, count) in execution.calls) profileCalls[name] = (profileCalls[name] ?: 0) + count
            }
            for (kind in kinds) dynamicCounts[p][kind] = dynamicCounts[p].getValue(kind) + execution.counts.getValue(kind)
        }
        val equal = outputs[0] == outputs[1] && outputs[0] == outputs[2]
        if (equal) same++
        comparison.add("  result: " + if (equal) "same" else "different")
    }
    comparison.add("== profile ==")
    for (function in original.functions) {
        val name = function.name
        comparison.add("$name: calls=${profileCalls[name] ?: 0} original=${profileSteps[0][name] ?: 0} optimized=${profileSteps[1][name] ?: 0} allocated=${profileSteps[2][name] ?: 0}")
    }
    val before = kindCounts(original)
    val after = kindCounts(optimized)
    comparison.addAll(listOf("== summary ==", "runs=${runs.size} same=$same different=${runs.size - same}", "instructions: original=${before.values.sum()} optimized=${after.values.sum()}", "kinds: " + kinds.joinToString(" ") {
        "$it=${before.getValue(it)}->${after.getValue(it)}"
    }, "steps: original=${totalSteps[0]} optimized=${totalSteps[1]} allocated=${totalSteps[2]}"))
    for (p in 0..2) comparison.add("dynamic ${labels[p]}: " + kinds.joinToString(" ") {
        "$it=${dynamicCounts[p].getValue(it)}"
    })
    write("optimized.tac", optimized.text)
    write("analysis.txt", analysisLines)
    write("passes.txt", passes)
    write("regalloc.txt", allocationLines)
    write("comparison.txt", comparison)
}
