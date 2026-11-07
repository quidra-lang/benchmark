sealed class BacktrackState(int pc, int position, int?[] capture, HashSet<int> splits) {
    public int Pc = pc, Position = position;
    public int?[] Capture = capture;
    public HashSet<int> Splits = splits;
}
sealed class StepLimit : Exception {
}
sealed class Backtrack(List<Instruction> code, List<int> subject, Flags flags, int groups, bool full) {
    public int Steps {
        get;
        private set;
    }
    public (int?[] Capture, int Position)? Execute(int pc, int position, int?[] capture, bool partial) {
        Stack<BacktrackState> stack = new();
        stack.Push(new(pc, position, capture.ToArray(), new()));
        while (stack.Count > 0) {
            BacktrackState state = stack.Pop();
            bool failed = false;
            while (!failed) {
                if (++Steps > 200000) throw new StepLimit();
                switch (code[state.Pc]) {
                    case CharInstruction or AnyInstruction or ClassInstruction:
                    if (!Program.Consumes(code[state.Pc], subject, state.Position, flags)) {
                        failed = true;
                        break;
                    }
                    state.Position++;
                    state.Pc++;
                    state.Splits.Clear();
                    break;
                    case SplitInstruction instruction:
                    if (!state.Splits.Add(state.Pc)) {
                        failed = true;
                        break;
                    }
                    stack.Push(new(instruction.Y, state.Position, state.Capture.ToArray(), new(state.Splits)));
                    state.Pc = instruction.X;
                    break;
                    case JumpInstruction instruction: state.Pc = instruction.Target;
                    break;
                    case SaveInstruction instruction: state.Capture[instruction.Slot] = state.Position;
                    state.Pc++;
                    break;
                    case AssertInstruction instruction:
                    if (!Charset.Assertion(instruction.Kind, subject, state.Position, flags)) failed = true;
                    else state.Pc++;
                    break;
                    case BackrefInstruction instruction: {
                        int? a = state.Capture[2 * instruction.Group], b = state.Capture[2 * instruction.Group + 1];
                        if (!a.HasValue || !b.HasValue || a.Value > b.Value) {
                            failed = true;
                            break;
                        }
                        int length = b.Value - a.Value;
                        if (state.Position + length > subject.Count || Enumerable.Range(0, length).Any(j => !Charset.Equal(subject[state.Position + j], subject[a.Value + j], flags))) {
                            failed = true;
                            break;
                        }
                        state.Position += length;
                        state.Pc++;
                        if (length > 0) state.Splits.Clear();
                        break;
                    }
                    case LookInstruction instruction: {
                        var result = Execute(state.Pc + 1, state.Position, state.Capture, true);
                        if (instruction.Kind == "NOT") {
                            if (result.HasValue) failed = true;
                            else state.Pc = instruction.Target;
                        }
                        else {
                            if (!result.HasValue) {
                                failed = true;
                                break;
                            }
                            state.Capture = result.Value.Capture.ToArray();
                            if (instruction.Kind == "ATOMIC") {
                                if (result.Value.Position > state.Position) state.Splits.Clear();
                                state.Position = result.Value.Position;
                            }
                            state.Pc = instruction.Target;
                        }
                        break;
                    }
                    case MatchInstruction:
                    if (partial || !full || state.Position == subject.Count) return (state.Capture.ToArray(), state.Position);
                    failed = true;
                    break;
                }
            }
        }
        return null;
    }
    public int?[]? Search(int start) {
        for (int b = full ? 0 : start; b <= (full ? 0 : subject.Count); b++) {
            var result = Execute(0, b, new int?[2 * groups + 2], false);
            if (result.HasValue) return result.Value.Capture;
        }
        return null;
    }
}
