data class BacktrackState(var pc: Int, var position: Int, var capture: MutableList<Int?>, var splits: MutableSet<Int>)
class StepLimit : Exception()
class Backtrack(val code: List<Instruction>, val subject: List<Int>, val flags: Flags, val groups: Int, val full: Boolean) {
    var steps = 0
    fun execute(pc: Int, position: Int, capture: Capture, partial: Boolean): Pair<Capture, Int>? {
        val stack = mutableListOf(BacktrackState(pc, position, capture.toMutableList(), mutableSetOf()))
        while (stack.isNotEmpty()) {
            val state = stack.removeAt(stack.lastIndex)
            path@ while (true) {
                steps++;
                if (steps > 200000) throw StepLimit()
                when (val instruction = code[state.pc]) {
                    is Instruction.Char, Instruction.Any, is Instruction.Class -> {
                        if (!consumes(instruction, subject, state.position, flags)) break@path;
                        state.position++;
                        state.pc++;
                        state.splits.clear()
                    }
                    is Instruction.Split -> {
                        if (!state.splits.add(state.pc)) break@path;
                        stack.add(BacktrackState(instruction.y, state.position, state.capture.toMutableList(), state.splits.toMutableSet()));
                        state.pc = instruction.x
                    }
                    is Instruction.Jump -> state.pc = instruction.target
                    is Instruction.Save -> {
                        state.capture[instruction.slot] = state.position;
                        state.pc++
                    }
                    is Instruction.Assert -> {
                        if (!Charset.assertion(instruction.kind, subject, state.position, flags)) break@path;
                        state.pc++
                    }
                    is Instruction.Backref -> {
                        val a = state.capture[2 * instruction.group];
                        val b = state.capture[2 * instruction.group + 1];
                        if (a == null || b == null || a > b) break@path;
                        val length = b - a
                        if (state.position + length > subject.size || (0 until length).any {
                            !Charset.equal(subject[state.position + it], subject[a + it], flags)
                        }) break@path
                        state.position += length;
                        state.pc++;
                        if (length > 0) state.splits.clear()
                    }
                    is Instruction.Look -> {
                        val result = execute(state.pc + 1, state.position, state.capture, true)
                        if (instruction.kind == "NOT") {
                            if (result != null) break@path;
                            state.pc = instruction.target
                        }
                        else {
                            if (result == null) break@path;
                            state.capture = result.first.toMutableList();
                            if (instruction.kind == "ATOMIC") {
                                if (result.second > state.position) state.splits.clear();
                                state.position = result.second
                            };
                            state.pc = instruction.target
                        }
                    }
                    Instruction.Match -> {
                        if (partial || !full || state.position == subject.size) return Pair(state.capture.toList(), state.position);
                        break@path
                    }
                }
            }
        }
        return null
    }
    fun search(start: Int): Capture? {
        for (b in (if (full) 0 else start)..(if (full) 0 else subject.size)) {
            val result = execute(0, b, List(2 * groups + 2) {
                null
            }, false);
            if (result != null) return result.first
        };
        return null
    }
}
