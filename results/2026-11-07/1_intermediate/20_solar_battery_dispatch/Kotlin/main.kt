import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.max
import kotlin.math.min

private val settingNames = listOf(
    "CAPACITY", "INITIAL", "CHARGE", "DISCHARGE", "CEFF", "DEFF", "RESERVE", "COST",
    "EXPORT", "FEEDIN", "FIXED", "DEMAND", "PVSCALE"
)
private val settingRanges = mapOf(
    "CAPACITY" to (1L..100000L), "INITIAL" to (0L..100L),
    "CHARGE" to (1L..20000L), "DISCHARGE" to (1L..20000L),
    "CEFF" to (1L..100L), "DEFF" to (1L..100L),
    "RESERVE" to (0L..100L), "COST" to (0L..100000L),
    "EXPORT" to (0L..100000L), "FEEDIN" to (0L..10000L),
    "FIXED" to (0L..100000L), "DEMAND" to (0L..100000L),
    "PVSCALE" to (0L..300L)
)
private val strategyRanges = mapOf(
    "TOU" to (1L..100L), "PEAKSHAVE" to (0L..100000L), "BACKUP" to (0L..100L)
)
private val weekdays = listOf("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")
private val flowNames = listOf(
    "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
    "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY"
)

private class CommandError(message: String) : Exception(message)
private fun fail(message: String): Nothing = throw CommandError(message)
private fun ceil(numerator: Long, denominator: Long): Long =
    (numerator + denominator - 1) / denominator
private fun money(cents: Long): String {
    val absolute = if (cents < 0) -cents else cents
    return "${if (cents < 0) "-" else ""}${absolute / 100}.${(absolute % 100).toString().padStart(2, '0')}"
}
private fun percentage(numerator: Long, denominator: Long): String {
    val n = if (denominator == 0L) 0 else 10000 * numerator / denominator
    return "${n / 100}.${(n % 100).toString().padStart(2, '0')}"
}
private fun rightRow(values: List<Any>, widths: List<Int>): String =
    values.zip(widths).joinToString("") { (value, width) -> value.toString().padStart(width) }
private fun bar(width: Int): String = "|${"#".repeat(width)}${".".repeat(20 - width)}|"
private fun gcd(left: Long, right: Long): Long {
    var a = left
    var b = right
    while (b != 0L) { val old = b; b = a % b; a = old }
    return a
}

private data class Strategy(val name: String, val parameter: Long? = null) {
    override fun toString(): String = if (parameter == null) name else "$name $parameter"
}

private fun readStrategies(words: List<String>): List<Strategy> {
    val strategies = mutableListOf<Strategy>()
    var i = 0
    while (i < words.size) {
        val name = words[i++]
        if (name == "SELF" || name == "EXPORTPEAK") {
            strategies.add(Strategy(name))
            continue
        }
        val valid = strategyRanges[name] ?: fail("unknown strategy $name")
        if (i >= words.size) fail("missing parameter for $name")
        val parameter = words[i++].toLong()
        if (parameter !in valid) fail("invalid parameter for $name")
        strategies.add(Strategy(name, parameter))
    }
    return strategies
}
private fun requireCount(args: List<String>, expected: Int) {
    if (args.size != expected) fail("wrong number of arguments")
}
private fun oneStrategy(args: List<String>): Strategy {
    val strategies = readStrategies(args)
    if (strategies.size != 1) fail("wrong number of arguments")
    return strategies.single()
}
private fun checkedRange(low: Long, high: Long, step: Long, range: LongRange): List<Long> {
    if (low < range.first || high > range.last || high < low || step < 1L ||
        (high - low) / step + 1 > 20) fail("invalid range")
    return generateSequence(low) { it + step }.takeWhile { it <= high }.toList()
}

