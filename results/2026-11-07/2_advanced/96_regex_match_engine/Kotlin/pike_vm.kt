class Threads {
    val sequence = mutableListOf<Pair<Int, Capture>>();
    val marks = mutableSetOf<Int>()
}
class Pike(val code: List<Instruction>, val subject: List<Int>, val flags: Flags, val groups: Int, val full: Boolean) {
    var steps = 0
    fun add(list: Threads, pc: Int, capture: Capture, position: Int) {
        if (!list.marks.add(pc)) return
        steps++
        when (val instruction = code[pc]) {
            is Instruction.Jump -> add(list, instruction.target, capture, position)
            is Instruction.Split -> {
                add(list, instruction.x, capture, position);
                add(list, instruction.y, capture, position)
            }
            is Instruction.Save -> {
                val changed = capture.toMutableList();
                changed[instruction.slot] = position;
                add(list, pc + 1, changed, position)
            }
            is Instruction.Assert -> if (Charset.assertion(instruction.kind, subject, position, flags)) add(list, pc + 1, capture, position)
            else -> list.sequence.add(Pair(pc, capture.toList()))
        }
    }
    fun search(start: Int): Capture? {
        var matched: Capture? = null;
        var list = Threads();
        var position = start
        while (true) {
            if (matched == null && (!full || position == start)) add(list, 0, List(2 * groups + 2) {
                null
            }, position)
            val next = Threads()
            for ((pc, capture) in list.sequence) {
                steps++;
                if (code[pc] == Instruction.Match) {
                    if (!full || position == subject.size) {
                        matched = capture.toList();
                        break
                    }
                } else if (consumes(code[pc], subject, position, flags)) add(next, pc + 1, capture, position + 1)
            }
            if (position == subject.size || next.sequence.isEmpty() && (matched != null || full)) return matched
            list = next;
            position++
        }
    }
}
