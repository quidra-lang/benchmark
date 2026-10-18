import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

private class Fault(reason: String) : RuntimeException(reason)
private fun failIf(condition: Boolean, reason: String) { if (condition) throw Fault(reason) }
private class Item(val day: Int, val kind: String, val isbn: String, val amount: Int) {
    var unpaid = amount
}
private class Member(val id: String, val type: String, val name: String) {
    private val student = type == "STUDENT"
    val limit = if (student) 3 else 10
    val period = if (student) 14 else 28
    val rate = if (student) 25 else 10
    val cap = if (student) 1000 else 2000
    val reservationLimit = if (student) 2 else 5
    val fee = if (student) 50 else 100
    var queued = 0
    val loans = sortedMapOf<String,Copy>()
    val holds = sortedMapOf<String,Copy>()
    val items = mutableListOf<Item>()
    val history = mutableListOf<String>()
    fun balance() = items.sumOf { it.unpaid }
    fun reservations() = queued+holds.size
    fun blocked() = balance() > 500
    fun status() = if (blocked()) "BLOCKED" else "OK"
}
private class Title(val isbn: String, val name: String, var price: Int) {
    var borrowed = 0
    val copies = mutableListOf<Copy>()
    val queue = mutableListOf<Member>()
    fun count(state: String) = copies.count { it.state == state }
    fun holdings() = count("AVAILABLE")+count("LOANED")+count("HOLD")
}
private class Copy(val title: Title, val number: Int) {
    var state = "AVAILABLE"
    var owner: Member? = null
    var loanDay = 0
    var due = 0
    var renewals = 0
    var expiry = 0
}
private fun normalize(raw: String): String {
    val s = raw.replace("-","")
    if (s.matches(Regex("[0-9]{9}[0-9X]"))) {
        var sum = 0
        for (i in 0 until 10) sum += (10-i)*(if (s[i] == 'X') 10 else s[i]-'0')
        failIf(sum%11 != 0,"invalid isbn")
        val prefix = "978"+s.take(9)
        sum = 0
        for (i in 0 until 12) sum += (if (i%2 == 0) 1 else 3)*(prefix[i]-'0')
        return prefix+((10-sum%10)%10)
    }
    failIf(!s.matches(Regex("97[89][0-9]{10}")),"invalid isbn")
    var sum = 0
    for (i in 0 until 13) sum += (if (i%2 == 0) 1 else 3)*(s[i]-'0')
    failIf(sum%10 != 0,"invalid isbn")
    return s
}
private fun parseMoney(s: String): Int {
    val p = s.split('.')
    return p[0].toInt()*100+p[1].toInt()
}
private fun money(n: Int) = "${n/100}.${(n%100).toString().padStart(2,'0')}"
private fun lower(s: String) = s.lowercase(Locale.ROOT)
private class Library {
    var day = 1
    var borrowed = 0
    var returned = 0
    var renewed = 0
    var lost = 0
    var fines = 0
    var fees = 0
    var charges = 0
    var paid = 0
    var waived = 0
    val titles = sortedMapOf<String,Title>()
    val members = sortedMapOf<String,Member>()
    val closed = mutableSetOf<Int>()
    val copies = mutableListOf<Copy>()
    var output = mutableListOf<String>()
    fun emit(line: String) { output.add(line) }
    fun member(id: String): Member = members[id] ?: throw Fault("unknown member")
    fun book(raw: String): Title = titles[normalize(raw)] ?: throw Fault("unknown book")
    fun loan(m: Member, b: Title): Copy = m.loans[b.isbn] ?: throw Fault("not borrowed")
    fun open(start: Int): Int {
        var d = start
        while (d in closed) d++
        return d
    }
    fun late(c: Copy) = max(0,day-c.due)
    fun fine(c: Copy) = min(late(c)*c.owner!!.rate,c.owner!!.cap)
    fun charge(m: Member, kind: String, b: Title, amount: Int) {
        if (amount == 0) return
        m.items.add(Item(day,kind,b.isbn,amount))
        when (kind) {
            "FINE" -> fines += amount
            "FEE" -> fees += amount
            else -> charges += amount
        }
    }
    fun release(c: Copy) {
        val b = c.title
        c.owner = null
        if (b.queue.isEmpty()) c.state = "AVAILABLE"
        else {
            val m = b.queue.removeAt(0)
            m.queued--
            c.state = "HOLD"
            c.owner = m
            c.expiry = open(day+3)
            m.holds[b.isbn] = c
            emit("HOLD ${b.isbn} copy ${c.number} ${m.id} until ${c.expiry}")
        }
    }
    fun endLoan(c: Copy, loss: Boolean): Pair<Int,Int> {
        val m = c.owner!!
        val l = late(c)
        val f = fine(c)
        m.loans.remove(c.title.isbn)
        charge(m,"FINE",c.title,f)
        m.history.add((if (loss) "LOST " else "RETURNED ")+"${c.title.isbn} copy ${c.number}"+
            " from ${c.loanDay} to $day late $l fine ${money(f)}"+(if (loss) " price ${money(c.title.price)}" else ""))
        return l to f
    }
    fun loss(c: Copy, heading: String) {
        val m = c.owner!!
        val b = c.title
        val (l,f) = endLoan(c,true)
        charge(m,"PRICE",b,b.price)
        c.state = "LOST"
        c.owner = null
        lost++
        emit("$heading ${m.id} ${b.isbn} copy ${c.number} late $l fine ${money(f)} price ${money(b.price)} balance ${money(m.balance())}")
        if (b.holdings() == 0) {
            for (queued in b.queue) {
                queued.queued--
                emit("DROPPED ${b.isbn} ${queued.id}")
            }
            b.queue.clear()
        }
    }
    fun renewalReason(c: Copy): String? {
        if (c.due < day) return "loan overdue"
        if (c.renewals == 2) return "renewal limit"
        if (c.title.queue.isNotEmpty()) return "title reserved"
        return null
    }
    fun renew(c: Copy) {
        c.due = open(day+c.owner!!.period)
        c.renewals++
        renewed++
        emit("RENEW ${c.owner!!.id} ${c.title.isbn} copy ${c.number} due ${c.due} renewals ${c.renewals}")
    }
    fun orderedLoans(m: Member) = m.loans.values.sortedWith(compareBy<Copy> { it.due }.thenBy { it.title.isbn })
    fun orderedHolds(m: Member) = m.holds.values.sortedWith(compareBy<Copy> { it.expiry }.thenBy { it.title.isbn })
    fun showMember(m: Member) {
        emit("MEMBER ${m.id} ${m.type} ${m.name}")
        emit("STATUS loans ${m.loans.size}/${m.limit} reservations ${m.reservations()}/${m.reservationLimit} balance ${money(m.balance())} ${m.status()}")
        for (c in orderedLoans(m)) emit("LOAN ${c.title.isbn} copy ${c.number} due ${c.due} renewals ${c.renewals}"+
            (if (c.due < day) " late ${late(c)} fine ${money(fine(c))}" else ""))
        for (c in orderedHolds(m)) emit("HOLD ${c.title.isbn} copy ${c.number} until ${c.expiry}")
        for (b in titles.values) {
            val p = b.queue.indexOf(m)
            if (p >= 0) emit("QUEUE ${b.isbn} position ${p+1}")
        }
    }
    fun execute(line: String) {
        val t = line.split(' ')
        when (t[0]) {
            "DAY" -> {
                val d = t[1].toInt()
                failIf(d <= day,"invalid day")
                emit("DAY $d")
                while (day < d) {
                    day++
                    val losses = copies.filter { it.state == "LOANED" && it.due+365 <= day }
                        .sortedWith(compareBy<Copy> { it.owner!!.id }.thenBy { it.title.isbn })
                    for (c in losses) loss(c,"AUTOLOST")
                    val expired = copies.filter { it.state == "HOLD" && it.expiry < day }
                        .sortedWith(compareBy<Copy> { it.title.isbn }.thenBy { it.number })
                    for (c in expired) {
                        val m = c.owner!!
                        charge(m,"FEE",c.title,m.fee)
                        m.holds.remove(c.title.isbn)
                        emit("EXPIRED ${c.title.isbn} copy ${c.number} ${m.id} fee ${money(m.fee)}")
                        release(c)
                    }
                }
            }
            "CLOSED" -> {
                val d = t[1].toInt()
                failIf(d <= day,"invalid day")
                failIf(d in closed,"already closed")
                closed.add(d)
                emit("CLOSED $d")
                for (b in titles.values) {
                    for (c in b.copies) {
                        if (c.state == "LOANED" && c.due == d) {
                            c.due = open(d)
                            emit("MOVED ${b.isbn} copy ${c.number} ${c.owner!!.id} due ${c.due}")
                        } else if (c.state == "HOLD" && c.expiry == d) {
                            c.expiry = open(d)
                            emit("MOVED ${b.isbn} copy ${c.number} ${c.owner!!.id} until ${c.expiry}")
                        }
                    }
                }
            }
            "ADDBOOK" -> {
                val isbn = normalize(t[1])
                val name = t.drop(4).joinToString(" ")
                val existing = titles[isbn]
                failIf(existing != null && existing.name != name,"title mismatch")
                val count = t[2].toInt()
                val price = parseMoney(t[3])
                val b = existing ?: Title(isbn,name,price).also { titles[isbn] = it }
                b.price = price
                val added = mutableListOf<Copy>()
                repeat(count) {
                    val c = Copy(b,b.copies.size+1)
                    b.copies.add(c)
                    copies.add(c)
                    added.add(c)
                }
                emit("ADDBOOK $isbn added $count total ${b.holdings()}")
                for (c in added) release(c)
            }
            "ADDMEMBER" -> {
                failIf(t[1] in members,"duplicate member")
                failIf(t[2] != "STUDENT" && t[2] != "STAFF","unknown type")
                val m = Member(t[1],t[2],t.drop(3).joinToString(" "))
                members[m.id] = m
                emit("ADDMEMBER ${m.id} ${m.type} loans ${m.limit} days ${m.period}")
            }
            "WITHDRAW" -> {
                val b = book(t[1])
                val n = t[2].toInt()
                failIf(n < 1 || n > b.copies.size,"unknown copy")
                val c = b.copies[n-1]
                failIf(c.state != "AVAILABLE","copy not available")
                c.state = "WITHDRAWN"
                emit("WITHDRAW ${b.isbn} copy $n total ${b.holdings()}")
            }
            "BORROW" -> {
                val m = member(t[1])
                val b = book(t[2])
                failIf(day in closed,"library closed")
                failIf(b.isbn in m.loans,"already borrowed")
                failIf(m.blocked(),"member blocked")
                failIf(m.loans.values.any { it.due < day },"overdue loans")
                failIf(m.loans.size >= m.limit,"loan limit")
                val c = m.holds[b.isbn] ?: b.copies.firstOrNull { it.state == "AVAILABLE" }
                    ?: throw Fault(if (b.count("HOLD") > 0) "all copies on hold" else "no copy available")
                m.holds.remove(b.isbn)
                c.state = "LOANED"
                c.owner = m
                c.loanDay = day
                c.due = open(day+m.period)
                c.renewals = 0
                m.loans[b.isbn] = c
                b.borrowed++
                borrowed++
                emit("BORROW ${m.id} ${b.isbn} copy ${c.number} due ${c.due}")
            }
            "RETURN" -> {
                val m = member(t[1])
                val b = book(t[2])
                val c = loan(m,b)
                val (l,f) = endLoan(c,false)
                returned++
                emit("RETURN ${m.id} ${b.isbn} copy ${c.number} late $l fine ${money(f)} balance ${money(m.balance())}")
                release(c)
            }
            "RENEW" -> {
                val m = member(t[1])
                val c = loan(m,book(t[2]))
                failIf(m.blocked(),"member blocked")
                renewalReason(c)?.let { throw Fault(it) }
                renew(c)
            }
            "RENEWALL" -> {
                val m = member(t[1])
                failIf(m.loans.isEmpty(),"no loans")
                failIf(m.blocked(),"member blocked")
                var done = 0
                var skipped = 0
                for (c in m.loans.values) {
                    val reason = renewalReason(c)
                    if (reason != null) {
                        emit("SKIP ${c.title.isbn} $reason")
                        skipped++
                    } else {
                        renew(c)
                        done++
                    }
                }
                emit("RENEWALL ${m.id} renewed $done skipped $skipped")
            }
            "RESERVE" -> {
                val m = member(t[1])
                val b = book(t[2])
                failIf(b.isbn in m.loans,"already borrowed")
                failIf(m in b.queue || b.isbn in m.holds,"already reserved")
                failIf(m.blocked(),"member blocked")
                failIf(m.reservations() >= m.reservationLimit,"reservation limit")
                failIf(b.holdings() == 0,"no copies")
                failIf(b.count("AVAILABLE") > 0,"copy available")
                b.queue.add(m)
                m.queued++
                val p = b.queue.size
                val dues = b.copies.filter { it.state == "LOANED" }.map { it.due }.sorted()
                val estimate = if (p <= dues.size) dues[p-1].toString() else "none"
                emit("RESERVE ${m.id} ${b.isbn} position $p estimate $estimate")
            }
            "CANCEL" -> {
                val m = member(t[1])
                val b = book(t[2])
                val p = b.queue.indexOf(m)
                val c = m.holds[b.isbn]
                failIf(p < 0 && c == null,"not reserved")
                if (p >= 0) {
                    b.queue.removeAt(p)
                    m.queued--
                    emit("CANCEL ${m.id} ${b.isbn} queue")
                } else {
                    m.holds.remove(b.isbn)
                    emit("CANCEL ${m.id} ${b.isbn} hold copy ${c!!.number}")
                    release(c!!)
                }
            }
            "LOST" -> {
                val m = member(t[1])
                loss(loan(m,book(t[2])),"LOST")
            }
            "PAYFINE" -> {
                val m = member(t[1])
                failIf(m.balance() == 0,"no fines")
                val amount = parseMoney(t[2])
                var rest = amount
                val details = mutableListOf<String>()
                for ((i,item) in m.items.withIndex()) {
                    if (rest == 0) break
                    val applied = min(rest,item.unpaid)
                    if (applied == 0) continue
                    rest -= applied
                    item.unpaid -= applied
                    details.add("ITEM ${i+1} ${item.kind} paid ${money(applied)} remaining ${money(item.unpaid)}")
                }
                paid += amount-rest
                emit("PAYFINE ${m.id} paid ${money(amount-rest)} change ${money(rest)} balance ${money(m.balance())}")
                output.addAll(details)
            }
            "WAIVE" -> {
                val m = member(t[1])
                val n = t[2].toInt()
                failIf(n < 1 || n > m.items.size,"unknown item")
                val item = m.items[n-1]
                failIf(item.unpaid == 0,"item settled")
                val amount = item.unpaid
                item.unpaid = 0
                waived += amount
                emit("WAIVE ${m.id} item $n ${item.kind} amount ${money(amount)} balance ${money(m.balance())}")
            }
            "FINES" -> {
                val m = member(t[1])
                emit("FINES ${m.id} items ${m.items.count { it.unpaid > 0 }} balance ${money(m.balance())}")
                for ((i,item) in m.items.withIndex()) {
                    if (item.unpaid > 0) emit("${i+1} day ${item.day} ${item.kind} ${item.isbn} amount ${money(item.amount)} remaining ${money(item.unpaid)}")
                }
            }
            "SEARCH" -> {
                val keyword = lower(t.drop(1).joinToString(" "))
                val found = titles.values.filter { lower(it.name).contains(keyword) }
                    .sortedWith(compareBy<Title> { lower(it.name) }.thenBy { it.isbn })
                emit("SEARCH ${found.size}")
                for (b in found) emit("${b.isbn} ${b.count("AVAILABLE")}/${b.holdings()} ${b.name}")
            }
            "OVERDUE" -> {
                val found = copies.filter { it.state == "LOANED" && it.due < day }
                    .sortedWith(compareBy<Copy> { it.due }.thenBy { it.owner!!.id }.thenBy { it.title.isbn })
                emit("OVERDUE ${found.size}")
                for (c in found) emit("${c.owner!!.id} ${c.title.isbn} copy ${c.number} due ${c.due} late ${late(c)} fine ${money(fine(c))}")
            }
            "NOTICES" -> {
                val notices = mutableListOf<String>()
                for (m in members.values) {
                    val loans = orderedLoans(m)
                    for (c in loans) if (c.due < day) notices.add("OVERDUE ${m.id} ${c.title.isbn} due ${c.due}")
                    for (c in loans) if (c.due >= day && c.due <= day+2) notices.add("DUESOON ${m.id} ${c.title.isbn} due ${c.due}")
                    for (c in orderedHolds(m)) notices.add("PICKUP ${m.id} ${c.title.isbn} until ${c.expiry}")
                }
                emit("NOTICES ${notices.size}")
                output.addAll(notices)
            }
            "MEMBER" -> showMember(member(t[1]))
            "MEMBERS" -> {
                emit("MEMBERS ${members.size}")
                for (m in members.values) emit("${m.id} ${m.type} loans ${m.loans.size} reservations ${m.reservations()} balance ${money(m.balance())} ${m.status()}")
            }
            "BOOK" -> {
                val b = book(t[1])
                emit("BOOK ${b.isbn} ${b.name}")
                emit("PRICE ${money(b.price)} copies ${b.holdings()} borrowed ${b.borrowed}")
                for (c in b.copies) {
                    val detail = when (c.state) {
                        "LOANED" -> " ${c.owner!!.id} due ${c.due}"
                        "HOLD" -> " ${c.owner!!.id} until ${c.expiry}"
                        else -> ""
                    }
                    emit("COPY ${c.number} ${c.state}$detail")
                }
                emit("QUEUE ${b.queue.size}"+(if (b.queue.isEmpty()) "" else " "+b.queue.joinToString(" ") { it.id }))
            }
            "INVENTORY" -> {
                val a = copies.count { it.state == "AVAILABLE" }
                val l = copies.count { it.state == "LOANED" }
                val h = copies.count { it.state == "HOLD" }
                val x = copies.count { it.state == "LOST" }
                val w = copies.count { it.state == "WITHDRAWN" }
                emit("INVENTORY titles ${titles.size} copies ${a+l+h} available $a loaned $l hold $h lost $x withdrawn $w")
                for (b in titles.values) emit("${b.isbn} copies ${b.holdings()} available ${b.count("AVAILABLE")} loaned ${b.count("LOANED")} hold ${b.count("HOLD")} queue ${b.queue.size}")
            }
            "HISTORY" -> {
                val m = member(t[1])
                emit("HISTORY ${m.id} ${m.history.size}")
                output.addAll(m.history)
            }
            "STATS" -> {
                val active = members.values.sumOf { it.loans.size }
                val outstanding = members.values.sumOf { it.balance() }
                emit("STATS day $day titles ${titles.size} members ${members.size} closed ${closed.size}")
                emit("LOANS borrowed $borrowed returned $returned renewed $renewed lost $lost active $active")
                emit("MONEY fines ${money(fines)} fees ${money(fees)} charges ${money(charges)} paid ${money(paid)} waived ${money(waived)} outstanding ${money(outstanding)}")
                val top = titles.values.filter { it.borrowed > 0 }.sortedWith(compareByDescending<Title> { it.borrowed }.thenBy { it.isbn }).take(3)
                for ((i,b) in top.withIndex()) emit("TOP ${i+1} ${b.isbn} ${b.borrowed} ${b.name}")
            }
        }
    }
    fun process(line: String): List<String> {
        output = mutableListOf()
        try { execute(line) }
        catch (fault: Fault) { output.add("ERROR ${fault.message}") }
        return output
    }
}
fun main() {
    val input = BufferedReader(InputStreamReader(System.`in`))
    val output = System.out.bufferedWriter()
    val library = Library()
    repeat(input.readLine().toInt()) {
        for (line in library.process(input.readLine())) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
