fun main() {
    val values = intArrayOf(3,8,11,15,19,24,27,31,36,42,47,53,58,64,70,77)
    for (target in intArrayOf(42,3,77,31,50,1)) {
        var lo = 0
        var hi = 15
        var found = -1
        val probes = mutableListOf<Int>()
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            probes.add(mid)
            if (values[mid] == target) {
                found = mid
                break
            }
            if (values[mid] < target) lo = mid + 1 else hi = mid - 1
        }
        println("$target: probes ${probes.joinToString(" ")} -> ${if (found >= 0) "index $found" else "not found"}")
    }
}
