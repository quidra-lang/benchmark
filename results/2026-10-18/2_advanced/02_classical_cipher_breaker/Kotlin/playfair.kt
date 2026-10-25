object Playfair {
    fun square(key: String): String = buildString {
        val used = mutableSetOf<Char>()
        for (c in (key.uppercase().replace('J', 'I') + "ABCDEFGHIKLMNOPQRSTUVWXYZ"))
            if (used.add(c)) append(c)
    }

    fun valid(text: String): Boolean {
        val letters = text.replace('J', 'I')
        if (letters.length % 2 != 0) return false
        return letters.indices.step(2).all { letters[it] != letters[it + 1] }
    }

    fun prepare(text: String): String {
        val normalized = text.replace('J', 'I')
        val result = StringBuilder()
        var index = 0
        while (index < normalized.length) {
            val a = normalized[index]
            val b = if (index + 1 < normalized.length && normalized[index + 1] != a) {
                index += 2
                normalized[index - 1]
            } else {
                index++
                if (a == 'X') 'Q' else 'X'
            }
            result.append(a).append(b)
        }
        return result.toString()
    }

    fun apply(text: String, key: String, encrypt: Boolean): String {
        val board = square(key)
        val input = if (encrypt) prepare(text) else text.replace('J', 'I')
        val result = StringBuilder()
        val distance = if (encrypt) 1 else 4
        for (i in input.indices.step(2)) {
            val first = board.indexOf(input[i])
            val second = board.indexOf(input[i + 1])
            var ra = first / 5
            var rb = second / 5
            var ca = first % 5
            var cb = second % 5
            if (ra == rb) {
                ca = (ca + distance) % 5
                cb = (cb + distance) % 5
            } else if (ca == cb) {
                ra = (ra + distance) % 5
                rb = (rb + distance) % 5
            } else {
                val temp = ca
                ca = cb
                cb = temp
            }
            result.append(board[5 * ra + ca]).append(board[5 * rb + cb])
        }
        return result.toString()
    }
}
