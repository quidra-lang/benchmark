private val classes = listOf("F","J","Y")
data class Seat(val id: String, val row: Int, val letter: Char, val block: Int, val cabin: String, val kind: String)
class Cabin(val name: String, val first: Int, val last: Int, val blocks: List<String>) {
    val seats = mutableListOf<Seat>()
}
class Aircraft(val model: String, val base: Int, val limit: Int) {
    val cabins = linkedMapOf<String,Cabin>()
    val seats = linkedMapOf<String,Seat>()
    val exits = mutableSetOf<Int>()
    val blocked = mutableSetOf<String>()
}
class Flight(val name: String, val aircraft: Aircraft) {
    var closed = false
    val limits = mutableMapOf<String,Int>()
    val blocked = aircraft.blocked.toMutableSet()
    val occupied = mutableMapOf<String,Passenger>()
    val bookings = mutableListOf<Booking>()
    val volunteers = mutableListOf<Passenger>()
}
class Booking(val pnr: String, val flight: Flight) {
    var checked = false
    val passengers = mutableListOf<Passenger>()
}
class Passenger(val name: String, val type: String, val pref: String?, var cabin: String, val booking: Booking) {
    var order = 0
    var lap: Passenger? = null
    var parent: Passenger? = null
    var seat: Seat? = null
    val needsSeat get() = type != "INFANT"
    val result get() = if (!needsSeat) "LAP" else seat?.id ?: "UNASSIGNED"
}
class Problem(message: String) : RuntimeException(message)

