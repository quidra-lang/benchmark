import java.util.TreeMap

private val rateSettings = setOf(
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
    "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"
)
private val initialSettings = linkedMapOf(
    "STATE" to 500L, "SUPP" to 2200L, "SSRATE" to 620L, "MEDRATE" to 145L,
    "ADDMED" to 90L, "UIRATE" to 270L, "MATCH" to 5000L, "MATCHMAX" to 600L,
    "GARNCAP" to 2500L, "SSBASE" to 16860000L, "ADDBASE" to 20000000L,
    "UIBASE" to 700000L, "RETIRECAP" to 2300000L, "ALLOWANCE" to 15000L,
    "NIGHT" to 100L
)
private val fields = listOf(
    "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
    "sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
    "federal", "supplemental", "state", "social", "medicare", "garnishment", "net",
    "employer_social", "employer_medicare", "unemployment", "match", "employer",
    "W", "Y", "F", "J"
)
private val weekdays = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

private fun cents(text: String): Long {
    val parts = text.split('.')
    return parts[0].toLong() * 100 + parts[1].toLong()
}

private fun money(value: Long): String =
    (value / 100).toString() + "." + (value % 100).toString().padStart(2, '0')

private fun rateText(value: Long) = money(value) + "%"
private fun duration(value: Long) = (value / 60).toString() + ":" +
    (value % 60).toString().padStart(2, '0')

private fun clock(value: Int) = (value / 60).toString().padStart(2, '0') + ":" +
    (value % 60).toString().padStart(2, '0')

private fun weekday(day: Int) = weekdays[(day - 1) % 7]
private fun periodOf(day: Int) = (day - 1) / 14 + 1
private fun emptyTotals(): MutableMap<String, Long> =
    fields.associateWithTo(linkedMapOf()) { 0L }

private fun progressive(table: Map<Long, Long>, amount: Long): Long {
    val entries = table.entries.sortedBy { it.key }
    var numerator = 0L
    for ((index, entry) in entries.withIndex()) {
        if (entry.key >= amount) break
        val upper = if (index + 1 < entries.size) entries[index + 1].key else amount
        numerator += entry.value * (minOf(amount, upper) - entry.key)
    }
    return numerator / 10000
}

private class CommandError(message: String) : RuntimeException(message)
private fun fail(reason: String): Nothing = throw CommandError(reason)

private data class Shift(val start: Int, val end: Int)
private data class Garnishment(val rate: Long, var balance: Long)
private data class Daily(
    val worked: Long, val regular: Long, val overtime: Long,
    val double: Long, val night: Long, val pto: Long
)
private data class Weekly(val values: List<Long>, val excess: Long)

private class Stub {
    val values = emptyTotals()
    var garnishmentBalance = 0L
    var ptoBalance = 0L
    operator fun get(field: String): Long = values.getValue(field)
    operator fun set(field: String, value: Long) { values[field] = value }
}

private data class Calculation(val stub: Stub, val balances: List<Long>)
private data class StoredStub(val stub: Stub, val department: String)

private fun sumStubs(stubs: Collection<Stub>): Stub {
    val total = Stub()
    for (stub in stubs)
        for (field in fields)
            total[field] += stub[field]
    return total
}

private class Employee(
    val id: Int, var department: String, val kind: String, var base: Long
) {
    var active = true
    var retirement = 0L
    var health = 0L
    var allowances = 0L
    var extra = 0L
    val garnishments = mutableListOf<Garnishment>()
    var bonus = 0L
    var ptoBalance = 0L
    val shifts = mutableMapOf<Int, MutableList<Shift>>()
    val pto = mutableMapOf<Int, Long>()
    val leave = mutableSetOf<Int>()
    val sales = mutableMapOf<Int, Long>()
    val stubs = mutableMapOf<Int, StoredStub>()
    val ytd = emptyTotals()
    var periods = 0
    fun garnishBalance(): Long = garnishments.sumOf { it.balance }
}

