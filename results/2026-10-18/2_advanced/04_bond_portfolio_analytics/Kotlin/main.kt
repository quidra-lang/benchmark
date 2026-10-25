import java.io.File

val bondTypes = listOf("FIXED", "ZERO", "AMORT", "FRN")
val bucketNames = listOf("0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+")
val frequencies = setOf(1, 2, 4, 12)
val dayCounts = setOf("30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT")
val businessRules = setOf("FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED")

fun roundRatio(numerator: Long, denominator: Long) = (2 * numerator + denominator) / (2 * denominator)
fun priceValue(text: String) = text.replace(".", "").toLong()
fun hundredths(value: Long): String { val magnitude = if (value < 0) -value else value; return (if (value < 0) "-" else "") + "${magnitude / 100}.${(magnitude % 100).toString().padStart(2, '0')}" }
fun decimal(value: Double, digits: Int): String {
    var scale = 1L
    repeat(digits) { scale *= 10 }
    val magnitude = ((if (value < 0.0) -value else value) * scale.toDouble() + 0.5).toLong()
    return (if (value < 0.0 && magnitude != 0L) "-" else "") + "${magnitude / scale}.${(magnitude % scale).toString().padStart(digits, '0')}"
}
fun percent(value: Double) = decimal(value * 100.0, 4)
fun amount(value: Double) = decimal(value / 100.0, 2)
fun maturityBucket(days: Int) = when { days < 365 -> 0; days < 1095 -> 1; days < 1825 -> 2; days < 3650 -> 3; else -> 4 }

class InputProblem(message: String) : Exception(message)
data class ScheduleOption(val date: String, val value: Long)
data class Call(val date: Int, val price: Long)
data class Fixing(val date: Int, val rate: Int)
data class Scenario(val name: String, val shifts: List<Int>)
data class Limit(val kind: String, val arguments: List<String>)
data class BondOptions(var eom: Boolean = false, var longStub: Boolean = false, var lag: Int = 0, var cap: Int = 1200, var floor: Int = 0, val sinks: MutableList<ScheduleOption> = mutableListOf(), val calls: MutableList<ScheduleOption> = mutableListOf())
data class Payment(val period: Int, val start: Int, val end: Int, val payment: Int, val fraction: Fraction, val rate: Int, val outstanding: Long, val coupon: Long, val principal: Long) { val cashFlow get() = coupon + principal }
data class Bond(val code: String, val type: String, val issue: Int, val maturity: Int, val frequency: Int, val daycount: String, val face: Long, val calls: List<Call>, val periods: List<Payment>)

fun parseOptions(type: String, text: String): BondOptions {
    val result = BondOptions()
    val allowed = setOf("EOM", "LONG") + when (type) { "FIXED" -> setOf("CALL"); "AMORT" -> setOf("SINK"); "FRN" -> setOf("LAG", "CAP", "FLOOR"); else -> emptySet() }
    val seen = mutableSetOf<String>()
    if (text != "-") for (item in text.split(';')) {
        val key = item.substringBefore('=')
        if (key !in allowed || key in seen && key != "SINK" && key != "CALL") throw InputProblem("invalid option")
        seen += key
        val value = item.substringAfter('=', "")
        when (key) {
            "EOM" -> result.eom = true
            "LONG" -> result.longStub = true
            "LAG" -> result.lag = value.toInt()
            "CAP" -> result.cap = value.toInt()
            "FLOOR" -> result.floor = value.toInt()
            "SINK", "CALL" -> {
                val parts = value.split(':')
                val entry = ScheduleOption(parts[0], if (key == "CALL") priceValue(parts[1]) else parts[1].toLong())
                if (key == "SINK") result.sinks += entry else result.calls += entry
            }
        }
    }
    if (type == "FRN" && ("LAG" !in seen || result.lag !in 1..5 || result.cap > 1200 || result.floor > result.cap)) throw InputProblem("invalid option")
    return result
}

fun fixingRate(fixings: List<Fixing>, day: Int): Int? {
    var lo = 0
    var hi = fixings.size
    while (lo < hi) { val mid = (lo + hi) / 2; if (fixings[mid].date <= day) lo = mid + 1 else hi = mid }
    return if (lo == 0) null else fixings[lo - 1].rate
}

