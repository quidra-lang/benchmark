object Formatter {
    fun character(c: Int): String = if (c in 33..126 && c !in listOf(92, 93, 94, 45)) c.toChar().toString() else 92.toChar().toString() + "x" + c.toString(16).uppercase().padStart(2, '0')
    fun set(set: Set<Int>, negated: Boolean = false): String {
        val values = set.sorted();
        val result = StringBuilder(if (negated) "[^" else "[");
        var i = 0
        while (i < values.size) {
            var end = i;
            while (end + 1 < values.size && values[end + 1] == values[end] + 1) end++;
            result.append(character(values[i]));
            if (end > i) {
                if (end - i >= 2) result.append('-');
                result.append(character(values[end]))
            };
            i = end + 1
        };
        return result.append(']').toString()
    }
    fun instruction(instruction: Instruction): String = when (instruction) {
        is Instruction.Char -> "CHAR " + character(instruction.code)
        Instruction.Any -> "ANY"
        is Instruction.Class -> "CLASS " + set(instruction.set, instruction.negated)
        is Instruction.Split -> "SPLIT ${instruction.x}, ${instruction.y}"
        is Instruction.Jump -> "JMP ${instruction.target}"
        is Instruction.Save -> "SAVE ${instruction.slot}"
        is Instruction.Assert -> "ASSERT ${instruction.kind}"
        is Instruction.Backref -> "BACKREF ${instruction.group}"
        is Instruction.Look -> "LOOK ${instruction.kind} ${instruction.target}"
        Instruction.Match -> "MATCH"
    }
    fun quote(bytes: List<Int>): String = buildString {
        append(34.toChar())
        for (c in bytes) {
            when (c) {
                92 -> {
                    append(92.toChar());
                    append(92.toChar())
                };
                34 -> {
                    append(92.toChar());
                    append(34.toChar())
                };
                10 -> {
                    append(92.toChar());
                    append('n')
                };
                9 -> {
                    append(92.toChar());
                    append('t')
                };
                else -> append(c.toChar())
            }
        }
        append(34.toChar())
    }
}
