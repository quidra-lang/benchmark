static class Formatter {
    public static string Character(int c) => c >= 33 && c <= 126 && !new[] {
        92, 93, 94, 45
    }.Contains(c) ? ((char)c).ToString() : ((char)92).ToString() + "x" + c.ToString("X2");
    public static string Set(HashSet<int> set, bool negated = false) {
        List<int> values = set.OrderBy(value => value).ToList();
        StringBuilder result = new(negated ? "[^" : "[");
        int i = 0;
        while (i < values.Count) {
            int end = i;
            while (end + 1 < values.Count && values[end + 1] == values[end] + 1) end++;
            result.Append(Character(values[i]));
            if (end > i) {
                if (end - i >= 2) result.Append('-');
                result.Append(Character(values[end]));
            } i = end + 1;
        }
        return result.Append(']').ToString();
    }
    public static string Instruction(Instruction instruction) => instruction switch {
        CharInstruction x => "CHAR " + Character(x.Code), AnyInstruction => "ANY", ClassInstruction x => "CLASS " + Set(x.Set, x.Negated),
        SplitInstruction x => $"SPLIT {x.X}, {x.Y}", JumpInstruction x => $"JMP {x.Target}", SaveInstruction x => $"SAVE {x.Slot}",
        AssertInstruction x => $"ASSERT {x.Kind}", BackrefInstruction x => $"BACKREF {x.Group}", LookInstruction x => $"LOOK {x.Kind} {x.Target}", MatchInstruction => "MATCH", _ => throw new InvalidOperationException()
    };
    public static string Quote(IEnumerable<int> bytes) {
        StringBuilder result = new();
        result.Append((char)34);
        foreach (int c in bytes) {
            switch(c) {
                case 92: result.Append((char)92).Append((char)92);
                break;
                case 34: result.Append((char)92).Append((char)34);
                break;
                case 10: result.Append((char)92).Append('n');
                break;
                case 9: result.Append((char)92).Append('t');
                break;
                default: result.Append((char)c);
                break;
            }
        }
        return result.Append((char)34).ToString();
    }
}
