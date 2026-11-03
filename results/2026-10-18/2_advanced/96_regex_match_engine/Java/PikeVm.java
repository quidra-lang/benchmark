import java.util.*;
final class PikeVm implements Main.Searcher {
    record Thread(int pc, int[] captures) {}
    static final class ThreadList {
        List<Thread> threads = new ArrayList<>();
        BitSet marks = new BitSet();
    }
    List<Main.Instruction> program;
    String flags, text;
    int groups, steps;
    boolean full;
    PikeVm(List<Main.Instruction> program, String flags, int groups, String text, boolean full) {
        this.program = program;
        this.flags = flags;
        this.groups = groups;
        this.text = text;
        this.full = full;
    }
    void add(ThreadList list, int pc, int[] captures, int position) {
        Deque<Thread> pending = new ArrayDeque<>();
        pending.push(new Thread(pc, captures));
        while (!pending.isEmpty()) {
            Thread thread = pending.pop();
            int current = thread.pc();
            if (list.marks.get(current))
                continue;
            list.marks.set(current);
            steps++;
            Main.Instruction instruction = program.get(current);
            switch (instruction.op()) {
            case JMP -> pending.push(new Thread(instruction.x(), thread.captures()));
            case SPLIT -> {
                pending.push(new Thread(instruction.y(), thread.captures()));
                pending.push(new Thread(instruction.x(), thread.captures()));
            }
            case SAVE -> {
                int[] updated = thread.captures().clone();
                updated[instruction.value()] = position;
                pending.push(new Thread(current + 1, updated));
            }
            case ASSERT -> {
                if (Charset.assertion(instruction.kind(), text, position, flags))
                    pending.push(new Thread(current + 1, thread.captures()));
            }
            default -> list.threads.add(new Thread(current, thread.captures().clone()));
            }
        }
    }
    public int[] search(int start) {
        ThreadList list = new ThreadList();
        int position = start;
        int[] matched = null;
        while (true) {
            if (matched == null && (!full || position == start)) {
                int[] captures = new int[2 * groups + 2];
                Arrays.fill(captures, -1);
                add(list, 0, captures, position);
            }
            ThreadList following = new ThreadList();
            for (Thread thread : list.threads) {
                steps++;
                Main.Instruction instruction = program.get(thread.pc());
                if (instruction.op() == Main.Op.MATCH) {
                    if (!full || position == text.length()) {
                        matched = thread.captures();
                        break;
                    }
                } else if (Main.matchesCharacter(instruction, text, position, flags))
                    add(following, thread.pc() + 1, thread.captures(), position + 1);
            }
            if (position == text.length())
                return matched;
            if (following.threads.isEmpty() && (matched != null || full))
                return matched;
            list = following;
            position++;
        }
    }
    public int steps() { return steps; }
}
