import kotlin.math.max

object Resolver {
    data class Period(val start: Long, val offset: Long, val dst: Boolean, val abbreviation: String) {
        fun sameState(other: Period): Boolean = offset == other.offset && dst == other.dst && abbreviation == other.abbreviation
    }

    class Timeline(val periods: List<Period>) {
        fun indexAt(time: Long): Int {
            var low = 0
            var high = periods.size
            while (low < high) { val middle = (low + high) / 2; if (periods[middle].start <= time) low = middle + 1 else high = middle }
            return low - 1
        }

        fun periodAt(time: Long): Period = periods[indexAt(time)]
        fun endOf(index: Int): Long = if (index + 1 < periods.size) periods[index + 1].start else DayRules.POS_INFINITY
        fun nearbyFirst(local: Long): Int = indexAt(local - 57600)
        fun nearbyLast(local: Long): Int = indexAt(local + 57600)

        fun candidates(local: Long): List<Int> {
            val found = mutableListOf<Int>()
            for (index in nearbyFirst(local)..nearbyLast(local)) {
                val period = periods[index]
                val time = local - period.offset
                if (period.start <= time && time < endOf(index)) found.add(index)
            }
            return found
        }

        fun skippingTransition(local: Long): Int {
            for (index in max(1, nearbyFirst(local))..nearbyLast(local)) {
                val start = periods[index].start
                if (start + periods[index - 1].offset <= local && local < start + periods[index].offset) return index
            }
            error("unresolved gap")
        }
    }
}
