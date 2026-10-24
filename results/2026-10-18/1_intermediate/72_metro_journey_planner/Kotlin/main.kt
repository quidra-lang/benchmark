private class Problem(val text: String) : RuntimeException(text)
private fun fail(reason: String): Nothing = throw Problem(reason)
private fun time(s: String): Int {
    val p = s.split(':')
    return p[0].toInt()*60+p[1].toInt()
}
private fun clock(t: Int) = "%02d:%02d".format(t/60,t%60)
private fun pair(a: String, b: String) = if (a < b) a to b else b to a
private data class Station(val zone: Int, val name: String, var transfer: Int = 0, var closed: Boolean = false)
private data class Line(val first: Int, val last: Int, val headway: Int, val stops: List<String>, val offsets: List<Int>, var delay: Int = 0, var suspended: Boolean = false) {
    val total get() = offsets.last()
    val trips get() = (last-first)/headway+1
    fun direction(reverse: Boolean) = if (reverse) stops.asReversed() to offsets.asReversed().map {
        total-it
    } else stops to offsets
    fun next(offset: Int, ready: Int): Int? {
        val delta = ready-first-delay-offset
        val q = if (delta <= 0) 0 else (delta+headway-1)/headway
        return q.takeIf {
            it < trips
        }
    }
    fun at(q: Int, offset: Int) = first+delay+q*headway+offset
}
private sealed interface Leg {
    val end: Int
}
private data class Ride(val line: String, val terminal: String, val from: String, val departure: Int, val to: String, val arrival: Int, val stops: Int) : Leg {
    override val end get() = arrival
}
private data class Walk(val from: String, val departure: Int, val to: String, val arrival: Int) : Leg {
    override val end get() = arrival
}
private data class Stay(val station: String, val start: Int, override val end: Int) : Leg
private data class Label(val arrival: Int, val journey: List<Leg>)
private typealias Labels = Map<String,Label>
private data class Tariff(val discount: Int, val window: Int, val prices: List<Int>)
private fun rides(journey: List<Leg>) = journey.count {
    it is Ride
}
private fun relax(labels: MutableMap<String,Label>, station: String, arrival: Int, journey: List<Leg>, leg: Leg): Boolean {
    if (labels[station]?.let {
        it.arrival <= arrival
    } == true) return false
    labels[station] = Label(arrival,journey+leg)
    return true
}
private fun printJourney(heading: String, departure: Int, label: Label): List<String> {
    val out = mutableListOf("$heading ${clock(departure)} -> ${clock(label.arrival)} total ${label.arrival-departure} rides ${rides(label.journey)} walks ${label.journey.count { it is Walk }}")
    var previous = departure
    for (leg in label.journey) {
        out.add(when(leg) {
            is Ride -> "RIDE ${leg.line} toward ${leg.terminal} ${leg.from} ${clock(leg.departure)} -> ${leg.to} ${clock(leg.arrival)} wait ${leg.departure-previous} stops ${leg.stops}"
            is Walk -> "WALK ${leg.from} ${clock(leg.departure)} -> ${leg.to} ${clock(leg.arrival)}"
            is Stay -> "STAY ${leg.station} ${clock(leg.start)} -> ${clock(leg.end)}"
        })
        previous = leg.end
    }
    return out
}
private class Planner {
    val stations = sortedMapOf<String,Station>()
    val lines = sortedMapOf<String,Line>()
    val walks = mutableMapOf<Pair<String,String>,Int>()
    val closed = mutableSetOf<Pair<String,String>>()
    var tariff: Tariff? = null
    fun station(s: String) = stations[s] ?: fail("unknown station $s")
    fun line(s: String) = lines[s] ?: fail("unknown line $s")
    fun openStation(s: String) {
        if (station(s).closed) fail("station $s is closed")
    }
    fun common(a: String, b: String) {
        station(a)
        station(b)
        if (a == b) fail("origin and destination are the same")
        openStation(a)
        openStation(b)
    }
    fun neighbors(s: String) = walks.mapNotNull {
        (key,t) -> when(s) {
            key.first -> key.second to t
            key.second -> key.first to t
            else -> null
        }
    }.sortedBy {
        it.first
    }
    fun earliest(origin: String, departure: Int): Labels {
        val labels = mutableMapOf(origin to Label(departure,emptyList()))
        val settled = mutableSetOf<String>()
        while (true) {
            val entry = labels.entries.filter {
                it.key !in settled
            }.minWithOrNull(compareBy<Map.Entry<String,Label>> {
                it.value.arrival
            }.thenBy {
                it.key
            }) ?: break
            val u = entry.key
            val label = entry.value
            settled.add(u)
            val ready = label.arrival+(if (u == origin) 0 else station(u).transfer)
            for ((id,line) in lines) {
                if (line.suspended || u !in line.stops) continue
                for (reverse in listOf(false,true)) {
                    val (stops,offsets) = line.direction(reverse)
                    val i = stops.indexOf(u)
                    if (i == stops.lastIndex) continue
                    val q = line.next(offsets[i],ready) ?: continue
                    val d = line.at(q,offsets[i])
                    for (j in i+1 until stops.size) {
                        if (pair(stops[j-1],stops[j]) in closed) break
                        if (station(stops[j]).closed) continue
                        val t = line.at(q,offsets[j])
                        relax(labels,stops[j],t,label.journey,Ride(id,stops.last(),u,d,stops[j],t,j-i))
                    }
                }
            }
            for ((v,w) in neighbors(u)) {
                val t = label.arrival+w
                if (!station(v).closed && t <= 1440) relax(labels,v,t,label.journey,Walk(u,label.arrival,v,t))
            }
        }
        return labels
    }
    fun walkStep(labels: MutableMap<String,Label>, sources: Set<String>, changed: MutableSet<String>) {
        // All walks use source labels captured before this walk step.
        val recorded = sources.sorted().map {
            it to labels.getValue(it)
        }
        for ((u,label) in recorded) for ((v,w) in neighbors(u)) {
            val t = label.arrival+w
            if (!station(v).closed && t <= 1440 && relax(labels,v,t,label.journey,Walk(u,label.arrival,v,t))) changed.add(v)
        }
    }
    fun rounds(origin: String, departure: Int): List<Labels> {
        val labels = mutableMapOf(origin to Label(departure,emptyList()))
        var changed = mutableSetOf(origin)
        walkStep(labels,setOf(origin),changed)
        val result = mutableListOf(labels.toMap())
        data class Boarded(val q: Int, val index: Int, val departure: Int, val journey: List<Leg>)
        while (changed.isNotEmpty()) {
            val previous = labels.toMap()
            val marked = changed
            changed = mutableSetOf()
            val sources = mutableSetOf<String>()
            for ((id,line) in lines) {
                if (line.suspended) continue
                for (reverse in listOf(false,true)) {
                    val (stops,offsets) = line.direction(reverse)
                    var boarded: Boarded? = null
                    for (j in stops.indices) {
                        if (j > 0 && pair(stops[j-1],stops[j]) in closed) boarded = null
                        if (station(stops[j]).closed) continue
                        boarded?.let {
                            b -> val t = line.at(b.q,offsets[j])
                            if (relax(labels,stops[j],t,b.journey,Ride(id,stops.last(),stops[b.index],b.departure,stops[j],t,j-b.index))) {
                                sources.add(stops[j])
                                changed.add(stops[j])
                            }
                        }
                        if (j < stops.lastIndex && stops[j] in marked) {
                            val old = previous.getValue(stops[j])
                            val ready = old.arrival+(if (stops[j] == origin) 0 else station(stops[j]).transfer)
                            val q = line.next(offsets[j],ready)
                            if (q != null && (boarded == null || q < boarded!!.q)) boarded = Boarded(q,j,line.at(q,offsets[j]),old.journey)
                        }
                    }
                }
            }
            walkStep(labels,sources,changed)
            result.add(labels.toMap())
        }
        return result
    }
    fun fare(journey: List<Leg>, child: Boolean): Pair<Int,List<String>> {
        val tariff = tariff!!
        fun half(n: Int) = (n+19)/20*10
        val cap = if (child) half(tariff.discount) else tariff.discount
        var previous: Int? = null
        var total = 0
        val tickets = mutableListOf<String>()
        for (leg in journey) if (leg is Ride) {
            val stops = line(leg.line).stops
            val a = stops.indexOf(leg.from)
            val b = stops.indexOf(leg.to)
            val zones = stops.subList(minOf(a,b),maxOf(a,b)+1).map {
                station(it).zone
            }.toSet().size
            var price = tariff.prices[minOf(zones,tariff.prices.size)-1]
            if (child) price = half(price)
            val reduction = if (previous?.let {
                leg.departure-it <= tariff.window
            } == true) minOf(cap,price) else 0
            val pay = price-reduction
            total += pay
            previous = leg.arrival
            tickets.add("TICKET ${leg.line} ${leg.from} ${leg.to} zones $zones price $price discount $reduction pay $pay")
        }
        return total to tickets
    }
    fun command(w: List<String>): List<String> {
        val c = w[0]
        val a = w.drop(1)
        fun num(i: Int) = a[i].toInt()
        val out = mutableListOf<String>()
        when(c) {
            "STATION" -> {
                if (a[0] in stations) fail("station ${a[0]} already exists")
                stations[a[0]] = Station(num(1),a[2])
                out.add("STATION ${a[0]} zone ${num(1)} ${a[2]}")
            }
            "LINE" -> {
                if (a[0] in lines) fail("line ${a[0]} already exists")
                val stops = (4 until a.size step 2).map {
                    a[it]
                }
                for (s in stops) station(s)
                val seen = mutableSetOf<String>()
                for (s in stops) if (!seen.add(s)) fail("station $s appears twice on line ${a[0]}")
                val first = time(a[1])
                val last = time(a[2])
                val offsets = mutableListOf(0)
                for (i in 5 until a.size step 2) offsets.add(offsets.last()+num(i))
                if (first > last) fail("line ${a[0]} first departure is after last departure")
                if (last+offsets.last() > 1440) fail("line ${a[0]} runs past 24:00")
                val line = Line(first,last,num(3),stops,offsets)
                lines[a[0]] = line
                out.add("LINE ${a[0]} stops ${stops.size} time ${line.total} trips ${line.trips}")
            }
            "TRANSFER" -> {
                station(a[0]).transfer = num(1)
                out.add("TRANSFER ${a[0]} ${num(1)}")
            }
            "WALK" -> {
                station(a[0])
                station(a[1])
                if (a[0] == a[1]) fail("walk from ${a[0]} to itself")
                val old = walks.put(pair(a[0],a[1]),num(2))
                out.add("WALK ${a[0]} ${a[1]} ${num(2)}${old?.let { " was $it" } ?: ""}")
            }
            "TARIFF" -> {
                val prices = (2 until a.size).map(::num)
                if (prices.zipWithNext().any {
                    it.first > it.second
                }) fail("tariff prices must not decrease")
                tariff = Tariff(num(0),num(1),prices)
                out.add("TARIFF zones ${prices.size} discount ${num(0)} window ${num(1)}")
            }
            "CLOSE","OPEN" -> {
                station(a[0])
                val close = c == "CLOSE"
                if (a.size == 1) {
                    val station = station(a[0])
                    if (station.closed == close) fail("station ${a[0]} is ${if (close) "already" else "not"} closed")
                    station.closed = close
                    out.add("$c ${a[0]}")
                }
                else {
                    station(a[1])
                    val key = pair(a[0],a[1])
                    val ids = lines.filterValues {
                        it.stops.zipWithNext().any {
                            p -> pair(p.first,p.second) == key
                        }
                    }.keys.toList()
                    if (close && ids.isEmpty()) fail("no segment ${a[0]}-${a[1]}")
                    if ((key in closed) == close) fail("segment ${a[0]}-${a[1]} is ${if (close) "already" else "not"} closed")
                    if (close) closed.add(key) else closed.remove(key)
                    out.add("$c ${a[0]}-${a[1]}${if (close) " lines "+ids.joinToString(" ") else ""}")
                }
            }
            "DELAY" -> {
                val line = line(a[0])
                if (line.last+num(1)+line.total > 1440) fail("line ${a[0]} runs past 24:00")
                line.delay = num(1)
                out.add("DELAY ${a[0]} ${num(1)}")
            }
            "SUSPEND","RESUME" -> {
                val line = line(a[0])
                val suspended = c == "SUSPEND"
                if (line.suspended == suspended) fail("line ${a[0]} is ${if (suspended) "already" else "not"} suspended")
                line.suspended = suspended
                out.add("$c ${a[0]}")
            }
            "ROUTE","FEWEST","PARETO","FARE","LASTTRAIN","ARRIVEBY","PROFILE" -> {
                common(a[0],a[1])
                if (c == "FARE") {
                    if (a[3] !in setOf("ADULT","CHILD")) fail("unknown fare class ${a[3]}")
                    if (tariff == null) fail("no tariff")
                }
                if (c == "PROFILE" && time(a[2]) > time(a[3])) fail("empty interval ${a[2]} ${a[3]}")
                val heading = "$c ${a[0]} ${a[1]}"
                if (c == "LASTTRAIN" || c == "ARRIVEBY") {
                    val bound = if (c == "LASTTRAIN") 1440 else time(a[2])
                    val title = if (c == "ARRIVEBY") "$heading by ${a[2]}" else heading
                    for (t in bound-1 downTo 0) {
                        val label = earliest(a[0],t)[a[1]]
                        if (label != null && (c == "LASTTRAIN" || label.arrival <= bound)) return printJourney(title,t,label)
                    }
                    out.add("$title none")
                } else if (c == "PROFILE") {
                    val start = time(a[2])
                    val end = time(a[3])
                    val arrivals = (start..end).map {
                        earliest(a[0],it)[a[1]]?.arrival
                    }
                    val selected = mutableListOf<String>()
                    for (i in arrivals.indices) {
                        val arrival = arrivals[i] ?: continue
                        if (i == arrivals.lastIndex || arrivals[i+1] == null || arrival < arrivals[i+1]!!) selected.add("${clock(start+i)} -> ${clock(arrival)} total ${arrival-start-i}")
                    }
                    out.add("$heading ${a[2]} ${a[3]} count ${selected.size}")
                    out.addAll(selected)
                } else if (c == "FEWEST" || c == "PARETO") {
                    val start = time(a[2])
                    val rounds = rounds(a[0],start)
                    if (c == "FEWEST") {
                        for ((k,labels) in rounds.withIndex()) labels[a[1]]?.let {
                            return printJourney("$heading trips $k",start,it)
                        }
                        out.add("$heading ${a[2]} unreachable")
                    }
                    else {
                        val options = mutableListOf<String>()
                        var previous: Int? = null
                        var count = 0
                        for ((k,labels) in rounds.withIndex()) {
                            val label = labels[a[1]] ?: continue
                            if (previous == null || previous!! > label.arrival) {
                                count++
                                options.addAll(printJourney("OPTION trips $k",start,label))
                            }
                            previous = label.arrival
                        }
                        out.add("$heading ${a[2]} options $count")
                        out.addAll(options)
                    }
                } else {
                    val start = time(a[2])
                    val label = earliest(a[0],start)[a[1]]
                    if (label == null) out.add("$heading ${a[2]}${if (c == "FARE") " "+a[3] else ""} unreachable")
                    else if (c == "FARE") {
                        val (total,tickets) = fare(label.journey,a[3] == "CHILD")
                        out.add("$heading ${a[2]} ${a[3]} rides ${rides(label.journey)} total $total")
                        out.addAll(tickets)
                    }
                    else return printJourney(heading,start,label)
                }
            }
            "VIA" -> {
                station(a[0])
                station(a[1])
                station(a[2])
                if (a[0] == a[2]) fail("origin and destination are the same")
                if (a[1] == a[0] || a[1] == a[2]) fail("via station ${a[1]} must differ from origin and destination")
                openStation(a[0])
                openStation(a[1])
                openStation(a[2])
                val start = time(a[3])
                val heading = "VIA ${a[0]} ${a[1]} ${a[2]}"
                val first = earliest(a[0],start)[a[1]]
                if (first != null) {
                    val next = first.arrival+station(a[1]).transfer
                    val second = earliest(a[1],next)[a[2]]
                    if (second != null) return printJourney(heading,start,Label(second.arrival,first.journey+Stay(a[1],first.arrival,next)+second.journey))
                }
                out.add("$heading ${a[3]} unreachable")
            }
            "REACH" -> {
                openStation(a[0])
                val start = time(a[1])
                val selected = earliest(a[0],start).entries.filter {
                    it.value.arrival <= start+num(2)
                }.sortedWith(compareBy<Map.Entry<String,Label>> {
                    it.value.arrival
                }.thenBy {
                    it.key
                })
                out.add("REACH ${a[0]} ${a[1]} ${num(2)} count ${selected.size}")
                for ((s,label) in selected) out.add("$s ${station(s).name} ${clock(label.arrival)} ${label.arrival-start} rides ${rides(label.journey)}")
            }
            "TIMETABLE" -> {
                station(a[0])
                val line = line(a[1])
                if (a[0] !in line.stops) fail("station ${a[0]} is not on line ${a[1]}")
                if (a[2] != line.stops.first() && a[2] != line.stops.last()) fail("${a[2]} is not a terminal of line ${a[1]}")
                if (a[0] == a[2]) fail("no departures from ${a[0]} toward ${a[2]}")
                if (line.suspended) fail("line ${a[1]} is suspended")
                openStation(a[0])
                val (stops,offsets) = line.direction(a[2] == line.stops.first())
                val i = stops.indexOf(a[0])
                val selected = (0 until line.trips).map {
                    line.at(it,offsets[i])
                }.filter {
                    it >= time(a[3])
                }.take(num(4))
                out.add("TIMETABLE ${a[0]} ${a[1]} toward ${a[2]} ${a[3]} next ${selected.size}"+selected.joinToString("") {
                    " ${clock(it)}"
                })
            }
            "DEPARTURES","ARRIVALS" -> {
                openStation(a[0])
                data class Event(val time: Int, val line: String, val direction: Int, val endpoint: String)
                val events = mutableListOf<Event>()
                for ((id,line) in lines) if (!line.suspended && a[0] in line.stops) for (direction in 0..1) {
                    val (stops,offsets) = line.direction(direction == 1)
                    val i = stops.indexOf(a[0])
                    if ((c == "DEPARTURES" && i == stops.lastIndex) || (c == "ARRIVALS" && i == 0)) continue
                    for (q in 0 until line.trips) {
                        val t = line.at(q,offsets[i])
                        if (t >= time(a[1])) events.add(Event(t,id,direction,if (c == "DEPARTURES") stops.last() else stops.first()))
                    }
                }
                val selected = events.sortedWith(compareBy<Event> {
                    it.time
                }.thenBy {
                    it.line
                }.thenBy {
                    it.direction
                }).take(num(2))
                out.add("$c ${a[0]} ${a[1]} count ${selected.size}")
                for (e in selected) out.add("${clock(e.time)} ${e.line} ${if (c == "DEPARTURES") "toward" else "from"} ${e.endpoint}")
            }
            "TRIP" -> {
                val line = line(a[0])
                if (a[1] != line.stops.first() && a[1] != line.stops.last()) fail("${a[1]} is not a terminal of line ${a[0]}")
                if (line.suspended) fail("line ${a[0]} is suspended")
                val (stops,offsets) = line.direction(a[1] == line.stops.first())
                val heading = "TRIP ${a[0]} toward ${a[1]} ${a[2]}"
                val q = line.next(0,time(a[2]))
                if (q == null) out.add("$heading none") else {
                    out.add("$heading trip ${q+1} departs ${clock(line.at(q,0))}")
                    for (j in stops.indices) out.add("${clock(line.at(q,offsets[j]))} ${stops[j]}${if (station(stops[j]).closed) " closed" else ""}${if (j > 0 && pair(stops[j-1],stops[j]) in closed) " blocked" else ""}")
                }
            }
            "SHOWLINE" -> {
                val line = line(a[0])
                out.add("SHOWLINE ${a[0]} ${if (line.suspended) "suspended" else "running"} first ${clock(line.first)} last ${clock(line.last)} headway ${line.headway} delay ${line.delay} trips ${line.trips}")
                for (j in line.stops.indices) {
                    val s = line.stops[j]
                    out.add("${line.offsets[j]} $s zone ${station(s).zone}${if (station(s).closed) " closed" else ""}${if (j > 0 && pair(line.stops[j-1],s) in closed) " blocked" else ""}")
                }
            }
            "INFO" -> {
                val s = station(a[0])
                out.add("INFO ${a[0]} ${s.name} zone ${s.zone} transfer ${s.transfer} ${if (s.closed) "closed" else "open"}")
                val ids = lines.filterValues {
                    a[0] in it.stops
                }.keys
                out.add("LINES ${if (ids.isEmpty()) "none" else ids.joinToString(" ")}")
                val links = neighbors(a[0])
                out.add("WALKS ${if (links.isEmpty()) "none" else links.joinToString(" ") { "${it.first} ${it.second}" }}")
            }
            "STATUS" -> {
                out.add("STATUS stations ${stations.size} lines ${lines.size} walks ${walks.size}")
                for ((s,station) in stations) if (station.closed) out.add("CLOSED $s")
                for ((a,b) in closed.sortedWith(compareBy<Pair<String,String>> {
                    it.first
                }.thenBy {
                    it.second
                })) out.add("CLOSED $a-$b")
                for ((id,line) in lines) if (line.suspended) out.add("SUSPENDED $id")
                for ((id,line) in lines) if (line.delay != 0) out.add("DELAYED $id ${line.delay}")
            }
        }
        return out
    }
}
fun main() {
    val planner = Planner()
    repeat(readLine()!!.toInt()) {
        try {
            planner.command(readLine()!!.split(' ')).forEach(::println)
        } catch (p: Problem) {
            println("ERROR ${p.text}")
        }
    }
}
