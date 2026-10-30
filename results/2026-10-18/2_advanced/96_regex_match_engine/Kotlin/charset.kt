object Charset {
    fun letter(c: Int): Boolean = c in 65..90 || c in 97..122
    fun digit(c: Int): Boolean = c in 48..57
    fun word(c: Int): Boolean = letter(c) || digit(c) || c == 95
    fun swap(c: Int): Int = if (c in 97..122) c - 32 else if (c in 65..90) c + 32 else c
    fun equal(a: Int, b: Int, flags: Flags): Boolean = a == b || flags.i && letter(a) && swap(a) == b
    fun base(c: Int): Set<Int> {
        val lower = if (c in 65..90) c + 32 else c;
        val set = (0..127).filter {
            when (lower) {
                100 -> digit(it);
                119 -> word(it);
                else -> it in listOf(9, 10, 11, 12, 13, 32)
            }
        }.toSet();
        return if (c in 65..90) (0..127).toSet() - set else set
    }
    fun classMatches(c: Int, set: Set<Int>, negated: Boolean, flags: Flags): Boolean = (c in set || flags.i && letter(c) && swap(c) in set) != negated
    fun assertion(kind: String, subject: List<Int>, q: Int, flags: Flags): Boolean {
        if (kind == "BOL") return q == 0 || flags.m && subject[q - 1] == 10
        if (kind == "EOL") return q == subject.size || flags.m && subject[q] == 10
        val left = q > 0 && word(subject[q - 1]);
        val right = q < subject.size && word(subject[q]);
        return (left != right) == (kind == "WORD")
    }
}
