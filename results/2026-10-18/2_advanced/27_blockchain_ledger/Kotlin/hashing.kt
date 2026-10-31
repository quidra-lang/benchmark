object Hashing {
    fun digest(text: String): String {
        val bases = longArrayOf(1000003, 1500007, 2750159, 4194301)
        val initials = longArrayOf(11, 23, 37, 53)
        return bases.indices.joinToString("") {
            lane ->
            var value = initials[lane]
            for (character in text) value = (value * bases[lane] + character.code) % 2147483647
            for (extra in intArrayOf(text.length, 0, 0)) value = (value * bases[lane] + extra) % 2147483647
            value.toString(16).padStart(8, '0')
        }
    }
    fun merkle(hashes: List<String>): String {
        var level = hashes.toMutableList()
        while (level.size > 1) {
            if (level.size % 2 == 1) level.add(level.last())
            level = level.chunked(2).map {
                digest(it[0] + it[1])
            }.toMutableList()
        }
        return level.first()
    }
    fun shortId(value: String): String = value.take(8)
}
