static class Charset {
    public static bool Letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
    public static bool Digit(int c) => c >= 48 && c <= 57;
    public static bool Word(int c) => Letter(c) || Digit(c) || c == 95;
    public static int Swap(int c) => c >= 97 && c <= 122 ? c - 32 : c >= 65 && c <= 90 ? c + 32 : c;
    public static bool Equal(int a, int b, Flags flags) => a == b || flags.I && Letter(a) && Swap(a) == b;
    public static HashSet<int> Base(int c) {
        int lower = c >= 65 && c <= 90 ? c + 32 : c;
        HashSet<int> set = Enumerable.Range(0, 128).Where(value => lower == 100 ? Digit(value) : lower == 119 ? Word(value) : new[] {
            9, 10, 11, 12, 13, 32
        }.Contains(value)).ToHashSet();
        return c >= 65 && c <= 90 ? Enumerable.Range(0, 128).Except(set).ToHashSet() : set;
    }
    public static bool ClassMatches(int c, HashSet<int> set, bool negated, Flags flags) => (set.Contains(c) || flags.I && Letter(c) && set.Contains(Swap(c))) != negated;
    public static bool Assertion(string kind, IReadOnlyList<int> subject, int q, Flags flags) {
        if (kind == "BOL") return q == 0 || flags.M && subject[q - 1] == 10;
        if (kind == "EOL") return q == subject.Count || flags.M && subject[q] == 10;
        bool left = q > 0 && Word(subject[q - 1]), right = q < subject.Count && Word(subject[q]);
        return (left != right) == (kind == "WORD");
    }
}
