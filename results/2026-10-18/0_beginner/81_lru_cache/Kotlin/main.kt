fun main() {
    val cache = mutableListOf<Char>()
    var hits = 0
    var misses = 0
    for (key in "BACBDABEADDCAEB") {
        var status: String
        if (cache.remove(key)) {
            hits++
            status = "hit"
        } else {
            misses++
            status = "miss"
            if (cache.size == 3) status += ", evict ${cache.removeAt(cache.lastIndex)}"
        }
        cache.add(0,key)
        println("$key: $status [${cache.joinToString(" ")}]")
    }
    println("hits: $hits misses: $misses")
}
