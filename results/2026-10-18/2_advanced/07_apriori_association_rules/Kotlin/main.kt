import java.io.File

class Params(values: Map<String, String>) {
    val minSupport = values.getValue("min_support").toInt()
    val minConfidence = parseFraction(values.getValue("min_confidence"))
    val minLift = parseFraction(values.getValue("min_lift"))
    val maxSize = values.getValue("max_size").toInt()
    val categorySupport = values.getValue("category_min_support").toInt()
    val sequenceSupport = values.getValue("sequence_min_support").toInt()
    val splitDay = values.getValue("split_day").toInt()
    val trainSupport = values.getValue("train_min_support").toInt()
    val testSupport = values.getValue("test_min_support").toInt()
    val top = values.getValue("recommend_top").toInt()
    val matrixSize = values.getValue("matrix_size").toInt()
    val groupLift = parseFraction(values.getValue("group_min_lift"))
    val negativeLift = parseFraction(values.getValue("negative_max_lift"))
    val negativeExpected = values.getValue("negative_min_expected").toInt()
    val trendThreshold = parseFraction(values.getValue("trend_threshold"))
}
fun parseFraction(text: String): Fraction { val parts = text.split('/'); return Fraction(parts[0].toLong(), parts[1].toLong()) }
fun readParams() = Params(File("input/params.txt").readLines().associate { val words = it.split(' '); words[0] to words[1] })
fun median(values: List<Int>): Fraction { val ordered = values.sorted(); val middle = ordered.size / 2; return if (ordered.size % 2 == 1) Fraction(ordered[middle]) else Fraction(ordered[middle - 1] + ordered[middle], 2) }
fun splitItems(items: List<String>, mask: Int) = items.filterIndexed { index, _ -> mask and (1 shl index) != 0 } to items.filterIndexed { index, _ -> mask and (1 shl index) == 0 }
fun recommend(held: Set<String>, candidates: List<String>, limit: Int): List<String> {
    val selected = mutableListOf<String>()
    for (candidate in candidates) { if (selected.size == limit) break; if (candidate !in held && candidate !in selected) selected += candidate }
    return selected
}
fun ruleCandidates(rules: List<Rule>, held: Set<String>) = rules.filter { it.consequent.size == 1 && contains(held, it.antecedent) }.map { it.consequent[0] }
class Dataset {
    val errors = mutableListOf<String>()
    val products = mutableMapOf<String, Product>()
    val transactions = mutableListOf<Transaction>()
    var itemRows = 0
    var transactionLines = 0
    var adopted = 0
    var rejected = 0
    var duplicates = 0
    val baskets get() = transactions.filter { it.counts.isNotEmpty() }
    init {
        val items = readRecords("items.csv")
        itemRows = items.size
        for ((index, row) in items.withIndex()) {
            val price = row[2].toLong()
            val problem = when { row[0] in products -> "duplicate item ${row[0]}"; price == 0L -> "bad price $price"; else -> null }
            if (problem != null) errors += "items.csv line ${index + 2}: $problem"
            else products[row[0]] = Product(row[0], row[1], price)
        }
        val rows = readRecords("transactions.csv")
        transactionLines = rows.size
        val known = mutableSetOf<String>()
        for ((index, row) in rows.withIndex()) {
            val (tid, customer, dayText, item) = row
            val day = dayText.toInt()
            var problem: String? = null
            if (tid in known && tid != transactions.last().tid) problem = "tid $tid not contiguous"
            else {
                if (known.add(tid)) transactions += Transaction(tid, customer, day)
                val current = transactions.last()
                problem = when { customer != current.customer -> "tid $tid customer $customer differs from ${current.customer}"; day != current.day -> "tid $tid day $day differs from ${current.day}"; item !in products -> "unknown item $item"; else -> null }
            }
            if (problem != null) { errors += "transactions.csv line ${index + 2}: $problem"; rejected++ }
            else { adopted++; if (transactions.last().add(item)) duplicates++ }
        }
    }
}
data class Level(val number: Int, val candidates: Int, val excluded: Int, val pruned: Int, val counted: Int, val items: List<List<String>>)
data class AprioriResult(val levels: MutableList<Level> = mutableListOf(), val supports: MutableMap<List<String>, Int> = mutableMapOf(), val singles: MutableMap<String, Int> = mutableMapOf())
fun runApriori(index: BasketIndex, universe: List<String>, minimum: Int, maxSize: Int, taxonomy: Map<String, String>? = null): AprioriResult {
    val result = AprioriResult()
    fun addLevel(number: Int, candidates: Int, excluded: Int, pruned: Int, items: List<List<String>>): List<List<String>> {
        val counts = countSupports(index, items)
        val frequent = items.filter { counts.getValue(it) >= minimum }.sortedWith(::compareItems)
        result.levels += Level(number, candidates, excluded, pruned, items.size, frequent)
        for (item in frequent) result.supports[item] = counts.getValue(item)
        if (number == 1) for ((item, count) in counts) result.singles[item[0]] = count
        return frequent
    }
    val singles = universe.sorted().map { listOf(it) }
    var previous = addLevel(1, singles.size, 0, 0, singles)
    var size = 2
    while (size <= maxSize && previous.isNotEmpty()) {
        val level = generateCandidates(previous, size, taxonomy)
        previous = addLevel(size, level.joined, level.excluded, level.pruned, level.items)
        size++
    }
    return result
}
fun makeRules(supports: Map<List<String>, Int>, total: Int, params: Params, required: Set<String>? = null): RuleSet {
    var generated = 0
    val kept = mutableListOf<Rule>()
    fun support(items: List<String>) = if (items.isEmpty()) total else supports.getValue(items)
    for ((items, count) in supports) {
        if (items.size < 2 || required != null && items.none { it in required }) continue
        for (mask in 1 until (1 shl items.size) - 1) {
            val (first, second) = splitItems(items, mask)
            generated++
            val rule = Rule(items, first, second, count, total, support(first), support(second))
            if (!meets(rule.confidence, rule.lift, params)) continue
            var reference = Fraction(0)
            for (subsetMask in 0 until (1 shl first.size) - 1) {
                val subset = splitItems(first, subsetMask).first
                val candidate = Fraction(support((subset + second).sorted()), support(subset))
                if (candidate > reference) reference = candidate
            }
            rule.improvement = rule.confidence - reference
            kept += rule
        }
    }
    kept.sortWith(::compareRules)
    for ((index, rule) in kept.withIndex()) rule.rank = index + 1
    return RuleSet(generated, kept)
}
data class Sequence(val first: String, val second: String, val count: Int, val base: Int, val confidence: Fraction, val lift: Fraction, val gap: Fraction)
data class Repeat(val name: String, val customers: Int, val intervals: List<Int>) { val mean get() = Fraction(intervals.sum(), intervals.size) }
class Tally {
    var cases = 0
    var covered = 0
    var topHits = 0
    var hits = 0
    var baselineHits = 0
    fun add(held: String, suggested: List<String>, baseline: List<String>) { cases++; if (suggested.isNotEmpty()) covered++; if (suggested.firstOrNull() == held) topHits++; if (held in suggested) hits++; if (held in baseline) baselineHits++ }
    fun describe() = "cases $cases covered $covered hit1 $topHits hit $hits rate ${fractionText(Fraction(hits, cases))} baseline $baselineHits rate ${fractionText(Fraction(baselineHits, cases))}"
}
data class RuleCheck(val rule: Rule, val together: Int, val first: Int, val confidence: Fraction?, val lift: Fraction?, val verdict: String)
data class ProductGroup(val members: List<String>, val edges: Int, val core: String, val revenue: Long)
data class Substitute(val first: String, val second: String, val count: Int, val expected: Fraction, val lift: Fraction)
data class Trend(val name: String, val units: Long, val slope: Fraction, val relative: Fraction?, val verdict: String)
data class CustomerSummary(val name: String, val baskets: Int, val days: Int, val first: Int, val last: Int, val products: Int, val units: Int, val revenue: Long, val favorite: String, val segment: String, val offer: List<String>)

