fun compareItems(first: List<String>, second: List<String>): Int {
    for (index in 0 until minOf(first.size, second.size)) { val difference = first[index].compareTo(second[index]); if (difference != 0) return difference }
    return first.size.compareTo(second.size)
}
fun sizeOrder(first: List<String>, second: List<String>) = if (first.size != second.size) first.size.compareTo(second.size) else compareItems(first, second)
fun smallerSubsets(items: List<String>) = items.indices.map { omitted -> items.filterIndexed { index, _ -> index != omitted } }
data class CandidateLevel(val joined: Int, val excluded: Int, val pruned: Int, val items: List<List<String>>)
fun generateCandidates(previous: List<List<String>>, size: Int, taxonomy: Map<String, String>?): CandidateLevel {
    val ordered = previous.sortedWith(::compareItems)
    val known = previous.toSet()
    val joined = mutableListOf<List<String>>()
    for (first in ordered.indices) for (second in first + 1 until ordered.size) {
        if (ordered[first].dropLast(1) != ordered[second].dropLast(1)) break
        joined += ordered[first] + ordered[second].last()
    }
    val remaining = if (size == 2 && taxonomy != null) joined.filter { taxonomy[it[0]] != it[1] && taxonomy[it[1]] != it[0] } else joined
    val survivors = remaining.filter { candidate -> smallerSubsets(candidate).all { it in known } }
    return CandidateLevel(joined.size, joined.size - remaining.size, remaining.size - survivors.size, survivors)
}
fun countSupports(index: BasketIndex, candidates: List<List<String>>) = candidates.associateWith(index::count)
