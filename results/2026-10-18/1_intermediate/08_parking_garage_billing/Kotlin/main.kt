import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.min

private val types = arrayOf("MOTORCYCLE","CAR","ECAR","VAN","BUS")
private val kinds = arrayOf("MOTO","COMPACT","LARGE","EV")
private val prefs = arrayOf(intArrayOf(0,1,2),intArrayOf(1,2),intArrayOf(3,1,2),intArrayOf(2),intArrayOf(2))
private class Fault(message: String) : RuntimeException(message)
private fun error(condition: Boolean, message: String) { if (condition) throw Fault(message) }
private fun two(n: Int) = n.toString().padStart(2,'0')
private fun time(n: Int) = "${n/1440+1}-${two(n/60%24)}:${two(n%60)}"
private fun duration(n: Int) = "${n/60}:${two(n%60)}"
private fun tenths(n: Int) = "${n/10}.${n%10}"
private class Spot(val level: Int, val number: Int, val kind: Int, val order: Int) {
    var closed = false
    var occupant: Vehicle? = null
    fun id() = "L$level-$number"
    fun free() = !closed && occupant == null
}
private class Vehicle(val plate: String, val kind: Int, val entry: Int, var spots: List<Spot>) {
    var energy = 0
    var charge = 0
    var validation = 0
    var paidAt = -1
    var paidParking = 0
    var paidNight = 0
    fun location() = spots[0].id()+(if (kind == 4) "..${spots[2].number}" else "")
}
private data class Waiting(val plate: String, val kind: Int, val joined: Int)
private data class Visit(val entry: Int, val exit: Int, val location: String, val kind: Int, val total: Int, val loss: Boolean)
private class Garage {
    var now = 0
    var peak = 0
    var peakAt = 0
    val levels = mutableListOf<List<Spot>>()
    val spots = mutableListOf<Spot>()
    val parked = mutableMapOf<String,Vehicle>()
    val queue = mutableListOf<Waiting>()
    val passes = sortedMapOf<String,Int>()
    val history = mutableMapOf<String,MutableList<Visit>>()
    val rates = arrayOf(intArrayOf(100,800),intArrayOf(200,1600),intArrayOf(200,1600),intArrayOf(300,2400),intArrayOf(600,4800))
    var night = 300
    var lost = 2000
    var kwh = 30
    val stats = Array(5) { IntArray(9) }
    val days = mutableMapOf<Int,Array<IntArray>>()
    var output = mutableListOf<String>()
    fun emit(s: String) { output.add(s) }
    fun daily(date: Int) = days.getOrPut(date) { Array(5) { IntArray(4) } }
    fun pass(plate: String) = (passes[plate] ?: 0) >= now/1440+1
    fun vehicle(plate: String) = parked[plate] ?: throw Fault("$plate is not parked")
    fun spot(id: String): Spot {
        val p = id.drop(1).split('-')
        val l = p[0].toInt()
        val n = p[1].toInt()
        error(l > levels.size || n > levels[l-1].size,"unknown spot $id")
        return levels[l-1][n-1]
    }
    fun assign(kind: Int): List<Spot>? {
        if (kind == 4) {
            for (level in levels) {
                for (i in 0 until level.size-2) {
                    val triple = level.subList(i,i+3)
                    if (triple.all { it.kind == 2 && it.free() }) return triple.toList()
                }
            }
        } else {
            for (wanted in prefs[kind]) {
                for (s in spots) if (s.kind == wanted && s.free()) return listOf(s)
            }
        }
        return null
    }
    fun occupy(v: Vehicle) { for (s in v.spots) s.occupant = v }
    fun free(v: Vehicle) { for (s in v.spots) s.occupant = null }
    fun park(plate: String, kind: Int, assigned: List<Spot>): Vehicle {
        val v = Vehicle(plate,kind,now,assigned)
        parked[plate] = v
        occupy(v)
        stats[kind][0]++
        daily(now/1440+1)[kind][0]++
        if (parked.size > peak) {
            peak = parked.size
            peakAt = now
        }
        return v
    }
    fun refuse(kind: Int, at: Int) {
        stats[kind][2]++
        daily(at/1440+1)[kind][2]++
    }
    fun giveup() {
        for (w in queue.toList()) {
            if (now-w.joined >= 30) {
                queue.remove(w)
                refuse(w.kind,w.joined+30)
                emit("GIVEUP ${w.plate} ${types[w.kind]} ${time(w.joined+30)}")
            }
        }
    }
    fun admit() {
        for (w in queue.toList()) {
            val assigned = assign(w.kind)
            if (assigned != null) {
                queue.remove(w)
                val v = park(w.plate,w.kind,assigned)
                emit("ADMIT ${v.plate} ${types[v.kind]} ${v.location()} waited ${duration(now-w.joined)}")
            }
        }
    }
    fun interval(v: Vehicle, start: Int, free: Int): IntArray {
        val total = now-start
        if (pass(v.plate) || total <= free) return intArrayOf(0,0)
        var parking = 0
        var offset = 0
        while (offset < total) {
            val billable = min(total-offset,1440)-(if (offset == 0) free else 0)
            parking += min((billable+29)/30*rates[v.kind][0],rates[v.kind][1])
            offset += 1440
        }
        return intArrayOf(parking,(now/1440-start/1440)*night)
    }
    fun fees(v: Vehicle, loss: Boolean): IntArray {
        val pair = interval(v,if (v.paidAt < 0) v.entry else v.paidAt,if (v.paidAt < 0) 15+v.validation else 15)
        val parking = pair[0]+(if (v.paidAt < 0) 0 else v.paidParking)
        val surcharge = pair[1]+(if (v.paidAt < 0) 0 else v.paidNight)
        val ticket = if (loss) lost else 0
        val total = parking+surcharge+ticket+v.charge
        return intArrayOf(parking,surcharge,ticket,v.charge,total,if (v.paidAt < 0) total else pair[0]+pair[1])
    }
    fun feeLine(label: String, v: Vehicle, f: IntArray) = "$label ${v.plate} ${v.location()} stay ${duration(now-v.entry)}"+
        " parking ${f[0]} night ${f[1]} lost ${f[2]} charge ${f[3]} total ${f[4]} due ${f[5]}"
    fun annotation(v: Vehicle) = (if (pass(v.plate)) " PASS" else "")+(if (v.validation > 0) " VAL ${v.validation}" else "")+
        (if (v.energy > 0) " KWH ${v.energy}" else "")+(if (v.paidAt >= 0) " PAID" else "")
    fun ordered() = parked.values.sortedBy { it.spots[0].order }
    fun move(v: Vehicle, target: List<Spot>) {
        val old = v.location()
        free(v)
        v.spots = target
        occupy(v)
        emit("MOVE ${v.plate} $old -> ${v.location()}")
    }
    fun occupancy(target: List<Spot>): IntArray {
        val a = IntArray(9)
        for (s in target) {
            if (s.closed) a[8]++ else a[4+s.kind]++
            if (s.occupant != null) a[s.kind]++
        }
        return a
    }
    fun occupancyLine(label: String, a: IntArray) = label+(0..3).joinToString("") { " ${kinds[it]} ${a[it]}/${a[it+4]}" }+" closed ${a[8]}"
    fun revenueLine(label: String, a: IntArray) = "$label exits ${a[1]} parking ${a[4]} night ${a[5]} lost ${a[6]} charge ${a[7]} total ${a[8]}"
    fun statsLine(label: String, a: IntArray) = "$label entries ${a[0]} exits ${a[1]} refused ${a[2]} avg_stay ${tenths(if (a[1] == 0) 0 else a[3]*10/a[1])}"
    fun dailyLine(label: String, a: IntArray) = "$label entries ${a[0]} exits ${a[1]} refused ${a[2]} revenue ${a[3]}"
    fun sum(a: Array<IntArray>, width: Int) = IntArray(width) { i -> a.sumOf { it[i] } }
    fun execute(t: List<String>) {
        var trigger = false
        val command = t[2]
        when (command) {
            "LEVEL" -> {
                val added = mutableListOf<Spot>()
                val counts = IntArray(4) { t[it+3].toInt() }
                for (k in 0..3) {
                    repeat(counts[k]) {
                        val s = Spot(levels.size+1,added.size+1,k,spots.size)
                        added.add(s)
                        spots.add(s)
                    }
                }
                levels.add(added)
                emit("LEVEL ${levels.size} spots ${added.size} MOTO ${counts[0]} COMPACT ${counts[1]} LARGE ${counts[2]} EV ${counts[3]}")
                trigger = true
            }
            "CLOSE", "OPEN" -> {
                val s = spot(t[3])
                if (command == "CLOSE") {
                    error(s.closed,"spot ${t[3]} is already closed")
                    error(s.occupant != null,"spot ${t[3]} is occupied by ${s.occupant?.plate}")
                    s.closed = true
                } else {
                    error(!s.closed,"spot ${t[3]} is not closed")
                    s.closed = false
                    trigger = true
                }
                emit("$command ${s.id()} ${kinds[s.kind]}")
            }
            "RATE" -> {
                val k = types.indexOf(t[3])
                error(k < 0,"unknown type ${t[3]}")
                val rate = t[4].toInt()
                val cap = t[5].toInt()
                error(cap < rate,"cap below rate for ${t[3]}")
                rates[k] = intArrayOf(rate,cap)
                emit("RATE ${t[3]} $rate $cap")
            }
            "FEE" -> {
                val amount = t[4].toInt()
                error(t[3] !in listOf("NIGHT","LOST","KWH"),"unknown fee ${t[3]}")
                when (t[3]) {
                    "NIGHT" -> night = amount
                    "LOST" -> lost = amount
                    else -> kwh = amount
                }
                emit("FEE ${t[3]} $amount")
            }
            "ENTER" -> {
                val plate = t[3]
                val k = types.indexOf(t[4])
                error(k < 0,"unknown type ${t[4]}")
                val existing = parked[plate]
                error(existing != null,"$plate is already parked at ${existing?.location()}")
                error(queue.any { it.plate == plate },"$plate is already waiting")
                val assigned = assign(k)
                if (assigned != null) emit("ENTER $plate ${types[k]} ${park(plate,k,assigned).location()}")
                else if (queue.size < 3) {
                    queue.add(Waiting(plate,k,now))
                    emit("WAIT $plate ${types[k]} ${queue.size}")
                } else {
                    refuse(k,now)
                    emit("FULL $plate ${types[k]}")
                }
            }
            "LEAVE" -> {
                val w = queue.firstOrNull { it.plate == t[3] } ?: throw Fault("${t[3]} is not waiting")
                queue.remove(w)
                emit("LEAVE ${w.plate} ${types[w.kind]}")
            }
            "EXIT", "PAY", "QUOTE" -> {
                val v = vehicle(t[3])
                val loss = t.size == 5
                error(v.paidAt >= 0 && (command == "PAY" || loss),"${v.plate} has already paid")
                val f = fees(v,loss)
                if (command == "PAY") {
                    v.paidAt = now
                    v.paidParking = f[0]
                    v.paidNight = f[1]
                    emit("PAY ${v.plate} parking ${f[0]} night ${f[1]} charge ${f[3]} total ${f[4]}")
                } else {
                    emit(feeLine(command,v,f))
                    if (command == "EXIT") {
                        history.getOrPut(v.plate) { mutableListOf() }.add(Visit(v.entry,now,v.location(),v.kind,f[4],loss))
                        stats[v.kind][1]++
                        stats[v.kind][3] += now-v.entry
                        for (i in 0..4) stats[v.kind][i+4] += f[i]
                        val d = daily(now/1440+1)[v.kind]
                        d[1]++
                        d[3] += f[4]
                        free(v)
                        parked.remove(v.plate)
                        trigger = true
                    }
                }
            }
            "CHARGE" -> {
                val v = vehicle(t[3])
                error(v.kind != 2,"${v.plate} is not an electric car")
                error(v.spots[0].kind != 3,"${v.plate} is not at a charger")
                error(v.paidAt >= 0,"${v.plate} has already paid")
                val energy = t[4].toInt()
                error(v.energy+energy > 100,"charge limit exceeded for ${v.plate}")
                val cost = energy*kwh
                v.energy += energy
                v.charge += cost
                emit("CHARGE ${v.plate} kwh $energy cost $cost stay_kwh ${v.energy} stay_cost ${v.charge}")
            }
            "VALIDATE" -> {
                val v = vehicle(t[3])
                error(v.paidAt >= 0,"${v.plate} has already paid")
                val minutes = t[4].toInt()
                error(v.validation+minutes > 180,"validation limit exceeded for ${v.plate}")
                v.validation += minutes
                emit("VALIDATE ${v.plate} $minutes total ${v.validation}")
            }
            "PASS" -> {
                val end = (if (pass(t[3])) passes.getValue(t[3]) else now/1440)+t[4].toInt()
                passes[t[3]] = end
                emit("PASS ${t[3]} until $end")
            }
            "UNPASS" -> {
                error(!pass(t[3]),"${t[3]} has no pass")
                passes.remove(t[3])
                emit("UNPASS ${t[3]}")
            }
            "MOVE" -> {
                val v = vehicle(t[3])
                error(v.kind == 4,"bus ${v.plate} cannot be moved")
                val s = spot(t[4])
                error(v.spots[0] === s,"${v.plate} is already at ${t[4]}")
                error(s.closed,"spot ${t[4]} is closed")
                error(s.occupant != null,"spot ${t[4]} is occupied by ${s.occupant?.plate}")
                error(s.kind !in prefs[v.kind],"${types[v.kind]} cannot use ${kinds[s.kind]} spot ${t[4]}")
                move(v,listOf(s))
                trigger = true
            }
            "REBALANCE" -> {
                var moved = 0
                for (v in ordered()) {
                    if (v.kind == 4) continue
                    val target = assign(v.kind)
                    if (target != null && prefs[v.kind].indexOf(target[0].kind) < prefs[v.kind].indexOf(v.spots[0].kind)) {
                        move(v,target)
                        moved++
                    }
                }
                emit("REBALANCE $moved")
                trigger = true
            }
            "WHERE" -> {
                val v = parked[t[3]]
                val p = queue.indexOfFirst { it.plate == t[3] }
                val visits = history[t[3]]
                error(v == null && p < 0 && visits == null,"unknown plate ${t[3]}")
                if (v != null) emit("WHERE ${v.plate} ${v.location()} ${types[v.kind]} ${time(v.entry)} stay ${duration(now-v.entry)}${annotation(v)}")
                else if (p >= 0) emit("WHERE ${t[3]} waiting ${p+1}")
                else emit("WHERE ${t[3]} gone ${time(visits!!.last().exit)}")
            }
            "LIST" -> {
                val l = if (t.size == 4) t[3].toInt() else 0
                error(l > levels.size,"unknown level $l")
                val found = ordered().filter { l == 0 || it.spots[0].level == l }
                emit("LIST ${found.size}")
                for (v in found) emit("${v.location()} ${v.plate} ${types[v.kind]} ${time(v.entry)}${annotation(v)}")
            }
            "MAP" -> {
                emit("MAP ${levels.size}")
                for ((i,level) in levels.withIndex()) {
                    val symbols = level.map { s -> if (s.closed) '#' else if (s.occupant != null) kinds[s.kind][0] else kinds[s.kind][0].lowercaseChar() }.joinToString("")
                    emit("L${i+1} "+symbols.chunked(10).joinToString(" "))
                }
            }
            "OCCUPANCY" -> {
                emit("OCCUPANCY vehicles ${parked.size} waiting ${queue.size}")
                for ((i,level) in levels.withIndex()) emit(occupancyLine("L${i+1}",occupancy(level)))
                val a = occupancy(spots)
                val used = a.take(4).sum()
                val available = a.drop(4).take(4).sum()
                emit(occupancyLine("TOTAL",a)+" rate ${tenths(if (available == 0) 0 else used*1000/available)}%")
            }
            "SIGN" -> {
                var line = "SIGN"
                for (k in 0..4) {
                    var count = 0
                    if (k == 4) {
                        for (level in levels) {
                            var run = 0
                            for (s in level) {
                                if (s.kind == 2 && s.free()) {
                                    run++
                                    if (run == 3) {
                                        count++
                                        run = 0
                                    }
                                } else run = 0
                            }
                        }
                    } else {
                        for (wanted in prefs[k]) count += spots.count { it.kind == wanted && it.free() }
                    }
                    line += " ${types[k]} "+(if (count == 0) "FULL" else count.toString())
                }
                emit(line)
            }
            "RATES" -> {
                emit("RATES")
                for (k in 0..4) emit("${types[k]} ${rates[k][0]} ${rates[k][1]}")
                emit("NIGHT $night LOST $lost KWH $kwh")
            }
            "PASSES" -> {
                val found = passes.keys.filter { pass(it) }
                emit("PASSES ${found.size}")
                for (plate in found) emit("$plate until ${passes[plate]}"+(if (plate in parked) " IN" else ""))
            }
            "OVERSTAY" -> {
                val hours = t[3].toInt()
                val found = ordered().filter { now-it.entry >= hours*60 }.sortedBy { it.entry }
                emit("OVERSTAY $hours ${found.size}")
                for (v in found) emit("${v.location()} ${v.plate} ${types[v.kind]} ${time(v.entry)} stay ${duration(now-v.entry)}")
            }
            "HISTORY" -> {
                val visits = history[t[3]] ?: throw Fault("no history for ${t[3]}")
                emit("HISTORY ${t[3]} visits ${visits.size} paid ${visits.sumOf { it.total }}")
                for (v in visits) emit("${time(v.entry)} ${time(v.exit)} ${v.location} ${types[v.kind]} ${v.total}"+(if (v.loss) " LOST" else ""))
            }
            "REVENUE" -> {
                emit("REVENUE")
                for (k in 0..4) emit(revenueLine(types[k],stats[k]))
                emit(revenueLine("TOTAL",sum(stats,9)))
            }
            "DAILY" -> {
                val d = t[3].toInt()
                val a = daily(d)
                emit(dailyLine("DAILY $d",sum(a,4)))
                for (k in 0..4) emit(dailyLine(types[k],a[k]))
            }
            "STATS" -> {
                emit("STATS parked ${parked.size} peak $peak at "+(if (peak == 0) "-" else time(peakAt)))
                for (k in 0..4) emit(statsLine(types[k],stats[k]))
                emit(statsLine("ALL",sum(stats,9)))
            }
        }
        if (trigger) admit()
    }
    fun process(line: String): List<String> {
        val t = line.split(' ')
        val hm = t[1].split(':')
        now = (t[0].toInt()-1)*1440+hm[0].toInt()*60+hm[1].toInt()
        output = mutableListOf()
        giveup()
        try { execute(t) }
        catch (f: Fault) { emit("ERROR ${f.message}") }
        return output
    }
}
fun main() {
    val input = BufferedReader(InputStreamReader(System.`in`))
    val output = System.out.bufferedWriter()
    val garage = Garage()
    repeat(input.readLine().toInt()) {
        for (line in garage.process(input.readLine())) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