class Airline {
    private val aircraft = mutableMapOf<String,Aircraft>()
    private val flights = linkedMapOf<String,Flight>()
    private val bookings = mutableMapOf<String,Booking>()
    private val used = mutableSetOf<String>()
    private val tiers = mutableMapOf<String,String>()
    private lateinit var defining: Aircraft
    private var nextOrder = 0
    private fun fail(message: String): Nothing = throw Problem(message)
    private fun tier(p: Passenger) = tiers.getOrDefault(p.name,"NONE")
    private fun tierRank(p: Passenger) = listOf("PLATINUM","GOLD","SILVER","NONE").indexOf(tier(p))
    private fun flight(name: String, open: Boolean): Flight {
        val f = flights[name] ?: fail("unknown flight $name")
        if (open && f.closed) fail("flight $name is closed")
        return f
    }
    private fun booking(pnr: String, open: Boolean): Booking {
        val b = bookings[pnr] ?: fail("unknown PNR $pnr")
        if (b.passengers.isEmpty()) fail("unknown PNR $pnr")
        if (open && b.flight.closed) fail("flight ${b.flight.name} is closed")
        return b
    }
    private fun passenger(b: Booking, name: String) = b.passengers.firstOrNull { it.name == name }
        ?: fail("no passenger $name in ${b.pnr}")
    private fun passengers(f: Flight) = f.bookings.flatMap { it.passengers }
    private fun booked(f: Flight, cabin: String) = passengers(f).count { it.needsSeat && it.cabin == cabin }
    private fun seats(a: Aircraft, cabin: String, blocked: Set<String>) = a.cabins.getValue(cabin).seats.count { it.id !in blocked }
    private fun requireCabin(f: Flight, cabin: String) {
        if (cabin !in f.aircraft.cabins) fail("no cabin $cabin on ${f.name}")
    }
    private fun sameBlock(a: Seat, b: Seat) = a.row == b.row && a.block == b.block
    private fun exitAllowed(p: Passenger, s: Seat) = s.row !in p.booking.flight.aircraft.exits || p.type != "CHILD" && p.lap == null
    private fun infantAllowed(p: Passenger, s: Seat, vacated: Set<Passenger>, proposed: Map<Passenger,Seat>): Boolean {
        if (p.lap == null) return true
        val f = p.booking.flight
        for (letter in f.aircraft.cabins.getValue(s.cabin).blocks[s.block]) {
            val q = f.occupied["${s.row}$letter"]
            if (q != null && q !== p && q.lap != null && q !in vacated) return false
        }
        for ((q,target) in proposed) {
            if (q !== p && q.lap != null && sameBlock(target,s)) return false
        }
        return true
    }
    private fun fits(p: Passenger, s: Seat, vacated: Set<Passenger> = emptySet(), proposed: Map<Passenger,Seat> = emptyMap()): Boolean {
        val f = p.booking.flight
        val occupant = f.occupied[s.id]
        return s.id !in f.blocked && (occupant == null || occupant in vacated) && exitAllowed(p,s) && infantAllowed(p,s,vacated,proposed)
    }
    private fun seat(p: Passenger, target: Seat?) {
        val f = p.booking.flight
        p.seat?.let { f.occupied.remove(it.id) }
        p.seat = target
        if (target != null) f.occupied[target.id] = p
    }
    private fun select(p: Passenger, cabin: String): Seat? {
        val candidates = p.booking.flight.aircraft.cabins.getValue(cabin).seats.filter { fits(p,it) }
        return candidates.firstOrNull { it.kind == p.pref } ?: candidates.firstOrNull()
    }
    private fun reassign(f: Flight, output: MutableList<String>) {
        for (p in passengers(f)) {
            if (p.needsSeat && p.seat == null) {
                val target = select(p,p.cabin)
                if (target != null) {
                    seat(p,target)
                    output.add("REASSIGNED ${p.booking.pnr} ${p.name} ${target.id}")
                }
            }
        }
    }
    private fun candidate(people: List<Passenger>, positions: List<Seat>): Boolean {
        val proposed = people.zip(positions).toMap()
        if (!people.all { fits(it,proposed.getValue(it),proposed = proposed) }) return false
        for (p in people) seat(p,proposed.getValue(p))
        return true
    }
    private fun assign(b: Booking, cabinName: String): String {
        val people = b.passengers.filter { it.needsSeat }
        if (people.size == 1) {
            seat(people[0],select(people[0],cabinName))
            return "SINGLE"
        }
        val cabin = b.flight.aircraft.cabins.getValue(cabinName)
        val a = b.flight.aircraft
        val k = people.size
        for (stage in 1..3) {
            val lastH = if (stage == 3) k else 2
            for (h in 2..lastH) {
                val width = (k+h-1)/h
                for (row in cabin.first..cabin.last) {
                    val blocks = if (stage == 2) listOf(cabin.blocks.joinToString("")) else cabin.blocks
                    for (block in blocks) {
                        val span = if (stage == 3) width else k
                        for (x in 0..block.length-span) {
                            val positions = mutableListOf<Seat>()
                            for (j in 0 until k) {
                                val r = row+if (stage == 3) j/width else 0
                                if (r > cabin.last) break
                                val letter = block[x+if (stage == 3) j%width else j]
                                positions.add(a.seats.getValue("$r$letter"))
                            }
                            if (positions.size == k && candidate(people,positions)) return when (stage) {
                                1 -> "BLOCK"
                                2 -> "ROW"
                                else -> "STACK"
                            }
                        }
                    }
                }
            }
        }
        for (p in people) seat(p,select(p,cabinName))
        return "SPLIT"
    }
    private fun targets(p: Passenger) = listOfNotNull(p,p.lap)
    private fun remove(targets: List<Passenger>) {
        for (p in targets) {
            seat(p,null)
            p.booking.flight.volunteers.remove(p)
            p.booking.passengers.remove(p)
            p.parent?.lap = null
        }
    }
    private val seatOrder = compareBy<Passenger> { it.seat!!.row }.thenBy { it.seat!!.letter }
    private fun load(seated: Int, count: Int): String {
        val q = seated*1000/count
        return "${q/10}.${q%10}%"
    }
    private fun boardingRank(p: Passenger) = when {
        p.booking.passengers.any { !it.needsSeat } -> 0
        p.cabin != "Y" -> 1
        tierRank(p) <= 1 -> 2
        else -> 3
    }
    private fun zone(p: Passenger) = (p.seat!!.row-p.booking.flight.aircraft.cabins.getValue("Y").first)/5+1
    fun execute(line: String): List<String> {
        val t = line.split(' ')
        val command = t[0]
        val output = mutableListOf<String>()
        when (command) {
            "AIRCRAFT" -> defining = Aircraft(t[1],t[2].toInt(),t[3].toInt())
            "CABIN" -> {
                val c = Cabin(t[1],t[2].toInt(),t[3].toInt(),t.drop(4))
                for (row in c.first..c.last) {
                    for ((block,letters) in c.blocks.withIndex()) {
                        for ((i,letter) in letters.withIndex()) {
                            val window = block == 0 && i == 0 || block == c.blocks.lastIndex && i == letters.lastIndex
                            val kind = if (window) "W" else if (i == 0 || i == letters.lastIndex) "A" else "M"
                            val s = Seat("$row$letter",row,letter,block,c.name,kind)
                            c.seats.add(s)
                            defining.seats[s.id] = s
                        }
                    }
                }
                defining.cabins[c.name] = c
            }
            "EXIT" -> defining.exits.addAll(t.drop(1).map { it.toInt() })
            "BLOCKED" -> defining.blocked.addAll(t.drop(1))
            "END" -> {
                aircraft[defining.model] = defining
                output.add("AIRCRAFT ${defining.model}"+classes.filter { it in defining.cabins }.joinToString("") { " $it ${seats(defining,it,defining.blocked)}" })
            }
            "FLIGHT" -> {
                if (t[1] in flights) fail("duplicate flight ${t[1]}")
                val a = aircraft[t[2]] ?: fail("unknown aircraft ${t[2]}")
                val f = Flight(t[1],a)
                var result = "FLIGHT ${f.name} ${a.model}"
                for (c in classes.filter { it in a.cabins }) {
                    val count = seats(a,c,a.blocked)
                    val limit = count*(100+t[3].toInt())/100
                    f.limits[c] = limit
                    result += " $c $count/$limit"
                }
                flights[f.name] = f
                output.add(result)
            }
            "BOOK" -> {
                if (t[1] in used) fail("duplicate PNR ${t[1]}")
                val f = flight(t[2],true)
                requireCabin(f,t[3])
                val b = Booking(t[1],f)
                val seen = mutableSetOf<String>()
                val adults = mutableListOf<Passenger>()
                val infants = mutableListOf<Passenger>()
                for (token in t.drop(4)) {
                    val parts = token.split(':')
                    if (!seen.add(parts[0])) fail("duplicate name ${parts[0]} in ${b.pnr}")
                    val p = Passenger(parts[0],parts[1],parts.getOrNull(2),t[3],b)
                    b.passengers.add(p)
                    if (p.type == "ADULT") adults.add(p)
                    if (p.type == "INFANT") infants.add(p)
                }
                val present = passengers(f).map { it.name }.toSet()
                for (p in b.passengers) {
                    if (p.name in present) fail("${p.name} already on ${f.name}")
                }
                if (adults.isEmpty()) fail("no adult in ${b.pnr}")
                if (infants.size > adults.size) fail("too many infants in ${b.pnr}")
                if (booked(f,t[3])+b.passengers.count { it.needsSeat } > f.limits.getValue(t[3])) fail("limit exceeded for ${f.name} ${t[3]}")
                for (i in infants.indices) {
                    adults[i].lap = infants[i]
                    infants[i].parent = adults[i]
                }
                for (p in b.passengers) p.order = nextOrder++
                val method = assign(b,t[3])
                f.bookings.add(b)
                bookings[b.pnr] = b
                used.add(b.pnr)
                output.add("BOOKED ${b.pnr} ${f.name} ${t[3]} $method "+b.passengers.joinToString(" ") { "${it.name}:${it.result}" })
            }
            "SEAT" -> {
                val b = booking(t[1],true)
                val p = passenger(b,t[2])
                if (!p.needsSeat) fail("infant ${p.name} has no seat")
                val target = b.flight.aircraft.seats[t[3]]
                if (target == null || target.cabin != p.cabin) fail("no seat ${t[3]} in cabin ${p.cabin}")
                if (t[3] in b.flight.blocked) fail("seat ${t[3]} is blocked")
                if (t[3] in b.flight.occupied) fail("seat ${t[3]} is occupied")
                if (!exitAllowed(p,target)) fail("exit row ${target.row} not allowed for ${p.name}")
                if (!infantAllowed(p,target,emptySet(),emptyMap())) fail("infant limit reached at ${t[3]}")
                val old = p.result
                seat(p,target)
                output.add("MOVED ${b.pnr} ${p.name} $old -> ${t[3]}")
                reassign(b.flight,output)
            }
            "SWAP" -> {
                val a = booking(t[1],true)
                val p = passenger(a,t[2])
                val b = booking(t[3],true)
                val q = passenger(b,t[4])
                if (p === q) fail("cannot swap ${p.name} with itself")
                for (x in listOf(p,q)) {
                    if (!x.needsSeat) fail("infant ${x.name} has no seat")
                }
                if (a.flight !== b.flight) fail("${a.pnr} and ${b.pnr} are on different flights")
                if (p.cabin != q.cabin) fail("${p.name} and ${q.name} are in different cabins")
                for (x in listOf(p,q)) {
                    if (x.seat == null) fail("${x.name} has no seat")
                }
                val ps = p.seat!!
                val qs = q.seat!!
                val vacated = setOf(p,q)
                val proposed = mapOf(p to qs,q to ps)
                if (!fits(p,qs,vacated,proposed) || !fits(q,ps,vacated,proposed)) fail("swap of ${p.name} and ${q.name} breaks seating rules")
                seat(p,null)
                seat(q,null)
                seat(p,qs)
                seat(q,ps)
                output.add("SWAPPED ${a.pnr} ${p.name} ${p.result} ${b.pnr} ${q.name} ${q.result}")
                reassign(a.flight,output)
            }
            "CANCEL" -> {
                val b = booking(t[1],true)
                val targets = if (t.size == 2) b.passengers.toList() else {
                    val selected = targets(passenger(b,t[2]))
                    val remaining = b.passengers.filter { it !in selected }
                    if (remaining.isNotEmpty() && remaining.none { it.type == "ADULT" }) fail("${b.pnr} would have no adult")
                    b.passengers.filter { it in selected }
                }
                val names = targets.joinToString(" ") { it.name }
                remove(targets)
                output.add("CANCELLED ${b.pnr} $names")
                reassign(b.flight,output)
            }
            "STATUS" -> {
                tiers[t[1]] = t[2]
                output.add("STATUS ${t[1]} ${t[2]}")
            }
            "CHECKIN" -> {
                val b = booking(t[1],true)
                if (b.checked) fail("${b.pnr} already checked in")
                b.checked = true
                output.add("CHECKIN ${b.pnr} ${b.passengers.size}")
            }
            "VOLUNTEER" -> {
                val b = booking(t[1],true)
                val p = passenger(b,t[2])
                if (p.type != "ADULT" || p.lap != null) fail("${p.name} cannot volunteer")
                if (p.seat == null) fail("${p.name} has no seat")
                if (p in b.flight.volunteers) fail("${p.name} already volunteered")
                b.flight.volunteers.add(p)
                output.add("VOLUNTEER ${b.pnr} ${p.name} ${p.result}")
            }
            "UPGRADE" -> {
                val f = flight(t[1],true)
                val cabins = classes.filter { it in f.aircraft.cabins }
                var count = 0
                for (i in 0 until cabins.size-1) {
                    val higher = cabins[i]
                    val lower = cabins[i+1]
                    val targets = passengers(f).filter { it.cabin == lower && it.type == "ADULT" && it.lap == null && tier(it) != "NONE" }
                        .sortedWith(compareBy<Passenger> { tierRank(it) }.thenBy { it.order })
                    for (p in targets) {
                        if (booked(f,higher) >= f.limits.getValue(higher)) break
                        val target = select(p,higher) ?: break
                        val old = p.result
                        p.cabin = higher
                        seat(p,target)
                        output.add("UPGRADED ${p.booking.pnr} ${p.name} $lower $old -> $higher ${target.id}")
                        count++
                    }
                }
                reassign(f,output)
                output.add("UPGRADE ${f.name} $count")
            }
            "CLOSE" -> {
                val f = flight(t[1],true)
                for (b in f.bookings) {
                    if (b.passengers.isNotEmpty() && !b.checked) {
                        output.add("NOSHOW ${b.pnr} ${b.passengers.size}")
                        remove(b.passengers.toList())
                    }
                }
                reassign(f,output)
                var count = 0
                var compensation = 0
                for (c in classes.filter { it in f.aircraft.cabins }) {
                    val volunteers = f.volunteers.filter { it.seat != null && it.cabin == c }
                    for (p in volunteers) {
                        val useful = passengers(f).any { it.needsSeat && it.seat == null && it.cabin == c && fits(it,p.seat!!,setOf(p)) }
                        if (useful) {
                            val value = if (c == "F") 500 else if (c == "J") 300 else 150
                            output.add("DENIED VOLUNTARY ${p.booking.pnr} ${p.name} $c $value")
                            count++
                            compensation += value
                            remove(targets(p))
                            reassign(f,output)
                        }
                    }
                }
                for (p in passengers(f)) {
                    if (p.needsSeat && p.seat == null) {
                        var value = if (p.cabin == "F") 1000 else if (p.cabin == "J") 600 else 300
                        if (p.type == "CHILD") value /= 2
                        output.add("DENIED INVOLUNTARY ${p.booking.pnr} ${p.name} ${p.cabin} $value")
                        count++
                        compensation += value
                        remove(targets(p))
                    }
                }
                f.closed = true
                output.add("CLOSED ${f.name} denied $count compensation $compensation")
            }
            "BLOCK", "UNBLOCK" -> {
                val f = flight(t[1],true)
                if (t[2] !in f.aircraft.seats) fail("no seat ${t[2]} on ${f.name}")
                val blocked = t[2] in f.blocked
                if (command == "BLOCK" && blocked) fail("seat ${t[2]} is blocked")
                if (command == "UNBLOCK" && !blocked) fail("seat ${t[2]} is not blocked")
                output.add("$command ${f.name} ${t[2]}")
                if (command == "BLOCK") {
                    f.blocked.add(t[2])
                    val p = f.occupied[t[2]]
                    if (p != null) {
                        seat(p,null)
                        seat(p,select(p,p.cabin))
                        output.add("DISPLACED ${p.booking.pnr} ${p.name} ${t[2]} -> ${p.result}")
                    }
                } else f.blocked.remove(t[2])
                reassign(f,output)
            }
            "MAP" -> {
                val f = flight(t[1],false)
                output.add("MAP ${f.name}")
                for (name in classes) {
                    val c = f.aircraft.cabins[name] ?: continue
                    output.add("CABIN $name")
                    output.add("   "+c.blocks.joinToString(" "))
                    for (row in c.first..c.last) {
                        val blocks = c.blocks.map { block -> block.map { letter ->
                            val id = "$row$letter"
                            when {
                                id in f.blocked -> '#'
                                id in f.occupied -> 'X'
                                row in f.aircraft.exits -> 'E'
                                else -> '.'
                            }
                        }.joinToString("") }
                        output.add(row.toString().padStart(2)+" "+blocks.joinToString(" "))
                    }
                }
            }
            "MANIFEST" -> {
                val f = flight(t[1],false)
                val all = passengers(f)
                val seated = all.filter { it.seat != null }.sortedWith(seatOrder)
                val unassigned = all.filter { it.needsSeat && it.seat == null }
                output.add("MANIFEST ${f.name} seated ${seated.size} unassigned ${unassigned.size} infants ${all.count { !it.needsSeat }}")
                for (p in seated+unassigned) {
                    var result = "${p.seat?.id ?: "---"} ${p.cabin} ${p.booking.pnr} ${p.name} ${p.type}"
                    p.lap?.let { result += " +${it.name}" }
                    if (tier(p) != "NONE") result += " ${tier(p)}"
                    if (p.booking.checked) result += " CHECKED"
                    if (p in f.volunteers) result += " VOL"
                    output.add(result)
                }
            }
            "LOADFACTOR" -> {
                val f = flight(t[1],false)
                output.add("LOADFACTOR ${f.name}")
                var totalSeated = 0
                var totalSeats = 0
                for (c in classes.filter { it in f.aircraft.cabins }) {
                    val count = seats(f.aircraft,c,f.blocked)
                    val seated = passengers(f).count { it.cabin == c && it.seat != null }
                    output.add("$c $seated/$count ${load(seated,count)} booked ${booked(f,c)}/${f.limits.getValue(c)}")
                    totalSeated += seated
                    totalSeats += count
                }
                output.add("ALL $totalSeated/$totalSeats ${load(totalSeated,totalSeats)}")
            }
            "BALANCE" -> {
                val f = flight(t[1],false)
                var weight = 0
                var moment = 0
                for (p in passengers(f)) {
                    val s = p.seat ?: continue
                    val w = (if (p.type == "ADULT") 80 else 40)+(if (p.lap == null) 0 else 10)
                    weight += w
                    moment += w*(s.row-f.aircraft.base)
                }
                val limit = f.aircraft.limit
                val verdict = if (moment < -limit) "NOSE-HEAVY" else if (moment > limit) "TAIL-HEAVY" else "OK"
                output.add("BALANCE ${f.name} weight $weight moment $moment limit $limit $verdict")
            }
            "BOARDING" -> {
                val f = flight(t[1],false)
                val ordered = passengers(f).filter { it.seat != null }.sortedWith { a,b ->
                    val ar = boardingRank(a)
                    val br = boardingRank(b)
                    when {
                        ar != br -> ar.compareTo(br)
                        ar < 3 -> seatOrder.compare(a,b)
                        zone(a) != zone(b) -> zone(b).compareTo(zone(a))
                        a.seat!!.kind != b.seat!!.kind -> "WMA".indexOf(a.seat!!.kind).compareTo("WMA".indexOf(b.seat!!.kind))
                        a.seat!!.row != b.seat!!.row -> b.seat!!.row.compareTo(a.seat!!.row)
                        else -> a.seat!!.letter.compareTo(b.seat!!.letter)
                    }
                }
                output.add("BOARDING ${f.name} ${ordered.size}")
                for ((i,p) in ordered.withIndex()) {
                    val group = when (boardingRank(p)) {
                        0 -> "PRE"
                        1 -> "CABIN"
                        2 -> "TIER"
                        else -> "ZONE${zone(p)}"
                    }
                    output.add("${i+1} $group ${p.result} ${p.booking.pnr} ${p.name}")
                }
            }
            "AVAIL" -> {
                val f = flight(t[1],false)
                requireCabin(f,t[2])
                val free = f.aircraft.cabins.getValue(t[2]).seats.filter { it.id !in f.blocked && it.id !in f.occupied }
                output.add("AVAIL ${f.name} ${t[2]} free ${free.size} W ${free.count { it.kind == "W" }} M ${free.count { it.kind == "M" }} A ${free.count { it.kind == "A" }} EXIT ${free.count { it.row in f.aircraft.exits }}")
            }
            "INFO" -> {
                val b = booking(t[1],false)
                output.add("INFO ${b.pnr} ${b.flight.name} ${b.passengers.size} ${if (b.checked) "CHECKED" else "NOT-CHECKED"}")
                for (p in b.passengers) output.add("${p.name} ${p.type} ${p.cabin} ${p.result}")
            }
            "FIND" -> {
                val found = mutableListOf<String>()
                for (f in flights.values) {
                    for (p in passengers(f)) {
                        if (p.name == t[1]) found.add("${f.name} ${p.booking.pnr} ${p.cabin} ${p.result} ${if (f.closed) "CLOSED" else "OPEN"}")
                    }
                }
                output.add("FIND ${t[1]} ${tiers.getOrDefault(t[1],"NONE")} ${found.size}")
                output.addAll(found)
            }
        }
        return output
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val app = Airline()
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