fun buildBond(fields: List<String>, calendar: BusinessCalendar, fixings: List<Fixing>): Bond {
    val code = fields[0]
    val type = fields[1]
    if (type !in bondTypes) throw InputProblem("unknown type")
    if (!validDate(fields[2]) || !validDate(fields[3])) throw InputProblem("invalid date")
    val issue = parseDate(fields[2])
    val maturity = parseDate(fields[3])
    if (maturity <= issue) throw InputProblem("maturity not after issue")
    val coupon = fields[4].toInt()
    val frequency = fields[5].toInt()
    if (frequency !in frequencies) throw InputProblem("invalid frequency")
    val daycount = fields[6]
    if (daycount !in dayCounts) throw InputProblem("unknown day count")
    val bdc = fields[7]
    if (bdc !in businessRules) throw InputProblem("unknown business day rule")
    val face = fields[8].toLong()
    if (face % 100000L != 0L || face > 10000000L) throw InputProblem("invalid face")
    if (coupon > 1200 || type == "ZERO" && coupon != 0) throw InputProblem("invalid coupon")
    val options = parseOptions(type, fields[9])
    val dates = couponSchedule(issue, maturity, frequency, options.eom, options.longStub)
    val intermediate = dates.drop(1).dropLast(1).toSet()
    val sinks = mutableMapOf<Int, Long>()
    var previous = -1
    var total = 0L
    for (entry in options.sinks) {
        if (!validDate(entry.date)) throw InputProblem("invalid sinking fund")
        val date = parseDate(entry.date)
        if (date !in intermediate || date <= previous || entry.value == 0L) throw InputProblem("invalid sinking fund")
        previous = date
        total += entry.value
        sinks[date] = entry.value
    }
    if (type == "AMORT" && (total == 0L || total >= face)) throw InputProblem("invalid sinking fund")
    val calls = mutableListOf<Call>()
    previous = -1
    for (entry in options.calls) {
        if (!validDate(entry.date)) throw InputProblem("invalid call schedule")
        val date = parseDate(entry.date)
        if (date !in intermediate || date <= previous || entry.value !in 100000L..110000L) throw InputProblem("invalid call schedule")
        previous = date
        calls += Call(date, entry.value)
    }
    val periods = mutableListOf<Payment>()
    var outstanding = face
    for (index in 1 until dates.size) {
        val start = dates[index - 1]
        val end = dates[index]
        val fraction = yearFraction(daycount, start, end)
        var rate = if (type == "ZERO") 0 else coupon
        if (type == "FRN") {
            val fixingDay = calendar.move(calendar.adjust(start, bdc), options.lag, -1)
            rate += fixingRate(fixings, fixingDay) ?: throw InputProblem("missing fixing")
            rate = minOf(maxOf(rate, options.floor), options.cap)
        }
        val principal = if (index == dates.lastIndex) outstanding else sinks[end] ?: 0L
        val interest = roundRatio(outstanding * rate.toLong() * fraction.numerator, 10000L * fraction.denominator)
        periods += Payment(index, start, end, calendar.adjust(end, bdc), fraction, rate, outstanding, interest, principal)
        outstanding -= principal
    }
    return Bond(code, type, issue, maturity, frequency, daycount, face, calls, periods)
}

