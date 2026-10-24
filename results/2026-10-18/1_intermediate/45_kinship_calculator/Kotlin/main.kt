import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.min

private class CommandError(message: String) : RuntimeException(message)

private data class Person(
    val id: String,
    val sex: String,
    val birth: Int,
    val name: String,
    var death: Int? = null,
    val parents: MutableSet<String> = mutableSetOf()
) {
    fun lifeYears() = "$birth-${death ?: ""}"
    fun duplicate() = copy(parents = parents.toMutableSet())
}

private data class Marriage(
    val first: String,
    val second: String,
    val start: Int,
    var end: Int? = null,
    var status: String = "current",
    var died: String? = null
) {
    fun contains(id: String) = first == id || second == id
    fun other(id: String) = if (first == id) second else first
}

private data class Fraction private constructor(val numerator: Long, val denominator: Long) {
    operator fun plus(other: Fraction): Fraction {
        // All denominators are powers of two, so the larger one is their LCM.
        val common = maxOf(denominator, other.denominator)
        return of(numerator * (common / denominator) +
            other.numerator * (common / other.denominator), common)
    }

    fun half() = of(numerator, denominator * 2)
    override fun toString() = "$numerator/$denominator"

    companion object {
        val ZERO = Fraction(0, 1)
        val ONE = Fraction(1, 1)
        val HALF = Fraction(1, 2)

        fun of(numerator: Long, denominator: Long): Fraction {
            var a = numerator
            var b = denominator
            while (b != 0L) {
                val remainder = a % b
                a = b
                b = remainder
            }
            return Fraction(numerator / a, denominator / a)
        }
    }
}

private data class Apex(
    val id: String,
    val da: Int,
    val db: Int,
    val shares: Int = 0,
    val collateral: Boolean = false
)

private fun sexWord(sex: String, male: String, female: String, neutral: String) = when (sex) {
    "M" -> male
    "F" -> female
    else -> neutral
}

private fun generationPrefix(generation: Int) = when (generation) {
    1 -> ""
    2 -> "grand"
    else -> "great-".repeat(generation - 2) + "grand"
}

private fun ordinal(number: Int): String {
    val words = listOf("first", "second", "third", "fourth", "fifth", "sixth",
        "seventh", "eighth", "ninth", "tenth")
    if (number <= 10) return words[number - 1]
    val suffix = if (number % 100 in 11..13) "th" else when (number % 10) {
        1 -> "st"
        2 -> "nd"
        3 -> "rd"
        else -> "th"
    }
    return "$number$suffix"
}

private fun term(da: Int, db: Int, sex: String): String = when {
    da == 0 && db == 0 -> "self"
    da == 0 -> generationPrefix(db) + sexWord(sex, "father", "mother", "parent")
    db == 0 -> generationPrefix(da) + sexWord(sex, "son", "daughter", "child")
    da == 1 && db == 1 -> sexWord(sex, "brother", "sister", "sibling")
    da == 1 -> generationPrefix(db - 1) + sexWord(sex, "uncle", "aunt", "pibling")
    db == 1 -> generationPrefix(da - 1) + sexWord(sex, "nephew", "niece", "nibling")
    else -> {
        val removal = when (val distance = abs(da - db)) {
            0 -> ""
            1 -> " once removed"
            2 -> " twice removed"
            else -> " $distance times removed"
        }
        ordinal(min(da, db) - 1) + " cousin" + removal
    }
}

private data class Snapshot(
    val people: MutableMap<String, Person>,
    val marriages: MutableList<Marriage>
)

private data class UndoEntry(val line: String, val state: Snapshot)
private data class Event(val year: Int, val rank: Int, val counterpart: String, val text: String)

private class Family {
    private var people = mutableMapOf<String, Person>()
    private var marriages = mutableListOf<Marriage>()
    private val history = mutableListOf<UndoEntry>()
    private val ancestorCache = mutableMapOf<String, Map<String, Int>>()
    private val kinshipCache = mutableMapOf<Pair<String, String>, Fraction>()

