sealed class Threads {
    public List<(int Pc, int?[] Capture)> Sequence = new();
    public HashSet<int> Marks = new();
}
sealed class Pike(List<Instruction> code, List<int> subject, Flags flags, int groups, bool full) {
    public int Steps {
        get;
        private set;
    }
    void Add(Threads list, int pc, int?[] capture, int position) {
        if (!list.Marks.Add(pc)) return;
        Steps++;
        switch (code[pc]) {
            case JumpInstruction instruction: Add(list, instruction.Target, capture, position);
            break;
            case SplitInstruction instruction: Add(list, instruction.X, capture, position);
            Add(list, instruction.Y, capture, position);
            break;
            case SaveInstruction instruction: {
                int?[] changed = capture.ToArray();
                changed[instruction.Slot] = position;
                Add(list, pc + 1, changed, position);
                break;
            }
            case AssertInstruction instruction: if (Charset.Assertion(instruction.Kind, subject, position, flags)) Add(list, pc + 1, capture, position);
            break;
            default: list.Sequence.Add((pc, capture.ToArray()));
            break;
        }
    }
    public int?[]? Search(int start) {
        int?[]? matched = null;
        Threads list = new();
        int position = start;
        while (true) {
            if (matched == null && (!full || position == start)) Add(list, 0, new int?[2 * groups + 2], position);
            Threads next = new();
            foreach (var (pc, capture) in list.Sequence) {
                Steps++;
                if (code[pc] is MatchInstruction) {
                    if (!full || position == subject.Count) {
                        matched = capture.ToArray();
                        break;
                    }
                }
                else if (Program.Consumes(code[pc], subject, position, flags)) Add(next, pc + 1, capture, position + 1);
            }
            if (position == subject.Count || next.Sequence.Count == 0 && (matched != null || full)) return matched;
            list = next;
            position++;
        }
    }
}