private class Payroll {
    private val settings = LinkedHashMap(initialSettings)
    private val brackets = TreeMap<Long, Long>()
    private val tiers = TreeMap<Long, Long>()
    private val holidays = mutableSetOf<Int>()
    private val employees = TreeMap<Int, Employee>()
    private val output = mutableListOf<String>()
    private var closed = 0

    private fun emit(vararg parts: Any, indent: Int = 0) {
        output.add(" ".repeat(indent) + parts.joinToString(" "))
    }

    private fun employee(text: String, active: Boolean = false, kind: String? = null): Employee {
        val person = employees[text.toInt()] ?: fail("unknown employee " + text)
        if (active && !person.active) fail("terminated employee " + text)
        if (kind != null && person.kind != kind)
            fail("not " + kind.lowercase(java.util.Locale.ROOT) + " " + text)
        return person
    }

    private fun dayCheck(text: String): Int {
        val day = text.toInt()
        if (day !in 1..364) fail("invalid day " + text)
        val period = periodOf(day)
        if (period <= closed) fail("period closed " + period)
        return day
    }

    private fun periodCheck(text: String): Int {
        val period = text.toInt()
        if (period !in 1..26) fail("invalid period " + text)
        return period
    }

    private fun rateCheck(text: String): Long {
        val value = cents(text)
        if (value > 10000) fail("invalid rate " + text)
        return value
    }

    private fun amountCheck(text: String): Long {
        val value = cents(text)
        if (value == 0L) fail("invalid amount")
        return value
    }

    private fun timeCheck(text: String): Int {
        val parts = text.split(':')
        val hour = parts[0].toInt()
        val minute = parts[1].toInt()
        if (hour > 23 || minute > 59) fail("invalid time " + text)
        return hour * 60 + minute
    }

    private fun daily(person: Employee, day: Int): Daily {
        val shifts = person.shifts[day].orEmpty()
        val worked = shifts.sumOf { (it.end - it.start).toLong() }
        val night = shifts.sumOf {
            maxOf(0, minOf(it.end, 360) - it.start).toLong() +
                maxOf(0, it.end - maxOf(it.start, 1320))
        }
        val pto = person.pto[day] ?: 0L
        if (day % 7 == 0 || day in holidays)
            return Daily(worked, 0, 0, worked, night, pto)
        return Daily(
            worked, minOf(worked, 480L), minOf(maxOf(worked - 480L, 0L), 240L),
            maxOf(worked - 720L, 0L), night, pto
        )
    }

    private fun weekly(person: Employee, week: Int): Weekly {
        val totals = MutableList(5) { 0L }
        for (day in (7 * week - 6)..(7 * week)) {
            val values = daily(person, day).let {
                listOf(it.regular, it.overtime, it.double, it.night, it.pto)
            }
            for (i in totals.indices) totals[i] += values[i]
        }
        val excess = maxOf(0L, totals[0] - 2400)
        totals[0] -= excess
        totals[1] += excess
        return Weekly(totals, excess)
    }

    private fun breakdown(person: Employee, period: Int): List<Long> {
        val left = weekly(person, 2 * period - 1).values
        val right = weekly(person, 2 * period).values
        return left.indices.map { left[it] + right[it] }
    }

