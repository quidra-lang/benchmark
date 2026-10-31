import java.io.File

fun timeText(step: Int): String = step.toString().padStart(4, '0')
fun flag(value: Boolean): String = if (value) "Y" else "N"
fun optional(value: Int): String = if (value == 0) "-" else value.toString()
class Ratio(a: Long, b: Long = 1L) {
    private val divisor = gcd(a, b)
    val numerator = a / divisor
    val denominator = b / divisor
    fun times(weight: Int, total: Int): Ratio = Ratio(numerator * weight, denominator * total)
    fun plus(other: Ratio): Ratio { val common = gcd(denominator, other.denominator); return Ratio(numerator * (other.denominator / common) + other.numerator * (denominator / common), denominator / common * other.denominator) }
    override fun toString(): String = "$numerator/$denominator"
}
data class Route(val segments: List<String>, val share: Ratio)
class Source(val node: String, val rates: List<Pair<Int, Long>>, val segment: Segment) {
    val queue = ArrayDeque<Vehicle>()
    var queueStart = 0
    var queueMax = 0
    fun rate(step: Int): Int = rates.firstOrNull { step <= it.second }?.first ?: 0
}
data class Detector(val name: String, val segment: Segment, val cell: Int, val width: Int)
class Diagram(val segment: Segment, val lane: Int, val start: Int, val end: Int) { val lines = mutableListOf<String>() }
data class Ring(val number: Int, val length: Int, val vmax: Int, val warmup: Int, val measure: Int, val seed: Long, val counts: List<Int>)
class Interval(count: Int) {
    var arrivals = 0
    var insertions = 0
    var exits = 0
    var vehicleSteps = 0L
    var speedSum = 0L
    val passing = IntArray(count)
    val occupancy = LongArray(count)
    val occupancySpeed = LongArray(count)
}
class Move(val vehicle: Vehicle) { val segment = vehicle.segment!!; val cell = vehicle.cell; var speed = 0 }
fun runRing(ring: Ring, count: Int, moving: Int, stopped: Int): Long {
    val rng = Minstd(ring.seed)
    val positions = IntArray(count) { it * ring.length / count }
    var speeds = IntArray(count)
    var total = 0L
    for (step in 1..ring.warmup + ring.measure) {
        val order = positions.indices.sortedByDescending { positions[it] }
        val next = IntArray(count)
        for ((rank, index) in order.withIndex()) {
            val ahead = order[(rank + count - 1) % count]
            val gap = (positions[ahead] - positions[index] - 1 + ring.length) % ring.length
            next[index] = randomSlowdown(minOf(speeds[index] + 1, ring.vmax, gap), speeds[index], rng.draw(), moving, stopped)
        }
        for (index in positions.indices) positions[index] = (positions[index] + next[index]) % ring.length
        speeds = next
        if (step > ring.warmup) total += next.sumOf { it.toLong() }
    }
    return total
}
class Simulation {
    val segments = mutableListOf<Segment>()
    val segmentByID = mutableMapOf<String, Segment>()
    val junctions = mutableListOf<Junction>()
    val incidents = mutableListOf<Incident>()
    val stops = mutableListOf<BusStop>()
    val classes = mutableListOf<VehicleClass>()
    val sources = mutableListOf<Source>()
    val sinks = mutableListOf<String>()
    var seed = 1L
    var steps = 0
    var dawdle = 0
    var dawdleStopped = 0
    var intervalLength = 1
    var binWidth = 1L
    val detectors = mutableListOf<Detector>()
    val diagrams = mutableListOf<Diagram>()
    var trackNumbers = emptyList<Long>()
    val rings = mutableListOf<Ring>()
    var rng = Minstd(1L)
    val vehicles = mutableListOf<Vehicle>()
    val intervals = mutableListOf<Interval>()
    val events = mutableListOf<String>()
    val tracks = mutableMapOf<Long, MutableList<String>>()
    fun load() {
        for (file in listOf("network.txt", "demand.txt", "params.txt")) {
            for (line in File("input/$file").readLines()) {
                val fields = line.split(' ')
                fun n(index: Int): Int = fields[index].toInt()
                when (fields[0]) {
                    "SEGMENT" -> { val road = Segment(fields[1], fields[2], fields[3], n(4), n(5), n(6)); segments += road; segmentByID[road.id] = road }
                    "JUNCTION" -> { val junction = Junction(fields[1], n(2), fields.drop(3)); junctions += junction; segments.filter { it.end == junction.node }.forEach { it.junction = junction } }
                    "INCIDENT" -> incidents += Incident(segmentByID.getValue(fields[1]), n(2), n(3), fields[4].toLong(), fields[5].toLong())
                    "STOP" -> { val road = segmentByID.getValue(fields[1]); val stop = BusStop(road, n(2), n(3)); road.stop = stop; stops += stop }
                    "CLASS" -> classes += VehicleClass(fields[1], n(2), n(3), fields[4] == "Y", fields[5] == "Y")
                    "SOURCE" -> sources += Source(fields[1], fields.drop(2).map { val pair = it.split(':'); pair[0].toInt() to pair[1].toLong() }, segments.first { it.start == fields[1] })
                    "SINK" -> sinks += fields[1]
                    "TURN" -> segmentByID.getValue(fields[1]).turns += Turn(segmentByID.getValue(fields[2]), n(3))
                    "seed" -> seed = fields[1].toLong()
                    "steps" -> steps = n(1)
                    "dawdle" -> { dawdle = n(1); dawdleStopped = n(2) }
                    "interval" -> intervalLength = n(1)
                    "bin" -> binWidth = fields[1].toLong()
                    "detector" -> detectors += Detector(fields[1], segmentByID.getValue(fields[2]), n(3), n(4))
                    "diagram" -> diagrams += Diagram(segmentByID.getValue(fields[1]), n(2), n(3), n(4))
                    "track" -> { trackNumbers = fields.drop(1).map(String::toLong); trackNumbers.forEach { tracks[it] = mutableListOf() } }
                    "ring" -> rings += Ring(rings.size + 1, n(1), n(2), n(3), n(4), fields[5].toLong(), fields.drop(6).map(String::toInt))
                }
            }
        }
    }
    fun record(step: Int, text: String) { events += "${timeText(step)} $text" }
    fun present(segment: Segment): List<Vehicle> = (1..segment.lanes).flatMap { lane -> segment.vehicleNumbers(lane).map { vehicles[it - 1] } }
    fun enter(vehicle: Vehicle, segment: Segment) { vehicle.route += segment.id; segment.entered++; if (segment.junction != null) vehicle.turn = segment.turns[select(segment.turns.map { it.weight }, rng.draw())] }
    fun arrive(step: Int) {
        for (source in sources) {
            if (rng.draw() % 1000 < source.rate(step)) {
                val kind = classes[select(classes.map { it.weight }, rng.draw())]
                val vehicle = Vehicle(vehicles.size + 1, kind, source.node, step)
                vehicles += vehicle; source.queue.addLast(vehicle); intervals.last().arrivals++
            }
        }
    }
    fun insert(step: Int) {
        for (source in sources) {
            val road = source.segment
            while (source.queue.isNotEmpty()) {
                var lane = 0; var best = -1
                for (candidate in 1..road.lanes) {
                    if (road.cells[candidate - 1][0] == 0) { val first = road.first(candidate); if (first > best) { lane = candidate; best = first } }
                }
                if (lane == 0) break
                val vehicle = source.queue.removeFirst()
                vehicle.place(road, lane, 0); vehicle.inserted = step; enter(vehicle, road); intervals.last().insertions++
            }
            if (source.queue.isNotEmpty() && source.queueStart == 0) { source.queueStart = step; source.queueMax = 0 }
            if (source.queueStart != 0) {
                source.queueMax = maxOf(source.queueMax, source.queue.size)
                if (source.queue.isEmpty()) { record(step, "QUEUE ${source.node} from ${source.queueStart} max ${source.queueMax}"); source.queueStart = 0 }
            }
        }
    }
    fun desiredLane(vehicle: Vehicle): Pair<Int, Int> {
        val road = vehicle.segment!!; val lane = vehicle.lane; val cell = vehicle.cell; val top = vehicle.maxSpeed()
        val here = road.free(lane, cell, top + 1); val want = minOf(vehicle.speed + 1, top); val ahead = cell + here + 1
        if (here < top + 1 && ahead < road.length && road.cells[lane - 1][ahead] == -1) {
            for (target in listOf(lane + 1, lane - 1)) if (target in 1..road.lanes && road.free(target, cell, top + 1) > here && road.safe(target, cell)) return target to 2
        }
        if (vehicle.headingForStop()) return if (lane >= 2 && road.safe(lane - 1, cell)) lane - 1 to 1 else lane to 1
        if (vehicle.vehicleClass.overtakes && lane < road.lanes && here < want && road.free(lane + 1, cell, top + 1) > here && road.safe(lane + 1, cell)) return lane + 1 to 0
        if (lane >= 2 && road.free(lane - 1, cell, top + 1) > want && road.safe(lane - 1, cell)) return lane - 1 to 1
        return lane to 0
    }
    fun changeLanes() {
        val changes = mutableListOf<Triple<Vehicle, Int, Int>>()
        for (road in segments) {
            if (road.lanes < 2) continue
            val reserved = mutableSetOf<Int>()
            for (lane in 1..road.lanes) {
                for (number in road.vehicleNumbers(lane)) {
                    val vehicle = vehicles[number - 1]
                    if (vehicle.dwell > 0) continue
                    val (target, kind) = desiredLane(vehicle)
                    if (target != lane && reserved.add(target * road.length + vehicle.cell)) changes += Triple(vehicle, target, kind)
                }
            }
        }
        for ((vehicle, target, kind) in changes) { val road = vehicle.segment!!; vehicle.place(road, target, vehicle.cell); vehicle.laneChanges++; road.changes[kind]++ }
    }
    fun determineSpeed(vehicle: Vehicle, step: Int): Int {
        val road = vehicle.segment!!; val lane = vehicle.lane; val cell = vehicle.cell
        val accelerated = minOf(vehicle.speed + 1, vehicle.maxSpeed())
        var gap = road.free(lane, cell, accelerated)
        if (gap < accelerated && cell + gap == road.length - 1) {
            if (road.junction == null) gap = accelerated
            else if (road.junction!!.green(road.id, step)) { val target = vehicle.turn!!.target; gap += target.free(minOf(lane, target.lanes), -1, accelerated - gap) }
        }
        if (vehicle.headingForStop()) gap = minOf(gap, road.stop!!.cell - cell)
        var speed = randomSlowdown(minOf(accelerated, gap), vehicle.speed, rng.draw(), dawdle, dawdleStopped)
        if (vehicle.dwell > 0) { speed = 0; vehicle.dwell-- }
        return speed
    }
    fun move(moves: List<Move>, step: Int) {
        val passing = mutableListOf<Move>()
        for (move in moves) {
            val vehicle = move.vehicle; val road = move.segment
            if (move.cell + move.speed < road.length) vehicle.place(road, vehicle.lane, move.cell + move.speed)
            else if (road.junction == null) { vehicle.leave(); vehicle.exited = step; vehicle.sink = road.end; intervals.last().exits++ }
            else passing += move
        }
        for (move in passing) {
            val vehicle = move.vehicle; val road = move.segment; val turn = vehicle.turn!!; val target = turn.target
            val lane = minOf(vehicle.lane, target.lanes); val overshoot = move.cell + move.speed - road.length
            val cell = minOf(overshoot, target.first(lane) - 1)
            if (cell < overshoot) road.blocked++
            if (cell >= 0) { vehicle.place(target, lane, cell); move.speed = road.length - move.cell + cell; road.passed++; turn.vehicles++; enter(vehicle, target) }
            else { vehicle.place(road, vehicle.lane, road.length - 1); move.speed = road.length - 1 - move.cell }
        }
    }
    fun aggregateVehicle(move: Move, step: Int) {
        val vehicle = move.vehicle; val speed = move.speed; val interval = intervals.last()
        vehicle.steps++; vehicle.distance += speed
        if (speed == 0) { vehicle.stoppedSteps++; if (vehicle.speed > 0) vehicle.stopCount++ }
        vehicle.speed = speed; interval.vehicleSteps++; interval.speedSum += speed
        if (vehicle.headingForStop() && vehicle.lane == 1) {
            val road = vehicle.segment!!; val stop = road.stop!!
            if (vehicle.cell == stop.cell) { vehicle.completedStops += road.id; vehicle.dwell = stop.dwell; stop.buses++; record(step, "BUS_STOP ${vehicle.number} ${road.id} cell ${stop.cell}") }
        }
        tracks[vehicle.number.toLong()]?.add(vehicle.segment?.let { "${timeText(step)} ${it.id} ${vehicle.lane} ${vehicle.cell} ${vehicle.speed}" } ?: "${timeText(step)} EXIT ${vehicle.speed}")
        for ((index, detector) in detectors.withIndex()) if (move.segment === detector.segment && move.cell < detector.cell && (vehicle.segment !== detector.segment || vehicle.cell >= detector.cell)) interval.passing[index]++
    }
    fun aggregateState(step: Int) {
        val interval = intervals.last()
        for ((index, detector) in detectors.withIndex()) {
            for (vehicle in present(detector.segment)) if (vehicle.cell in detector.cell until detector.cell + detector.width) { interval.occupancy[index]++; interval.occupancySpeed[index] += vehicle.speed.toLong() }
        }
        for (road in segments) {
            val present = present(road); val count = present.size
            road.vehicleSum += count; road.speedSum += present.sumOf { it.speed.toLong() }; road.maxVehicles = maxOf(road.maxVehicles, count)
            road.junction?.let { junction ->
                val green = junction.green(road.id, step); val queued = present.count { it.speed == 0 }
                if (green) road.greenSteps++
                road.queueSum += queued; road.maxQueue = maxOf(road.maxQueue, queued)
                if (step < steps && queued > 0 && green && !junction.green(road.id, step + 1)) road.failures++
            }
        }
        for (diagram in diagrams) if (step in diagram.start..diagram.end) { val road = diagram.segment; val signal = road.junction?.let { if (it.green(road.id, step)) "G" else "R" } ?: "E"; diagram.lines += "${timeText(step)} ${road.cellsText(diagram.lane, vehicles)} $signal" }
    }
    fun run() {
        rng = Minstd(seed)
        for (step in 1..steps) {
            for (incident in incidents) incident.update(step)?.let { record(step, "$it ${incident.segment.id} lane ${incident.lane} cell ${incident.cell}") }
            if ((step - 1) % intervalLength == 0) intervals += Interval(detectors.size)
            arrive(step); insert(step); changeLanes()
            val moves = segments.flatMap { road -> (1..road.lanes).flatMap { lane -> road.vehicleNumbers(lane).asReversed().map { Move(vehicles[it - 1]) } } }
            for (move in moves) move.speed = determineSpeed(move.vehicle, step)
            move(moves, step)
            for (move in moves) aggregateVehicle(move, step)
            aggregateState(step)
        }
        for (source in sources) if (source.queueStart != 0) record(steps, "QUEUE ${source.node} from ${source.queueStart} max ${source.queueMax} open")
    }
    fun routes(road: Segment): List<Route> {
        if (road.junction == null) return listOf(Route(listOf(road.id), Ratio(1L)))
        val total = road.turns.sumOf { it.weight }
        return road.turns.flatMap { turn -> routes(turn.target).map { Route(listOf(road.id) + it.segments, it.share.times(turn.weight, total)) } }
    }
    fun travelBlock(heading: String, group: List<Vehicle>): List<String> {
        val times = group.map { it.travelTime }.sorted()
        if (times.isEmpty()) return listOf("$heading exited 0")
        return listOf("$heading exited ${times.size} min ${times.first()} p50 ${percentile(times, 50)} p90 ${percentile(times, 90)} max ${times.last()} mean ${decimal(times.sumOf { it.toLong() }, times.size, 2)}") + histogram(times, binWidth)
    }
    fun outcome(group: List<Vehicle>, total: Int): String = "vehicles ${group.size} share ${fraction(group.size, total)} mean ${decimal(group.sumOf { it.travelTime.toLong() }, group.size, 2)}"
    fun travelLines(): List<String> {
        val exited = vehicles.filter { it.exited != 0 }
        val lines = classes.flatMap { kind -> travelBlock("CLASS ${kind.name}", exited.filter { it.vehicleClass == kind }) }.toMutableList()
        lines += travelBlock("ALL", exited)
        for (source in sources) {
            val group = exited.filter { it.source == source.node }; val options = routes(source.segment)
            lines += "SOURCE ${source.node} exited ${group.size}"
            for (route in options) lines += "  ROUTE ${route.segments.joinToString(",")} expected ${route.share} " + outcome(group.filter { it.route == route.segments }, group.size)
            for (sink in sinks) {
                val shares = options.filter { segmentByID.getValue(it.segments.last()).end == sink }.map { it.share }
                if (shares.isNotEmpty()) lines += "  SINK $sink expected ${shares.fold(Ratio(0L)) { sum, share -> sum.plus(share) }} " + outcome(group.filter { it.sink == sink }, group.size)
            }
        }
        return lines
    }
    fun classBlock(heading: String, group: List<Vehicle>): List<String> {
        val inserted = group.count { it.inserted != 0 }; val exited = group.filter { it.exited != 0 }; val count = exited.size
        val steps = group.sumOf { it.steps }; val distance = group.sumOf { it.distance }
        return listOf(heading,
            "  generated ${group.size} inserted $inserted exited $count in_network ${inserted - count} queued ${group.size - inserted}",
            "  vehicle_steps $steps distance $distance mean_speed ${fraction(distance, steps)} = ${decimal(distance, steps, 3)}",
            "  travel ${decimal(exited.sumOf { it.travelTime.toLong() }, count, 2)} entry_delay ${decimal(exited.sumOf { (it.inserted - it.arrival).toLong() }, count, 2)} stopped ${decimal(exited.sumOf { it.stoppedSteps }, count, 2)} stops ${decimal(exited.sumOf { it.stopCount }, count, 2)} lane_changes ${decimal(exited.sumOf { it.laneChanges }, count, 2)}")
    }
    fun classLines(): List<String> = classes.flatMap { kind -> classBlock("CLASS ${kind.name} vmax ${kind.vmax} weight ${kind.weight} overtake ${flag(kind.overtakes)} stops ${flag(kind.stops)}", vehicles.filter { it.vehicleClass == kind }) } + classBlock("ALL", vehicles)
    fun networkLines(): List<String> {
        val lines = segments.map { "SEGMENT ${it.id} ${it.start} ${it.end} length ${it.length} lanes ${it.lanes} limit ${it.limit} entered ${it.entered} mean_vehicles ${decimal(it.vehicleSum, steps, 3)} density ${decimal(it.vehicleSum, steps.toLong() * it.length * it.lanes, 4)} mean_speed ${decimal(it.speedSum, it.vehicleSum, 2)} max_vehicles ${it.maxVehicles} changes ${it.changes.joinToString("/")}" }.toMutableList()
        for (junction in junctions) {
            lines += junction.planLines()
            for (road in segments.filter { it.end == junction.node }) {
                lines += "  IN ${road.id} green ${road.greenSteps} passed ${road.passed} blocked ${road.blocked} max_queue ${road.maxQueue} mean_queue ${decimal(road.queueSum, steps, 3)} failures ${road.failures}"
                lines += road.turns.map { "    TURN ${it.target.id} weight ${it.weight} vehicles ${it.vehicles}" }
            }
        }
        lines += stops.map { "STOP ${it.segment.id} cell ${it.cell} dwell ${it.dwell} buses ${it.buses}" }
        lines += incidents.map { "INCIDENT ${it.segment.id} lane ${it.lane} cell ${it.cell} planned ${it.start}-${it.end} active " + if (it.activeStart == 0) "none" else "${it.activeStart}-${it.activeEnd}" }
        return lines
    }
    fun detectorLines(): List<String> = listOf("detector,interval,flow,density,speed") + detectors.flatMapIndexed { index, detector -> intervals.mapIndexed { number, interval -> "${detector.name},${number + 1},${interval.passing[index]},${decimal(interval.occupancy[index], intervalLength.toLong() * detector.width * detector.segment.lanes, 4)},${decimal(interval.occupancySpeed[index], interval.occupancy[index], 2)}" } }
    fun timelineLines(): List<String> {
        val lines = mutableListOf("interval,arrived,inserted,exited,in_network,queued,mean_speed")
        var arrived = 0; var inserted = 0; var exited = 0
        for ((index, interval) in intervals.withIndex()) { arrived += interval.arrivals; inserted += interval.insertions; exited += interval.exits; lines += "${index + 1},${interval.arrivals},${interval.insertions},${interval.exits},${inserted - exited},${arrived - inserted},${decimal(interval.speedSum, interval.vehicleSteps, 2)}" }
        return lines
    }
    fun trackLines(): List<String> = trackNumbers.flatMap { number ->
        if (number > vehicles.size) listOf("VEHICLE $number none")
        else { val vehicle = vehicles[number.toInt() - 1]; listOf("VEHICLE $number class ${vehicle.vehicleClass.name} source ${vehicle.source} arrival ${vehicle.arrival} inserted ${optional(vehicle.inserted)} exited ${optional(vehicle.exited)} sink ${vehicle.sink}", "ROUTE " + if (vehicle.route.isEmpty()) "-" else vehicle.route.joinToString(" ")) + tracks.getValue(number) }
    }
    fun fundamentalLines(): List<String> = listOf("ring,vehicles,density,flow,speed") + rings.flatMap { ring -> ring.counts.map { count -> val total = runRing(ring, count, dawdle, dawdleStopped); "${ring.number},$count,${decimal(count, ring.length, 4)},${decimal(total, ring.length.toLong() * ring.measure, 4)},${decimal(total, count.toLong() * ring.measure, 3)}" } }
    fun write() {
        val space = diagrams.flatMap { listOf("DIAGRAM ${it.segment.id} lane ${it.lane} steps ${it.start}-${it.end}") + it.lines }
        val outputs = listOf("spacetime.txt" to space, "detectors.csv" to detectorLines(), "travel_times.txt" to travelLines(), "class_stats.txt" to classLines(), "network_stats.txt" to networkLines(), "timeline.csv" to timelineLines(), "tracks.txt" to trackLines(), "fundamental.csv" to fundamentalLines(), "events.txt" to events)
        File("output").mkdirs()
        for ((name, lines) in outputs) File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n"))
    }
}
fun main() { val simulation = Simulation(); simulation.load(); simulation.run(); simulation.write() }
