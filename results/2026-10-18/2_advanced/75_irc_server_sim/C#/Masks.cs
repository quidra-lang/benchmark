public static class Masks {
    public static bool Matches(string inputMask, string inputValue) {
        string mask = Protocol.Fold(inputMask), value = Protocol.Fold(inputValue);
        int pattern = 0, position = 0, star = -1, restart = 0;
        while (position < value.Length) {
            if (pattern < mask.Length && mask[pattern] == '*') {
                star = pattern++;
                restart = position;
            } else if (pattern < mask.Length &&
                       (mask[pattern] == '?' || mask[pattern] == value[position])) {
                pattern++;
                position++;
            } else if (star >= 0) {
                position = ++restart;
                pattern = star + 1;
            } else
                return false;
        }
        while (pattern < mask.Length && mask[pattern] == '*')
            pattern++;
        return pattern == mask.Length;
    }
    public static string Normalize(string argument) {
        if (argument.Contains('!') && argument.Contains('@'))
            return argument;
        if (argument.Contains('@'))
            return "*!" + argument;
        if (argument.Contains('!'))
            return argument + "@*";
        if (argument.Contains('.'))
            return "*!*@" + argument;
        return argument + "!*@*";
    }
}