    private fun calculate(person: Employee, period: Int): Calculation? {
        val stub = Stub()
        val ytd = person.ytd
        when (person.kind) {
            "HOURLY" -> {
                val values = breakdown(person, period)
                for ((index, field) in listOf("R", "O", "D", "N", "P").withIndex())
                    stub[field] = values[index]
                val weighted = 2 * (stub["R"] + stub["P"]) + 3 * stub["O"] + 4 * stub["D"]
                stub["earnings"] = (weighted * person.base +
                    2 * stub["N"] * settings.getValue("NIGHT")) / 120
            }
            "SALARIED" -> if (person.active) {
                stub["salary"] = person.base / 26
                stub["leave"] = person.leave.count {
                    periodOf(it) == period && it !in holidays
                }.toLong()
                stub["deduction"] = stub["leave"] * (person.base / 260)
                stub["earnings"] = stub["salary"] - stub["deduction"]
            }
            "COMMISSION" -> {
                stub["sales"] = person.sales[period] ?: 0L
                stub["commission"] = progressive(tiers, stub["sales"])
                stub["earnings"] = stub["commission"] +
                    (if (person.active) person.base else 0L)
            }
        }
        stub["bonus"] = person.bonus
        val gross = stub["earnings"] + stub["bonus"]
        if (gross == 0L) return null
        stub["gross"] = gross
        var remaining = gross

        fun deduct(field: String, amount: Long) {
            stub[field] = minOf(amount, remaining)
            remaining -= stub[field]
        }

        val room = maxOf(0L, settings.getValue("RETIRECAP") - ytd.getValue("retirement"))
        deduct("retirement", minOf(gross * person.retirement / 10000, room))
        deduct("health", person.health)
        stub["W"] = remaining
        val baseTaxable = maxOf(0L, stub["earnings"] - stub["retirement"] - stub["health"])
        val allowanceTaxable = maxOf(
            0L, baseTaxable - person.allowances * settings.getValue("ALLOWANCE")
        )
        deduct("federal", progressive(brackets, allowanceTaxable) + person.extra)
        deduct("supplemental", (stub["W"] - baseTaxable) * settings.getValue("SUPP") / 10000)
        deduct("state", stub["W"] * settings.getValue("STATE") / 10000)
        val medicareWages = gross - stub["health"]
        val socialWages = minOf(
            medicareWages, maxOf(0L, settings.getValue("SSBASE") - ytd.getValue("Y"))
        )
        val additional = maxOf(
            0L, minOf(medicareWages, ytd.getValue("F") + medicareWages - settings.getValue("ADDBASE"))
        )
        stub["F"] = medicareWages
        stub["Y"] = socialWages
        deduct("social", socialWages * settings.getValue("SSRATE") / 10000)
        deduct(
            "medicare", medicareWages * settings.getValue("MEDRATE") / 10000 +
                additional * settings.getValue("ADDMED") / 10000
        )

        val disposable = remaining
        val cap = disposable * settings.getValue("GARNCAP") / 10000
        var garnishment = 0L
        val balances = mutableListOf<Long>()
        for (order in person.garnishments) {
            val taken = minOf(disposable * order.rate / 10000, order.balance, cap - garnishment)
            garnishment += taken
            balances.add(order.balance - taken)
        }
        stub["garnishment"] = garnishment
        stub.garnishmentBalance = balances.sum()
        stub["net"] = remaining - garnishment
        stub["employer_social"] = socialWages * settings.getValue("SSRATE") / 10000
        stub["employer_medicare"] = medicareWages * settings.getValue("MEDRATE") / 10000
        stub["J"] = minOf(medicareWages, maxOf(0L, settings.getValue("UIBASE") - ytd.getValue("J")))
        stub["unemployment"] = stub["J"] * settings.getValue("UIRATE") / 10000
        val eligibleMatch = minOf(stub["retirement"], gross * settings.getValue("MATCHMAX") / 10000)
        stub["match"] = eligibleMatch * settings.getValue("MATCH") / 10000
        stub["employer"] = listOf(
            "employer_social", "employer_medicare", "unemployment", "match"
        ).sumOf { stub[it] }
        if (person.kind == "HOURLY") {
            stub["accrued"] = minOf(
                960L - person.ptoBalance, (stub["R"] + stub["O"] + stub["D"]) / 20
            )
        }
        stub.ptoBalance = person.ptoBalance + stub["accrued"]
        return Calculation(stub, balances)
    }

    private fun hoursParts(values: List<Long>): String =
        listOf("reg", "ot", "dbl", "night", "pto")
            .zip(values).joinToString(" ") { (label, value) -> label + " " + duration(value) }

