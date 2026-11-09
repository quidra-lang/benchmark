data class CommonPair(val size: Int, val alignment: Int)
class Resolution {
    var kind = "weakundef"
    var definition: Reference? = null
    var definer = "-"
    var size = 0
    var alignment = 1
    var strong: List<Int> = emptyList()
    var common: List<CommonPair> = emptyList()
    val referrers = mutableListOf<Int>()
    var live = false
    var address = 0L
}
object Resolver {
    fun resolve(objects: List<LinkObject>, entries: List<Reference>, script: Boolean): Resolution {
        val strong = mutableListOf<Reference>()
        val weak = mutableListOf<Reference>()
        val common = mutableListOf<Pair<Reference, Definition.Common>>()
        var globalReference = false
        val result = Resolution()
        for (entry in entries) {
            val symbol = objects[entry.objectIndex].symbols[entry.index]
            when (val definition = symbol.definition) {
                is Definition.SectionDef -> if (symbol.binding == "global") strong.add(entry) else weak.add(entry)
                is Definition.Common -> common.add(Pair(entry, definition))
                Definition.Undefined -> {
                    if (entry.objectIndex !in result.referrers) result.referrers.add(entry.objectIndex)
                    globalReference = globalReference || symbol.binding == "global"
                }
            }
        }
        result.strong = strong.map {
            it.objectIndex
        }
        result.common = common.map {
            CommonPair(it.second.size, it.second.alignment)
        }
        when {
            script -> {
                result.kind = "script"
                result.definer = "*script*"
                result.live = true
            }
            strong.isNotEmpty() -> {
                val entry = strong[0]
                result.kind = "global"
                result.definition = entry
                result.definer = objects[entry.objectIndex].name
            }
            common.isNotEmpty() -> {
                result.kind = "common"
                result.size = common.maxOf {
                    it.second.size
                }
                result.alignment = common.maxOf {
                    it.second.alignment
                }
                result.definer = objects[common.first {
                    it.second.size == result.size
                }.first.objectIndex].name
            }
            weak.isNotEmpty() -> {
                val entry = weak[0]
                result.kind = "weak"
                result.definition = entry
                result.definer = objects[entry.objectIndex].name
            }
            globalReference -> result.kind = "undefined"
        }
        return result
    }
}