class Analytics(val bond: Bond, val price: Long, val settlement: Int, curve: ZeroCurve) {
    val current = bond.periods.indexOfFirst { it.end > settlement }
    val remaining = bond.periods.drop(current)
    val outstanding = remaining[0].outstanding
    val accruedFraction = yearFraction(bond.daycount, remaining[0].start, settlement)
    val accrued = remaining[0].rate.toDouble() * accruedFraction.numerator.toDouble() / (100.0 * accruedFraction.denominator.toDouble())
    val accruedAmount = roundRatio(outstanding * remaining[0].rate.toLong() * accruedFraction.numerator, 10000L * accruedFraction.denominator)
    val cleanAmount = roundRatio(outstanding * price, 100000L)
    val unitValue = cleanAmount + accruedAmount
    val target = price.toDouble() / 1000.0 + accrued
    val fraction = bond.frequency.toDouble() * yearFraction(bond.daycount, settlement, remaining[0].end).value()
    val pricer = YieldPricer(remaining.map { it.cashFlow }, fraction, bond.frequency, outstanding)
    init { if (!pricer.inRange(target)) throw InputProblem("yield out of range") }
    val ytm = pricer.solve(target)
    val risk = pricer.risk(ytm)
    var ytw = ytm
    var workout = bond.maturity
    init {
        for (call in bond.calls) if (call.date > settlement) {
            val periods = remaining.takeWhile { it.end <= call.date }
            val cashFlows = periods.map { it.coupon }.toMutableList()
            cashFlows[cashFlows.lastIndex] += roundRatio(periods.last().outstanding * call.price, 100000L)
            val callYield = YieldPricer(cashFlows, fraction, bond.frequency, outstanding).solve(target)
            if (callYield < ytw) { ytw = callYield; workout = call.date }
        }
    }
    val cashPeriods = remaining.filter { it.cashFlow > 0L }
    val flows = cashPeriods.map { CurveFlow(it.payment - settlement, it.cashFlow.toDouble()) }
    val nextPayment = cashPeriods[0].payment
    val wal: Double = run { var total = 0.0; for (period in cashPeriods) total += period.principal.toDouble() * (period.payment - settlement).toDouble(); total / (365.0 * outstanding.toDouble()) }
    val curveClean = curve.presentValue(flows) * 100.0 / outstanding.toDouble() - accrued
    val zspread = curve.zSpread(flows, unitValue.toDouble())
}

data class Position(val analytics: Analytics, var units: Long = 0L, var book: Long = 0L) {
    val bond get() = analytics.bond
    val value get() = units * analytics.unitValue
    val face get() = units * bond.face
    val outstanding get() = units * analytics.outstanding
    val gain get() = units * analytics.cleanAmount - book
    val dv01 get() = analytics.risk.dv01 * units.toDouble() * analytics.outstanding.toDouble() / 10000.0
    fun curveValue(curve: ZeroCurve) = units.toDouble() * curve.presentValue(analytics.flows, analytics.zspread)
}

class PortfolioReporter(val curve: ZeroCurve, val settlement: Int, val scenarios: List<Scenario>, val limits: List<Limit>) {
    val report = mutableListOf<String>()
    val scenarioLines = mutableListOf("portfolio,scenario,bond,value,pnl")
    val compliance = mutableListOf<String>()