    private fun stubBlock(person: Employee, stub: Stub, indent: Int) {
        when (person.kind) {
            "HOURLY" -> {
                emit("hours", hoursParts(listOf("R", "O", "D", "N", "P").map { stub[it] }), indent = indent)
                emit("pto", "accrued", duration(stub["accrued"]),
                     "balance", duration(stub.ptoBalance), indent = indent)
            }
            "SALARIED" -> emit(
                "salary", money(stub["salary"]), "leave", stub["leave"],
                "deduction", money(stub["deduction"]), indent = indent
            )
            else -> emit(
                "sales", money(stub["sales"]), "commission", money(stub["commission"]), indent = indent
            )
        }
        for (field in listOf(
            "earnings", "bonus", "gross", "retirement", "health", "federal",
            "supplemental", "state", "social", "medicare"
        )) {
            emit(if (field == "social") "social-security" else field, money(stub[field]), indent = indent)
        }
        emit("garnishment", money(stub["garnishment"]),
             "balance", money(stub.garnishmentBalance), indent = indent)
        emit("net", money(stub["net"]), indent = indent)
        emit(
            "employer", "social-security", money(stub["employer_social"]),
            "medicare", money(stub["employer_medicare"]),
            "unemployment", money(stub["unemployment"]),
            "match", money(stub["match"]), indent = indent
        )
    }

    private fun printStub(person: Employee, period: Int, stub: Stub, department: String) {
        emit("STUB", person.id, department, person.kind, "period", period, indent = 2)
        stubBlock(person, stub, 4)
    }

    private fun showHours(person: Employee, period: Int) {
        emit("HOURS", person.id, "period", period)
        var found = false
        for (day in (14 * period - 13)..(14 * period)) {
            val shifts = person.shifts[day].orEmpty().sortedBy { it.start }
            if (shifts.isEmpty() && day !in person.pto) continue
            val daily = daily(person, day)
            val parts = mutableListOf("day", day.toString(), weekday(day))
            if (day in holidays) parts.add("holiday")
            for (shift in shifts)
                parts.add(clock(shift.start) + "-" + clock(shift.end))
            val amounts = listOf(daily.regular, daily.overtime, daily.double, daily.night, daily.pto)
            emit(parts.joinToString(" "), "total", duration(daily.worked),
                 hoursParts(amounts), indent = 2)
            found = true
        }
        if (!found) emit("(none)", indent = 2)
        for (week in listOf(2 * period - 1, 2 * period)) {
            val values = weekly(person, week)
            emit("week", week, hoursParts(values.values),
                 "weekly-ot", duration(values.excess), indent = 2)
        }
        emit("total", hoursParts(breakdown(person, period)), indent = 2)
    }

    private fun run(period: Int) {
        closed = period
        emit("RUN", period, "days", (14 * period - 13).toString() + "-" + 14 * period)
        var paid = 0
        var skipped = 0
        val stubs = mutableListOf<Stub>()
        for (person in employees.values) {
            val result = calculate(person, period)
            if (result == null) {
                if (person.active) skipped++
                continue
            }
            val stub = result.stub
            printStub(person, period, stub, person.department)
            person.bonus = 0L
            person.ptoBalance = stub.ptoBalance
            for ((index, balance) in result.balances.withIndex())
                person.garnishments[index].balance = balance
            for (field in fields)
                person.ytd[field] = person.ytd.getValue(field) + stub[field]
            person.periods++
            person.stubs[period] = StoredStub(stub, person.department)
            stubs.add(stub)
            paid++
        }
        val total = sumStubs(stubs)
        emit(
            "TOTAL", "paid", paid, "skipped", skipped, "gross", money(total["gross"]),
            "deductions", money(total["gross"] - total["net"]), "net", money(total["net"]),
            "employer", money(total["employer"]), indent = 2
        )
    }