private class InputData(lines: List<String>) {
    val initialSettings: Map<String, Long>
    val initialPrices: Map<String, Long>
    val priceOrder: List<String>
    val dayCount: Int
    val loads: List<Long>
    val basePV: List<Long>
    val dayNames: List<String>
    val weekendDays: List<Boolean>
    val periods: List<String>
    val commands: List<String>

    init {
        var position = 0
        fun read(): List<String> = lines[position++].split(' ')
        val settings = (read().drop(1) + read().drop(1) + "100").map(String::toLong)
        initialSettings = settingNames.zip(settings).toMap()
        val prices = linkedMapOf<String, Long>()
        repeat(read()[1].toInt()) {
            val tokens = read()
            prices[tokens[0]] = tokens[1].toLong()
        }
        initialPrices = prices
        priceOrder = prices.keys.toList()
        val weekdayHours = periodHours(read().drop(1))
        val weekendHours = periodHours(read().drop(1))
        val profiles = mutableMapOf<Pair<String, String>, List<Long>>()
        repeat(read()[1].toInt()) {
            val tokens = read()
            profiles[tokens[0] to tokens[1]] = tokens.drop(2).map(String::toLong)
        }
        dayCount = read()[1].toInt()
        val hourlyLoads = mutableListOf<Long>()
        val hourlyPV = mutableListOf<Long>()
        repeat(dayCount) {
            val tokens = read()
            hourlyLoads.addAll(profiles.getValue("LOAD" to tokens[0]).map { it * tokens[1].toLong() / 100 })
            hourlyPV.addAll(profiles.getValue("PV" to tokens[2]).map { it * tokens[3].toLong() / 100 })
        }
        val holidays = read().drop(2).map(String::toInt).toSet()
        repeat(read()[1].toInt()) {
            val tokens = read().map(String::toLong)
            val hour = ((tokens[0] - 1) * 24 + tokens[1]).toInt()
            hourlyLoads[hour] = tokens[2]
            hourlyPV[hour] = tokens[3]
        }
        loads = hourlyLoads
        basePV = hourlyPV
        dayNames = (1..dayCount).map { if (it in holidays) "HOL" else weekdays[(it - 1) % 7] }
        weekendDays = (1..dayCount).map { it in holidays || (it - 1) % 7 >= 5 }
        periods = weekendDays.flatMap { if (it) weekendHours else weekdayHours }
        commands = lines.drop(position)
    }

    private fun periodHours(tokens: List<String>): List<String> = buildList {
        for (i in tokens.indices step 2) {
            val start = tokens[i].toInt()
            val end = if (i + 2 < tokens.size) tokens[i + 2].toInt() else 24
            repeat(end - start) { add(tokens[i + 1]) }
        }
    }
}

private class HourRecord(
    val index: Int, val period: String, val load: Long, val pv: Long,
    val soc: Long, val flows: List<Long>, val drawn: Long, val shortfall: Long,
    val loss: Long, price: Long, feedin: Long
) {
    val day = index / 24 + 1
    val hour = index % 24
    val charge = flows[1] + flows[7]
    val discharge = flows[4] + flows[5]
    val imported = flows[6] + flows[7]
    val exported = flows[2] + flows[5]
    val curtailed = flows[3]
    val importCost = imported * price / 100000
    val exportIncome = exported * feedin / 100000
    val netCost = importCost - exportIncome
}

private class Totals(records: List<HourRecord>) {
    val count = records.size
    val load = records.sumOf { it.load }
    val pv = records.sumOf { it.pv }
    val charge = records.sumOf { it.charge }
    val discharge = records.sumOf { it.discharge }
    val imported = records.sumOf { it.imported }
    val exported = records.sumOf { it.exported }
    val curtailed = records.sumOf { it.curtailed }
    val drawn = records.sumOf { it.drawn }
    val loss = records.sumOf { it.loss }
    val shortfall = records.sumOf { it.shortfall }
    val importCost = records.sumOf { it.importCost }
    val exportIncome = records.sumOf { it.exportIncome }
    val netCost = importCost - exportIncome
    val flows = flowNames.indices.map { i -> records.sumOf { it.flows[i] } }
}