    fun write(name: String, positions: List<Position>) {
        val totalValue = positions.sumOf { it.value }
        fun weighted(value: (Analytics) -> Double): Double { var total = 0.0; for (position in positions) total += position.value.toDouble() * value(position.analytics); return total / totalValue.toDouble() }
        val ytm = weighted { it.ytm }
        val modified = weighted { it.risk.modified }
        val convexity = weighted { it.risk.convexity }
        val zspread = weighted { it.zspread }
        var dv01 = 0.0
        for (position in positions) dv01 += position.dv01
        val flows = positions.flatMap { position -> position.analytics.cashPeriods.map { CurveFlow(it.payment - settlement, (position.units * it.cashFlow).toDouble()) } }
        val cashYield = bisection(0.0, 1.0, totalValue.toDouble()) { ZeroCurve(listOf(0), listOf(it)).presentValue(flows) }
        fun values(shifted: ZeroCurve) = positions.map { it.curveValue(shifted) }
        fun sum(values: List<Double>): Double { var total = 0.0; for (value in values) total += value; return total }
        val base = values(curve)
        val baseValue = sum(base)
        val down = curve.shifted(List(curve.days.size) { -0.0001 })
        val up = curve.shifted(List(curve.days.size) { 0.0001 })
        val effective = (sum(values(down)) - sum(values(up))) / (2.0 * 0.0001 * baseValue)
        val krd = curve.days.indices.map { index ->
            val delta = MutableList(curve.days.size) { 0.0 }
            delta[index] = -0.0001
            val lower = sum(values(curve.shifted(delta)))
            delta[index] = 0.0001
            (lower - sum(values(curve.shifted(delta)))) / (2.0 * 0.0001 * baseValue)
        }
        report += "portfolio $name"
        for (position in positions) {
            val a = position.analytics
            report += "position ${position.bond.code} face ${hundredths(position.face)} outstanding ${hundredths(position.outstanding)} clean ${decimal(a.price.toDouble() / 1000.0, 6)} value ${hundredths(position.value)} weight ${decimal(position.value.toDouble() * 100.0 / totalValue.toDouble(), 4)} book ${hundredths(position.book)} gain ${hundredths(position.gain)} ytm ${percent(a.ytm)} modified ${decimal(a.risk.modified, 4)} dv01 ${decimal(position.dv01, 2)}"
        }
        var income = 0L
        for (position in positions) for (period in position.analytics.cashPeriods) if (period.payment - settlement <= 365) income += position.units * period.coupon
        report += "total positions ${positions.size} face ${hundredths(positions.sumOf { it.face })} outstanding ${hundredths(positions.sumOf { it.outstanding })} value ${hundredths(totalValue)} book ${hundredths(positions.sumOf { it.book })} gain ${hundredths(positions.sumOf { it.gain })} income ${hundredths(income)}"
        report += "risk ytm ${percent(ytm)} yield ${percent(cashYield)} modified ${decimal(modified, 4)} convexity ${decimal(convexity, 4)} zspread ${percent(zspread)} dv01 ${decimal(dv01, 2)}"
        report += "curve effective ${decimal(effective, 4)} krd ${krd.joinToString(" ") { decimal(it, 4) }}"
        fun groupLine(label: String, group: String, selected: List<Position>): String {
            val value = selected.sumOf { it.value }
            var duration = 0.0
            var risk = 0.0
            for (position in selected) { duration += position.value.toDouble() * position.analytics.risk.modified; risk += position.dv01 }
            return "$label $group positions ${selected.size} value ${hundredths(value)} weight ${decimal(value.toDouble() * 100.0 / totalValue.toDouble(), 4)} duration ${decimal(duration / totalValue.toDouble(), 4)} dv01 ${decimal(risk, 2)}"
        }
        for (type in bondTypes) report += groupLine("type", type, positions.filter { it.bond.type == type })
        for (index in bucketNames.indices) report += groupLine("bucket", bucketNames[index], positions.filter { maturityBucket(it.bond.maturity - settlement) == index })
        val ladder = sortedMapOf<Int, Pair<Long, Long>>()
        for (position in positions) for (period in position.analytics.cashPeriods) {
            val year = civilDate(period.payment).year
            val previous = ladder[year] ?: (0L to 0L)
            ladder[year] = previous.first + position.units * period.coupon to previous.second + position.units * period.principal
        }
        var coupons = 0L
        var principal = 0L
        for ((year, totals) in ladder) {
            coupons += totals.first
            principal += totals.second
            report += "ladder $year coupon ${hundredths(totals.first)} principal ${hundredths(totals.second)} total ${hundredths(totals.first + totals.second)}"
        }
        report += "ladder total coupon ${hundredths(coupons)} principal ${hundredths(principal)} total ${hundredths(coupons + principal)}"
        var worst: Scenario? = null
        var worstPnl = 0.0
        var worstPositions = emptyList<Double>()
        for (scenario in listOf(Scenario("BASE", List(curve.days.size) { 0 })) + scenarios) {
            val scenarioValues = if (scenario.name == "BASE") base else values(curve.shifted(scenario.shifts.map { it.toDouble() * 0.0001 }))
            val pnl = scenarioValues.indices.map { scenarioValues[it] - base[it] }
            for (index in positions.indices) scenarioLines += "$name,${scenario.name},${positions[index].bond.code},${amount(scenarioValues[index])},${amount(pnl[index])}"
            val portfolioPnl = sum(scenarioValues) - baseValue
            scenarioLines += "$name,${scenario.name},*,${amount(sum(scenarioValues))},${amount(portfolioPnl)}"
            if (scenario.name != "BASE" && (worst == null || portfolioPnl < worstPnl)) { worst = scenario; worstPnl = portfolioPnl; worstPositions = pnl }
        }
        if (worst != null) {
            val losers = positions.indices.sortedWith(compareBy<Int> { worstPositions[it] }.thenBy { positions[it].bond.code }).take(3)
            report += "stress worst ${worst.name} pnl ${amount(worstPnl)} losers " + losers.joinToString(" ") { "${positions[it].bond.code} ${amount(worstPositions[it])}" }
        }
        var breaches = 0
        for (limit in limits) {
            val args = limit.arguments
            val details: String
            val breach: Boolean
            when (limit.kind) {
                "position_weight" -> {
                    val position = positions.sortedWith(compareByDescending<Position> { it.value }.thenBy { it.bond.code }).first()
                    val threshold = args[0].toLong()
                    breach = position.value * 10000L > threshold * totalValue
                    details = "${position.bond.code} ${decimal(position.value.toDouble() * 100.0 / totalValue.toDouble(), 4)} limit ${hundredths(threshold)}"
                }
                "type_weight" -> {
                    val value = positions.filter { it.bond.type == args[0] }.sumOf { it.value }
                    val threshold = args[1].toLong()
                    breach = value * 10000L > threshold * totalValue
                    details = "${args[0]} ${decimal(value.toDouble() * 100.0 / totalValue.toDouble(), 4)} limit ${hundredths(threshold)}"
                }
                "max_maturity" -> { val years = args[0].toInt(); val count = positions.count { it.bond.maturity - settlement > 365 * years }; breach = count > 0; details = "${years}Y positions $count" }
                "min_yield" -> { val threshold = args[0].toLong(); breach = ytm * 10000.0 < threshold.toDouble(); details = "${percent(ytm)} limit ${hundredths(threshold)}" }
                "duration" -> { val low = args[0].toLong(); val high = args[1].toLong(); breach = modified < low.toDouble() / 100.0 || modified > high.toDouble() / 100.0; details = "${decimal(modified, 4)} range ${hundredths(low)} ${hundredths(high)}" }
                else -> { val threshold = args[0].toLong(); breach = dv01 * 100.0 > threshold.toDouble(); details = "${decimal(dv01, 2)} limit ${hundredths(threshold)}" }
            }
            if (breach) breaches++
            compliance += "$name ${limit.kind} $details ${if (breach) "BREACH" else "PASS"}"
        }
        compliance += "$name breaches $breaches"
    }
}

