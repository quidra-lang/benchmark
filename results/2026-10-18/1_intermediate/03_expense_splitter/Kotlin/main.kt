import java.util.TreeMap

data class Amount(val value: Long, val currency: String = "")
data class Member(val active: Boolean, val day: Long)
data class Part(val name: String, val value: Long)
data class Settlement(val day: Long, val record: Long, val from: String, val to: String, val amount: Amount, val total: Long)
data class Entry(val day: Long, val record: Long, val label: String, val change: Long)
data class Transfer(val from: String, val to: String, val amount: Long)
data class Expense(var id: String = "", var category: String = "", var mode: String = "",
    var amount: Amount = Amount(0), var payers: List<Part> = emptyList(), var participants: List<Part> = emptyList(),
    var contributions: List<Long> = emptyList(), var shares: List<Long> = emptyList(), var day: Long = 0,
    var record: Long = 0, var total: Long = 0, var interval: Long = 0, var next: Long = 0, var copies: Long = 0)
class Problem(message: String) : RuntimeException(message)

class Splitter {
    private val members = TreeMap<String,Member>()
    private val currencies = TreeMap<String,Long>()
    private val budgets = TreeMap<String,Long>()
    private val expenses = linkedMapOf<String,Expense>()
    private val used = mutableSetOf<String>()
    private val settlements = mutableListOf<Settlement>()
    private var day = 1L
    private var serial = 0L
    private fun fail(message: String): Nothing = throw Problem(message)
    private fun money(s: String): Long {
        val (a,b) = s.split('.')
        return a.toLong()*100+b.toLong()
    }
    private fun amount(s: String): Amount {
        val parts = s.split('@')
        return Amount(money(parts[0]),parts.getOrElse(1) { "" })
    }
    private fun fmt(n: Long) = "${n/100}.${(n%100).toString().padStart(2,'0')}"
    private fun signed(n: Long) = if (n > 0) "+${fmt(n)}" else if (n < 0) "-${fmt(-n)}" else "0.00"
    private fun rate(n: Long) = "${n/10000}.${(n%10000).toString().padStart(4,'0')}"
    private fun percent(p: Long, w: Long) = "${fmt(p*10000/w)}%"
    private fun note(a: Amount) = if (a.currency.isEmpty()) "" else " [${fmt(a.value)} ${a.currency}]"
    private fun registered(name: String) {
        if (name !in members) fail("unknown member $name")
    }
    private fun active(name: String) {
        registered(name)
        if (!members.getValue(name).active) fail("inactive member $name")
    }
    private fun convert(a: Amount): Long {
        if (a.currency.isEmpty()) return a.value
        val rate = currencies[a.currency] ?: fail("unknown currency ${a.currency}")
        return (a.value*rate+5000)/10000
    }
    private fun expense(id: String) = expenses[id] ?: fail("unknown expense $id")
    private fun thawed(e: Expense) {
        for (p in e.payers+e.participants) {
            if (!members.getValue(p.name).active) fail("inactive member ${p.name}")
        }
    }
    private fun distribute(total: Long, weights: List<Long>): List<Long> {
        val sum = weights.sum()
        val result = weights.map { total*it/sum }.toMutableList()
        val remainders = weights.map { total*it%sum }
        val order = weights.indices.sortedWith(compareByDescending<Int> { remainders[it] }.thenBy { it })
        val left = (total-result.sum()).toInt()
        for (i in 0 until left) result[order[i]]++
        return result
    }
    private fun compute(e: Expense) {
        val a = e.amount.value
        e.total = convert(e.amount)
        val sum = e.participants.sumOf { it.value }
        val portions = when (e.mode) {
            "EXACT" -> {
                if (sum != a) fail("splits do not add up")
                e.participants.map { it.value }
            }
            "PERCENT", "SHARES" -> {
                if (e.mode == "PERCENT" && sum != 10000L || e.mode == "SHARES" && sum == 0L) fail("splits do not add up")
                distribute(a,e.participants.map { it.value })
            }
            else -> {
                val extras = if (e.mode == "ADJUST") sum else 0L
                if (extras > a) fail("splits do not add up")
                val k = e.participants.size
                e.participants.mapIndexed { i,p ->
                    (a-extras)/k+(if (i < (a-extras)%k) 1 else 0)+(if (e.mode == "ADJUST") p.value else 0L)
                }
            }
        }
        e.shares = distribute(e.total,portions)
        e.contributions = distribute(e.total,e.payers.map { it.value })
    }
    private fun build(t: List<String>): Expense {
        active(t[2])
        val a = amount(t[3])
        if (convert(a) == 0L || a.value == 0L) fail("invalid amount")
        val e = Expense(category = t[4],mode = t[5],amount = a,payers = listOf(Part(t[2],a.value)))
        e.participants = if (e.mode == "EQUAL" && t[6] == "ALL") {
            members.filterValues { it.active }.keys.map { Part(it,0) }
        } else {
            val seen = mutableSetOf<String>()
            t.drop(6).map { token ->
                val p = token.split(':')
                active(p[0])
                if (!seen.add(p[0])) fail("duplicate member ${p[0]}")
                val value = if (p.size == 1) 0L else if (e.mode in setOf("EXACT","ADJUST")) money(p[1]) else p[1].toLong()
                Part(p[0],value)
            }
        }
        compute(e)
        return e
    }
    private fun chronological() = expenses.values.sortedWith(compareBy<Expense> { it.day }.thenBy { it.record })
    private fun includes(e: Expense, name: String) = (e.payers+e.participants).any { it.name == name }
    private fun net(e: Expense): TreeMap<String,Long> {
        val result = TreeMap<String,Long>()
        for ((i,p) in e.payers.withIndex()) result[p.name] = result.getOrDefault(p.name,0)+e.contributions[i]
        for ((i,p) in e.participants.withIndex()) result[p.name] = result.getOrDefault(p.name,0)-e.shares[i]
        return result
    }
    private fun balances(): TreeMap<String,Long> {
        val result = TreeMap<String,Long>()
        for (name in members.keys) result[name] = 0
        for (e in expenses.values) {
            for ((name,value) in net(e)) result[name] = result.getValue(name)+value
        }
        for (s in settlements) {
            result[s.from] = result.getValue(s.from)+s.total
            result[s.to] = result.getValue(s.to)-s.total
        }
        return result
    }
    private fun activeNames() = members.filterValues { it.active }.keys.toList()
    private fun categoryTotals(): TreeMap<String,Long> {
        val result = TreeMap<String,Long>()
        for (e in expenses.values) result[e.category] = result.getOrDefault(e.category,0)+e.total
        return result
    }
    private fun warning(e: Expense, output: MutableList<String>) {
        val budget = budgets[e.category] ?: return
        val spent = categoryTotals().getValue(e.category)
        if (spent > budget) output.add("  WARNING ${e.category} over budget by ${fmt(spent-budget)}")
    }
    private fun pairs(people: List<Part>, values: List<Long>) = people.indices.joinToString(" + ") { "${people[it].name} ${fmt(values[it])}" }
    private fun greedy(balances: Map<String,Long>): List<Transfer> {
        val work = TreeMap(balances)
        val result = mutableListOf<Transfer>()
        while (true) {
            var from = ""
            var to = ""
            var minimum = 0L
            var maximum = 0L
            for ((name,value) in work) {
                if (value < minimum) {
                    minimum = value
                    from = name
                }
                if (value > maximum) {
                    maximum = value
                    to = name
                }
            }
            if (minimum == 0L) break
            val value = minOf(-minimum,maximum)
            result.add(Transfer(from,to,value))
            work[from] = minimum+value
            work[to] = maximum-value
        }
        return result
    }
    private fun debts(names: List<String>): Array<LongArray> {
        val index = names.withIndex().associate { it.value to it.index }
        val result = Array(names.size) { LongArray(names.size) }
        for (e in expenses.values) {
            val amounts = net(e)
            val borrowers = amounts.filterValues { it < 0 }.keys.toList()
            val lenders = amounts.filterValues { it > 0 }.keys.toList()
            var a = 0
            var b = 0
            while (a < borrowers.size && b < lenders.size) {
                val x = borrowers[a]
                val y = lenders[b]
                val value = minOf(-amounts.getValue(x),amounts.getValue(y))
                val i = index.getValue(x)
                val j = index.getValue(y)
                result[i][j] += value
                result[j][i] -= value
                amounts[x] = amounts.getValue(x)+value
                amounts[y] = amounts.getValue(y)-value
                if (amounts[x] == 0L) a++
                if (amounts[y] == 0L) b++
            }
        }
        for (s in settlements) {
            val i = index.getValue(s.from)
            val j = index.getValue(s.to)
            result[i][j] -= s.total
            result[j][i] += s.total
        }
        return result
    }
    private fun indexes(mask: Int, n: Int) = (0 until n).filter { mask and (1 shl it) != 0 }
    private fun lexLess(a: List<Int>, b: List<Int>): Boolean {
        for (i in 0 until minOf(a.size,b.size)) {
            if (a[i] != b[i]) return a[i] < b[i]
        }
        return a.size < b.size
    }
    fun execute(line: String): List<String> {
        val t = line.split(' ')
        val command = t[0]
        val output = mutableListOf<String>()
        when (command) {
            "DAY" -> {
                val d = t[1].toLong()
                if (d <= day) fail("invalid day ${t[1]}")
                output.add("DAY $d")
                while (true) {
                    val template = expenses.values.filter { it.interval > 0 && it.next <= d }
                        .minWithOrNull(compareBy<Expense> { it.next }.thenBy { it.record }) ?: break
                    if ((template.payers+template.participants).any { !members.getValue(it.name).active } || convert(template.amount) == 0L) {
                        template.interval = 0
                        output.add("  CANCEL ${template.id}")
                    } else {
                        val copy = template.copy(id = "${template.id}#${template.copies+2}",day = template.next,
                            record = ++serial,interval = 0,next = 0,copies = 0)
                        compute(copy)
                        expenses[copy.id] = copy
                        used.add(copy.id)
                        template.copies++
                        template.next += template.interval
                        output.add("  RECUR ${copy.id} ${fmt(copy.total)}")
                        warning(copy,output)
                    }
                }
                day = d
            }
            "MEMBER" -> {
                val old = members[t[1]]
                if (old?.active == true) fail("duplicate member ${t[1]}")
                members[t[1]] = Member(true,day)
                output.add("MEMBER ${t[1]} "+if (old == null) "joined" else "rejoined")
            }
            "LEAVE" -> {
                active(t[1])
                if (balances().getValue(t[1]) != 0L) fail("member has a balance ${t[1]}")
                members[t[1]] = Member(false,day)
                output.add("LEAVE ${t[1]}")
            }
            "CURRENCY" -> {
                val value = t[2].toLong()
                val old = currencies.put(t[1],value)
                output.add("CURRENCY ${t[1]} ${rate(value)}"+if (old == null) "" else " was ${rate(old)}")
            }
            "EXPENSE", "EDIT" -> {
                val old = if (command == "EDIT") expense(t[1]).also(::thawed) else null
                if (old == null && t[1] in used) fail("duplicate id ${t[1]}")
                val e = build(t)
                e.id = t[1]
                e.day = old?.day ?: day
                e.record = old?.record ?: ++serial
                e.interval = old?.interval ?: 0
                e.next = old?.next ?: 0
                e.copies = old?.copies ?: 0
                expenses[e.id] = e
                used.add(e.id)
                output.add("$command ${e.id} ${fmt(e.total)}${note(e.amount)} = ${pairs(e.participants,e.shares)}")
                warning(e,output)
            }
            "PAYERS" -> {
                val e = expense(t[1])
                thawed(e)
                val seen = mutableSetOf<String>()
                val payers = t.drop(2).map { token ->
                    val (name,value) = token.split(':')
                    active(name)
                    if (!seen.add(name)) fail("duplicate member $name")
                    Part(name,money(value))
                }
                if (payers.sumOf { it.value } != e.amount.value) fail("payers do not add up")
                val contributions = distribute(e.total,payers.map { it.value })
                e.payers = payers
                e.contributions = contributions
                output.add("PAYERS ${e.id} ${fmt(e.total)}${note(e.amount)} = ${pairs(payers,contributions)}")
            }
            "DELETE" -> {
                val e = expense(t[1])
                thawed(e)
                expenses.remove(e.id)
                output.add("DELETE ${e.id}")
            }
            "RECURRING" -> {
                val e = expense(t[1])
                e.interval = t[2].toLong()
                e.next = day+e.interval
                output.add("RECURRING ${e.id}"+if (e.interval == 0L) " stopped" else " interval ${e.interval} next ${e.next}")
            }
            "SETTLE" -> {
                active(t[1])
                active(t[2])
                if (t[1] == t[2]) fail("same member ${t[1]}")
                val a = amount(t[3])
                val total = convert(a)
                if (a.value == 0L || total == 0L) fail("invalid amount")
                settlements.add(Settlement(day,++serial,t[1],t[2],a,total))
                output.add("SETTLE ${t[1]} -> ${t[2]} ${fmt(total)}${note(a)}")
            }
            "BUDGET" -> {
                val value = money(t[2])
                if (value == 0L) budgets.remove(t[1]) else budgets[t[1]] = value
                output.add("BUDGET ${t[1]}"+if (value == 0L) " removed" else " ${fmt(value)}")
            }
            "BALANCES" -> {
                output.add("BALANCES")
                val balances = balances()
                for (name in activeNames()) output.add("  $name ${signed(balances.getValue(name))}")
            }
            "OWES", "MATRIX" -> {
                if (command == "OWES") registered(t[1])
                val names = members.keys.toList()
                val debt = debts(names)
                output.add(if (command == "OWES") "OWES ${t[1]}" else "MATRIX")
                if (command == "OWES") {
                    val i = names.indexOf(t[1])
                    for (j in names.indices) {
                        if (debt[i][j] > 0) output.add("  ${t[1]} owes ${names[j]} ${fmt(debt[i][j])}")
                        if (debt[i][j] < 0) output.add("  ${names[j]} owes ${t[1]} ${fmt(-debt[i][j])}")
                    }
                } else {
                    val active = activeNames()
                    if (active.isEmpty()) output.add("  (none)")
                    else {
                        val l = active.maxOf { it.length }
                        fun cell(a: String,b: String) = if (a == b) "-" else fmt(maxOf(0,debt[names.indexOf(a)][names.indexOf(b)]))
                        val width = maxOf(l,active.maxOf { a -> active.maxOf { b -> cell(a,b).length } })
                        output.add(" ".repeat(l)+active.joinToString("") { "  "+it.padStart(width) })
                        for (a in active) output.add(a.padEnd(l)+active.joinToString("") { "  "+cell(a,it).padStart(width) })
                    }
                }
            }
            "HISTORY" -> {
                registered(t[1])
                val entries = mutableListOf<Entry>()
                for (e in expenses.values) {
                    if (includes(e,t[1])) entries.add(Entry(e.day,e.record,e.id,net(e).getValue(t[1])))
                }
                for (s in settlements) {
                    if (t[1] == s.from || t[1] == s.to) entries.add(Entry(s.day,s.record,"${s.from}->${s.to}",if (t[1] == s.from) s.total else -s.total))
                }
                output.add("HISTORY ${t[1]}")
                var balance = 0L
                for (e in entries.sortedWith(compareBy<Entry> { it.day }.thenBy { it.record })) {
                    balance += e.change
                    output.add("  day ${e.day} ${e.label} ${signed(e.change)} balance ${signed(balance)}")
                }
            }
            "CATEGORY" -> {
                output.add("CATEGORY")
                val totals = categoryTotals()
                val all = totals.values.sum()
                for (category in totals.keys.sortedWith(compareByDescending<String> { totals.getValue(it) }.thenBy { it })) {
                    val total = totals.getValue(category)
                    output.add("  $category ${fmt(total)} ${percent(total,all)}")
                    val shares = mutableMapOf<String,Long>()
                    for (e in expenses.values.filter { it.category == category }) {
                        for ((i,p) in e.participants.withIndex()) shares[p.name] = shares.getOrDefault(p.name,0)+e.shares[i]
                    }
                    for (name in shares.keys.filter { shares.getValue(it) > 0 }.sortedWith(compareByDescending<String> { shares.getValue(it) }.thenBy { it })) {
                        output.add("    $name ${fmt(shares.getValue(name))} ${percent(shares.getValue(name),total)}")
                    }
                }
            }
            "BUDGETS" -> {
                output.add("BUDGETS")
                val totals = categoryTotals()
                for ((category,budget) in budgets) {
                    val spent = totals.getOrDefault(category,0)
                    output.add("  $category spent ${fmt(spent)} budget ${fmt(budget)} used ${percent(spent,budget)}"+
                        if (spent <= budget) " left ${fmt(budget-spent)}" else " over ${fmt(spent-budget)}")
                }
            }
            "TOTALS" -> {
                output.add("TOTALS")
                for (name in members.keys) {
                    var paid = 0L
                    var share = 0L
                    for (e in expenses.values) {
                        for ((i,p) in e.payers.withIndex()) {
                            if (p.name == name) paid += e.contributions[i]
                        }
                        for ((i,p) in e.participants.withIndex()) {
                            if (p.name == name) share += e.shares[i]
                        }
                    }
                    val sent = settlements.filter { it.from == name }.sumOf { it.total }
                    val received = settlements.filter { it.to == name }.sumOf { it.total }
                    output.add("  $name paid ${fmt(paid)} share ${fmt(share)} sent ${fmt(sent)} received ${fmt(received)}")
                }
                for (currency in currencies.keys) {
                    val group = expenses.values.filter { it.amount.currency == currency }
                    if (group.isNotEmpty()) output.add("  currency $currency expenses ${group.size} amount ${fmt(group.sumOf { it.amount.value })} base ${fmt(group.sumOf { it.total })}")
                }
                output.add("  expenses ${expenses.size} total ${fmt(expenses.values.sumOf { it.total })} settlements ${settlements.size} total ${fmt(settlements.sumOf { it.total })}")
            }
            "MEMBERS" -> {
                output.add("MEMBERS")
                for ((name,m) in members) {
                    val count = expenses.values.count { includes(it,name) }
                    output.add("  $name ${if (m.active) "active" else "left"} day ${m.day} expenses $count")
                }
            }
            "EXPENSES" -> {
                if (t[1] == "MEMBER") registered(t[2])
                output.add(line)
                var count = 0
                var total = 0L
                for (e in chronological()) {
                    val matches = when (t[1]) {
                        "CATEGORY" -> e.category == t[2]
                        "MEMBER" -> includes(e,t[2])
                        "DAYS" -> e.day in t[2].toLong()..t[3].toLong()
                        else -> true
                    }
                    if (matches) {
                        output.add("  day ${e.day} ${e.id} ${e.category} ${fmt(e.total)} by ${e.payers.joinToString(",") { it.name }}")
                        count++
                        total += e.total
                    }
                }
                output.add("  count $count total ${fmt(total)}")
            }
            "PERIODS" -> {
                val k = t[1].toLong()
                output.add("PERIODS $k")
                val groups = expenses.values.groupBy { (it.day-1)/k }.toSortedMap()
                for ((i,group) in groups) output.add("  days ${i*k+1}-${i*k+k} expenses ${group.size} total ${fmt(group.sumOf { it.total })}")
            }
            "SHOW" -> {
                val e = expense(t[1])
                output.add("SHOW ${e.id}")
                output.add("  day ${e.day} category ${e.category} mode ${e.mode} total ${fmt(e.total)}${note(e.amount)}")
                for ((i,p) in e.payers.withIndex()) output.add("  paid ${p.name} ${fmt(e.contributions[i])}")
                val sum = e.participants.sumOf { it.value }
                for ((i,p) in e.participants.withIndex()) {
                    val suffix = when (e.mode) {
                        "EXACT" -> " ${fmt(p.value)}"
                        "PERCENT" -> " ${fmt(p.value)}%"
                        "SHARES" -> " ${p.value}/$sum"
                        "ADJUST" -> " +${fmt(p.value)}"
                        else -> ""
                    }
                    output.add("  share ${p.name} ${fmt(e.shares[i])}$suffix")
                }
                if (e.interval > 0) output.add("  recurring interval ${e.interval} next ${e.next}")
            }
            "SIMPLIFY" -> {
                val all = balances().filterValues { it != 0L }
                if (t[1] == "GREEDY") {
                    val transfers = greedy(all)
                    output.add("SIMPLIFY GREEDY transfers ${transfers.size}")
                    for (x in transfers) output.add("  ${x.from} -> ${x.to} ${fmt(x.amount)}")
                } else {
                    val names = all.keys.toList()
                    val n = names.size
                    if (n > 12) fail("too many members")
                    val size = 1 shl n
                    val sums = LongArray(size)
                    val dp = IntArray(size) { -1000 }
                    dp[0] = 0
                    for (mask in 1 until size) {
                        val bit = Integer.numberOfTrailingZeros(mask)
                        sums[mask] = sums[mask xor (1 shl bit)]+all.getValue(names[bit])
                        val first = mask and -mask
                        var sub = mask
                        while (sub > 0) {
                            if (sub and first != 0 && sums[sub] == 0L) dp[mask] = maxOf(dp[mask],1+dp[mask xor sub])
                            sub = (sub-1) and mask
                        }
                    }
                    val groups = mutableListOf<Int>()
                    var remaining = size-1
                    while (remaining != 0) {
                        val first = remaining and -remaining
                        var best = 0
                        var sub = remaining
                        while (sub > 0) {
                            if (sub and first != 0 && sums[sub] == 0L && 1+dp[remaining xor sub] == dp[remaining] &&
                                (best == 0 || lexLess(indexes(sub,n),indexes(best,n)))) best = sub
                            sub = (sub-1) and remaining
                        }
                        groups.add(best)
                        remaining = remaining xor best
                    }
                    val transfers = groups.map { mask -> greedy(indexes(mask,n).associate { names[it] to all.getValue(names[it]) }) }
                    output.add("SIMPLIFY OPTIMAL transfers ${transfers.sumOf { it.size }} groups ${groups.size}")
                    for (i in groups.indices) {
                        output.add("  group ${indexes(groups[i],n).joinToString(" ") { names[it] }}")
                        for (x in transfers[i]) output.add("    ${x.from} -> ${x.to} ${fmt(x.amount)}")
                    }
                }
            }
        }
        if (command in setOf("BALANCES","OWES","HISTORY","CATEGORY","BUDGETS","MEMBERS","PERIODS") && output.size == 1) {
            output.add("  (none)")
        }
        return output
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val app = Splitter()
    repeat(input.readLine().toInt()) {
        val lines = try {
            app.execute(input.readLine())
        } catch (problem: Problem) {
            listOf("ERROR ${problem.message}")
        }
        for (line in lines) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
