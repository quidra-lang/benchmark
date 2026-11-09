import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

private const val NO_NET = 1000000
private class Fault(reason: String) : RuntimeException(reason)
private fun error(condition: Boolean, reason: String) { if (condition) throw Fault(reason) }
private fun away(n: Long, d: Long) = (if (n < 0) -((2*(-n)+d)/(2*d)) else (2*n+d)/(2*d)).toInt()
private fun up(n: Long, d: Long) = Math.floorDiv(2*n+d,2*d).toInt()
private fun signed(n: Int) = (if (n < 0) "-" else "")+"${abs(n)/10}.${abs(n)%10}"
private fun index(n: Int?) = if (n == null) "none" else if (n < 0) "+"+signed(-n) else signed(n)
private fun handicap(n: Int?) = if (n == null) "none" else if (n < 0) "+${-n}" else n.toString()
private fun cents(n: Int) = "${n/100}.${(n%100).toString().padStart(2,'0')}"
private fun average(total: Int, count: Int) = if (count == 0) "-" else cents(total*100/count)
private fun sum(a: IntArray, from: Int = 0, to: Int = 18) = (from until to).sumOf { a[it] }
private data class Tee(val id: String, val rating: Int, val slope: Int)
private class Course(val id: String, val par: IntArray, val si: IntArray) {
    val total = par.sum()
    val tees = mutableMapOf<String,Tee>()
}
private data class IndexRecord(val day: Int, val value: Int)
private data class Calculation(val k: Int, val average: Int, val adjustment: Int, val low: Int?, val hard: Boolean, val soft: Boolean, val maximum: Boolean)
private class Round(val course: Course, val tee: Tee, val day: Int, val raw: List<String>, val handicap: Int?,
    val scores: IntArray, val adjusted: IntArray, val ags: Int, val diff: Int, val exceptional: Int,
    val oldIndex: Int?, val oldCalculation: Calculation?, val oldRecords: Int)
private class Player(val id: String, val name: String, var index: Int?) {
    var calculation: Calculation? = null
    val rounds = mutableListOf<Round>()
    val records = mutableListOf<IndexRecord>()
}
private data class Event(val id: String, val format: String, val course: Course, val tee: Tee, val day: Int, val allowance: Int, val players: List<Player>)
private data class Eligible(val start: Int, val adjusted: IntArray, val counting: List<Int>, val k: Int, val adjustment: Int)
private data class EventData(val e: Event, val rounds: List<Round>, val ph: IntArray, val strokes: IntArray,
    val nets: Array<IntArray>, val points: Array<IntArray>, val par: Array<IntArray>)