class MarketAnalysis(val params: Params, val data: Dataset) {
    val products = data.products
    val names = products.keys.sorted()
    val taxonomy = products.mapValues { it.value.category }
    val categories = taxonomy.values.distinct().sorted()
    val baskets = data.baskets
    val itemSets = baskets.map { it.products }
    val index = BasketIndex(itemSets)
    val extended = BasketIndex(itemSets.map { extendedBasket(it, taxonomy) })
    val total = baskets.size
    val customerBaskets = baskets.groupBy { it.customer }
    val customers = customerBaskets.keys.sorted()
    val histories = customerBaskets.mapValues { (_, baskets) ->
        val days = mutableMapOf<String, MutableSet<Int>>()
        for (basket in baskets) for (name in basket.products) days.getOrPut(name) { mutableSetOf() } += basket.day
        days.mapValues { it.value.sorted() }
    }
    val buyers = names.associateWith { name -> histories.values.count { name in it } }
    val firstDay = baskets.minOf { it.day }
    val lastDay = baskets.maxOf { it.day }
    val main = runApriori(index, names, params.minSupport, params.maxSize)
    val frequent = main.supports
    val counts = main.singles
    val pairs = frequent.keys.filter { it.size == 2 }
    val growth = fpGrowth(itemSets.map { Pattern(it.sorted(), 1) }, params.minSupport, params.maxSize)
    val mainRules = makeRules(frequent, total, params)
    val categoryRun = runApriori(extended, names + categories, params.categorySupport, params.maxSize, taxonomy)
    val categoryRules = makeRules(categoryRun.supports, total, params, categories.toSet())
    val training = baskets.filter { it.day <= params.splitDay }
    val testing = baskets.filter { it.day > params.splitDay }
    val trainIndex = BasketIndex(training.map { it.products })
    val testIndex = BasketIndex(testing.map { it.products })
    val trainRun = runApriori(trainIndex, names, params.trainSupport, params.maxSize)
    val testRun = runApriori(testIndex, names, params.testSupport, params.maxSize)
    val trainRules = makeRules(trainRun.supports, training.size, params).rules
    val testRules = makeRules(testRun.supports, testing.size, params).rules
    val checks = trainRules.map { rule ->
        val a = testIndex.count(rule.antecedent)
        val b = testIndex.count(rule.consequent)
        val c = testIndex.count(rule.items)
        val confidence = if (a == 0 || b == 0) null else Fraction(c, a)
        val lift = if (a == 0 || b == 0) null else liftOf(testing.size, c, a, b)
        RuleCheck(rule, c, a, confidence, lift, if (confidence == null || lift == null) "UNSEEN" else if (meets(confidence, lift, params)) "HOLD" else "FAIL")
    }
    val emerging = testRules.filter { test -> trainRules.none { it.antecedent == test.antecedent && it.consequent == test.consequent } }
    val heldOut = names.associateWith { 0 }.toMutableMap()
    val heldHits = names.associateWith { 0 }.toMutableMap()
    val tallies = mutableMapOf<Int, Tally>()
    val overall = Tally()
    val units = names.associateWith { name -> baskets.sumOf { it.counts[name] ?: 0 } }
    val revenue = names.associateWith { units.getValue(it).toLong() * products.getValue(it).price }
    val totalRevenue = revenue.values.sum()
    val sequences = mutableListOf<Sequence>()
    val repeats = mutableListOf<Repeat>()
    var sequencePairs = 0
    val closed: List<List<String>>
    val maximal: List<List<String>>
    val generators: List<List<String>>
    val groups: List<ProductGroup>
    val substitutes: List<Substitute>
    val customerSummaries: List<CustomerSummary>
    init {
        val nonClosed = mutableSetOf<List<String>>()
        val nonMaximal = mutableSetOf<List<String>>()
        for ((items, count) in frequent) if (items.size > 1) for (subset in smallerSubsets(items)) { nonMaximal += subset; if (frequent[subset] == count) nonClosed += subset }
        val ordered = frequent.keys.sortedWith(::sizeOrder)
        closed = ordered.filter { it !in nonClosed }
        maximal = ordered.filter { it !in nonMaximal }
        generators = ordered.filter { items -> smallerSubsets(items).all { (if (it.isEmpty()) total else frequent.getValue(it)) > frequent.getValue(items) } }
        analyzeSequences()
        val popularity = names.sortedWith(compareBy({ -trainRun.singles.getValue(it) }, { it }))
        for (basket in testing) if (basket.products.size >= 2) for (held in basket.products.sorted()) {
            val atHand = basket.products - held
            val suggestion = recommend(atHand, ruleCandidates(trainRules, atHand), params.top)
            val baseline = recommend(atHand, popularity, params.top)
            tallies.getOrPut(basket.products.size) { Tally() }.add(held, suggestion, baseline)
            overall.add(held, suggestion, baseline)
            heldOut[held] = heldOut.getValue(held) + 1
            if (held in suggestion) heldHits[held] = heldHits.getValue(held) + 1
        }
        groups = buildGroups()
        substitutes = buildSubstitutes()
        customerSummaries = customers.map { customer ->
            val baskets = customerBaskets.getValue(customer)
            val days = baskets.map { it.day }.distinct().sorted()
            val categoryUnits = categories.associateWith { category -> baskets.sumOf { basket -> basket.counts.filterKeys { taxonomy.getValue(it) == category }.values.sum() } }
            val favorite = categories.sortedWith(compareBy({ -categoryUnits.getValue(it) }, { it })).first()
            val segment = when { days.first() > lastDay - 28 -> "NEW"; baskets.size >= 4 && lastDay - days.last() <= 14 -> "LOYAL"; lastDay - days.last() > 28 -> "AT_RISK"; else -> "REGULAR" }
            val held = histories.getValue(customer).keys
            CustomerSummary(customer, baskets.size, days.size, days.first(), days.last(), held.size, baskets.sumOf { it.units }, baskets.sumOf { basket -> basket.counts.entries.sumOf { (name, count) -> count.toLong() * products.getValue(name).price } }, favorite, segment, recommend(held, ruleCandidates(mainRules.rules, held), params.top))
        }
    }
    fun analyzeSequences() {
        for (first in names) for (second in names) {
            val gaps = mutableListOf<Int>()
            for (history in histories.values) {
                val a = history[first] ?: continue
                val b = history[second] ?: continue
                if (a.first() >= b.last()) continue
                var shortest = Int.MAX_VALUE
                for (earlier in a) for (later in b) if (earlier < later) shortest = minOf(shortest, later - earlier)
                gaps += shortest
            }
            if (gaps.isNotEmpty()) sequencePairs++
            if (gaps.size >= params.sequenceSupport) sequences += Sequence(first, second, gaps.size, buyers.getValue(first), Fraction(gaps.size, buyers.getValue(first)), liftOf(customers.size, gaps.size, buyers.getValue(first), buyers.getValue(second)), median(gaps))
        }
        sequences.sortWith { a, b -> when { a.count != b.count -> b.count.compareTo(a.count); a.confidence != b.confidence -> b.confidence.compareTo(a.confidence); a.first != b.first -> a.first.compareTo(b.first); else -> a.second.compareTo(b.second) } }
        for (name in names) {
            val intervals = mutableListOf<Int>()
            var buyers = 0
            for (history in histories.values) { val days = history[name] ?: continue; if (days.size > 1) { buyers++; intervals += days.zipWithNext { a, b -> b - a } } }
            if (intervals.isNotEmpty()) repeats += Repeat(name, buyers, intervals)
        }
        repeats.sortWith { a, b -> if (a.mean != b.mean) a.mean.compareTo(b.mean) else a.name.compareTo(b.name) }
    }
    fun pairLift(pair: List<String>) = liftOf(total, frequent.getValue(pair), counts.getValue(pair[0]), counts.getValue(pair[1]))
    fun buildGroups(): List<ProductGroup> {
        val edges = pairs.filter { pairLift(it) >= params.groupLift }
        val neighbors = names.associateWith { mutableSetOf<String>() }
        for (edge in edges) { neighbors.getValue(edge[0]) += edge[1]; neighbors.getValue(edge[1]) += edge[0] }
        val visited = mutableSetOf<String>()
        val groups = mutableListOf<ProductGroup>()
        for (name in names) {
            if (name in visited || neighbors.getValue(name).isEmpty()) continue
            val stack = mutableListOf(name)
            val members = mutableListOf<String>()
            visited += name
            while (stack.isNotEmpty()) { val current = stack.removeAt(stack.lastIndex); members += current; for (neighbor in neighbors.getValue(current)) if (visited.add(neighbor)) stack += neighbor }
            members.sort()
            val core = members.sortedWith(compareBy({ -neighbors.getValue(it).size }, { -counts.getValue(it) }, { it })).first()
            groups += ProductGroup(members, edges.count { it[0] in members }, core, members.sumOf { revenue.getValue(it) })
        }
        return groups.sortedWith(compareBy({ -it.members.size }, { it.members[0] }))
    }
    fun buildSubstitutes(): List<Substitute> {
        val singles = main.levels[0].items.map { it[0] }
        val result = mutableListOf<Substitute>()
        for (first in singles.indices) for (second in first + 1 until singles.size) {
            val a = singles[first]
            val b = singles[second]
            val expected = counts.getValue(a).toLong() * counts.getValue(b)
            if (expected < params.negativeExpected.toLong() * total) continue
            val together = index.count(listOf(a, b))
            val lift = liftOf(total, together, counts.getValue(a), counts.getValue(b))
            if (lift <= params.negativeLift) result += Substitute(a, b, together, Fraction(expected, total.toLong()), lift)
        }
        return result.sortedWith { a, b -> when { a.lift != b.lift -> a.lift.compareTo(b.lift); a.expected != b.expected -> b.expected.compareTo(a.expected); a.first != b.first -> a.first.compareTo(b.first); else -> a.second.compareTo(b.second) } }
    }
    fun summaryLines(): List<String> {
        val sizes = itemSets.map { it.size }
        val lines = data.errors.map { "ERROR $it" }.toMutableList()
        lines += "ITEMS rows ${data.itemRows} adopted ${products.size} categories ${categories.size}"
        lines += "TRANSACTIONS lines ${data.transactionLines} adopted ${data.adopted} rejected ${data.rejected} duplicates ${data.duplicates} transactions ${data.transactions.size} empty ${data.transactions.size - total}"
        lines += "BASKETS count $total customers ${customers.size} first_day $firstDay last_day $lastDay average_size ${fractionText(Fraction(sizes.sum(), total))} largest ${sizes.max()}"
        for (size in 1..sizes.max()) { val count = sizes.count { it == size }; lines += "SIZE $size baskets $count share ${percentText(count.toLong(), total.toLong())}" }
        lines += "FREQUENT itemsets ${frequent.size} closed ${closed.size} maximal ${maximal.size} generators ${generators.size} levels ${main.levels.size}"
        val matched = growth.itemsets == frequent
        lines += "FPGROWTH header ${growth.header} nodes ${growth.nodes} conditional_trees ${growth.conditionalTrees} conditional_nodes ${growth.conditionalNodes} itemsets ${growth.itemsets.size} ${if (matched) "MATCH" else "MISMATCH"}"
        if (!matched) for ((label, first, second) in listOf(Triple("ONLY_APRIORI", frequent, growth.itemsets), Triple("ONLY_FPGROWTH", growth.itemsets, frequent))) for (items in first.keys.sortedWith(::sizeOrder)) if (first[items] != second[items]) lines += "$label ${itemsetText(items)} ${first.getValue(items)}"
        lines += "RULES generated ${mainRules.generated} passed ${mainRules.rules.size} productive ${mainRules.productive}"
        for (level in categoryRun.levels) lines += "CATEGORY_LEVEL ${level.number} candidates ${level.candidates} taxonomy ${level.excluded} pruned ${level.pruned} counted ${level.counted} frequent ${level.items.size}"
        lines += "CATEGORY_RULES itemsets ${categoryRun.supports.size} generated ${categoryRules.generated} passed ${categoryRules.rules.size} productive ${categoryRules.productive}"
        lines += "SEQUENCES customers ${customers.size} multi_day ${customerSummaries.count { it.days >= 2 }} pairs $sequencePairs frequent ${sequences.size}"
        return lines
    }
    fun itemsetLines() = main.levels.flatMap { level -> listOf("LEVEL ${level.number} candidates ${level.candidates} pruned ${level.pruned} counted ${level.counted} frequent ${level.items.size}") + level.items.map { "${itemsetText(it)} ${frequent.getValue(it)}" } }
    fun closedLines() = listOf("CLOSED" to closed, "MAXIMAL" to maximal, "GENERATOR" to generators).flatMap { (label, items) -> items.map { "$label ${itemsetText(it)} ${frequent.getValue(it)}" } }
    fun sequenceLines() = sequences.mapIndexed { rank, sequence -> "SEQ ${rank + 1} ${sequence.first} -> ${sequence.second} customers ${sequence.count} base ${sequence.base} confidence ${fractionText(sequence.confidence)} lift ${fractionText(sequence.lift)} gap ${fractionText(sequence.gap)}" } + repeats.map { "REPEAT ${it.name} customers ${it.customers} intervals ${it.intervals.size} min ${it.intervals.min()} max ${it.intervals.max()} mean ${fractionText(it.mean)} median ${fractionText(median(it.intervals))}" }
    fun validationLines(): List<String> {
        val lines = checks.map { check ->
            val rule = check.rule
            "RULE ${rule.rank} ${ruleArrow(rule)} train ${rule.count} confidence ${fractionText(rule.confidence)} lift ${fractionText(rule.lift)} test ${check.together} of ${check.first} confidence ${check.confidence?.let(::fractionText) ?: "-"} lift ${check.lift?.let(::fractionText) ?: "-"} ${check.verdict}"
        }.toMutableList()
        for (rule in emerging) lines += "EMERGING ${rule.rank} ${ruleArrow(rule)} test ${rule.count} confidence ${fractionText(rule.confidence)} lift ${fractionText(rule.lift)}"
        lines += "VALIDATION train ${training.size} test ${testing.size} itemsets ${trainRun.supports.size} rules ${trainRules.size} hold ${checks.count { it.verdict == "HOLD" }} fail ${checks.count { it.verdict == "FAIL" }} unseen ${checks.count { it.verdict == "UNSEEN" }} emerging ${emerging.size}"
        for (size in tallies.keys.sorted()) lines += "RECOMMEND size $size ${tallies.getValue(size).describe()}"
        lines += "RECOMMEND total ${overall.describe()}"
        return lines
    }
    fun partner(name: String): String {
        val eligible = pairs.filter { name in it }.sortedWith { a, b ->
            val first = pairLift(a)
            val second = pairLift(b)
            when { first != second -> second.compareTo(first); frequent.getValue(a) != frequent.getValue(b) -> frequent.getValue(b).compareTo(frequent.getValue(a)); else -> a.first { it != name }.compareTo(b.first { it != name }) }
        }
        val pair = eligible.firstOrNull() ?: return "none"
        return "${pair.first { it != name }} ${fractionText(pairLift(pair))}"
    }
    fun matrixLines(label: String, names: List<String>, index: BasketIndex, counts: Map<String, Int>): List<String> {
        val lines = names.mapIndexed { position, name -> "$label ${position + 1} $name baskets ${counts.getValue(name)}" }.toMutableList()
        lines += "    " + (1..names.size).joinToString("") { it.toString().padStart(7) }
        for ((row, first) in names.withIndex()) lines += (row + 1).toString().padStart(4) + names.mapIndexed { column, second -> if (row == column) "-" else (100L * index.baskets.size * index.count(listOf(first, second)) / (counts.getValue(first).toLong() * counts.getValue(second))).toString() }.joinToString("") { it.padStart(7) }
        return lines
    }
    fun itemLines(): List<String> {
        val lines = mutableListOf<String>()
        for ((position, name) in names.sortedWith(compareBy({ -revenue.getValue(it) }, { it })).withIndex()) {
            val product = products.getValue(name)
            val strongest = mainRules.rules.firstOrNull { name in it.items }?.let { "${it.rank} ${ruleArrow(it)}" } ?: "none"
            lines += "ITEM ${position + 1} $name ${product.category} price ${money(product.price)} units ${units.getValue(name)} revenue ${money(revenue.getValue(name))} share ${percentText(revenue.getValue(name), totalRevenue)} baskets ${counts.getValue(name)} support ${fractionText(Fraction(counts.getValue(name), total))} customers ${buyers.getValue(name)} itemsets ${frequent.keys.count { name in it }} heldout ${heldOut.getValue(name)} hits ${heldHits.getValue(name)} partner ${partner(name)} best $strongest"
        }
        val categoryRevenue = categories.associateWith { category -> names.filter { taxonomy.getValue(it) == category }.sumOf { revenue.getValue(it) } }
        for (category in categories.sortedWith(compareBy({ -categoryRevenue.getValue(it) }, { it }))) {
            val members = names.filter { taxonomy.getValue(it) == category }
            val count = categoryRun.singles.getValue(category)
            lines += "CATEGORY $category items ${members.size} units ${members.sumOf { units.getValue(it) }} revenue ${money(categoryRevenue.getValue(category))} share ${percentText(categoryRevenue.getValue(category), totalRevenue)} baskets $count support ${fractionText(Fraction(count, total))}"
        }
        lines += "TOTAL items ${products.size} units ${units.values.sum()} revenue ${money(totalRevenue)} baskets $total customers ${customers.size}"
        for ((position, group) in groups.withIndex()) lines += "GROUP ${position + 1} items ${group.members.size} edges ${group.edges} core ${group.core} revenue ${money(group.revenue)} share ${percentText(group.revenue, totalRevenue)} members ${itemsetText(group.members)}"
        for (substitute in substitutes) lines += "SUBSTITUTE ${substitute.first} ${substitute.second} count ${substitute.count} expected ${fractionText(substitute.expected)} lift ${fractionText(substitute.lift)}"
        lines += matrixLines("MATRIX", names.sortedWith(compareBy({ -counts.getValue(it) }, { it })).take(params.matrixSize), index, counts)
        lines += matrixLines("CATEGORY_MATRIX", categories.sortedWith(compareBy({ -categoryRun.singles.getValue(it) }, { it })), extended, categoryRun.singles)
        return lines
    }
    fun trendLines(): List<String> {
        val weeks = (lastDay - 1) / 7 + 1
        val weekBaskets = IntArray(weeks)
        val weekUnits = IntArray(weeks)
        val weekCustomers = List(weeks) { mutableSetOf<String>() }
        val series = (categories + names).associateWith { LongArray(weeks) }
        for (basket in baskets) {
            val week = (basket.day - 1) / 7
            weekBaskets[week]++
            weekUnits[week] += basket.units
            weekCustomers[week] += basket.customer
            for ((name, count) in basket.counts) { series.getValue(name)[week] += count.toLong(); series.getValue(taxonomy.getValue(name))[week] += count.toLong() }
        }
        fun row(label: String, values: List<String>) = label.padEnd(17) + values.joinToString("") { it.padStart(6) }
        val lines = mutableListOf(row("WEEK", (1..weeks).map(Int::toString)), row("BASKETS", weekBaskets.map(Int::toString)), row("UNITS", weekUnits.map(Int::toString)), row("CUSTOMERS", weekCustomers.map { it.size.toString() }))
        for (name in categories + names) lines += row(name, series.getValue(name).map(Long::toString))
        val weekSum = (1..weeks).sumOf { it.toLong() }
        val squareSum = (1..weeks).sumOf { it.toLong() * it }
        val trends = (categories + names).map { name ->
            val values = series.getValue(name)
            val total = values.sum()
            val weighted = values.withIndex().sumOf { (position, value) -> (position + 1).toLong() * value }
            val slope = Fraction(weeks.toLong() * weighted - weekSum * total, weeks.toLong() * squareSum - weekSum * weekSum)
            val relative = if (total == 0L) null else Fraction(slope.numerator * weeks, slope.denominator * total)
            val verdict = when { relative == null -> "NONE"; relative >= params.trendThreshold -> "RISING"; relative <= -params.trendThreshold -> "FALLING"; else -> "FLAT" }
            Trend(name, total, slope, relative, verdict)
        }.sortedWith { a, b -> when { a.relative == null && b.relative != null -> 1; a.relative != null && b.relative == null -> -1; a.relative != null && b.relative != null && a.relative != b.relative -> b.relative.compareTo(a.relative); else -> a.name.compareTo(b.name) } }
        for (trend in trends) lines += "TREND ${trend.name} units ${trend.units} slope ${fractionText(trend.slope)} relative ${trend.relative?.let(::fractionText) ?: "-"} ${trend.verdict}"
        return lines
    }
    fun customerLines(): List<String> {
        val lines = customerSummaries.map { summary -> "CUSTOMER ${summary.name} baskets ${summary.baskets} days ${summary.days} first ${summary.first} last ${summary.last} items ${summary.products} units ${summary.units} revenue ${money(summary.revenue)} average ${money(summary.revenue / summary.baskets)} favorite ${summary.favorite} segment ${summary.segment} offer ${if (summary.offer.isEmpty()) "none" else itemsetText(summary.offer)}" }.toMutableList()
        for (segment in listOf("NEW", "LOYAL", "AT_RISK", "REGULAR")) { val members = customerSummaries.filter { it.segment == segment }; val revenue = members.sumOf { it.revenue }; lines += "SEGMENT $segment customers ${members.size} revenue ${money(revenue)} share ${percentText(revenue, totalRevenue)}" }
        return lines
    }
    fun write() {
        for ((name, lines) in listOf("summary.txt" to summaryLines(), "itemsets.txt" to itemsetLines(), "closed_maximal.txt" to closedLines(), "rules.csv" to rulesCsv(mainRules.rules), "category_rules.csv" to rulesCsv(categoryRules.rules), "sequences.txt" to sequenceLines(), "validation.txt" to validationLines(), "items_report.txt" to itemLines(), "trends.txt" to trendLines(), "customers.txt" to customerLines())) writeReport(name, lines)
    }
}
fun main() { MarketAnalysis(readParams(), Dataset()).write() }
