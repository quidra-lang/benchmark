import java.io.BufferedWriter
import java.util.TreeMap
import kotlin.math.abs

private const val LAST_DAY = 36524
private typealias Cents = Long

private class CommandError(message: String) : RuntimeException(message)

private enum class AccountType {
    ASSET, LIABILITY, EQUITY, REVENUE, EXPENSE, CONTRA_ASSET;

    fun typeClass() = if (this == CONTRA_ASSET) ASSET else this
    fun sign(): Cents = if (this == ASSET || this == EXPENSE) 1 else -1
    fun temporary() = this == REVENUE || this == EXPENSE
}

private enum class Category {
    JOURNAL, RECURRING, REVERSAL, CLOSING, REOPEN, DEPRECIATION, INTEREST, WRITEOFF;

    fun text() = name.lowercase()
}

private fun parseMoney(text: String): Cents {
    val (whole, fraction) = text.split('.')
    return whole.toLong() * 100 + fraction.toLong()
}

private fun money(value: Cents): String {
    val magnitude = abs(value)
    return (if (value < 0) "-" else "") + "${magnitude / 100}.${(magnitude % 100).toString().padStart(2, '0')}"
}

private fun leap(year: Int) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
private fun yearLength(year: Int) = if (leap(year)) 366 else 365