private data class Match(val statuses: List<String>, val result: String)
private fun allocate(c: Course, h: Int) = IntArray(18) { i ->
    if (h >= 0) h/18+(if (c.si[i] <= h%18) 1 else 0)
    else -((-h)/18)-(if (c.si[i] >= 19-(-h)%18) 1 else 0)
}
private fun courseHandicap(c: Course, t: Tee, i: Int) = up(i.toLong()*t.slope+113L*(t.rating-10*c.total),1130)
private class Scorer {
    val courses = sortedMapOf<String,Course>()
    val players = sortedMapOf<String,Player>()
    val events = linkedMapOf<String,Event>()
    var output = mutableListOf<String>()
    fun player(id: String) = players[id] ?: throw Fault("unknown player")
    fun course(id: String) = courses[id] ?: throw Fault("unknown course")
    fun tee(c: Course, id: String) = c.tees[id] ?: throw Fault("unknown tee")
    fun low(p: Player, day: Int) = p.records.filter { it.day >= day-365 && it.day < day }
        .minWithOrNull(compareBy<IndexRecord> { it.value }.thenBy { it.day })
    fun eligible(p: Player): Eligible {
        val start = max(0,p.rounds.size-20)
        val n = p.rounds.size-start
        var reduction = 0
        val adjusted = IntArray(n)
        for (i in n-1 downTo 0) {
            val r = p.rounds[start+i]
            reduction += r.exceptional
            adjusted[i] = r.diff-reduction
        }
        val k = when {
            n < 3 -> 0
            n <= 5 -> 1
            n <= 8 -> 2
            n <= 11 -> 3
            n <= 14 -> 4
            n <= 16 -> 5
            n <= 18 -> 6
            n == 19 -> 7
            else -> 8
        }
        val adjustment = if (n == 3) -20 else if (n == 4 || n == 6) -10 else 0
        val counting = (0 until n).sortedWith(compareBy<Int> { adjusted[it] }.thenByDescending { it }).take(k)
        return Eligible(start,adjusted,counting,k,adjustment)
    }
    fun update(p: Player, day: Int) {
        val e = eligible(p)
        if (e.k == 0) {
            p.calculation = null
            return
        }
        val a = away(e.counting.sumOf { e.adjusted[it] }.toLong(),e.k.toLong())
        var c = a+e.adjustment
        val l = low(p,day)?.value
        var soft = false
        var hard = false
        var maximum = false
        if (l != null && c-l > 30) {
            val next = l+30+(c-l-30)/2
            soft = next != c
            c = next
        }
        if (l != null && c-l > 50) {
            c = l+50
            hard = true
        }
        if (c > 540) {
            c = 540
            maximum = true
        }
        p.index = c
        p.calculation = Calculation(e.k,a,e.adjustment,l,hard,soft,maximum)
    }
    fun data(e: Event): EventData {
        val rounds = mutableListOf<Round>()
        val n = e.players.size
        val ph = IntArray(n)
        for (i in 0 until n) {
            val r = e.players[i].rounds.firstOrNull { it.course === e.course && it.tee === e.tee && it.day == e.day }
                ?: throw Fault("missing round")
            val h = r.handicap ?: throw Fault("no index")
            rounds.add(r)
            ph[i] = up(h.toLong()*e.allowance,100)
        }
        val minimum = ph.minOrNull()!!
        val relative = e.format in listOf("MATCH","NASSAU","FOURBALL")
        val strokes = IntArray(n) { ph[it]-(if (relative) minimum else 0) }
        val nets = Array(n) { IntArray(18) }
        val points = Array(n) { IntArray(18) }
        val par = Array(n) { IntArray(18) }
        for (i in 0 until n) {
            val allocation = allocate(e.course,strokes[i])
            for (h in 0 until 18) {
                nets[i][h] = if (rounds[i].scores[h] == NO_NET) NO_NET else rounds[i].scores[h]-allocation[h]
                points[i][h] = if (nets[i][h] == NO_NET) 0 else max(0,e.course.par[h]+2-nets[i][h])
                par[i][h] = if (nets[i][h] == NO_NET || nets[i][h] > e.course.par[h]) -1 else if (nets[i][h] < e.course.par[h]) 1 else 0
            }
        }
        return EventData(e,rounds,ph,strokes,nets,points,par)
    }
    fun rank(values: Array<IntArray>, candidates: List<Int>, high: Boolean, ids: List<String>) = candidates.sortedWith { a,b ->
        var cmp = 0
        for (start in intArrayOf(0,9,12,15,17)) {
            cmp = sum(values[a],start).compareTo(sum(values[b],start))
            if (cmp != 0) break
        }
        if (cmp == 0) ids[a].compareTo(ids[b]) else if (high) -cmp else cmp
    }
    fun ranked(d: EventData): List<Int> {
        val candidates = d.ph.indices.filter { d.e.format != "STROKE" || d.rounds[it].scores.none { s -> s == NO_NET } }
        val values = if (d.e.format == "STROKE") d.nets else if (d.e.format == "PAR") d.par else d.points
        return rank(values,candidates,d.e.format != "STROKE",d.e.players.map { it.id })
    }
    fun status(lead: Int) = if (lead == 0) "AS" else if (lead > 0) "$lead UP" else "${-lead} DN"
    fun match(wins: IntArray, first: Int, last: Int, a: String, b: String): Match {
        var lead = 0
        var remaining = 0
        val statuses = mutableListOf<String>()
        for (h in first..last) {
            lead += wins[h]
            remaining = last-h
            statuses.add(status(lead))
            if (abs(lead) > remaining) break
        }
        val result = if (lead == 0) "AS" else (if (lead > 0) a else b)+" ${abs(lead)}"+(if (remaining > 0) "&$remaining" else " UP")
        return Match(statuses,result)
    }
    fun results(e: Event, d: EventData) {
        output.add("results ${e.id}: ${e.format} ${e.course.id} ${e.tee.id} day ${e.day} allowance ${e.allowance}")
        val n = e.players.size
        val ids = e.players.map { it.id }
        when (e.format) {
            "STROKE", "STABLEFORD", "PAR" -> {
                val order = ranked(d)
                for ((r,i) in order.withIndex()) {
                    val value = when (e.format) {
                        "STROKE" -> "net ${sum(d.nets[i])} gross ${sum(d.rounds[i].scores)}"
                        "STABLEFORD" -> "points ${sum(d.points[i])}"
                        else -> status(sum(d.par[i]))
                    }
                    output.add("${r+1} ${ids[i]} $value hcp ${handicap(d.ph[i])}")
                }
                if (e.format == "STROKE") {
                    for (i in ids.indices.filter { it !in order }.sortedBy { ids[it] }) output.add("NR ${ids[i]} hcp ${handicap(d.ph[i])}")
                    if (order.isNotEmpty()) {
                        val gross = Array(n) { d.rounds[it].scores }
                        val winner = rank(gross,order,false,ids)[0]
                        output.add("gross ${ids[winner]} ${sum(gross[winner])}")
                    }
                }
            }
            "MATCH", "NASSAU", "FOURBALL" -> {
                output.add("strokes"+ids.indices.joinToString("") { " ${ids[it]} ${d.strokes[it]}" })
                val size = n/2
                val a = ids.take(size).joinToString("+")
                val b = ids.drop(size).joinToString("+")
                val wins = IntArray(18) { h ->
                    val left = (0 until size).minOf { d.nets[it][h] }
                    val right = (size until n).minOf { d.nets[it][h] }
                    right.compareTo(left)
                }
                if (e.format == "NASSAU") {
                    output.add("front ${match(wins,0,8,a,b).result}")
                    output.add("back ${match(wins,9,17,a,b).result}")
                    output.add("total ${match(wins,0,17,a,b).result}")
                } else {
                    val m = match(wins,0,17,a,b)
                    output.add("status "+m.statuses.joinToString(", "))
                    output.add("result ${m.result}")
                }
            }
            "BETTERBALL" -> {
                val values = Array(n/2) { i -> IntArray(18) { h -> max(d.points[2*i][h],d.points[2*i+1][h]) } }
                val order = rank(values,(0 until n/2).toList(),true,(0 until n/2).map { ids[2*it] })
                for ((r,i) in order.withIndex()) output.add("${r+1} ${ids[2*i]}+${ids[2*i+1]} points ${sum(values[i])} hcp ${handicap(d.ph[2*i])} ${handicap(d.ph[2*i+1])}")
            }
            "SKINS" -> {
                var carry = 0
                val totals = IntArray(n)
                var tied = ids.indices.toList()
                for (h in 0 until 18) {
                    carry++
                    val minimum = ids.indices.minOf { d.nets[it][h] }
                    tied = ids.indices.filter { d.nets[it][h] == minimum }
                    if (minimum != NO_NET && tied.size == 1) {
                        val i = tied[0]
                        output.add("hole ${h+1} ${ids[i]} $carry")
                        totals[i] += carry*100
                        carry = 0
                    }
                }
                if (carry > 0) {
                    tied = tied.sortedBy { ids[it] }
                    for (i in tied) totals[i] += carry*100/tied.size
                    output.add("carry $carry"+tied.joinToString("") { " ${ids[it]}" })
                }
                val order = ids.indices.sortedWith(compareByDescending<Int> { totals[it] }.thenBy { ids[it] })
                for (i in order) output.add("${ids[i]} ${cents(totals[i])}")
            }
        }
    }
    fun cardTotal(label: String, r: Round, strokes: IntArray, nets: IntArray, points: IntArray, from: Int, to: Int) {
        val complete = (from until to).none { r.scores[it] == NO_NET }
        output.add("$label ${sum(r.course.par,from,to)} "+(if (complete) sum(r.scores,from,to).toString() else "-")+
            " ${sum(r.adjusted,from,to)} ${sum(strokes,from,to)} "+(if (complete) sum(nets,from,to).toString() else "-")+" ${sum(points,from,to)}")
    }
    fun card(p: Player, number: Int, r: Round) {
        output.add("card ${p.id} $number: ${r.course.id} ${r.tee.id} day ${r.day} handicap ${handicap(r.handicap)}")
        val strokes = allocate(r.course,r.handicap ?: 0)
        val nets = IntArray(18) { if (r.scores[it] == NO_NET) NO_NET else r.scores[it]-strokes[it] }
        val points = IntArray(18) { if (nets[it] == NO_NET) 0 else max(0,r.course.par[it]+2-nets[it]) }
        for (h in 0 until 18) {
            val net = if (nets[h] == NO_NET) "-" else nets[h].toString()
            output.add("${h+1} ${r.course.par[h]} ${r.course.si[h]} ${r.raw[h]} ${r.adjusted[h]} ${strokes[h]} $net ${points[h]}")
            if (h == 8) cardTotal("OUT",r,strokes,nets,points,0,9)
            if (h == 17) {
                cardTotal("IN",r,strokes,nets,points,9,18)
                cardTotal("TOTAL",r,strokes,nets,points,0,18)
            }
        }
        output.add("ags ${r.ags} diff ${signed(r.diff)}")
    }
    fun statistics(p: Player) {
        val category = IntArray(7)
        val totals = IntArray(3)
        val counts = IntArray(3)
        val complete = mutableListOf<Int>()
        for (r in p.rounds) {
            var full = true
            for (h in 0 until 18) {
                if (r.raw[h] == "X") category[6]++
                if (r.scores[h] == NO_NET) {
                    full = false
                    continue
                }
                val relative = r.scores[h]-r.course.par[h]
                val k = if (relative <= -2) 0 else if (relative <= 2) relative+2 else 5
                category[k]++
                val i = r.course.par[h]-3
                totals[i] += r.scores[h]
                counts[i]++
            }
            if (full) complete.add(sum(r.scores))
        }
        var line = "stats ${p.id}: rounds ${p.rounds.size} best ${complete.minOrNull() ?: "-"} average ${average(complete.sum(),complete.size)}"
        val labels = listOf("eagles","birdies","pars","bogeys","doubles","others","pickups")
        for (i in 0..6) line += " ${labels[i]} ${category[i]}"
        for (i in 0..2) line += " par${i+3} ${average(totals[i],counts[i])}"
        output.add(line)
    }
    fun execute(t: List<String>) {
        when (t[0]) {
            "COURSE" -> {
                error(t[1] in courses,"duplicate course")
                val par = IntArray(18) { t[it+2].toInt() }
                val si = IntArray(18) { t[it+20].toInt() }
                error(par.any { it !in 3..5 } || si.toSet().size != 18 || si.any { it !in 1..18 },"invalid course")
                courses[t[1]] = Course(t[1],par,si)
            }
            "TEE" -> {
                val c = course(t[1])
                error(t[2] in c.tees,"duplicate tee")
                val rating = t[3].toInt()
                val slope = t[4].toInt()
                error(rating !in 500..900 || slope !in 55..155,"invalid tee")
                c.tees[t[2]] = Tee(t[2],rating,slope)
            }
            "PLAYER" -> {
                error(t[1] in players,"duplicate player")
                val i = if (t.size == 4) t[3].toInt() else null
                error(i != null && i !in -100..540,"invalid index")
                players[t[1]] = Player(t[1],t[2],i)
            }
            "ROUND" -> {
                val p = player(t[1])
                val c = course(t[2])
                val tee = tee(c,t[3])
                val day = t[4].toInt()
                error(p.rounds.isNotEmpty() && day < p.rounds.last().day,"invalid day")
                val raw = t.drop(5)
                error(raw.count { it == "-" } >= 5,"too few holes")
                val previous = p.index
                val hcp = previous?.let { courseHandicap(c,tee,it) }
                val strokes = allocate(c,hcp ?: 0)
                val scores = IntArray(18) { raw[it].toIntOrNull() ?: NO_NET }
                val adjusted = IntArray(18) { h ->
                    val limit = c.par[h]+(if (previous == null) 5 else 2+strokes[h])
                    when (raw[h]) {
                        "-" -> c.par[h]+strokes[h]
                        "X" -> limit
                        else -> min(scores[h],limit)
                    }
                }
                val ags = adjusted.sum()
                val diff = away(113L*(10*ags-tee.rating),tee.slope.toLong())
                val exceptional = if (previous != null && previous-diff >= 70) (if (previous-diff >= 100) 20 else 10) else 0
                val r = Round(c,tee,day,raw,hcp,scores,adjusted,ags,diff,exceptional,previous,p.calculation,p.records.size)
                p.rounds.add(r)
                update(p,day)
                p.index?.let { p.records.add(IndexRecord(day,it)) }
                output.add("round ${p.id} ${p.rounds.size}: ags $ags diff ${signed(diff)}"+(if (exceptional == 0) "" else " exceptional ${signed(-exceptional)}")+" index ${index(p.index)}")
            }
            "REMOVE" -> {
                val p = player(t[1])
                error(p.rounds.isEmpty(),"no rounds")
                val number = p.rounds.size
                val r = p.rounds.removeAt(number-1)
                p.index = r.oldIndex
                p.calculation = r.oldCalculation
                p.records.subList(r.oldRecords,p.records.size).clear()
                output.add("removed ${p.id} $number: index ${index(p.index)}")
            }
            "INDEX" -> {
                val p = player(t[1])
                var line = "index ${p.id}: ${index(p.index)} rounds ${p.rounds.size}"
                val c = p.calculation
                if (c != null) line += " lowest ${c.k} average ${signed(c.average)} adjustment ${signed(c.adjustment)}"+
                    (if (c.low == null) "" else " low ${index(c.low)}")+(if (c.hard) " hard cap" else if (c.soft) " soft cap" else "")+(if (c.maximum) " maximum" else "")
                output.add(line)
            }
            "HISTORY" -> {
                val p = player(t[1])
                val e = eligible(p)
                output.add("history ${p.id}: rounds ${p.rounds.size}")
                for (i in e.adjusted.indices) {
                    val r = p.rounds[e.start+i]
                    output.add("${e.start+i+1} day ${r.day} ${r.course.id} ${r.tee.id} ags ${r.ags} diff ${signed(r.diff)}"+
                        (if (r.diff == e.adjusted[i]) "" else " adjusted ${signed(e.adjusted[i])}")+(if (i in e.counting) " *" else ""))
                }
            }
            "LOWINDEX" -> {
                val p = player(t[1])
                val day = t[2].toInt()
                val r = low(p,day)
                output.add("lowindex ${p.id} $day: "+(if (r == null) "none" else "${index(r.value)} day ${r.day}"))
            }
            "COURSEHCP" -> {
                val p = player(t[1])
                val c = course(t[2])
                val tee = tee(c,t[3])
                val h = courseHandicap(c,tee,p.index ?: throw Fault("no index"))
                output.add("coursehcp ${p.id} ${c.id} ${tee.id}: ${handicap(h)} strokes "+allocate(c,h).joinToString(" "))
            }
            "HCPTABLE" -> {
                val c = course(t[1])
                val tee = tee(c,t[2])
                val first = t[3].toInt()
                val last = t[4].toInt()
                error(first < -100 || first > last || last > 540,"invalid index")
                output.add("hcptable ${c.id} ${tee.id}: ${index(first)} to ${index(last)}")
                var start = first
                var h = courseHandicap(c,tee,first)
                for (i in first+1..last+1) {
                    val next = if (i <= last) courseHandicap(c,tee,i) else h+1
                    if (next != h) {
                        output.add("${index(start)} to ${index(i-1)}: ${handicap(h)}")
                        start = i
                        h = next
                    }
                }
            }
            "CARD" -> {
                val p = player(t[1])
                val n = t[2].toInt()
                error(n > p.rounds.size,"unknown round")
                card(p,n,p.rounds[n-1])
            }
            "STATS" -> statistics(player(t[1]))
            "HOLESTATS" -> {
                val c = course(t[1])
                val rounds = players.values.flatMap { it.rounds }.filter { it.course === c }
                val totals = IntArray(18)
                val counts = IntArray(18)
                val ranks = IntArray(18)
                for (r in rounds) {
                    for (h in 0 until 18) {
                        if (r.scores[h] != NO_NET) {
                            totals[h] += r.scores[h]
                            counts[h]++
                        }
                    }
                }
                val order = (0 until 18).sortedWith { a,b ->
                    if (counts[a] == 0 || counts[b] == 0) {
                        if (counts[a] == counts[b]) a.compareTo(b) else if (counts[a] == 0) 1 else -1
                    } else {
                        val cmp = ((totals[b]-c.par[b]*counts[b]).toLong()*counts[a]).compareTo((totals[a]-c.par[a]*counts[a]).toLong()*counts[b])
                        if (cmp == 0) a.compareTo(b) else cmp
                    }
                }
                for ((i,h) in order.withIndex()) ranks[h] = i+1
                output.add("holestats ${c.id}: rounds ${rounds.size}")
                for (h in 0 until 18) output.add("${h+1} par ${c.par[h]} si ${c.si[h]} scores ${counts[h]} avg ${average(totals[h],counts[h])} rank ${ranks[h]}")
            }
            "PLAYERS" -> {
                val order = players.values.sortedWith(compareBy<Player> { it.index == null }.thenBy { it.index }.thenBy { it.id })
                output.add("players ${order.size}")
                for (p in order) output.add("${p.id} ${p.name} ${index(p.index)} rounds ${p.rounds.size}")
            }
            "EVENT" -> {
                error(t[1] in events,"duplicate event")
                val c = course(t[3])
                val tee = tee(c,t[4])
                val allowance = t[6].toInt()
                error(allowance !in 1..100,"invalid allowance")
                val list = t.drop(7).map { player(it) }
                val n = list.size
                val valid = when (t[2]) {
                    "MATCH", "NASSAU" -> n == 2
                    "FOURBALL" -> n == 4
                    "BETTERBALL" -> n in listOf(4,6,8)
                    else -> n in 2..8
                }
                error(list.toSet().size != n || !valid,"invalid players")
                events[t[1]] = Event(t[1],t[2],c,tee,t[5].toInt(),allowance,list)
            }
            "RESULTS" -> {
                val e = events[t[1]] ?: throw Fault("unknown event")
                results(e,data(e))
            }
            "MERIT" -> {
                val merit = mutableMapOf<String,IntArray>()
                val awards = intArrayOf(10,8,6,5,4,3,2,1)
                var count = 0
                for (e in events.values) {
                    if (e.format !in listOf("STROKE","STABLEFORD","PAR")) continue
                    val d = try { data(e) } catch (_: Fault) { continue }
                    count++
                    for (p in e.players) merit.getOrPut(p.id) { IntArray(3) }[2]++
                    for ((i,p) in ranked(d).withIndex()) {
                        val a = merit.getValue(e.players[p].id)
                        a[0] += awards[i]
                        if (i == 0) a[1]++
                    }
                }
                val order = merit.keys.sortedWith(compareByDescending<String> { merit.getValue(it)[0] }.thenByDescending { merit.getValue(it)[1] }.thenBy { it })
                output.add("merit: events $count")
                for ((i,id) in order.withIndex()) {
                    val a = merit.getValue(id)
                    output.add("${i+1} $id ${a[0]} wins ${a[1]} played ${a[2]}")
                }
            }
        }
    }
    fun process(line: String): List<String> {
        output = mutableListOf()
        try { execute(line.split(' ')) }
        catch (f: Fault) { output.add("ERROR ${f.message}") }
        return output
    }
}
fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val scorer = Scorer()
    repeat(input.readLine().toInt()) {
        for (line in scorer.process(input.readLine())) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
