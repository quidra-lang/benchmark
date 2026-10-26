data class NamingCondition(val feature: Int, val comparison: String, val threshold: Double) {
    fun holds(center: DoubleArray) = if (comparison == ">") center[feature] > threshold else center[feature] < threshold
}
data class NamingRule(val name: String, val conditions: List<NamingCondition>) {
    fun holds(center: DoubleArray) = conditions.all { it.holds(center) }
}
object Profiles {
    fun read(path: String): List<NamingRule> {
        val rules = mutableListOf<NamingRule>()
        for (line in Transactions.lines(path)) {
            val words = line.split(' ')
            val conditions = mutableListOf<NamingCondition>()
            for (i in 1 until words.size step 3) conditions.add(NamingCondition(Features.NAMES.indexOf(words[i]), words[i + 1], words[i + 2].toDouble()))
            rules.add(NamingRule(words[0], conditions))
        }
        return rules
    }
    fun ruleNumber(rules: List<NamingRule>, center: DoubleArray): Int {
        for (i in rules.indices) if (rules[i].holds(center)) return i + 1
        error("No segment rule")
    }
    fun originalScale(center: DoubleArray, means: DoubleArray, sds: DoubleArray): DoubleArray {
        return DoubleArray(center.size) { f ->
            val value = means[f] + sds[f] * center[f]
            if (Features.SQRT[f]) value * value else value
        }
    }
}
