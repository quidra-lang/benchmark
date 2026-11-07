import java.io.File
import java.util.BitSet

data class Product(val name: String, val category: String, val price: Long)
class Transaction(val tid: String, val customer: String, val day: Int) {
    val counts = mutableMapOf<String, Int>()
    val products get() = counts.keys.toSet()
    val units get() = counts.values.sum()
    fun add(name: String): Boolean { val duplicate = name in counts; counts[name] = (counts[name] ?: 0) + 1; return duplicate }
}
fun readRecords(name: String) = File("input/$name").readLines().drop(1).map { it.split(',') }
fun contains(items: Set<String>, candidate: List<String>) = candidate.all { it in items }
fun extendedBasket(items: Set<String>, taxonomy: Map<String, String>) = items + items.map { taxonomy.getValue(it) }
class BasketIndex(val baskets: List<Set<String>>) {
    private val columns = mutableMapOf<String, BitSet>()
    init { for ((index, basket) in baskets.withIndex()) for (item in basket) columns.getOrPut(item) { BitSet() }.set(index) }
    fun count(items: List<String>): Int {
        if (items.isEmpty()) return baskets.size
        val first = columns[items[0]] ?: return 0
        val matches = first.clone() as BitSet
        for (item in items.drop(1)) { val column = columns[item] ?: return 0; matches.and(column) }
        return matches.cardinality()
    }
}