    private fun snapshot() = Snapshot(
        people.mapValues { (_, person) -> person.duplicate() }.toMutableMap(),
        marriages.map { it.copy() }.toMutableList()
    )

    private fun person(id: String) = people.getValue(id)
    private fun children(id: String) = people.values.filter { id in it.parents }.map { it.id }
    private fun ageOrder(ids: Collection<String>) = ids.sortedWith(
        compareBy<String> { person(it).birth }.thenBy { it }
    )

    private fun personList(ids: Collection<String>) =
        ageOrder(ids).joinToString(" ").ifEmpty { "-" }

    private fun lastMarriage(a: String, b: String) = marriages.lastOrNull {
        it.contains(a) && it.contains(b)
    }

    private fun currentMarriage(id: String) = marriages.firstOrNull {
        it.status == "current" && it.contains(id)
    }

    private fun spouse(id: String) = currentMarriage(id)?.other(id)

    private fun partners(id: String): Set<String> {
        val latest = mutableMapOf<String, Marriage>()
        for (marriage in marriages) {
            if (marriage.contains(id)) latest[marriage.other(id)] = marriage
        }
        return latest.filterValues { it.status != "divorced" }.keys
    }

    private fun siblings(a: String, b: String) =
        a != b && person(a).parents.any { it in person(b).parents }

    private fun ancestors(id: String): Map<String, Int> = ancestorCache.getOrPut(id) {
        val distance = mutableMapOf(id to 0)
        val queue = ArrayDeque<String>()
        queue.add(id)
        while (queue.isNotEmpty()) {
            val current = queue.removeFirst()
            for (parent in person(current).parents) {
                if (parent !in distance) {
                    distance[parent] = distance.getValue(current) + 1
                    queue.add(parent)
                }
            }
        }
        distance
    }

    private fun descendants(id: String): Map<String, Int> {
        val distance = mutableMapOf(id to 0)
        val queue = ArrayDeque<String>()
        queue.add(id)
        while (queue.isNotEmpty()) {
            val current = queue.removeFirst()
            for (child in children(current)) {
                if (child !in distance) {
                    distance[child] = distance.getValue(current) + 1
                    queue.add(child)
                }
            }
        }
        distance.remove(id)
        return distance
    }

    private fun apex(a: String, b: String): Apex? {
        val fromA = ancestors(a)
        val fromB = ancestors(b)
        if (a in fromB) return Apex(a, 0, fromB.getValue(a))
        if (b in fromA) return Apex(b, fromA.getValue(b), 0)
        val common = fromA.keys.intersect(fromB.keys)
        val chosen = common.minWithOrNull(compareBy<String> {
            fromA.getValue(it) + fromB.getValue(it)
        }.thenBy { fromA.getValue(it) }.thenBy { it }) ?: return null
        val da = fromA.getValue(chosen)
        val db = fromB.getValue(chosen)
        val shares = common.count { fromA.getValue(it) == da && fromB.getValue(it) == db }
        return Apex(chosen, da, db, shares, true)
    }

    private fun bloodTerm(a: String, b: String, sex: String = person(a).sex): String {
        val top = apex(a, b)!!
        val prefix = when {
            !top.collateral -> ""
            top.shares == 1 -> "half-"
            top.shares >= 4 -> "double "
            else -> ""
        }
        return prefix + term(top.da, top.db, sex)
    }

