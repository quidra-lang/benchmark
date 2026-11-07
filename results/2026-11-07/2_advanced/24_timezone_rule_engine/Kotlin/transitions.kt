object Transitions {
    data class Rule(val number: Int, val fields: List<String>, val fromYear: Int, val toYear: Int, val month: Int, val day: DayRules.DaySpec, val at: Long, val type: Char, val save: Long, val letter: String) {
        val name: String get() = fields[1]
    }
    data class Instance(val rule: Rule, val nominal: Long)
    data class Applied(val time: Long, val rule: Rule)
    data class Switch(val time: Long, val save: Long, val letter: String)
    class LineRun {
        val preStart = mutableListOf<Rule>()
        val applied = mutableListOf<Applied>()
        var end = DayRules.POS_INFINITY
    }

    fun instances(rules: List<Rule>): List<Instance> {
        val result = mutableListOf<Instance>()
        for (rule in rules) for (year in rule.fromYear..rule.toYear) result.add(Instance(rule, rule.day.value(year, rule.month) * DayRules.DAY + rule.at))
        return result.sortedWith(compareBy<Instance> { it.nominal }.thenBy { it.rule.number })
    }

    fun adjustment(type: Char, offset: Long, save: Long): Long = if (type == 'u') 0 else if (type == 's') offset else offset + save

    fun run(instances: List<Instance>, offset: Long, start: Long, until: TzParser.Until?): LineRun {
        val result = LineRun()
        var save = 0L
        for (instance in instances) {
            val rule = instance.rule
            val time = instance.nominal - adjustment(rule.type, offset, save)
            if (until != null && time >= until.value - adjustment(until.type, offset, save)) break
            if (time <= start) result.preStart.add(rule) else result.applied.add(Applied(time, rule))
            save = rule.save
        }
        if (until != null) result.end = until.value - adjustment(until.type, offset, save)
        return result
    }

    fun abbreviation(format: String, save: Long, letter: String): String {
        if ('/' in format) { val parts = format.split('/'); return if (save == 0L) parts[0] else parts[1] }
        return format.replace("%s", letter)
    }
}