fun csvRows(name: String) = File("input/$name").readLines().drop(1).mapIndexed { index, line -> index + 2 to line.split(',') }
fun writeLines(name: String, lines: List<String>) { File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n")) }

fun main() {
    val parameters = File("input/params.txt").readLines().map { it.split(' ') }
    val valuation = parseDate(parameters.first { it[0] == "valuation_date" }[1])
    val calendar = BusinessCalendar(File("input/calendar.txt").readLines().map(::parseDate).toSet())
    val settlement = calendar.move(valuation, parameters.first { it[0] == "settlement_days" }[1].toInt())
    val fixings = csvRows("fixings.csv").map { (_, fields) -> Fixing(parseDate(fields[0]), fields[1].toInt()) }
    val errors = mutableListOf<String>()
    fun error(file: String, line: Int, key: String, reason: String) { errors += "$file:$line: $key: $reason" }
    val pillars = mutableListOf<Pillar>()
    val seenPillars = mutableSetOf<String>()
    for ((line, fields) in csvRows("curve_quotes.csv")) {
        val reason = when {
            !seenPillars.add(fields[0]) -> "duplicate pillar"
            !validDate(fields[0]) -> "invalid date"
            parseDate(fields[0]) <= settlement -> "pillar not after settlement"
            fields[2].toInt() !in frequencies -> "invalid frequency"
            else -> null
        }
        if (reason != null) error("curve_quotes.csv", line, fields[0], reason)
        else pillars += Pillar(parseDate(fields[0]), fields[1].toInt(), fields[2].toInt())
    }
    pillars.sortBy { it.maturity }
    val scenarios = mutableListOf<Scenario>()
    val seenScenarios = mutableSetOf<String>()
    val limits = mutableListOf<Limit>()
    for ((index, words) in parameters.withIndex()) {
        if (words[0] == "limit") limits += Limit(words[1], words.drop(2))
        if (words[0] != "scenario") continue
        val reason = when { !seenScenarios.add(words[1]) -> "duplicate scenario"; words.size - 2 != pillars.size -> "wrong number of shifts"; else -> null }
        if (reason != null) error("params.txt", index + 1, words[1], reason)
        else scenarios += Scenario(words[1], words.drop(2).map(String::toInt))
    }
    val curve = bootstrap(settlement, pillars)
    val bonds = sortedMapOf<String, Bond>()
    val seenBonds = mutableSetOf<String>()
    for ((line, fields) in csvRows("bonds.csv")) {
        if (!seenBonds.add(fields[0])) { error("bonds.csv", line, fields[0], "duplicate id"); continue }
        try { bonds[fields[0]] = buildBond(fields, calendar, fixings) }
        catch (problem: InputProblem) { error("bonds.csv", line, fields[0], problem.message!!) }
    }
    val priced = sortedMapOf<String, Analytics>()
    val seenPrices = mutableSetOf<String>()
    for ((line, fields) in csvRows("prices.csv")) {
        val duplicate = !seenPrices.add(fields[0])
        val bond = bonds[fields[0]]
        val reason = when { bond == null -> "unknown bond"; duplicate -> "duplicate price"; !(bond.issue <= settlement && settlement < bond.maturity) -> "not outstanding"; else -> null }
        if (reason != null) { error("prices.csv", line, fields[0], reason); continue }
        try { priced[fields[0]] = Analytics(bond!!, priceValue(fields[1]), settlement, curve) }
        catch (problem: InputProblem) { error("prices.csv", line, fields[0], problem.message!!) }
    }
    val portfolios = sortedMapOf<String, MutableMap<String, Position>>()
    for ((line, fields) in csvRows("holdings.csv")) {
        val bond = bonds[fields[1]]
        val analytics = priced[fields[1]]
        val face = fields[2].toLong()
        val reason = when { bond == null -> "unknown bond"; analytics == null -> "no price"; face % bond.face != 0L -> "invalid face"; else -> null }
        if (reason != null) { error("holdings.csv", line, fields[1], reason); continue }
        val units = face / bond!!.face
        val position = portfolios.getOrPut(fields[0]) { sortedMapOf() }.getOrPut(fields[1]) { Position(analytics!!) }
        position.units += units
        position.book += roundRatio(units * analytics!!.outstanding * priceValue(fields[3]), 100000L)
    }
    val cashflowLines = mutableListOf("bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal")
    for (bond in bonds.values) for (period in bond.periods) if (period.cashFlow > 0L) cashflowLines += "${bond.code},${period.period},${dateText(period.start)},${dateText(period.end)},${dateText(period.payment)},${decimal(period.fraction.value(), 6)},${period.rate},${period.outstanding},${period.coupon},${period.principal}"
    val analyticsLines = mutableListOf("bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread")
    for (a in priced.values) analyticsLines += listOf(a.bond.code, decimal(a.price.toDouble() / 1000.0, 6), decimal(a.accrued, 6), decimal(a.target, 6), percent(a.ytm), percent(a.ytw), dateText(a.workout), dateText(a.nextPayment), decimal(a.wal, 4), decimal(a.risk.macaulay, 4), decimal(a.risk.modified, 4), decimal(a.risk.convexity, 4), decimal(a.risk.dv01, 6), decimal(a.curveClean, 6), percent(a.zspread)).joinToString(",")
    val curveLines = mutableListOf("valuation ${dateText(valuation)} settlement ${dateText(settlement)}")
    for ((index, pillar) in pillars.withIndex()) {
        val days = pillar.maturity - settlement
        val previous = if (index == 0) 0 else pillars[index - 1].maturity - settlement
        curveLines += "pillar ${dateText(pillar.maturity)} days $days frequency ${pillar.frequency} par ${hundredths(pillar.coupon.toLong())} zero ${percent(curve.rates[index])} df ${decimal(curve.discount(days), 6)} forward ${percent(curve.forward(previous, days))}"
    }
    for (year in 1..curve.days.last() / 365) curveLines += "grid ${year}Y days ${365 * year} zero ${percent(curve.zeroRate(365 * year))} df ${decimal(curve.discount(365 * year), 6)} forward ${percent(curve.forward(365 * (year - 1), 365 * year))}"
    val reporter = PortfolioReporter(curve, settlement, scenarios, limits)
    for ((name, positions) in portfolios) reporter.write(name, positions.toSortedMap().values.toList())
    File("output").mkdirs()
    writeLines("errors.txt", errors)
    writeLines("cashflows.csv", cashflowLines)
    writeLines("analytics.csv", analyticsLines)
    writeLines("curve.txt", curveLines)
    writeLines("portfolio.txt", reporter.report)
    writeLines("scenarios.csv", reporter.scenarioLines)
    writeLines("compliance.txt", reporter.compliance)
}