    private fun relationships(a: String, b: String, sex: String = person(a).sex): List<String> {
        if (a == b) return listOf("self")
        val result = mutableListOf<String>()
        val parentsA = person(a).parents
        val parentsB = person(b).parents
        val partnersA = partners(a)
        val partnersB = partners(b)
        val marriage = lastMarriage(a, b)
        if (apex(a, b) != null) result.add(bloodTerm(a, b, sex))
        when (marriage?.status) {
            "current" -> result.add(sexWord(sex, "husband", "wife", "spouse"))
            "widowed" -> result.add(if (marriage.died == a)
                sexWord(sex, "late husband", "late wife", "late spouse")
                else sexWord(sex, "widower", "widow", "surviving spouse"))
            "divorced" -> result.add(sexWord(sex, "ex-husband", "ex-wife", "ex-spouse"))
        }
        if (marriage == null && children(a).any { b in person(it).parents }) {
            result.add("co-parent")
        }
        if (a !in parentsB && parentsB.any { it in partnersA }) {
            result.add(sexWord(sex, "stepfather", "stepmother", "stepparent"))
        }
        if (b !in parentsA && parentsA.any { it in partnersB }) {
            result.add(sexWord(sex, "stepson", "stepdaughter", "stepchild"))
        }
        if (parentsA.none { it in parentsB } &&
            parentsA.any { p -> parentsB.any { q -> q in partners(p) } }) {
            result.add(sexWord(sex, "stepbrother", "stepsister", "stepsibling"))
        }
        if (a !in ancestors(b) && ancestors(b).any { (id, g) -> g == 2 && id in partnersA }) {
            result.add(sexWord(sex, "stepgrandfather", "stepgrandmother", "stepgrandparent"))
        }
        if (b !in ancestors(a) && ancestors(a).any { (id, g) -> g == 2 && id in partnersB }) {
            result.add(sexWord(sex, "stepgrandson", "stepgranddaughter", "stepgrandchild"))
        }
        if (partnersB.any { a in person(it).parents }) {
            result.add(sexWord(sex, "father-in-law", "mother-in-law", "parent-in-law"))
        }
        if (partnersA.any { b in person(it).parents }) {
            result.add(sexWord(sex, "son-in-law", "daughter-in-law", "child-in-law"))
        }
        if (partnersB.any { siblings(a, it) } || partnersA.any { siblings(it, b) }) {
            result.add(sexWord(sex, "brother-in-law", "sister-in-law", "sibling-in-law"))
        }
        return result
    }

    private fun relationshipString(a: String, b: String) =
        relationships(a, b).joinToString(", ").ifEmpty { "no relation" }

    private fun kinship(a: String, b: String): Fraction {
        val key = if (a <= b) a to b else b to a
        return kinshipCache.getOrPut(key) {
            if (a == b) {
                val parents = person(a).parents.toList()
                if (parents.size == 2) (Fraction.ONE + kinship(parents[0], parents[1])).half()
                else Fraction.HALF
            } else {
                val x = if (person(a).birth >= person(b).birth) a else b
                val y = if (x == a) b else a
                person(x).parents.fold(Fraction.ZERO) { total, parent ->
                    total + kinship(parent, y)
                }.half()
            }
        }
    }

    private fun inbreeding(id: String): Fraction {
        val parents = person(id).parents.toList()
        return if (parents.size == 2) kinship(parents[0], parents[1]) else Fraction.ZERO
    }

    private fun upwardPath(id: String, top: String): List<String> {
        val result = mutableListOf(id)
        var current = id
        while (current != top) {
            val remaining = ancestors(current).getValue(top)
            current = person(current).parents.sorted().first {
                ancestors(it)[top] == remaining - 1
            }
            result.add(current)
        }
        return result
    }