private class SimulationResult(
    val strategy: Strategy, originalSettings: Map<String, Long>, originalPrices: Map<String, Long>,
    val startSOC: Long, val reserve: Long, val hours: List<HourRecord>, priceOrder: List<String>
) {
    val settings = originalSettings.toMap()
    val prices = originalPrices.toMap()
    val days = hours.chunked(24)
    val daily = days.map(::Totals)
    val byPeriod = priceOrder.associateWith { name -> Totals(hours.filter { it.period == name }) }
    val total = Totals(hours)
    val peak = hours.maxOf { it.imported }
    val demandCharge = peak * settings.getValue("DEMAND") / 1000
    val bill = total.netCost + settings.getValue("FIXED") + demandCharge
    val endSOC = hours.last().soc
    val sufficiency = percentage(max(0L, total.load - total.imported), total.load)
}

private class Simulator(
    private val data: InputData, private val strategy: Strategy,
    originalSettings: Map<String, Long>, originalPrices: Map<String, Long>,
    private val outage: IntRange? = null
) {
    private val settings = originalSettings.toMap()
    private val prices = originalPrices.toMap()
    private val name = strategy.name
    private val parameter = strategy.parameter ?: 0L
    private val capacity = settings.getValue("CAPACITY")
    private val ceff = settings.getValue("CEFF")
    private val deff = settings.getValue("DEFF")
    private val reservePercent = if (name == "BACKUP") max(settings.getValue("RESERVE"), parameter)
        else settings.getValue("RESERVE")
    private val reserve = capacity * reservePercent / 100
    private val startSOC = capacity * settings.getValue("INITIAL") / 100
    private var soc = startSOC
    private val cheapest = data.priceOrder.minBy { prices.getValue(it) }
    private val peak = data.priceOrder.maxBy { prices.getValue(it) }
    private val arbitrage = name == "EXPORTPEAK" && settings.getValue("FEEDIN") > prices.getValue(cheapest)

    private fun dischargeTarget(deficit: Long, period: String): Long = when {
        name == "TOU" -> if (period == peak) deficit else 0L
        name == "PEAKSHAVE" -> max(0L, deficit - parameter)
        arbitrage && period == cheapest && period != peak -> 0L
        else -> deficit
    }

    private fun gridCharge(period: String, pvCharge: Long, gridLoad: Long): Long {
        var headroom = settings.getValue("CHARGE") - pvCharge
        val target = when {
            name == "TOU" && period == cheapest && period != peak -> capacity * parameter / 100
            name == "PEAKSHAVE" && period == cheapest -> {
                headroom = min(headroom, max(0L, parameter - gridLoad))
                capacity
            }
            name == "BACKUP" && period == cheapest -> reserve
            arbitrage && period == cheapest && period != peak -> capacity
            else -> return 0L
        }
        val amount = min(headroom, ceil(100 * max(0L, target - soc), ceff))
        soc += amount * ceff / 100
        return amount
    }

    private fun hour(index: Int): HourRecord {
        val load = data.loads[index]
        val pv = data.basePV[index] * settings.getValue("PVSCALE") / 100
        val period = data.periods[index]
        val direct = min(load, pv)
        var surplus = pv - direct
        var deficit = load - direct
        val pvCharge = minOf(surplus, settings.getValue("CHARGE"), ceil(100 * (capacity - soc), ceff))
        soc += pvCharge * ceff / 100
        surplus -= pvCharge
        val isOutage = outage?.contains(index) == true
        val target = if (isOutage) deficit else dischargeTarget(deficit, period)
        val lowerBound = if (isOutage) 0L else reserve
        val loadDrawn = minOf(ceil(100 * target, deff), settings.getValue("DISCHARGE"),
            max(0L, soc - lowerBound))
        val loadDischarge = loadDrawn * deff / 100
        soc -= loadDrawn
        deficit -= loadDischarge
        var gridLoad = 0L
        var shortfall = 0L
        var pvExport = 0L
        var curtailed = 0L
        var gridCharge = 0L
        var exportDrawn = 0L
        var batteryExport = 0L
        if (isOutage) {
            shortfall = deficit
            curtailed = surplus
        } else {
            gridLoad = deficit
            pvExport = min(surplus, settings.getValue("EXPORT"))
            curtailed = surplus - pvExport
            gridCharge = gridCharge(period, pvCharge, gridLoad)
            if (arbitrage && period == peak && pvCharge == 0L) {
                exportDrawn = minOf(ceil(100 * (settings.getValue("EXPORT") - pvExport), deff),
                    settings.getValue("DISCHARGE") - loadDrawn, max(0L, soc - reserve))
                batteryExport = exportDrawn * deff / 100
                soc -= exportDrawn
            }
        }
        val loss = pvCharge - pvCharge * ceff / 100 + gridCharge - gridCharge * ceff / 100 +
            loadDrawn - loadDischarge + exportDrawn - batteryExport
        val flows = listOf(direct, pvCharge, pvExport, curtailed, loadDischarge,
            batteryExport, gridLoad, gridCharge)
        return HourRecord(index, period, load, pv, soc, flows, loadDrawn + exportDrawn,
            shortfall, loss, prices.getValue(period), settings.getValue("FEEDIN"))
    }

    fun run(): SimulationResult = SimulationResult(strategy, settings, prices, startSOC, reserve,
        data.loads.indices.map(::hour), data.priceOrder)
}

