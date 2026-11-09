object Transposition {
    fun rail(position: Int, rails: Int): Int {
        val cycle = 2 * rails - 2
        val offset = position % cycle
        return minOf(offset, cycle - offset)
    }

    fun railFence(text: String, rails: Int, encrypt: Boolean): String {
        val order = text.indices.sortedWith(compareBy<Int> { rail(it, rails) }.thenBy { it })
        val result = CharArray(text.length)
        for (i in order.indices) {
            if (encrypt) result[i] = text[order[i]]
            else result[order[i]] = text[i]
        }
        return result.concatToString()
    }

    fun columnOrder(key: String): List<Int> =
        key.indices.sortedWith(compareBy<Int> { key[it] }.thenBy { it })

    fun rankString(key: String): String {
        val rank = CharArray(key.length)
        for ((index, column) in columnOrder(key).withIndex())
            rank[column] = ('1'.code + index).toChar()
        return rank.concatToString()
    }

    fun columnar(text: String, key: String, encrypt: Boolean): String {
        val result = CharArray(text.length)
        var pointer = 0
        for (column in columnOrder(key)) {
            var index = column
            while (index < text.length) {
                if (encrypt) result[pointer++] = text[index]
                else result[index] = text[pointer++]
                index += key.length
            }
        }
        return result.concatToString()
    }
}
