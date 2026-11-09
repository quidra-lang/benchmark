data class DefinitionKey(val variable: String, val number: Int)
data class CopyKey(val destination: String, val source: String)
data class FlowSets<T>(val input: MutableList<Set<T>>, val output: MutableList<Set<T>>, var iterations: Int = 0)
object Transfer {
    fun definitions(set: Set<DefinitionKey>, instruction: Instruction, number: Int): Set<DefinitionKey> {
        val x = instruction.destination ?: return set
        return set.filter {
            it.variable != x
        }.toSet() + DefinitionKey(x, number)
    }
    fun live(set: Set<String>, instruction: Instruction): Set<String> = (if (instruction.destination == null) set else set - instruction.destination!!) + instruction.used
    fun expressions(original: Set<TacExpression>, instruction: Instruction): Set<TacExpression> {
        var set = original
        instruction.expression?.let {
            set = set + it
        }
        if (instruction.kind == "store") set = set.filter {
            it.kind != "load" || it.operation != instruction.array
        }.toSet()
        if (instruction.kind == "call") set = set.filter {
            it.kind != "load"
        }.toSet()
        instruction.destination?.let {
            x -> set = set.filter {
                !it.uses(x)
            }.toSet()
        }
        return set
    }
    fun copies(original: Set<CopyKey>, instruction: Instruction): Set<CopyKey> {
        val x = instruction.destination ?: return original
        var set = original.filter {
            it.destination != x && it.source != x
        }.toSet()
        val y = instruction.a?.variable
        if (instruction.kind == "copy" && y != null && y != x) set = set + CopyKey(x, y)
        return set
    }
}
class Analysis(function: Function, graph: Graph) {
    val definitions: FlowSets<DefinitionKey>
    val live: FlowSets<String>
    val expressions: FlowSets<TacExpression>
    val copies: FlowSets<CopyKey>
    val beforeDefinitions = MutableList<Set<DefinitionKey>>(graph.instructions.size) {
        emptySet()
    }
    val beforeExpressions = MutableList<Set<TacExpression>>(graph.instructions.size) {
        emptySet()
    }
    val beforeCopies = MutableList<Set<CopyKey>>(graph.instructions.size) {
        emptySet()
    }
    val beforeLive = MutableList<Set<String>>(graph.instructions.size) {
        emptySet()
    }
    val afterLive = MutableList<Set<String>>(graph.instructions.size) {
        emptySet()
    }
    init {
        val count = graph.blocks.size
        val reachableInstructions = graph.instructions.indices.filter {
            graph.owners[it] in graph.reachable
        }
        val universe = reachableInstructions.mapNotNull {
            graph.instructions[it].expression
        }.toSet()
        val copyUniverse = reachableInstructions.mapNotNull {
            i -> val instruction = graph.instructions[i]
            val x = instruction.destination
            val y = instruction.a?.variable
            if (instruction.kind == "copy" && x != null && y != null && x != y) CopyKey(x, y) else null
        }.toSet()
        definitions = FlowSets(MutableList(count) {
            emptySet()
        }, MutableList(count) {
            emptySet()
        })
        live = FlowSets(MutableList(count) {
            emptySet()
        }, MutableList(count) {
            emptySet()
        })
        expressions = FlowSets(MutableList(count) {
            emptySet()
        }, MutableList(count) {
            universe
        })
        copies = FlowSets(MutableList(count) {
            emptySet()
        }, MutableList(count) {
            copyUniverse
        })
        while (true) {
            definitions.iterations++
            var changed = false
            for (b in graph.order) {
                var set = if (b == 0) function.parameters.map {
                    DefinitionKey(it, 0)
                }.toSet() else emptySet()
                for (p in graph.blocks[b].predecessors.filter {
                    it in graph.reachable
                }) set = set + definitions.output[p]
                definitions.input[b] = set
                for (i in graph.blocks[b].first..graph.blocks[b].last) set = Transfer.definitions(set, graph.instructions[i], i + 1)
                if (definitions.output[b] != set) changed = true
                definitions.output[b] = set
            }
            if (!changed) break
        }
        while (true) {
            live.iterations++
            var changed = false
            for (b in graph.postorder) {
                var set = graph.blocks[b].successors.flatMap {
                    live.input[it]
                }.toSet()
                live.output[b] = set
                for (i in graph.blocks[b].last downTo graph.blocks[b].first) set = Transfer.live(set, graph.instructions[i])
                if (set != live.input[b]) changed = true
                live.input[b] = set
            }
            if (!changed) break
        }
        available(expressions, graph, universe, Transfer::expressions)
        available(copies, graph, copyUniverse, Transfer::copies)
        for (b in graph.reachable) {
            var d = definitions.input[b]
            var e = expressions.input[b]
            var c = copies.input[b]
            for (i in graph.blocks[b].first..graph.blocks[b].last) {
                beforeDefinitions[i] = d
                beforeExpressions[i] = e
                beforeCopies[i] = c
                d = Transfer.definitions(d, graph.instructions[i], i + 1)
                e = Transfer.expressions(e, graph.instructions[i])
                c = Transfer.copies(c, graph.instructions[i])
            }
            var l = live.output[b]
            for (i in graph.blocks[b].last downTo graph.blocks[b].first) {
                afterLive[i] = l
                l = Transfer.live(l, graph.instructions[i])
                beforeLive[i] = l
            }
        }
    }
    fun <T> available(result: FlowSets<T>, graph: Graph, universe: Set<T>, transfer: (Set<T>, Instruction) -> Set<T>) {
        while (true) {
            result.iterations++
            var changed = false
            for (b in graph.order) {
                var set = if (b == 0) emptySet() else universe
                if (b != 0) {
                    for (p in graph.blocks[b].predecessors.filter {
                        it in graph.reachable
                    }) set = set.intersect(result.output[p])
                }
                result.input[b] = set
                for (i in graph.blocks[b].first..graph.blocks[b].last) set = transfer(set, graph.instructions[i])
                if (set != result.output[b]) changed = true
                result.output[b] = set
            }
            if (!changed) return
        }
    }
}