private class DispatchDesk(private val data: InputData) {
    private var settings = data.initialSettings.toMutableMap()
    private var prices = data.initialPrices.toMutableMap()
    private var current: SimulationResult? = null

    fun execute(tokens: List<String>): List<String> = try {
        handle(tokens[0], tokens.drop(1))
    } catch (error: CommandError) {
        listOf("ERROR ${error.message}")
    }

    private fun simulate(
        strategy: Strategy, settings: Map<String, Long> = this.settings,
        prices: Map<String, Long> = this.prices, outage: IntRange? = null
    ) = Simulator(data, strategy, settings, prices, outage).run()

    private fun baseline(settings: Map<String, Long>, prices: Map<String, Long>) =
        simulate(Strategy("SELF"), settings + ("CAPACITY" to 0L), prices)

    private fun needResult() = current ?: fail("no run")
    private fun checkedDay(token: String): Int {
        val day = token.toInt()
        if (day !in 1..data.dayCount) fail("invalid day")
        return day
    }
    private fun resultNoArgs(args: List<String>): SimulationResult {
        requireCount(args, 0)
        return needResult()
    }
    private fun resultForDay(args: List<String>): Pair<Int, SimulationResult> {
        requireCount(args, 1)
        val day = checkedDay(args.single())
        return day to needResult()
    }

