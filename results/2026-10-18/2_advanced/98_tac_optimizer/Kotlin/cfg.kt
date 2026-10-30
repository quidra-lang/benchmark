data class Block(val first: Int, val last: Int, val labels: List<String>, val successors: MutableList<Int> = mutableListOf(), val predecessors: MutableList<Int> = mutableListOf())
data class NaturalLoop(val header: Int, val latches: List<Int>, val blocks: Set<Int>, val exits: Set<Int>, val outside: Set<Int>, var depth: Int = 0)
class Graph(function: Function) {
    val instructions = function.instructions
    val blocks = mutableListOf<Block>()
    val owners = IntArray(instructions.size)
    val positions = mutableListOf<Int>()
    val reachable = mutableSetOf<Int>()
    val postorder = mutableListOf<Int>()
    val order: List<Int>
    val dominators: MutableList<Set<Int>>
    val idom: MutableList<Int?>
    val loops = mutableListOf<NaturalLoop>()
    val depths: List<Int>
    init {
        val labels = mutableMapOf<Int, MutableList<String>>()
        val leaders = mutableSetOf(0)
        var index = 0
        for ((lineIndex, line) in function.code.withIndex()) {
            when (line) {
                is CodeLine.Label -> {
                    labels.getOrPut(index) {
                        mutableListOf()
                    }.add(line.name)
                    leaders.add(index)
                }
                is CodeLine.Code -> {
                    positions.add(lineIndex)
                    index++
                    if (line.instruction.kind in listOf("goto", "if", "return") && index < instructions.size) leaders.add(index)
                }
            }
        }
        val starts = leaders.sorted()
        for ((i, first) in starts.withIndex()) {
            val last = if (i + 1 < starts.size) starts[i + 1] - 1 else instructions.lastIndex
            blocks.add(Block(first, last, labels[first] ?: emptyList()))
            for (j in first..last) owners[j] = i
        }
        val labelBlocks = mutableMapOf<String, Int>()
        for ((i, block) in blocks.withIndex()) for (label in block.labels) labelBlocks[label] = i
        for ((i, block) in blocks.withIndex()) {
            val instruction = instructions[block.last]
            when (instruction.kind) {
                "goto" -> block.successors.add(labelBlocks.getValue(instruction.target))
                "if" -> {
                    block.successors.add(i + 1)
                    val target = labelBlocks.getValue(instruction.target)
                    if (target != i + 1) block.successors.add(target)
                }
                "return" -> Unit
                else -> block.successors.add(i + 1)
            }
        }
        for ((i, block) in blocks.withIndex()) for (j in block.successors) blocks[j].predecessors.add(i)
        visit(0)
        order = postorder.reversed()
        dominators = blocks.indices.map {
            if (it == 0) setOf(0) else reachable.toSet()
        }.toMutableList()
        idom = MutableList(blocks.size) {
            null
        }
        while (true) {
            var changed = false
            for (b in order.drop(1)) {
                var set = reachable.toSet()
                for (p in blocks[b].predecessors.filter {
                    it in reachable
                }) set = set.intersect(dominators[p])
                set = set + b
                if (set != dominators[b]) {
                    dominators[b] = set
                    changed = true
                }
            }
            if (!changed) break
        }
        for (b in order.drop(1)) idom[b] = (dominators[b] - b).sortedWith(compareByDescending<Int> {
            dominators[it].size
        }.thenBy {
            it
        }).first()
        for (h in reachable.sorted()) {
            val latches = reachable.filter {
                h in blocks[it].successors && h in dominators[it]
            }.sorted()
            if (latches.isEmpty()) continue
            val members = mutableSetOf(h)
            val pending = latches.toMutableList()
            while (pending.isNotEmpty()) {
                val b = pending.removeAt(pending.lastIndex)
                if (b == h || !members.add(b)) continue
                pending.addAll(blocks[b].predecessors.filter {
                    it in reachable
                })
            }
            val exits = mutableSetOf<Int>()
            val outside = mutableSetOf<Int>()
            for (b in members) {
                if (instructions[blocks[b].last].kind == "return") exits.add(b)
                for (s in blocks[b].successors) {
                    if (s !in members) {
                        exits.add(b)
                        outside.add(s)
                    }
                }
            }
            loops.add(NaturalLoop(h, latches, members.toSet(), exits.toSet(), outside.toSet()))
        }
        depths = blocks.indices.map {
            b -> loops.count {
                b in it.blocks
            }
        }
        for (loop in loops) loop.depth = loops.count {
            loop.header in it.blocks
        }
    }
    fun visit(b: Int) {
        reachable.add(b)
        for (s in blocks[b].successors) if (s !in reachable) visit(s)
        postorder.add(b)
    }
}