    private fun journal(period: Int) {
        val stubs = employees.values.mapNotNull { it.stubs[period]?.stub }
        val total = sumStubs(stubs)
        val rows = listOf(
            Triple("debit", "wages", total["gross"]),
            Triple("debit", "employer-tax",
                   total["employer_social"] + total["employer_medicare"] + total["unemployment"]),
            Triple("debit", "retirement-match", total["match"]),
            Triple("credit", "retirement", total["retirement"] + total["match"]),
            Triple("credit", "health", total["health"]),
            Triple("credit", "federal", total["federal"] + total["supplemental"]),
            Triple("credit", "state", total["state"]),
            Triple("credit", "fica", total["social"] + total["medicare"] +
                   total["employer_social"] + total["employer_medicare"]),
            Triple("credit", "unemployment", total["unemployment"]),
            Triple("credit", "garnishment", total["garnishment"]),
            Triple("credit", "net-pay", total["net"])
        )
        emit("JOURNAL", period, "stubs", stubs.size)
        for ((side, label, amount) in rows) emit(side, label, money(amount), indent = 2)
        val debits = rows.filter { it.first == "debit" }.sumOf { it.third }
        val credits = rows.filter { it.first == "credit" }.sumOf { it.third }
        emit("total", "debit", money(debits), "credit", money(credits), indent = 2)
    }

    private fun reportLine(department: String, stubs: Collection<Stub>) {
        val total = sumStubs(stubs)
        val taxes = listOf("federal", "supplemental", "state", "social", "medicare")
            .sumOf { total[it] }
        emit(
            department, "stubs", stubs.size, "gross", money(total["gross"]),
            "pretax", money(total["retirement"] + total["health"]),
            "taxes", money(taxes), "garnishment", money(total["garnishment"]),
            "net", money(total["net"]), "employer", money(total["employer"]), indent = 2
        )
    }

