object Relocator {
    val types = listOf("ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24")
    fun width(kind: String): Int = if (kind in listOf("ABS32", "REL32")) 4 else if (kind == "CALL24") 3 else 2
    fun value(kind: String, symbol: Long, addend: Long, position: Long, gp: Long): Long = symbol + addend - if (kind in listOf("REL32", "CALL24")) position else if (kind == "GPREL16") gp else 0L
    fun fits(kind: String, value: Long): Boolean = when (kind) {
        "ABS32", "HI16" -> value >= -2147483648L && value < 4294967296L
        "REL32" -> value >= -2147483648L && value < 2147483648L
        "ABS16" -> value >= -32768L && value < 65536L
        "GPREL16" -> value >= -32768L && value < 32768L
        "CALL24" -> value >= -33554432L && value < 33554432L
        else -> true
    }
    fun field(kind: String, value: Long): Long = when (kind) {
        "HI16" -> mod((mod(value, 4294967296L) + 32768L) / 65536L, 65536L)
        "CALL24" -> mod(Math.floorDiv(value, 4L), 16777216L)
        "ABS32", "REL32" -> mod(value, 4294967296L)
        else -> mod(value, 65536L)
    }
    fun unpaired(relocations: List<Relocation>, index: Int): Boolean {
        val current = relocations[index]
        if (current.kind != "HI16") return false
        val next = relocations.getOrNull(index + 1) ?: return true
        return next.kind != "LO16" || next.symbol != current.symbol || next.addend != current.addend
    }
    fun little(value: Long, width: Int): List<Int> = (0 until width).map {
        ((value ushr (8 * it)) and 255L).toInt()
    }
}
