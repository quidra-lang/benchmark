data class Trigram(val text: String, val positions: List<Int>, val gaps: List<Int>, val gcd: Int)
data class KasiskiData(val trigrams: List<Trigram>, val gaps: List<Int>) {
    fun count(period: Int): Int = gaps.count { it % period == 0 }
}

object Analysis {
    fun frequencies(text: String): IntArray {
        val counts = IntArray(26)
        for (c in text) counts[c - 'A']++
        return counts
    }

    fun ioc(text: String): Int {
        if (text.length < 2) return 0
        val counts = frequencies(text)
        val pairs = counts.sumOf { it.toLong() * (it - 1) }
        return (100000L * pairs / (text.length.toLong() * (text.length - 1))).toInt()
    }

    fun column(text: String, period: Int, offset: Int): String = buildString {
        var index = offset
        while (index < text.length) {
            append(text[index])
            index += period
        }
    }

    fun columnIocs(text: String, period: Int): List<Int> =
        (0 until period).map { ioc(column(text, period, it)) }

    fun averageIoc(text: String, period: Int): Int =
        columnIocs(text, period).sum() / period

    fun gcd(a: Int, b: Int): Int {
        var first = a
        var second = b
        while (second != 0) {
            val next = first % second
            first = second
            second = next
        }
        return first
    }

    fun kasiski(text: String): KasiskiData {
        val found = sortedMapOf<String, MutableList<Int>>()
        for (index in 0 until text.length - 2)
            found.getOrPut(text.substring(index, index + 3)) { mutableListOf() }.add(index + 1)
        val items = mutableListOf<Trigram>()
        val allGaps = mutableListOf<Int>()
        for ((trigram, positions) in found) {
            if (positions.size < 2) continue
            val gaps = (1 until positions.size).map { positions[it] - positions[it - 1] }
            allGaps.addAll(gaps)
            items.add(Trigram(trigram, positions, gaps, gaps.reduce(::gcd)))
        }
        return KasiskiData(items, allGaps)
    }

    fun periodTable(text: String, limit: Int, info: KasiskiData): List<String> =
        (1..limit).map { period ->
            val cols = columnIocs(text, period)
            "L=$period ioc=${cols.sum() / period} kasiski=${info.count(period)} cols=${cols.joinToString(",")}"
        }

    fun kasiskiTable(info: KasiskiData): List<String> =
        listOf("kasiski repeats=${info.trigrams.size} spacings=${info.gaps.size}") +
            info.trigrams.map {
                "${it.text} at=${it.positions.joinToString(",")} gaps=${it.gaps.joinToString(",")} gcd=${it.gcd}"
            }

    fun topPairs(text: String, digraphs: Boolean): String {
        val counts = mutableMapOf<String, Int>()
        val step = if (digraphs) 2 else 1
        var index = 0
        while (index + 1 < text.length) {
            val pair = text.substring(index, index + 2)
            counts[pair] = (counts[pair] ?: 0) + 1
            index += step
        }
        return counts.entries.sortedWith(
            compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }
        ).take(10).joinToString(" ") { "${it.key}:${it.value}" }
    }

    fun percentage(count: Int, total: Int): String {
        val tenths = (2000 * count + total) / (2 * total)
        return "${tenths / 10}.${tenths % 10}"
    }

    fun report(job: Int, source: String, text: String,
               mono: IntArray, bi: Array<IntArray>, maxlen: Int): List<String> {
        val info = kasiski(text)
        val frequency = frequencies(text)
        val doubles = (0 until text.length - 1).count { text[it] == text[it + 1] }
        val pairDoubles = (0 until text.length - 1).count { it % 2 == 0 && text[it] == text[it + 1] }
        val output = mutableListOf(
            "JOB $job ANALYZE source=$source",
            "letters=${text.length}",
            "ioc=${ioc(text)} mono=${Scoring.monogram(text, mono)} bigram=${Scoring.bigram(text, bi)}",
            "doubles=$doubles pair_doubles=$pairDoubles distinct=${frequency.count { it > 0 }}"
        )
        for (i in 0 until 26)
            output.add("${Scoring.upper(i)} ${frequency[i]} ${percentage(frequency[i], text.length)}")
        output.add("bigrams ${topPairs(text, false)}")
        output.addAll(periodTable(text, maxlen, info))
        output.addAll(kasiskiTable(info))
        return output
    }
}