    private fun command(name: String, a: List<String>) {
        when (name) {
            "SET" -> {
                val setting = a[0]
                if (setting !in settings) fail("unknown setting " + setting)
                val value = if (setting in rateSettings) rateCheck(a[1]) else cents(a[1])
                val old = settings.getValue(setting)
                settings[setting] = value
                val format: (Long) -> String =
                    if (setting in rateSettings) ::rateText else ::money
                emit("SET", setting, format(old), "->", format(value))
            }
            "BRACKET", "TIER" -> {
                val rate = rateCheck(a[1])
                val table = if (name == "BRACKET") brackets else tiers
                val lower = cents(a[0])
                val action = if (lower in table) "replaced" else "added"
                table[lower] = rate
                emit(name, money(lower), rateText(rate), action)
            }
            "EMP" -> {
                val id = a[0].toInt()
                if (id in employees) fail("duplicate employee " + a[0])
                val base = amountCheck(a[3])
                employees[id] = Employee(id, a[1], a[2], base)
                emit("EMP", id, a[1], a[2], money(base))
            }
            "RATE", "DEPT", "BENEFIT", "W4", "GARNISH", "TERM", "BONUS" -> {
                val person = employee(a[0], active = true)
                when (name) {
                    "RATE" -> {
                        val base = amountCheck(a[1])
                        val old = person.base
                        person.base = base
                        emit("RATE", person.id, money(old), "->", money(base))
                    }
                    "DEPT" -> {
                        if (person.department == a[1]) fail("same department " + a[1])
                        val old = person.department
                        person.department = a[1]
                        emit("DEPT", person.id, old, "->", person.department)
                    }
                    "BENEFIT" -> {
                        val rate = rateCheck(a[1])
                        person.retirement = rate
                        person.health = cents(a[2])
                        emit("BENEFIT", person.id, "retirement", rateText(rate),
                             "health", money(person.health))
                    }
                    "W4" -> {
                        person.allowances = a[1].toLong()
                        person.extra = cents(a[2])
                        emit("W4", person.id, "allowances", person.allowances,
                             "extra", money(person.extra))
                    }
                    "GARNISH" -> {
                        val rate = rateCheck(a[1])
                        val amount = amountCheck(a[2])
                        person.garnishments.add(Garnishment(rate, amount))
                        emit("GARNISH", person.id, "order", person.garnishments.size,
                             rateText(rate), "balance", money(amount))
                    }
                    "TERM" -> {
                        person.active = false
                        emit("TERM", person.id)
                    }
                    "BONUS" -> {
                        val amount = amountCheck(a[1])
                        person.bonus += amount
                        emit("BONUS", person.id, money(amount),
                             "pending", money(person.bonus))
                    }
                }
            }
            "HOLIDAY" -> {
                val day = dayCheck(a[0])
                if (day in holidays) fail("duplicate holiday " + a[0])
                holidays.add(day)
                emit("HOLIDAY", day, weekday(day))
            }
            "TIME", "UNTIME", "PTO", "LEAVE", "SALES" -> {
                val kind = when (name) {
                    "LEAVE" -> "SALARIED"
                    "SALES" -> "COMMISSION"
                    else -> "HOURLY"
                }
                val person = employee(a[0], active = true, kind = kind)
                val day = dayCheck(a[1])
                when (name) {
                    "TIME" -> {
                        val start = timeCheck(a[2])
                        val end = timeCheck(a[3])
                        if (start >= end)
                            fail("invalid shift " + a[2] + "-" + a[3])
                        val shifts = person.shifts[day].orEmpty()
                        for (shift in shifts.sortedBy { it.start }) {
                            if (start < shift.end && shift.start < end)
                                fail("overlapping shift " + clock(shift.start) +
                                     "-" + clock(shift.end))
                        }
                        if (shifts.sumOf { it.end - it.start } + end - start > 960)
                            fail("daily limit " + a[0] + " " + a[1])
                        person.shifts.getOrPut(day) { mutableListOf() }.add(Shift(start, end))
                        emit("TIME", person.id, "day", day,
                             clock(start) + "-" + clock(end), duration((end - start).toLong()))
                    }
                    "UNTIME" -> {
                        val start = timeCheck(a[2])
                        val shifts = person.shifts[day].orEmpty()
                        val found = shifts.find { it.start == start }
                            ?: fail("no shift " + a[0] + " " + a[1] + " " + a[2])
                        person.shifts[day]?.remove(found)
                        emit("UNTIME", person.id, "day", day,
                             clock(found.start) + "-" + clock(found.end))
                    }
                    "PTO" -> {
                        val pieces = a[2].split(':')
                        val hour = pieces[0].toLong()
                        val minute = pieces[1].toLong()
                        val length = hour * 60 + minute
                        if (minute > 59 || length !in 1L..480L)
                            fail("invalid duration " + a[2])
                        if (day in person.pto) fail("duplicate pto " + a[0] + " " + a[1])
                        if (length > person.ptoBalance)
                            fail("insufficient pto " + a[0] + " " + duration(person.ptoBalance))
                        person.pto[day] = length
                        person.ptoBalance -= length
                        emit("PTO", person.id, "day", day, duration(length),
                             "balance", duration(person.ptoBalance))
                    }
                    "LEAVE" -> {
                        if (day % 7 == 0 || day % 7 == 6 || day in holidays)
                            fail("not workday " + a[1])
                        if (day in person.leave)
                            fail("duplicate leave " + a[0] + " " + a[1])
                        person.leave.add(day)
                        emit("LEAVE", person.id, "day", day, weekday(day))
                    }
                    "SALES" -> {
                        val amount = amountCheck(a[2])
                        val period = periodOf(day)
                        person.sales[period] = (person.sales[period] ?: 0L) + amount
                        emit("SALES", person.id, "day", day, money(amount),
                             "period", period, "total", money(person.sales.getValue(period)))
                    }
                }
            }
            "HOURS" -> {
                val person = employee(a[0], kind = "HOURLY")
                showHours(person, periodCheck(a[1]))
            }
            "RUN" -> {
                val period = a[0].toInt()
                if (period != closed + 1 || period > 26)
                    fail("invalid period " + a[0])
                run(period)
            }
            "PREVIEW" -> {
                val person = employee(a[0])
                val period = closed + 1
                val result = calculate(person, period)
                emit("PREVIEW", person.id, "period", period)
                if (result == null) emit("no pay", indent = 2)
                else printStub(person, period, result.stub, person.department)
            }
            "REPRINT" -> {
                val person = employee(a[0])
                val period = periodCheck(a[1])
                val record = person.stubs[period] ?: fail("no stub " + a[0] + " " + a[1])
                emit("REPRINT", person.id, period)
                printStub(person, period, record.stub, record.department)
            }
            "YTD" -> {
                val person = employee(a[0])
                emit("YTD", person.id, person.department, person.kind,
                     if (person.active) "active" else "terminated",
                     "periods", person.periods)
                val totals = Stub()
                for (field in fields) totals[field] = person.ytd.getValue(field)
                totals.ptoBalance = person.ptoBalance
                totals.garnishmentBalance = person.garnishBalance()
                stubBlock(person, totals, 2)
                emit("wages", "federal", money(totals["W"]),
                     "social-security", money(totals["Y"]),
                     "medicare", money(totals["F"]),
                     "unemployment", money(totals["J"]), indent = 2)
                emit("retirement-room",
                     money(maxOf(0L, settings.getValue("RETIRECAP") - totals["retirement"])),
                     "pending-bonus", money(person.bonus), indent = 2)
            }
            "JOURNAL" -> {
                val period = a[0].toInt()
                if (period !in 1..closed) fail("no run " + a[0])
                journal(period)
            }
            "REPORT" -> {
                val departments = sortedMapOf<String, MutableList<Stub>>()
                val all = mutableListOf<Stub>()
                for (person in employees.values) {
                    for (record in person.stubs.values) {
                        departments.getOrPut(record.department) { mutableListOf() }.add(record.stub)
                        all.add(record.stub)
                    }
                }
                emit("REPORT", "period", closed)
                for ((department, stubs) in departments) reportLine(department, stubs)
                reportLine("total", all)
            }
            "TOP" -> {
                val count = a[0].toInt()
                val ranked = employees.values.filter { it.periods > 0 }
                    .sortedWith(compareByDescending<Employee> { it.ytd.getValue("gross") }.thenBy { it.id })
                emit("TOP", count)
                for ((index, person) in ranked.take(count).withIndex())
                    emit(index + 1, person.id, person.department,
                         "gross", money(person.ytd.getValue("gross")),
                         "net", money(person.ytd.getValue("net")), indent = 2)
                if (ranked.isEmpty()) emit("(none)", indent = 2)
            }
            "EMPLOYEES" -> {
                emit("EMPLOYEES")
                for (person in employees.values) {
                    emit(person.id, person.department, person.kind, money(person.base),
                         if (person.active) "active" else "terminated",
                         "retirement", rateText(person.retirement),
                         "health", money(person.health),
                         "allowances", person.allowances, "extra", money(person.extra),
                         "bonus", money(person.bonus), indent = 2)
                    for ((index, order) in person.garnishments.withIndex())
                        emit("garnish", index + 1, rateText(order.rate),
                             "balance", money(order.balance), indent = 4)
                }
                if (employees.isEmpty()) emit("(none)", indent = 2)
            }
            "CONFIG" -> {
                emit("CONFIG")
                for ((key, value) in settings)
                    emit(key, if (key in rateSettings) rateText(value) else money(value), indent = 2)
                for ((label, table) in listOf("bracket" to brackets, "tier" to tiers))
                    for ((lower, rate) in table)
                        emit(label, money(lower), rateText(rate), indent = 2)
            }
        }
    }

    fun execute(line: String) {
        val tokens = line.split(' ')
        try {
            command(tokens[0], tokens.drop(1))
        } catch (error: CommandError) {
            emit("ERROR", error.message ?: "")
        }
    }

    fun printOutput() {
        for (line in output) println(line)
    }
}

fun main() {
    val count = readLine()!!.toInt()
    val payroll = Payroll()
    repeat(count) { payroll.execute(readLine()!!) }
    payroll.printOutput()
}
