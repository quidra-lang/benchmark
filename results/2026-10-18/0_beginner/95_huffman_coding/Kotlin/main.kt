import java.math.BigDecimal
import java.math.RoundingMode

data class Node(val weight: Int, val minimum: Int, val symbol: Char? = null,
    val left: Node? = null, val right: Node? = null)
fun codes(node: Node, prefix: String, result: MutableMap<Char,String>) {
    if (node.symbol != null) result[node.symbol] = prefix
    else {
        codes(node.left!!,prefix + "0",result)
        codes(node.right!!,prefix + "1",result)
    }
}
fun main() {
    val text = "she sells sea shells by the sea shore"
    val frequencies = text.groupingBy { it }.eachCount().toSortedMap()
    val queue = java.util.PriorityQueue<Node>(compareBy<Node> { it.weight }.thenBy { it.minimum })
    for ((ch,count) in frequencies) queue.add(Node(count,ch.code,ch))
    while (queue.size > 1) {
        val left = queue.remove()
        val right = queue.remove()
        queue.add(Node(left.weight + right.weight,minOf(left.minimum,right.minimum),null,left,right))
    }
    val mapping = mutableMapOf<Char,String>()
    codes(queue.remove(),"",mapping)
    var bits = 0
    for ((ch,count) in frequencies) {
        val code = mapping.getValue(ch)
        bits += count * code.length
        println("'$ch' freq=$count code=$code")
    }
    println("encoded bits: $bits")
    println("fixed 8-bit: ${text.length * 8}")
}