    fun execute(line: String): List<String> {
        ancestorCache.clear()
        kinshipCache.clear()
        val words = line.split(' ')
        val command = words[0]
        val twoIds = command in setOf("PARENT", "UNPARENT", "SPOUSE", "DIVORCE",
            "RELATION", "PATH", "COMMON", "KINSHIP")
        val oneId = command in setOf("DEATH", "REMOVE", "INFO", "RELATIVES", "WHO",
            "ANCESTORS", "DESCENDANTS", "COUSINS", "SIBLINGS", "GENERATIONS",
            "TREE", "PEDIGREE", "TIMELINE", "FIND")
        val checkedIds = if (twoIds) 2 else if (oneId) 1 else 0
        for (index in 1..checkedIds) {
            if (words[index] !in people) throw CommandError("UNKNOWN PERSON ${words[index]}")
        }
        val modifying = command in setOf("PERSON", "DEATH", "REMOVE", "PARENT",
            "UNPARENT", "SPOUSE", "DIVORCE")
        val before = if (modifying) snapshot() else null
        val output = mutableListOf<String>()
        when (command) {
            "PERSON" -> {
                val id = words[1]
                if (id in people) throw CommandError("DUPLICATE PERSON $id")
                people[id] = Person(id, words[2], words[3].toInt(), words[4])
                output.add("ADDED $id ${words[4]} ${words[2]} ${words[3]}")
            }
            "DEATH" -> {
                val id = words[1]
                val year = words[2].toInt()
                val p = person(id)
                if (p.death != null) throw CommandError("ALREADY DECEASED $id")
                if (year < p.birth || marriages.any {
                        it.contains(id) && (year < it.start || (it.end != null && year < it.end!!))
                    }) throw CommandError("BAD YEAR $id")
                val child = children(id).sorted().firstOrNull { person(it).birth > year + 1 }
                if (child != null) throw CommandError("AFTER DEATH $child $id")
                val current = currentMarriage(id)
                p.death = year
                if (current != null) {
                    current.end = year
                    current.status = "widowed"
                    current.died = id
                }
                output.add("DIED $id $year" + (current?.let { " spouse=${it.other(id)}" } ?: ""))
            }
            "REMOVE" -> {
                val id = words[1]
                for (p in people.values) p.parents.remove(id)
                marriages.removeAll { it.contains(id) }
                people.remove(id)
                output.add("REMOVED $id")
            }
            "PARENT" -> {
                val child = words[1]
                val parent = words[2]
                val c = person(child)
                val p = person(parent)
                if (child == parent) throw CommandError("SAME PERSON $child")
                if (parent in c.parents) throw CommandError("ALREADY PARENT $child $parent")
                if (c.parents.size == 2) throw CommandError("TOO MANY PARENTS $child")
                if (child in ancestors(parent)) throw CommandError("CYCLE $child $parent")
                if (p.birth + 12 > c.birth) throw CommandError("AGE GAP $child $parent")
                if (p.death != null && p.death!! + 1 < c.birth) {
                    throw CommandError("AFTER DEATH $child $parent")
                }
                c.parents.add(parent)
                output.add("LINKED $child $parent ${sexWord(p.sex, "father", "mother", "parent")}")
            }
            "UNPARENT" -> {
                val child = words[1]
                val parent = words[2]
                if (parent !in person(child).parents) throw CommandError("NOT PARENT $child $parent")
                person(child).parents.remove(parent)
                output.add("UNLINKED $child $parent")
            }
            "SPOUSE" -> {
                val a = words[1]
                val b = words[2]
                val year = words[3].toInt()
                val ids = listOf(a, b)
                if (a == b) throw CommandError("SAME PERSON $a")
                for (id in ids) if (person(id).death != null) throw CommandError("DECEASED $id")
                for (id in ids) if (spouse(id) != null) throw CommandError("ALREADY MARRIED $id")
                if (a in ancestors(b) || b in ancestors(a) || siblings(a, b)) {
                    throw CommandError("CLOSE KIN $a $b")
                }
                for (id in ids) if (year < person(id).birth + 16) throw CommandError("TOO YOUNG $id")
                for (id in ids) {
                    if (marriages.any { it.contains(id) && it.end != null && it.end!! >= year }) {
                        throw CommandError("BAD YEAR $id")
                    }
                }
                marriages.add(Marriage(a, b, year))
                output.add("MARRIED $a $b $year")
            }
            "DIVORCE" -> {
                val a = words[1]
                val b = words[2]
                val year = words[3].toInt()
                if (spouse(a) != b) throw CommandError("NOT MARRIED $a $b")
                val marriage = currentMarriage(a)!!
                if (year <= marriage.start) throw CommandError("BAD YEAR $a")
                marriage.end = year
                marriage.status = "divorced"
                output.add("DIVORCED $a $b $year")
            }
            "UNDO" -> {
                if (history.isEmpty()) throw CommandError("NOTHING TO UNDO")
                val entry = history.removeAt(history.lastIndex)
                people = entry.state.people
                marriages = entry.state.marriages
                output.add("UNDONE ${entry.line}")
            }
            "INFO" -> {
                val id = words[1]
                val p = person(id)
                output.add("INFO $id ${p.name} ${p.sex} ${p.lifeYears()}")
                output.add("  parents: ${personList(p.parents)}")
                for (marriage in marriages.filter { it.contains(id) }) {
                    output.add("  marriage: ${marriage.other(id)} ${marriage.start}-${marriage.end ?: ""} ${marriage.status}")
                }
                output.add("  children: ${personList(children(id))}")
                output.add("  siblings: ${personList(people.keys.filter { siblings(id, it) })}")
                output.add("  inbreeding: ${inbreeding(id)}")
            }
            "RELATION" -> output.add("RELATION ${words[1]} ${words[2]}: ${relationshipString(words[1], words[2])}")
            "RELATIVES" -> {
                val id = words[1]
                val rows = people.keys.sorted().filter { it != id }.mapNotNull { other ->
                    val terms = relationships(other, id)
                    if (terms.isEmpty()) null else "  $other: ${terms.joinToString(", ")}"
                }
                output.add("RELATIVES $id ${rows.size}")
                output.addAll(rows)
            }
            "WHO" -> {
                val id = words[1]
                val query = words.drop(2).joinToString(" ")
                val rows = people.keys.sorted().filter { it != id }.mapNotNull { other ->
                    val actual = relationships(other, id)
                    val neutral = relationships(other, id, "X")
                    val index = actual.indices.firstOrNull { actual[it] == query || neutral[it] == query }
                    index?.let { "  $other: ${actual[it]}" }
                }
                output.add("WHO $id $query ${rows.size}")
                output.addAll(rows)
            }
            "PATH" -> {
                val a = words[1]
                val b = words[2]
                val top = apex(a, b)
                if (top == null) output.add("PATH $a $b none") else {
                    val path = upwardPath(a, top.id) + upwardPath(b, top.id).dropLast(1).reversed()
                    output.add("PATH $a $b ${top.da + top.db}: ${path.joinToString(" ")}")
                }
            }
            "COMMON" -> {
                val a = words[1]
                val b = words[2]
                val fromA = ancestors(a)
                val fromB = ancestors(b)
                val common = fromA.keys.intersect(fromB.keys)
                val nearest = common.filter { c -> children(c).none { it in common } }.sortedWith(
                    compareBy<String> { fromA.getValue(it) + fromB.getValue(it) }.thenBy { it }
                )
                output.add("COMMON $a $b ${nearest.size}")
                for (id in nearest) output.add("  $id ${fromA.getValue(id)} ${fromB.getValue(id)}")
            }
            "ANCESTORS", "DESCENDANTS" -> {
                val id = words[1]
                val upward = command == "ANCESTORS"
                val distances = if (upward) ancestors(id).filterKeys { it != id } else descendants(id)
                val ids = distances.keys.sortedWith(compareBy<String> { distances.getValue(it) }.thenBy { it })
                output.add("$command $id ${ids.size}")
                for (other in ids) {
                    val generation = distances.getValue(other)
                    val label = if (upward) term(0, generation, person(other).sex)
                        else term(generation, 0, person(other).sex)
                    output.add("  $generation $other $label")
                }
            }
            "COUSINS" -> {
                val id = words[1]
                val degree = words[2].toInt()
                val matches = people.keys.filter { it != id }.mapNotNull { other ->
                    val top = apex(other, id)
                    if (top != null && top.da >= 2 && top.db >= 2 && min(top.da, top.db) - 1 == degree)
                        other to abs(top.da - top.db) else null
                }.sortedWith(compareBy<Pair<String, Int>> { it.second }.thenBy { it.first })
                output.add("COUSINS $id $degree ${matches.size}")
                for ((other, _) in matches) output.add("  $other ${bloodTerm(other, id)}")
            }
            "SIBLINGS" -> {
                val id = words[1]
                val classes = mutableMapOf<String, String>()
                for (other in people.keys.filter { it != id }) {
                    val shared = person(id).parents.intersect(person(other).parents).size
                    val kind = when {
                        shared == 2 -> "full"
                        shared == 1 -> "half"
                        person(id).parents.any { p -> person(other).parents.any { it in partners(p) } } -> "step"
                        else -> null
                    }
                    if (kind != null) classes[other] = kind
                }
                val ordered = ageOrder(classes.keys)
                val earlier = ageOrder(classes.filterValues { it != "step" }.keys + id).indexOf(id)
                output.add("SIBLINGS $id ${classes.size} order=${earlier + 1}")
                for (other in ordered) output.add("  $other ${classes.getValue(other)} ${person(other).birth}")
            }
            "GENERATIONS" -> {
                val id = words[1]
                val groups = descendants(id).entries.groupBy({ it.value }, { it.key }).toSortedMap()
                output.add("GENERATIONS $id ${groups.size}")
                for ((generation, ids) in groups) {
                    val births = ids.map { person(it).birth }
                    output.add("  $generation ${ids.size} ${ids.count { person(it).death == null }} ${births.min()}-${births.max()}")
                }
            }
            "TREE" -> {
                val id = words[1]
                val visited = mutableSetOf<String>()
                output.add("TREE $id ${descendants(id).size}")
                fun visit(current: String, depth: Int) {
                    val indent = "  ".repeat(depth + 1)
                    if (!visited.add(current)) {
                        output.add("$indent$current (see above)")
                        return
                    }
                    val p = person(current)
                    output.add("$indent$current ${p.name} ${p.lifeYears()}" +
                        (spouse(current)?.let { " = $it" } ?: ""))
                    for (child in ageOrder(children(current))) visit(child, depth + 1)
                }
                visit(id, 0)
            }
            "PEDIGREE" -> {
                val id = words[1]
                val depth = words[2].toInt()
                val rows = mutableListOf<String>()
                val distinct = mutableSetOf<String>()
                fun enter(current: String, number: Int, generation: Int) {
                    val p = person(current)
                    distinct.add(current)
                    rows.add("${"  ".repeat(generation + 1)}$number $current ${p.name} ${p.lifeYears()}")
                    if (generation < depth) {
                        val parents = p.parents.sortedWith(compareBy<String> {
                            when (person(it).sex) { "M" -> 0; "F" -> 1; else -> 2 }
                        }.thenBy { it })
                        for ((index, parent) in parents.withIndex()) enter(parent, 2 * number + index, generation + 1)
                    }
                }
                enter(id, 1, 0)
                output.add("PEDIGREE $id $depth entries=${rows.size} distinct=${distinct.size}")
                output.addAll(rows)
            }
            "TIMELINE" -> {
                val id = words[1]
                val p = person(id)
                val events = mutableListOf(Event(p.birth, 0, "", "born"))
                for (marriage in marriages.filter { it.contains(id) }) {
                    val other = marriage.other(id)
                    events.add(Event(marriage.start, 1, other, "married $other"))
                    if (marriage.status == "divorced") {
                        events.add(Event(marriage.end!!, 3, other, "divorced $other"))
                    } else if (marriage.status == "widowed" && marriage.died == other) {
                        events.add(Event(marriage.end!!, 4, other, "widowed $other"))
                    }
                }
                for (child in children(id)) events.add(Event(person(child).birth, 2, child, "child $child"))
                fun loss(other: String, kind: String) {
                    val year = person(other).death ?: return
                    if (year >= p.birth && (p.death == null || year <= p.death!!)) {
                        events.add(Event(year, 5, other, "lost $kind $other"))
                    }
                }
                for (parent in p.parents) loss(parent, "parent")
                for (child in children(id)) loss(child, "child")
                p.death?.let { events.add(Event(it, 6, "", "died")) }
                output.add("TIMELINE $id ${events.size}")
                for (event in events.sortedWith(compareBy<Event> { it.year }.thenBy { it.rank }.thenBy { it.counterpart })) {
                    output.add("  ${event.year} ${event.text}")
                }
            }
            "CENSUS" -> {
                val year = words[1].toInt()
                val residents = ageOrder(people.keys.filter {
                    val p = person(it)
                    p.birth <= year && (p.death == null || p.death!! > year)
                })
                output.add("CENSUS $year ${residents.size}")
                for (id in residents) {
                    val marriage = marriages.lastOrNull { it.contains(id) && it.start <= year }
                    val status = when {
                        marriage == null -> "single"
                        marriage.end == null || marriage.end!! > year -> "married ${marriage.other(id)}"
                        else -> marriage.status
                    }
                    output.add("  $id ${year - person(id).birth} $status")
                }
            }
            "KINSHIP" -> output.add("KINSHIP ${words[1]} ${words[2]} ${kinship(words[1], words[2])}")
            "FIND" -> {
                val id = words[1]
                val route = words[2]
                var found = setOf(id)
                for (step in route.split('.')) {
                    val requiredSex = when (step) {
                        "father", "son", "brother", "husband" -> "M"
                        "mother", "daughter", "sister", "wife" -> "F"
                        else -> null
                    }
                    found = found.flatMap { current ->
                        when (step) {
                            "parent", "father", "mother" -> person(current).parents.toList()
                            "child", "son", "daughter" -> children(current)
                            "sibling", "brother", "sister" -> people.keys.filter { siblings(current, it) }
                            else -> listOfNotNull(spouse(current))
                        }
                    }.filter { requiredSex == null || person(it).sex == requiredSex }.toSet()
                }
                found = found - id
                output.add("FIND $id $route ${found.size}")
                for (other in found.sorted()) output.add("  $other: ${relationshipString(other, id)}")
            }
            "TERM" -> output.add("TERM ${words[1]} ${words[2]} ${words[3]} ${term(words[1].toInt(), words[2].toInt(), words[3])}")
            "STATS" -> {
                val lengths = mutableMapOf<String, Int>()
                fun length(id: String): Int = lengths.getOrPut(id) {
                    1 + (person(id).parents.maxOfOrNull { length(it) } ?: 0)
                }
                val generations = people.keys.maxOfOrNull { length(it) } ?: 0
                output.add("STATS persons=${people.size} living=${people.values.count { it.death == null }} " +
                    "links=${people.values.sumOf { it.parents.size }} couples=${marriages.count { it.status == "current" }} " +
                    "founders=${people.values.count { it.parents.isEmpty() }} generations=$generations")
            }
            "AUDIT" -> {
                val rows = mutableListOf<String>()
                for (marriage in marriages) {
                    if (apex(marriage.first, marriage.second) != null) {
                        rows.add("  marriage ${marriage.first} ${marriage.second} ${bloodTerm(marriage.first, marriage.second)}")
                    }
                }
                for (id in people.keys.sorted()) {
                    val coefficient = inbreeding(id)
                    if (coefficient.numerator != 0L) rows.add("  inbred $id $coefficient")
                }
                output.add("AUDIT ${rows.size}")
                output.addAll(rows)
            }
        }
        if (before != null) history.add(UndoEntry(line, before))
        return output
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val family = Family()
    repeat(input.readLine().toInt()) {
        val line = input.readLine()
        val result = try {
            family.execute(line)
        } catch (error: CommandError) {
            listOf("ERROR ${error.message}")
        }
        for (row in result) {
            output.write(row)
            output.newLine()
        }
    }
    output.flush()
}