    private fun handle(command: String, args: List<String>): List<String> = when (command) {
        "RUN" -> {
            val strategy = oneStrategy(args)
            val result = simulate(strategy)
            current = result
            listOf("RUN $strategy bill ${money(result.bill)} import ${result.total.imported} " +
                "export ${result.total.exported} soc ${result.endSOC}")
        }
        "SET" -> {
            requireCount(args, 2)
            val name = args[0]
            val allowed = settingRanges[name] ?: fail("unknown parameter $name")
            val number = args[1].toLong()
            if (number !in allowed) fail("invalid value for $name")
            val old = settings.getValue(name)
            settings[name] = number
            listOf("SET $name $old -> $number")
        }
        "PRICE" -> {
            requireCount(args, 2)
            val name = args[0]
            val old = prices[name] ?: fail("unknown period $name")
            val number = args[1].toLong()
            if (number !in 0L..10000L) fail("invalid value for $name")
            prices[name] = number
            val cheap = data.priceOrder.minBy { prices.getValue(it) }
            val expensive = data.priceOrder.maxBy { prices.getValue(it) }
            listOf("PRICE $name $old -> $number cheapest $cheap peak $expensive")
        }
        "RESET" -> {
            requireCount(args, 0)
            settings = data.initialSettings.toMutableMap()
            prices = data.initialPrices.toMutableMap()
            listOf("RESET")
        }
        "CONFIG" -> {
            requireCount(args, 0)
            val battery = settingNames.take(8).joinToString(" ") { "${it.lowercase()} ${settings.getValue(it)}" }
            val grid = settingNames.drop(8).take(4).joinToString(" ") { "${it.lowercase()} ${settings.getValue(it)}" }
            val tariff = data.priceOrder.joinToString(" ") { "$it ${prices.getValue(it)}" }
            val cheap = data.priceOrder.minBy { prices.getValue(it) }
            val expensive = data.priceOrder.maxBy { prices.getValue(it) }
            listOf("BATTERY $battery", "GRID $grid", "SOLAR pvscale ${settings.getValue("PVSCALE")}",
                "TARIFF $tariff cheapest $cheap peak $expensive")
        }
        "NOBATTERY" -> {
            requireCount(args, 0)
            val result = baseline(settings, prices)
            listOf("NOBATTERY bill ${money(result.bill)} import ${result.total.imported} " +
                "export ${result.total.exported} curtailed ${result.total.curtailed} peak ${result.peak}")
        }
        "COMPARE" -> {
            val strategies = readStrategies(args)
            if (strategies.isEmpty()) fail("wrong number of arguments")
            val reference = baseline(settings, prices)
            val trials = strategies.map { simulate(it) }.sortedBy { it.bill }
            buildList {
                add("COMPARE baseline ${money(reference.bill)}")
                trials.forEachIndexed { i, result ->
                    add("${i + 1}. ${result.strategy} bill ${money(result.bill)} " +
                        "saving ${money(reference.bill - result.bill)} sufficiency ${result.sufficiency}%")
                }
            }
        }
        "SIZE" -> {
            requireCount(args, 3)
            val limits = settingRanges.getValue("CAPACITY")
            val capacities = checkedRange(args[0].toLong(), args[1].toLong(), args[2].toLong(), limits)
            val reference = baseline(settings, prices)
            var bestCapacity: Long? = null
            var bestCost = 0L
            var bestSaving = 0L
            buildList {
                for (capacity in capacities) {
                    val trialSettings = settings + ("CAPACITY" to capacity)
                    val result = simulate(Strategy("SELF"), trialSettings)
                    val saving = reference.bill - result.bill
                    val cost = capacity * trialSettings.getValue("COST") / 1000
                    var payback = "never"
                    if (saving > 0) {
                        val tenth = 10 * cost / saving
                        payback = "${tenth / 10}.${tenth % 10}"
                        if (bestCapacity == null || cost * bestSaving < bestCost * saving) {
                            bestCapacity = capacity
                            bestCost = cost
                            bestSaving = saving
                        }
                    }
                    add("SIZE $capacity bill ${money(result.bill)} saving ${money(saving)} " +
                        "cost ${money(cost)} payback $payback")
                }
                add("BEST ${bestCapacity ?: "none"}")
            }
        }
        "SWEEP" -> {
            if (args.size < 5) fail("wrong number of arguments")
            val name = args[0]
            val limits = settingRanges[name] ?: fail("unknown parameter $name")
            val values = checkedRange(args[1].toLong(), args[2].toLong(), args[3].toLong(), limits)
            val strategy = oneStrategy(args.drop(4))
            var bestValue = values.first()
            var bestBill: Long? = null
            buildList {
                for (number in values) {
                    val newSettings = settings + (name to number)
                    val result = simulate(strategy, newSettings)
                    val reference = baseline(newSettings, prices)
                    if (bestBill == null || result.bill < bestBill!!) {
                        bestValue = number
                        bestBill = result.bill
                    }
                    add("SWEEP $name $number bill ${money(result.bill)} " +
                        "saving ${money(reference.bill - result.bill)} sufficiency ${result.sufficiency}%")
                }
                add("BEST $bestValue")
            }
        }
        "OUTAGE" -> {
            requireCount(args, 3)
            val day = checkedDay(args[0])
            val start = args[1].toInt()
            val finish = args[2].toInt()
            if (start < 0 || start > finish || finish > 23) fail("invalid hours")
            val previous = needResult()
            val first = (day - 1) * 24 + start
            val last = (day - 1) * 24 + finish
            val result = simulate(previous.strategy, previous.settings, previous.prices, first..last)
            val before = if (first == 0) result.startSOC else result.hours[first - 1].soc
            val subset = result.hours.subList(first, last + 1)
            val total = Totals(subset)
            val served = if (total.load == 0L) "100.00" else percentage(total.load - total.shortfall, total.load)
            buildList {
                add("OUTAGE day $day hours $start-$finish strategy ${result.strategy} soc $before")
                add("hour   load     pv  disch    soc  short   curt")
                subset.forEach { record -> add(rightRow(listOf(record.hour, record.load, record.pv,
                    record.discharge, record.soc, record.shortfall, record.curtailed),
                    listOf(4, 7, 7, 7, 7, 7, 7))) }
                add("TOTAL load ${total.load} unserved ${total.shortfall} served $served% bill ${money(result.bill)}")
            }
        }
        "DIFF" -> {
            if (args.size < 2) fail("wrong number of arguments")
            val day = checkedDay(args[0])
            val strategy = oneStrategy(args.drop(1))
            val previous = needResult()
            val comparison = simulate(strategy, previous.settings, previous.prices)
            val firstDay = previous.days[day - 1]
            val secondDay = comparison.days[day - 1]
            val cost1 = previous.daily[day - 1].netCost
            val cost2 = comparison.daily[day - 1].netCost
            buildList {
                add("DIFF day $day ${data.dayNames[day - 1]} ${previous.strategy} vs $strategy")
                add("hour   imp1   imp2   exp1   exp2   soc1   soc2")
                firstDay.zip(secondDay).forEach { (a, b) ->
                    add(rightRow(listOf(a.hour, a.imported, b.imported, a.exported, b.exported,
                        a.soc, b.soc), listOf(4, 7, 7, 7, 7, 7, 7)))
                }
                add("TOTAL cost1 ${money(cost1)} cost2 ${money(cost2)} difference ${money(cost2 - cost1)}")
            }
        }
        "HOURLY" -> {
            val (day, result) = resultForDay(args)
            val widths = listOf(4, 7, 7, 7, 7, 7, 7, 7, 7)
            val total = result.daily[day - 1]
            buildList {
                add("HOURLY day $day ${data.dayNames[day - 1]} strategy ${result.strategy}")
                add("hour   load     pv charge  disch    soc import export   curt")
                result.days[day - 1].forEach { r ->
                    add(rightRow(listOf(r.hour, r.load, r.pv, r.charge, r.discharge,
                        r.soc, r.imported, r.exported, r.curtailed), widths))
                }
                add(rightRow(listOf("sum", total.load, total.pv, total.charge,
                    total.discharge, "", total.imported, total.exported, total.curtailed), widths))
            }
        }
        "DAILY" -> {
            val result = resultNoArgs(args)
            val widths = listOf(3, 5, 8, 8, 8, 8, 8, 8, 10)
            val total = result.total
            buildList {
                add("DAILY strategy ${result.strategy}")
                add("day name    load      pv  import  export    curt     soc      cost")
                result.daily.forEachIndexed { i, item ->
                    add(rightRow(listOf(i + 1, data.dayNames[i], item.load, item.pv, item.imported,
                        item.exported, item.curtailed, result.days[i].last().soc,
                        money(item.netCost)), widths))
                }
                add("TOTAL load ${total.load} pv ${total.pv} import ${total.imported} " +
                    "export ${total.exported} curtailed ${total.curtailed} cost ${money(total.netCost)}")
            }
        }
        "BILL" -> {
            val result = resultNoArgs(args)
            buildList {
                add("BILL strategy ${result.strategy} days ${data.dayCount}")
                data.priceOrder.forEach { name ->
                    val total = result.byPeriod.getValue(name)
                    add("IMPORT $name ${total.imported} Wh ${money(total.importCost)}")
                }
                add("EXPORT ${result.total.exported} Wh ${money(-result.total.exportIncome)}")
                add("FIXED ${money(result.settings.getValue("FIXED"))}")
                add("DEMAND ${result.peak} Wh ${money(result.demandCharge)}")
                add("TOTAL ${money(result.bill)}")
            }
        }
        "SAVINGS" -> {
            val result = resultNoArgs(args)
            val reference = baseline(result.settings, result.prices)
            buildList {
                add("SAVINGS strategy ${result.strategy}")
                data.priceOrder.forEach { name ->
                    val before = reference.byPeriod.getValue(name).importCost
                    val after = result.byPeriod.getValue(name).importCost
                    add("$name ${money(before)} -> ${money(after)} saving ${money(before - after)}")
                }
                val pairs = listOf(
                    Triple("EXPORT", -reference.total.exportIncome, -result.total.exportIncome),
                    Triple("DEMAND", reference.demandCharge, result.demandCharge),
                    Triple("TOTAL", reference.bill, result.bill)
                )
                pairs.forEach { (name, before, after) ->
                    add("$name ${money(before)} -> ${money(after)} saving ${money(before - after)}")
                }
            }
        }
        "BYPERIOD" -> {
            val result = resultNoArgs(args)
            buildList {
                add("BYPERIOD strategy ${result.strategy}")
                data.priceOrder.forEach { name ->
                    val t = result.byPeriod.getValue(name)
                    add("$name hours ${t.count} load ${t.load} pv ${t.pv} charge ${t.charge} " +
                        "discharge ${t.discharge} import ${t.imported} export ${t.exported}")
                }
            }
        }
        "DAYTYPE" -> {
            val result = resultNoArgs(args)
            buildList {
                add("DAYTYPE strategy ${result.strategy}")
                listOf("WEEKDAY" to false, "WEEKEND" to true).forEach { (name, isWeekend) ->
                    val days = data.weekendDays.indices.filter { data.weekendDays[it] == isWeekend }
                    val total = Totals(days.flatMap { result.days[it] })
                    val count = days.size.toLong()
                    add("$name days $count load ${total.load / count} pv ${total.pv / count} " +
                        "import ${total.imported / count} export ${total.exported / count} " +
                        "cost ${money(total.netCost / count)}")
                }
            }
        }
        "PEAKS" -> {
            requireCount(args, 1)
            val count = args[0].toInt()
            if (count < 1) fail("invalid count")
            val result = needResult()
            val records = result.hours.filter { it.imported > 0 }
                .sortedWith(compareByDescending<HourRecord> { it.imported }.thenBy { it.index })
            buildList {
                add("PEAKS strategy ${result.strategy}")
                records.take(count).forEachIndexed { i, r ->
                    add("${i + 1}. day ${r.day} hour ${r.hour} ${r.period} " +
                        "import ${r.imported} load ${r.load} soc ${r.soc}")
                }
                if (records.isEmpty()) add("none")
            }
        }
        "PROFILE" -> {
            val result = resultNoArgs(args)
            buildList {
                add("PROFILE strategy ${result.strategy} days ${data.dayCount}")
                add("hour   load     pv import export    soc")
                repeat(24) { hour ->
                    val records = result.hours.filter { it.hour == hour }
                    val count = data.dayCount.toLong()
                    add(rightRow(listOf(hour, records.sumOf { it.load } / count,
                        records.sumOf { it.pv } / count, records.sumOf { it.imported } / count,
                        records.sumOf { it.exported } / count, records.sumOf { it.soc } / count),
                        listOf(4, 7, 7, 7, 7, 7)))
                }
            }
        }
        "FLOWS" -> {
            val result = resultNoArgs(args)
            buildList {
                add("FLOWS strategy ${result.strategy}")
                flowNames.forEachIndexed { i, name -> add("$name ${result.total.flows[i]}") }
                add("LOSSES ${result.total.loss}")
                add("STORED ${result.endSOC - result.startSOC}")
            }
        }
        "SELFSUFF" -> {
            val result = resultNoArgs(args)
            val flow = result.total.flows
            listOf("SELFSUFF sufficiency ${result.sufficiency}% " +
                "consumption ${percentage(flow[0] + flow[1], result.total.pv)}%")
        }
        "CYCLES" -> {
            val result = resultNoArgs(args)
            val drawn = result.total.drawn
            val capacity = result.settings.getValue("CAPACITY")
            val common = gcd(drawn, capacity)
            val thousandths = 1000 * drawn / capacity
            listOf("CYCLES ${drawn / common}/${capacity / common} " +
                "${thousandths / 1000}.${(thousandths % 1000).toString().padStart(3, '0')} " +
                "drawn $drawn losses ${result.total.loss}")
        }
        "USAGE" -> {
            val result = resultNoArgs(args)
            var low = 0
            var length = 0
            var longest = 0
            var first: HourRecord? = null
            result.hours.forEach { hour ->
                if (hour.soc <= result.reserve) {
                    low++
                    length++
                    if (length > longest) {
                        longest = length
                        first = result.hours[hour.index - length + 1]
                    }
                } else length = 0
            }
            val charging = result.hours.count { it.charge > 0 }
            val discharging = result.hours.count { it.drawn > 0 }
            val idle = result.hours.count { it.charge == 0L && it.drawn == 0L }
            val full = result.hours.count { it.soc == result.settings.getValue("CAPACITY") }
            val suffix = if (first == null) "" else " from day ${first!!.day} hour ${first!!.hour}"
            listOf("USAGE charging $charging discharging $discharging idle $idle " +
                "full $full low $low longest $longest$suffix")
        }
        "HISTOGRAM" -> {
            val result = resultNoArgs(args)
            val capacity = result.settings.getValue("CAPACITY")
            val bands = IntArray(10)
            result.hours.forEach { bands[min(9L, 10 * it.soc / capacity).toInt()]++ }
            buildList {
                add("HISTOGRAM strategy ${result.strategy}")
                bands.forEachIndexed { index, count ->
                    add("${(10 * index).toString().padStart(3)}% " +
                        "${bar(20 * count / result.hours.size)} $count")
                }
            }
        }
        "CHART" -> {
            val (day, result) = resultForDay(args)
            val capacity = result.settings.getValue("CAPACITY")
            buildList {
                add("CHART day $day ${data.dayNames[day - 1]} strategy ${result.strategy}")
                result.days[day - 1].forEach { r ->
                    add("${r.hour.toString().padStart(2)} ${bar((20 * r.soc / capacity).toInt())} " +
                        "${percentage(r.soc, capacity)}%")
                }
            }
        }
        else -> fail("unknown command $command")
    }
}

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`))
    val lines = generateSequence { reader.readLine() }.toList()
    if (lines.isEmpty()) return
    val data = InputData(lines)
    val desk = DispatchDesk(data)
    val output = mutableListOf<String>()
    for (line in data.commands) {
        val tokens = line.split(' ')
        if (tokens.first() == "END") break
        output.addAll(desk.execute(tokens))
    }
    if (output.isNotEmpty()) println(output.joinToString("\n"))
}
