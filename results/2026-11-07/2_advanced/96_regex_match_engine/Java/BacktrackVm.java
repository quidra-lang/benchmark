import java.util.*;
final class BacktrackVm implements Main.Searcher {
    static final class TooManySteps extends RuntimeException {}
    record State(int pc, int position, int[] captures, BitSet visited) {}
    record Found(int[] captures, int position) {}
    List<Main.Instruction> program;
    String flags, text;
    int groups, steps;
    boolean full;
    BacktrackVm(List<Main.Instruction> program, String flags, int groups, String text,
                boolean full) {
        this.program = program;
        this.flags = flags;
        this.groups = groups;
        this.text = text;
        this.full = full;
    }
    Found execute(int initialPc, int start, int[] captures, boolean partial) {
        Deque<State> stack = new ArrayDeque<>();
        stack.push(new State(initialPc, start, captures.clone(), new BitSet()));
        while (!stack.isEmpty()) {
            State state = stack.pop();
            int pc = state.pc(), position = state.position();
            int[] stored = state.captures();
            BitSet visited = state.visited();
            boolean failed = false;
            while (!failed) {
                if (++steps > 200000)
                    throw new TooManySteps();
                Main.Instruction instruction = program.get(pc);
                switch (instruction.op()) {
                case CHAR, ANY, CLASS -> {
                    if (!Main.matchesCharacter(instruction, text, position, flags)) {
                        failed = true;
                        break;
                    }
                    pc++;
                    position++;
                    visited = new BitSet();
                }
                case SPLIT -> {
                    if (visited.get(pc)) {
                        failed = true;
                        break;
                    }
                    visited.set(pc);
                    stack.push(new State(instruction.y(), position, stored.clone(),
                                         (BitSet)visited.clone()));
                    pc = instruction.x();
                }
                case JMP -> pc = instruction.x();
                case SAVE -> {
                    stored[instruction.value()] = position;
                    pc++;
                }
                case ASSERT -> {
                    if (Charset.assertion(instruction.kind(), text, position, flags))
                        pc++;
                    else
                        failed = true;
                }
                case BACKREF -> {
                    int first = stored[2 * instruction.value()],
                        last = stored[2 * instruction.value() + 1];
                    if (first < 0 || last < 0 || first > last ||
                        position + last - first > text.length()) {
                        failed = true;
                        break;
                    }
                    boolean equal = true;
                    for (int i = 0; i < last - first; i++)
                        if (!Charset.equal(text.charAt(position + i), text.charAt(first + i),
                                           flags)) {
                            equal = false;
                            break;
                        }
                    if (!equal) {
                        failed = true;
                        break;
                    }
                    position += last - first;
                    pc++;
                    if (last > first)
                        visited = new BitSet();
                }
                case LOOK -> {
                    Found found = execute(pc + 1, position, stored, true);
                    if (instruction.kind().equals("NOT")) {
                        if (found != null) {
                            failed = true;
                            break;
                        }
                    } else {
                        if (found == null) {
                            failed = true;
                            break;
                        }
                        stored = found.captures();
                        if (instruction.kind().equals("ATOMIC")) {
                            if (found.position() > position)
                                visited = new BitSet();
                            position = found.position();
                        }
                    }
                    pc = instruction.x();
                }
                case MATCH -> {
                    if (partial || !full || position == text.length())
                        return new Found(stored, position);
                    failed = true;
                }
                }
            }
        }
        return null;
    }
    public int[] search(int start) {
        int first = full ? 0 : start, last = full ? 0 : text.length();
        for (int position = first; position <= last; position++) {
            int[] captures = new int[2 * groups + 2];
            Arrays.fill(captures, -1);
            Found found = execute(0, position, captures, false);
            if (found != null)
                return found.captures();
        }
        return null;
    }
    public int steps() { return steps; }
}