private fun monthLength(year: Int, month: Int): Int {
    val lengths = intArrayOf(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    return if (month == 2 && leap(year)) 29 else lengths[month - 1]
}

private fun dayNumber(year: Int, month: Int, day: Int): Int {
    var number = day - 1
    for (y in 2000 until year) number += yearLength(y)
    for (m in 1 until month) number += monthLength(year, m)
    return number
}

private data class CalendarDate(val year: Int, val month: Int, val day: Int)

private fun calendar(day: Int): CalendarDate {
    var remaining = day
    var year = 2000
    var month = 1
    while (remaining >= yearLength(year)) { remaining -= yearLength(year); year++ }
    while (remaining >= monthLength(year, month)) { remaining -= monthLength(year, month); month++ }
    return CalendarDate(year, month, remaining + 1)
}

private fun dateText(day: Int): String {
    val date = calendar(day)
    return "${date.year.toString().padStart(4, '0')}-${date.month.toString().padStart(2, '0')}-${date.day.toString().padStart(2, '0')}"
}

private fun parseDate(text: String): Int {
    val year = text.substring(0, 4).toInt()
    val month = text.substring(5, 7).toInt()
    val day = text.substring(8).toInt()
    if (year !in 2000..2099 || month !in 1..12 || day < 1 || day > monthLength(year, month)) {
        throw CommandError("invalid date $text")
    }
    return dayNumber(year, month, day)
}

private fun dateRange(first: String, last: String): IntRange {
    val start = parseDate(first)
    val end = parseDate(last)
    if (start > end) throw CommandError("invalid range $first $last")
    return start..end
}

private fun monthsAfter(day: Int, offset: Int): Int {
    val date = calendar(day)
    val total = date.month - 1 + offset
    val year = date.year + total / 12
    val month = total % 12 + 1
    return dayNumber(year, month, minOf(date.day, monthLength(year, month)))
}

private class Account(val code: String, val type: AccountType, val name: String) {
    var active = true
}

private data class Totals(val debit: Cents = 0, val credit: Cents = 0) {
    val difference get() = debit - credit
    operator fun plus(other: Totals) = Totals(debit + other.debit, credit + other.credit)
    fun add(isDebit: Boolean, amount: Cents) = if (isDebit) Totals(debit + amount, credit) else Totals(debit, credit + amount)

    companion object { val ZERO = Totals() }
}

private data class Line(val debit: Boolean, val account: Account, val amount: Cents, val partner: String? = null) {
    val difference get() = if (debit) amount else -amount
    val side get() = if (debit) "DR" else "CR"
}

private class Lines(items: List<Line>) {
    val items = items.toList()
    val amount = items.filter { it.debit }.sumOf { it.amount }
    val accounts: Map<Account, Totals> = buildMap {
        for (line in items) put(line.account, (get(line.account) ?: Totals.ZERO).add(line.debit, line.amount))
    }

    fun totals(account: Account) = accounts[account] ?: Totals.ZERO
}

private data class DraftLine(val debit: Boolean, val code: String, val amount: Cents, val partner: String?)

private class Draft(val journal: Boolean, val key: String, val date: String?, val memo: String) {
    val lines = mutableListOf<DraftLine>()
    fun totals() = lines.fold(Totals.ZERO) { totals, line -> totals.add(line.debit, line.amount) }
}

private class Entry(val id: String, val day: Int, val category: Category, val memo: String, val lines: Lines, val sequence: Int) {
    var reverses: Entry? = null
    var reversedBy: Entry? = null
}

private class Template(val memo: String, val lines: Lines) { var uses = 0 }
private data class CloseRecord(val day: Int, val entry: Entry?)
private class OpenItem(val entry: Entry, val original: Cents, var remaining: Cents)

private class Settlement {
    val items = ArrayDeque<OpenItem>()
    var unapplied: Cents = 0
}

private data class Displayed(val account: Account, val amount: Cents)

private class Book(private val output: BufferedWriter) {
    private val accounts = TreeMap<String, Account>()
    private val entries = mutableListOf<Entry>()
    private val entryIds = mutableMapOf<String, Entry>()
    private val templates = TreeMap<String, Template>()
    private val closes = mutableListOf<CloseRecord>()
    private var draft: Draft? = null
    private var closeCount = 0
    private var depreciationCount = 0
    private var interestCount = 0
    private var writeoffCount = 0

    fun emit(text: String) { output.append(text).append('\n') }

    private fun account(code: String) = accounts[code] ?: throw CommandError("unknown account $code")

    private fun requireType(code: String, type: AccountType): Account {
        val account = account(code)
        if (account.type != type) throw CommandError("wrong type $code $type")
        return account
    }

    private fun active(vararg selected: Account) {
        for (account in selected) if (!account.active) throw CommandError("inactive account ${account.code}")
    }

    private fun activeLines(lines: Lines) {
        for (line in lines.items) active(line.account)
    }

    private fun checkOpen(day: Int) {
        val latest = closes.lastOrNull()
        if (latest != null && day <= latest.day) throw CommandError("period closed ${dateText(day)}")
    }

    private fun closedText() = closes.lastOrNull()?.let { dateText(it.day) } ?: "none"

    private fun parent(code: String): String {
        for (length in code.length - 1 downTo 1) if (code.take(length) in accounts) return code.take(length)
        return "none"
    }

    private fun top(code: String): String {
        for (length in 1 until code.length) if (code.take(length) in accounts) return code.take(length)
        return code
    }

    private fun ordered() = entries.sortedWith(compareBy<Entry> { it.day }.thenBy { it.sequence })

    private fun totals(first: Int, last: Int, operating: Boolean = false): Map<Account, Totals> {
        val totals = mutableMapOf<Account, Totals>()
        for (entry in entries) {
            if (entry.day !in first..last || operating && entry.category in setOf(Category.CLOSING, Category.REOPEN)) continue
            for ((account, amount) in entry.lines.accounts) totals[account] = (totals[account] ?: Totals.ZERO) + amount
        }
        return totals
    }

    private fun accountTotals(account: Account, first: Int, last: Int): Totals {
        var totals = Totals.ZERO
        for (entry in entries) if (entry.day in first..last) totals += entry.lines.totals(account)
        return totals
    }

    private fun balance(account: Account, day: Int) = account.type.sign() * accountTotals(account, 0, day).difference

    private fun dailySum(account: Account, first: Int, last: Int): Cents {
        val changes = LongArray(last - first + 1)
        var running = 0L
        var sum = 0L
        for (entry in entries) {
            if (entry.day > last) continue
            val value = account.type.sign() * entry.lines.totals(account).difference
            if (entry.day < first) running += value else changes[entry.day - first] += value
        }
        for (change in changes) { running += change; sum += running }
        return sum
    }

    private fun post(id: String, day: Int, category: Category, memo: String, lines: Lines): Entry {
        val entry = Entry(id, day, category, memo, lines, entries.size + 1)
        entries += entry
        entryIds[id] = entry
        return entry
    }

    private fun reverse(original: Entry, day: Int, category: Category, memo: String): Entry {
        val lines = Lines(original.lines.items.map { it.copy(debit = !it.debit) })
        val entry = post("${original.id}-R", day, category, memo, lines)
        original.reversedBy = entry
        entry.reverses = original
        return entry
    }

    private fun settlements(account: Account, day: Int): TreeMap<String, Settlement> {
        val settlements = TreeMap<String, Settlement>()
        for (entry in ordered()) {
            if (entry.day > day) continue
            for (line in entry.lines.items) {
                if (line.account !== account) continue
                val partner = line.partner ?: continue
                val settled = settlements.getOrPut(partner) { Settlement() }
                val value = account.type.sign() * line.difference
                if (value > 0) {
                    val applied = minOf(value, settled.unapplied)
                    settled.unapplied -= applied
                    if (value > applied) settled.items.addLast(OpenItem(entry, value, value - applied))
                } else {
                    var payment = -value
                    while (payment > 0 && settled.items.isNotEmpty()) {
                        val item = settled.items.first()
                        val applied = minOf(payment, item.remaining)
                        payment -= applied
                        item.remaining -= applied
                        if (item.remaining == 0L) settled.items.removeFirst()
                    }
                    settled.unapplied += payment
                }
            }
        }
        return settlements
    }

    private fun postDraft() {
        val block = draft ?: throw CommandError("no open entry")
        draft = null
        var day = 0
        if (block.journal) {
            if (block.key in entryIds) throw CommandError("duplicate entry ${block.key}")
            day = parseDate(block.date!!)
            checkOpen(day)
        } else if (block.key in templates) throw CommandError("duplicate template ${block.key}")
        if (block.lines.size < 2) throw CommandError("too few lines ${block.key}")
        val items = block.lines.map { line ->
            val account = account(line.code)
            if (block.journal) active(account)
            if (line.amount == 0L) throw CommandError("zero amount ${line.code}")
            Line(line.debit, account, line.amount, line.partner)
        }
        val totals = block.totals()
        if (totals.debit != totals.credit) throw CommandError("unbalanced ${block.key} debit ${money(totals.debit)} credit ${money(totals.credit)}")
        val lines = Lines(items)
        if (block.journal) {
            post(block.key, day, Category.JOURNAL, block.memo, lines)
            emit("POST ${block.key} ${dateText(day)} lines ${items.size} amount ${money(lines.amount)}")
        } else {
            templates[block.key] = Template(block.memo, lines)
            emit("TEMPLATE ${block.key} lines ${items.size} amount ${money(lines.amount)}")
        }
    }

    private fun section(heading: String, types: Set<AccountType>, sign: Int, totals: Map<Account, Totals>, earnings: Cents? = null): Cents {
        val groups = TreeMap<String, MutableList<Displayed>>()
        var total = earnings ?: 0L
        for (account in accounts.values) {
            if (account.type !in types) continue
            val value = sign * (totals[account] ?: Totals.ZERO).difference
            groups.getOrPut(top(account.code)) { mutableListOf() }.add(Displayed(account, value))
            total += value
        }
        emit("  $heading ${money(total)}")
        for ((root, group) in groups) {
            if (group.none { it.amount != 0L }) continue
            emit("    $root ${accounts.getValue(root).name} ${money(group.sumOf { it.amount })}")
            for ((account, amount) in group) if (amount != 0L) emit("      ${account.code} ${account.name} ${money(amount)}")
        }
        if (earnings != null) emit("    current earnings ${money(earnings)}")
        return total
    }

    private fun agingRow(partner: String, values: LongArray) {
        val balance = values[0] + values[1] + values[2] + values[3] - values[4]
        emit("  $partner 0-30 ${money(values[0])} 31-60 ${money(values[1])} 61-90 ${money(values[2])} " +
             "91+ ${money(values[3])} unapplied ${money(values[4])} balance ${money(balance)}")
    }

    fun execute(words: List<String>) {
        when (words[0]) {
            "ACCOUNT" -> {
                val code = words[1]
                if (code in accounts) throw CommandError("duplicate account $code")
                val type = AccountType.valueOf(words[2])
                for (other in accounts.values) {
                    if ((code.startsWith(other.code) || other.code.startsWith(code)) && type.typeClass() != other.type.typeClass()) {
                        throw CommandError("class mismatch $code ${other.code}")
                    }
                }
                accounts[code] = Account(code, type, words[3])
                emit("ACCOUNT $code $type ${words[3]} parent ${parent(code)}")
            }
            "DEACTIVATE" -> {
                val account = account(words[1])
                if (!account.active) throw CommandError("already inactive ${account.code}")
                val value = balance(account, LAST_DAY)
                if (value != 0L) throw CommandError("nonzero balance ${account.code} ${money(value)}")
                account.active = false
                emit("DEACTIVATE ${account.code} ${account.name}")
            }
            "JOURNAL", "TEMPLATE" -> {
                draft?.let { emit("DISCARD ${it.key} lines ${it.lines.size}") }
                val journal = words[0] == "JOURNAL"
                draft = Draft(journal, words[1], if (journal) words[2] else null, words[if (journal) 3 else 2])
            }
            "DR", "CR" -> {
                val block = draft ?: throw CommandError("no open entry")
                block.lines += DraftLine(words[0] == "DR", words[1], parseMoney(words[2]), words.getOrNull(3))
            }
            "POST" -> postDraft()
            "DRAFT" -> {
                val block = draft ?: throw CommandError("no open entry")
                val totals = block.totals()
                val kind = if (block.journal) "journal" else "template"
                emit("DRAFT $kind ${block.key} lines ${block.lines.size} debit ${money(totals.debit)} " +
                     "credit ${money(totals.credit)} difference ${money(totals.difference)}")
            }
            "REVERSE" -> {
                val original = entryIds[words[1]] ?: throw CommandError("unknown entry ${words[1]}")
                if (original.category in setOf(Category.REVERSAL, Category.CLOSING, Category.REOPEN)) throw CommandError("cannot reverse ${original.id}")
                if (original.reversedBy != null) throw CommandError("already reversed ${original.id}")
                val day = parseDate(words[2])
                if (day < original.day) throw CommandError("reverse before entry ${original.id} ${dateText(original.day)}")
                checkOpen(day)
                activeLines(original.lines)
                val entry = reverse(original, day, Category.REVERSAL, original.memo)
                emit("REVERSE ${original.id} entry ${entry.id} ${dateText(day)} amount ${money(entry.lines.amount)}")
            }
            "RECUR" -> {
                val model = templates[words[1]] ?: throw CommandError("unknown template ${words[1]}")
                val day = parseDate(words[2])
                val count = words[3].toInt()
                if (count == 0) throw CommandError("invalid count")
                checkOpen(day)
                activeLines(model.lines)
                emit("RECUR ${words[1]} count $count")
                for (offset in 0 until count) {
                    model.uses++
                    val entry = post("${words[1]}-${model.uses}", monthsAfter(day, offset), Category.RECURRING, model.memo, model.lines)
                    emit("  POST ${entry.id} ${dateText(entry.day)} lines ${entry.lines.items.size} amount ${money(entry.lines.amount)}")
                }
            }
            "DEPRECIATE" -> {
                val day = parseDate(words[1])
                checkOpen(day)
                val asset = requireType(words[2], AccountType.ASSET)
                val contra = requireType(words[3], AccountType.CONTRA_ASSET)
                val expense = requireType(words[4], AccountType.EXPENSE)
                active(contra, expense)
                val cost = balance(asset, day)
                val accumulated = balance(contra, day)
                val amount = if (cost > 0) minOf(cost / words[5].toInt(), cost - accumulated) else 0L
                if (amount <= 0) throw CommandError("nothing to depreciate ${asset.code}")
                val lines = Lines(listOf(Line(true, expense, amount), Line(false, contra, amount)))
                depreciationCount++
                val entry = post("DEP-$depreciationCount", day, Category.DEPRECIATION, "depreciation", lines)
                emit("DEPRECIATE ${asset.code} entry ${entry.id} ${dateText(day)} amount ${money(amount)} " +
                     "accumulated ${money(accumulated + amount)} book ${money(cost - accumulated - amount)}")
            }
            "INTEREST" -> {
                val account = account(words[1])
                if (account.type !in setOf(AccountType.ASSET, AccountType.LIABILITY)) throw CommandError("not interest bearing ${account.code}")
                val offset = requireType(words[2], if (account.type == AccountType.ASSET) AccountType.REVENUE else AccountType.EXPENSE)
                val range = dateRange(words[3], words[4])
                checkOpen(range.last)
                active(account, offset)
                val sum = dailySum(account, range.first, range.last)
                val amount = sum * words[5].toInt() / 3650000
                if (amount <= 0) throw CommandError("no interest ${account.code}")
                val asset = account.type == AccountType.ASSET
                val lines = Lines(listOf(Line(true, if (asset) account else offset, amount), Line(false, if (asset) offset else account, amount)))
                interestCount++
                val entry = post("INT-$interestCount", range.last, Category.INTEREST, "interest", lines)
                val days = range.last - range.first + 1
                emit("INTEREST ${account.code} entry ${entry.id} ${dateText(range.last)} days $days average ${money(sum / days)} amount ${money(amount)}")
            }
            "WRITEOFF" -> {
                val day = parseDate(words[1])
                checkOpen(day)
                val account = requireType(words[2], AccountType.ASSET)
                val expense = requireType(words[3], AccountType.EXPENSE)
                active(account, expense)
                val age = words[4].toInt()
                val targets = TreeMap<String, Cents>()
                for ((partner, settled) in settlements(account, day)) {
                    val amount = settled.items.filter { day - it.entry.day > age }.sumOf { it.remaining }
                    if (amount > 0) targets[partner] = amount
                }
                val total = targets.values.sum()
                if (total == 0L) throw CommandError("nothing to write off ${account.code}")
                val items = mutableListOf(Line(true, expense, total))
                for ((partner, amount) in targets) items += Line(false, account, amount, partner)
                writeoffCount++
                val entry = post("WO-$writeoffCount", day, Category.WRITEOFF, "writeoff", Lines(items))
                emit("WRITEOFF ${account.code} entry ${entry.id} ${dateText(day)} partners ${targets.size} amount ${money(total)}")
                for ((partner, amount) in targets) emit("  $partner ${money(amount)}")
            }
            "CLOSE" -> {
                val day = parseDate(words[1])
                checkOpen(day)
                val equity = requireType(words[2], AccountType.EQUITY)
                active(equity)
                val totals = totals(0, day)
                val targets = accounts.values.filter { it.type.temporary() && (totals[it] ?: Totals.ZERO).difference != 0L }
                for (account in targets) active(account)
                val items = mutableListOf<Line>()
                var income = 0L
                for (account in targets) {
                    val value = totals.getValue(account).difference
                    items += Line(value < 0, account, abs(value))
                    income -= value
                }
                if (income != 0L) items += Line(income < 0, equity, abs(income))
                closeCount++
                val entry = if (items.isEmpty()) null else post("CLOSE-$closeCount", day, Category.CLOSING, "closing", Lines(items))
                closes += CloseRecord(day, entry)
                if (entry == null) emit("CLOSE ${dateText(day)} no entry")
                else emit("CLOSE ${dateText(day)} entry ${entry.id} lines ${items.size} net income ${money(income)}")
            }
            "REOPEN" -> {
                val record = closes.lastOrNull() ?: throw CommandError("nothing to reopen")
                val detail = record.entry?.let {
                    activeLines(it.lines)
                    "entry ${reverse(it, record.day, Category.REOPEN, "reopen").id}"
                } ?: "no entry"
                closes.removeAt(closes.lastIndex)
                emit("REOPEN ${dateText(record.day)} $detail closed ${closedText()}")
            }
            "LEDGER" -> {
                val account = account(words[1])
                val range = dateRange(words[2], words[3])
                var running = balance(account, range.first - 1)
                var totals = Totals.ZERO
                emit("LEDGER ${account.code} ${account.name} ${words[2]} ${words[3]}")
                emit("  opening ${money(running)}")
                for (entry in ordered()) {
                    if (entry.day !in range) continue
                    for (line in entry.lines.items) {
                        if (line.account !== account) continue
                        totals = totals.add(line.debit, line.amount)
                        running += account.type.sign() * line.difference
                        emit("  ${dateText(entry.day)} ${entry.id} ${line.side} ${money(line.amount)} balance ${money(running)} ${entry.memo}")
                    }
                }
                val days = range.last - range.first + 1
                emit("  ending ${money(running)} debits ${money(totals.debit)} credits ${money(totals.credit)} days $days " +
                     "average ${money(dailySum(account, range.first, range.last) / days)}")
            }
            "ACTIVITY" -> {
                val account = account(words[1])
                val year = words[2].toInt()
                var totals = Totals.ZERO
                emit("ACTIVITY ${account.code} ${account.name} $year")
                for (month in 1..12) {
                    val first = dayNumber(year, month, 1)
                    val last = dayNumber(year, month, monthLength(year, month))
                    val current = accountTotals(account, first, last)
                    totals += current
                    emit("  $year-${month.toString().padStart(2, '0')} debit ${money(current.debit)} credit ${money(current.credit)} balance ${money(balance(account, last))}")
                }
                emit("  total debit ${money(totals.debit)} credit ${money(totals.credit)}")
            }
            "TRIAL" -> {
                val day = parseDate(words[1])
                val totals = totals(0, day)
                var debit = 0L
                var credit = 0L
                emit("TRIAL ${words[1]}")
                for (account in accounts.values) {
                    val value = (totals[account] ?: Totals.ZERO).difference
                    if (value == 0L) continue
                    if (value > 0) debit += value else credit -= value
                    val side = if (value > 0) "debit" else "credit"
                    emit("  ${account.code} ${account.name} $side ${money(abs(value))}")
                }
                emit("  total debit ${money(debit)} credit ${money(credit)}")
            }
            "INCOME" -> {
                val range = dateRange(words[1], words[2])
                val totals = totals(range.first, range.last, true)
                emit("INCOME ${words[1]} ${words[2]}")
                val revenue = section("REVENUE", setOf(AccountType.REVENUE), -1, totals)
                val expense = section("EXPENSE", setOf(AccountType.EXPENSE), 1, totals)
                emit("  NET INCOME ${money(revenue - expense)}")
            }
            "BALANCE" -> {
                val day = parseDate(words[1])
                val totals = totals(0, day)
                val earnings = -accounts.values.filter { it.type.temporary() }.sumOf { (totals[it] ?: Totals.ZERO).difference }
                emit("BALANCE ${words[1]}")
                val assets = section("ASSETS", setOf(AccountType.ASSET, AccountType.CONTRA_ASSET), 1, totals)
                val liabilities = section("LIABILITIES", setOf(AccountType.LIABILITY), -1, totals)
                val equity = section("EQUITY", setOf(AccountType.EQUITY), -1, totals, earnings)
                if (assets == liabilities + equity) emit("  check ok")
                else emit("  check mismatch ${money(assets - liabilities - equity)}")
            }
            "ROLLUP" -> {
                val day = parseDate(words[2])
                val targets = accounts.values.filter { it.code.startsWith(words[1]) }
                emit("ROLLUP ${words[1]} ${words[2]}")
                if (targets.isEmpty()) { emit("  (none)"); return }
                val totals = totals(0, day)
                var postings = Totals.ZERO
                for (account in targets) {
                    val depth = targets.count { it !== account && account.code.startsWith(it.code) }
                    val subtotal = targets.filter { it.code.startsWith(account.code) }.sumOf { (totals[it] ?: Totals.ZERO).difference }
                    val own = totals[account] ?: Totals.ZERO
                    emit("${" ".repeat(2 * (1 + depth))}${account.code} ${account.name} " +
                         "own ${money(account.type.sign() * own.difference)} total ${money(account.type.sign() * subtotal)}")
                    postings += own
                }
                emit("  postings debit ${money(postings.debit)} credit ${money(postings.credit)}")
            }
            "AGING", "ITEMS" -> {
                val account = account(words[1])
                val aging = words[0] == "AGING"
                val day = parseDate(words[if (aging) 2 else 3])
                val settlements = settlements(account, day)
                if (aging) {
                    emit("AGING ${account.code} ${account.name} ${words[2]}")
                    val totals = LongArray(5)
                    for ((partner, settled) in settlements) {
                        if (settled.items.isEmpty() && settled.unapplied == 0L) continue
                        val values = longArrayOf(0, 0, 0, 0, settled.unapplied)
                        for (item in settled.items) {
                            val age = day - item.entry.day
                            val bucket = when { age <= 30 -> 0; age <= 60 -> 1; age <= 90 -> 2; else -> 3 }
                            values[bucket] += item.remaining
                        }
                        agingRow(partner, values)
                        for (i in 0..4) totals[i] += values[i]
                    }
                    agingRow("total", totals)
                } else {
                    val settled = settlements[words[2]] ?: Settlement()
                    emit("ITEMS ${account.code} ${account.name} ${words[2]} ${words[3]}")
                    var remaining = 0L
                    for (item in settled.items) {
                        emit("  ${dateText(item.entry.day)} ${item.entry.id} amount ${money(item.original)} open ${money(item.remaining)} age ${day - item.entry.day}")
                        remaining += item.remaining
                    }
                    emit("  unapplied ${money(settled.unapplied)} balance ${money(remaining - settled.unapplied)}")
                }
            }
            "ENTRY" -> {
                val entry = entryIds[words[1]] ?: throw CommandError("unknown entry ${words[1]}")
                emit("ENTRY ${entry.id} ${dateText(entry.day)} ${entry.category.text()} ${entry.memo}")
                for (line in entry.lines.items) {
                    val partner = line.partner?.let { " $it" } ?: ""
                    emit("  ${line.side} ${line.account.code} ${line.account.name} ${money(line.amount)}$partner")
                }
                emit("  total ${money(entry.lines.amount)}")
                entry.reverses?.let { emit("  reverses ${it.id}") }
                entry.reversedBy?.let { emit("  reversed by ${it.id}") }
            }
            "DAYBOOK" -> {
                val range = dateRange(words[1], words[2])
                var total = 0L
                var count = 0
                emit("DAYBOOK ${words[1]} ${words[2]}")
                for (entry in ordered()) {
                    if (entry.day !in range) continue
                    total += entry.lines.amount
                    count++
                    emit("  ${dateText(entry.day)} ${entry.id} ${entry.category.text()} ${money(entry.lines.amount)} ${entry.memo}")
                }
                emit("  total entries $count amount ${money(total)}")
            }
            "ACCOUNTS" -> {
                val totals = totals(0, LAST_DAY)
                emit("ACCOUNTS")
                for (account in accounts.values) {
                    val status = if (account.active) "active" else "inactive"
                    emit("  ${account.code} ${account.type} ${account.name} parent ${parent(account.code)} " +
                         "balance ${money(account.type.sign() * (totals[account] ?: Totals.ZERO).difference)} $status")
                }
                if (accounts.isEmpty()) emit("  (none)")
            }
            "TEMPLATES" -> {
                emit("TEMPLATES")
                for ((name, model) in templates) emit("  $name ${model.memo} lines ${model.lines.items.size} amount ${money(model.lines.amount)} used ${model.uses}")
                if (templates.isEmpty()) emit("  (none)")
            }
            "STATUS" -> {
                val inactive = accounts.values.count { !it.active }
                emit("STATUS accounts ${accounts.size} inactive $inactive entries ${entries.size} templates ${templates.size} " +
                     "closed ${closedText()} open ${draft?.key ?: "none"}")
            }
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine().toInt()
    val book = Book(output)
    repeat(count) {
        try { book.execute(input.readLine().split(' ')) }
        catch (error: CommandError) { book.emit("ERROR ${error.message}") }
    }
    output.flush()
}
