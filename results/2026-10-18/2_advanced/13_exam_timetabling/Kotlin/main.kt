import java.io.File

data class OrderConstraint(val later: String, val earlier: String)
data class AttemptRecord(val size: Int, val deadEnds: Int, val failedCourse: String?)
data class AssignmentRecord(val course: String, val slot: Int, val saturation: Int)
data class Insertion(val course: String, val slot: Int, val increase: Int)
data class PenaltyPair(val first: String, val second: String, val relation: Int, val shared: Int)
data class StudentPair(val relation: Int, val lowSlot: Int, val lowCourse: String, val highSlot: Int, val highCourse: String)
data class StudentPenalty(val counts: IntArray, val total: Int)
data class Trial(val verdict: String, val assignment: MutableMap<String, Int>? = null, val total: Int = 0)
data class RoomGroup(val room: Room, val placements: List<Placement>)

class ExamCalendar(lines: List<String>) {
    private val settings = lines.take(6).map { line -> line.split(' ').drop(1).map { it.toInt() } }
    val days = settings[0][0]
    val lengths = settings[1]
    val periods = lengths.size
    val limit = settings[2][0]
    val weights = settings[3]
    val frontCount = settings[4][0]
    val deadline = settings[4][1]
    val ratio = settings[5][0]
    val slotCount = days * periods
    val closed = sortedSetOf<Int>()
    val unavailable = mutableMapOf<String, MutableSet<Int>>()
    val fixed = sortedMapOf<String, Int>()
    val orders = mutableListOf<OrderConstraint>()
    val arrows = mutableMapOf<String, MutableList<String>>()

    fun slots(): IntRange = 1..slotCount

    fun slotAt(dayText: String, periodText: String): Int {
        val day = dayText.toInt()
        val period = periodText.toInt()
        return if (day in 1..days && period in 1..periods) (day - 1) * periods + period else 0
    }

    fun dayOf(slot: Int): Int = (slot - 1) / periods + 1
    fun name(slot: Int): String = "D${dayOf(slot)}P${(slot - 1) % periods + 1}"
    fun length(slot: Int): Int = lengths[(slot - 1) % periods]

    fun relation(first: Int, second: Int): Int {
        val low = minOf(first, second)
        val high = maxOf(first, second)
        if (dayOf(low) == dayOf(high)) {
            if (high - low == 1) return 0
            if (high - low >= 2) return 1
        } else if (high - low == 1) return 2
        return -1
    }
}

class Breakdown(val counts: IntArray, val late: Int, weights: List<Int>) {
    val total = (0..2).sumOf { counts[it] * weights[it] } + late * weights[3]
    fun text(): String = "back_to_back ${counts[0]} same_day ${counts[1]} overnight ${counts[2]} front_load $late penalty $total"
}

class Scheduler(
    private val courses: Map<String, Course>, private val studentCourses: Map<String, List<String>>,
    private val rooms: List<Room>, private val calendar: ExamCalendar, private val errors: MutableList<String>
) {
    private val largestRoom = rooms.maxOf { it.capacity }
    private val ids = courses.keys.sorted()
    private val empty = ids.filter { courses.getValue(it).size == 0 }
    private val oversized = ids.filter { courses.getValue(it).size > largestRoom }
    private val schedulable = ids.filter { it !in empty && it !in oversized }
    private val graph = ConflictGraph(ids.filter { courses.getValue(it).size > 0 }, studentCourses.values)
    private val edges = graph.edges()
    private val frontLoad = bySize(schedulable).take(calendar.frontCount)
    private var openSlots = emptyList<Int>()
    private var fixedSlots = emptySet<Int>()
    private var assignment = mutableMapOf<String, Int>()
    private var penalty = 0
    private val attempts = mutableListOf<AttemptRecord>()
    private val assignmentOrder = mutableListOf<AssignmentRecord>()
    private val excluded = mutableListOf<String>()
    private val insertions = mutableListOf<Insertion>()
    private val reasons = mutableMapOf<String, List<String>>()
    private lateinit var initial: Breakdown
    private lateinit var exchanged: Breakdown
    private val exchangeLog = mutableListOf<String>()
    private val swapLog = mutableListOf<String>()
    private val placements = mutableMapOf<String, Placement>()
    private val slotPlacements = mutableMapOf<Int, List<Placement>>()

    private fun ceilDiv(numerator: Int, denominator: Int): Int = (numerator + denominator - 1) / denominator
    private fun bySize(ids: Collection<String>): List<String> =
        ids.sortedWith(compareByDescending<String> { courses.getValue(it).size }.thenBy { it })
    private fun byDegree(ids: Collection<String>): List<String> =
        ids.sortedWith(compareByDescending<String> { graph.degree(it) }.thenBy { it })

    private fun blockedStudents(course: Course, slot: Int): List<String> =
        course.students.filter { slot in calendar.unavailable[it].orEmpty() }

    private fun suitable(course: Course, slot: Int): Boolean =
        calendar.length(slot) >= course.duration && blockedStudents(course, slot).isEmpty()

    private fun packs(ids: Collection<String>): Boolean = Rooms.pack(rooms, ids.map { courses.getValue(it) }) != null
    private fun outside(day: String, period: String): String = "slot $day $period outside calendar"

    fun validateCalendar(lines: List<String>) {
        for (index in 6 until lines.size) {
            val fields = lines[index].split(' ')
            val message = when (fields[0]) {
                "closed" -> acceptClosed(fields[1], fields[2])
                "unavailable" -> acceptUnavailable(fields[1], fields[2], fields[3])
                "fixed" -> acceptFixed(fields[1], fields[2], fields[3])
                "after" -> acceptAfter(fields[1], fields[2])
                else -> error(fields[0])
            }
            if (message != null) errors += "calendar.txt line ${index + 1}: $message"
        }
        openSlots = calendar.slots().filter { it !in calendar.closed }
        fixedSlots = calendar.fixed.values.toSet()
    }

    private fun acceptClosed(day: String, period: String): String? {
        val slot = calendar.slotAt(day, period)
        if (slot == 0) return outside(day, period)
        if (!calendar.closed.add(slot)) return "duplicate closed ${calendar.name(slot)}"
        return null
    }

    private fun acceptUnavailable(student: String, day: String, period: String): String? {
        if (student !in studentCourses) return "unknown student $student"
        val slot = calendar.slotAt(day, period)
        if (slot == 0) return outside(day, period)
        if (!calendar.unavailable.getOrPut(student) { sortedSetOf() }.add(slot))
            return "duplicate unavailable $student ${calendar.name(slot)}"
        return null
    }

    private fun acceptFixed(id: String, day: String, period: String): String? {
        if (id !in courses) return "unknown course $id"
        if (id !in schedulable) return "course $id not schedulable"
        val slot = calendar.slotAt(day, period)
        if (slot == 0) return outside(day, period)
        val name = calendar.name(slot)
        if (slot in calendar.closed) return "slot $name closed"
        if (!suitable(courses.getValue(id), slot)) return "slot $name unsuitable for $id"
        if (id in calendar.fixed) return "duplicate fixed $id"
        val group = coursesAt(calendar.fixed, slot).toMutableList()
        val clash = group.firstOrNull { it in graph.neighbours(id) }
        if (clash != null) return "conflict $id $clash"
        group += id
        if (!packs(group)) return "rooms full $name"
        calendar.fixed[id] = slot
        return null
    }

    private fun acceptAfter(later: String, earlier: String): String? {
        for (id in listOf(later, earlier))
            if (id !in courses) return "unknown course $id"
        for (id in listOf(later, earlier))
            if (id !in schedulable) return "course $id not schedulable"
        if (later == earlier) return "bad order $later $earlier"
        val order = OrderConstraint(later, earlier)
        if (order in calendar.orders) return "duplicate order $later $earlier"
        if (ConflictGraph.reachable(calendar.arrows, earlier, later)) return "cycle $later $earlier"
        if (later in calendar.fixed && earlier in calendar.fixed
            && calendar.fixed.getValue(later) <= calendar.fixed.getValue(earlier)) return "fixed order $later $earlier"
        calendar.orders += order
        calendar.arrows.getOrPut(later) { mutableListOf() } += earlier
        return null
    }

    private fun coursesAt(slots: Map<String, Int>, slot: Int): List<String> =
        slots.keys.filter { slots[it] == slot }.sorted()

    private fun orderConflicts(id: String, slot: Int, slots: Map<String, Int>): List<String> = buildList {
        for ((later, earlier) in calendar.orders) {
            if (later == id && earlier in slots && slot <= slots.getValue(earlier)) add(earlier)
            else if (earlier == id && later in slots && slot >= slots.getValue(later)) add(later)
        }
    }

    private fun ordersSatisfied(slots: Map<String, Int>): Boolean = calendar.orders.all { (later, earlier) ->
        later !in slots || earlier !in slots || slots.getValue(later) > slots.getValue(earlier)
    }

    private fun candidateSlots(id: String, slots: Map<String, Int>): List<Int> = buildList {
        for (slot in openSlots) {
            if (!suitable(courses.getValue(id), slot)) continue
            if (graph.neighbours(id).keys.any { slots[it] == slot }) continue
            if (orderConflicts(id, slot, slots).isNotEmpty()) continue
            if (packs(coursesAt(slots, slot) + id)) add(slot)
        }
    }

    fun buildTimetable() {
        while (true) {
            val pending = schedulable.filter { it !in calendar.fixed && it !in excluded }
            val slots = calendar.fixed.toMutableMap()
            val attempt = Attempt(pending, graph, calendar.limit, ::candidateSlots)
            val succeeded = attempt.search(slots)
            attempts += AttemptRecord(pending.size, attempt.deadEnds, if (succeeded) null else attempt.deadEndCourse)
            if (succeeded) {
                assignment = slots
                for ((course, saturation) in attempt.chosen)
                    assignmentOrder += AssignmentRecord(course, slots.getValue(course), saturation)
                return
            }
            excluded += requireNotNull(attempt.deadEndCourse)
        }
    }

    private fun penaltyPairs(slots: Map<String, Int>): List<PenaltyPair> = buildList {
        for ((first, second, shared) in edges)
            if (first in slots && second in slots) {
                val relation = calendar.relation(slots.getValue(first), slots.getValue(second))
                if (relation >= 0) add(PenaltyPair(first, second, relation, shared))
            }
    }

    private fun lateCourses(slots: Map<String, Int>): List<String> =
        frontLoad.filter { it in slots && slots.getValue(it) > calendar.deadline }

    private fun breakdown(slots: Map<String, Int>): Breakdown {
        val counts = IntArray(3)
        for (pair in penaltyPairs(slots)) counts[pair.relation] += pair.shared
        return Breakdown(counts, lateCourses(slots).size, calendar.weights)
    }

    private fun contributions(): Map<String, Int> {
        val result = assignment.keys.associateWith { 0 }.toMutableMap()
        for (pair in penaltyPairs(assignment)) {
            val value = calendar.weights[pair.relation] * pair.shared
            result[pair.first] = result.getValue(pair.first) + value
            result[pair.second] = result.getValue(pair.second) + value
        }
        for (id in lateCourses(assignment)) result[id] = result.getValue(id) + calendar.weights[3]
        return result
    }

    private fun blockingReason(id: String, slot: Int): String {
        val course = courses.getValue(id)
        if (slot in calendar.closed) return "closed"
        if (calendar.length(slot) < course.duration) return "too_short"
        val blocked = blockedStudents(course, slot)
        if (blocked.isNotEmpty()) return "unavailable ${blocked.first()}"
        val neighbours = graph.neighbours(id)
        val clash = neighbours.keys.filter { assignment[it] == slot }.minWithOrNull(
            compareByDescending<String> { neighbours.getValue(it) }.thenBy { it }
        )
        if (clash != null) return "conflict $clash shared ${neighbours.getValue(clash)}"
        val conflicts = orderConflicts(id, slot, assignment)
        if (conflicts.isNotEmpty()) return "order ${conflicts.min()}"
        return "rooms"
    }

    fun insertExcluded() {
        for (id in excluded.sorted()) {
            val slots = candidateSlots(id, assignment)
            if (slots.isEmpty()) {
                reasons[id] = calendar.slots().map { blockingReason(id, it) }
                continue
            }
            val before = breakdown(assignment).total
            var best = 0
            var bestTotal = Int.MAX_VALUE
            for (slot in slots) {
                val trial = assignment.toMutableMap()
                trial[id] = slot
                val total = breakdown(trial).total
                if (total < bestTotal) {
                    best = slot
                    bestTotal = total
                }
            }
            assignment[id] = best
            insertions += Insertion(id, best, bestTotal - before)
        }
        initial = breakdown(assignment)
        penalty = initial.total
    }

    private fun unscheduled(): List<String> = (oversized + excluded.filter { it !in assignment }).sorted()
    private fun validTrial(trial: Map<String, Int>, moved: List<String>): Boolean =
        moved.all { suitable(courses.getValue(it), trial.getValue(it)) } && ordersSatisfied(trial)
    private fun movedCourses(trial: Map<String, Int>): List<String> = trial.keys.filter { trial[it] != assignment[it] }.sorted()

    private fun exchangeTrial(first: Int, second: Int): Trial {
        if (first in fixedSlots || second in fixedSlots) return Trial("fixed")
        val trial = assignment.toMutableMap()
        for ((id, slot) in assignment) {
            if (slot == first) trial[id] = second
            else if (slot == second) trial[id] = first
        }
        if (!validTrial(trial, movedCourses(trial))) return Trial("invalid")
        val total = breakdown(trial).total
        return if (total >= penalty) Trial("worse") else Trial("applied", trial, total)
    }

    private fun tally(verdicts: List<String>): MutableMap<String, Int> = verdicts.associateWith { 0 }.toMutableMap()
    private fun verdictCounts(tally: Map<String, Int>, verdicts: List<String>): String =
        verdicts.joinToString(" ") { "$it ${tally.getValue(it)}" }

    fun exchangeSlots() {
        var round = 0
        var serial = 0
        while (true) {
            round++
            val tally = tally(EXCHANGE_VERDICTS)
            val records = mutableListOf<String>()
            var pairs = 0
            for (i in openSlots.indices)
                for (j in i + 1 until openSlots.size) {
                    val first = openSlots[i]
                    val second = openSlots[j]
                    pairs++
                    val trial = exchangeTrial(first, second)
                    tally[trial.verdict] = tally.getValue(trial.verdict) + 1
                    if (trial.verdict == "applied") {
                        records += "EXCHANGE ${++serial} ${calendar.name(first)} ${calendar.name(second)} penalty $penalty -> ${trial.total}"
                        assignment = requireNotNull(trial.assignment)
                        penalty = trial.total
                    }
                }
            exchangeLog += "ROUND $round pairs $pairs ${verdictCounts(tally, EXCHANGE_VERDICTS)}"
            exchangeLog += records
            if (tally.getValue("applied") == 0) break
        }
        exchanged = breakdown(assignment)
    }

    private fun swapTrial(id: String, home: Int, target: Int): Trial {
        val chain = graph.kempeChain(assignment, id, home, target)
        if (chain.any { it in calendar.fixed }) return Trial("fixed")
        val trial = assignment.toMutableMap()
        for (member in chain) trial[member] = if (assignment[member] == home) target else home
        if (!validTrial(trial, chain)) return Trial("invalid")
        if (!packs(coursesAt(trial, home)) || !packs(coursesAt(trial, target))) return Trial("rooms")
        val total = breakdown(trial).total
        return if (total >= penalty) Trial("worse") else Trial("applied", trial, total)
    }

    fun swapChains() {
        var pass = 0
        var serial = 0
        while (true) {
            pass++
            val tally = tally(SWAP_VERDICTS)
            val records = mutableListOf<String>()
            var candidates = 0
            val movable = assignment.keys.filter { it !in calendar.fixed }.sorted()
            for (id in movable) {
                val home = assignment.getValue(id)
                for (target in openSlots) {
                    if (target == home) continue
                    candidates++
                    val trial = swapTrial(id, home, target)
                    tally[trial.verdict] = tally.getValue(trial.verdict) + 1
                    if (trial.verdict != "applied") continue
                    val slots = requireNotNull(trial.assignment)
                    val chain = movedCourses(slots)
                    records += "SWAP ${++serial} $id ${calendar.name(home)} ${calendar.name(target)} chain ${chain.size} penalty $penalty -> ${trial.total}"
                    for (member in chain)
                        records += "  MOVE $member ${calendar.name(assignment.getValue(member))} -> ${calendar.name(slots.getValue(member))}"
                    assignment = slots
                    penalty = trial.total
                    break
                }
            }
            swapLog += "PASS $pass candidates $candidates ${verdictCounts(tally, SWAP_VERDICTS)}"
            swapLog += records
            if (tally.getValue("applied") == 0) return
        }
    }

    fun assignRooms() {
        for (slot in openSlots) {
            val placed = requireNotNull(Rooms.pack(rooms, coursesAt(assignment, slot).map { courses.getValue(it) }))
            slotPlacements[slot] = placed
            for (placement in placed) placements[placement.course.id] = placement
        }
    }

    private fun roomGroups(slot: Int): List<RoomGroup> = rooms.mapNotNull { room ->
        val placed = slotPlacements.getValue(slot).filter { it.room == room }
        if (placed.isEmpty()) null else RoomGroup(room, placed)
    }

    private fun invigilators(slot: Int): Int = roomGroups(slot).sumOf { group ->
        ceilDiv(group.placements.sumOf { it.course.size }, calendar.ratio)
    }

    private fun slotLoad(slot: Int): Pair<Int, Int> {
        val ids = coursesAt(assignment, slot)
        return ids.size to ids.sumOf { courses.getValue(it).size }
    }

    private fun assignedCourses(student: String): List<String> = studentCourses.getValue(student)
        .filter { it in assignment }.sortedWith(compareBy<String> { assignment.getValue(it) }.thenBy { it })

    private fun studentPairs(student: String): List<StudentPair> = buildList {
        val ids = assignedCourses(student)
        for (i in ids.indices)
            for (j in i + 1 until ids.size) {
                val low = ids[i]
                val high = ids[j]
                val relation = calendar.relation(assignment.getValue(low), assignment.getValue(high))
                if (relation >= 0) add(StudentPair(relation, assignment.getValue(low), low, assignment.getValue(high), high))
            }
    }

    private fun studentPenalty(student: String): StudentPenalty {
        val counts = IntArray(3)
        for (pair in studentPairs(student)) counts[pair.relation]++
        return StudentPenalty(counts, (0..2).sumOf { counts[it] * calendar.weights[it] })
    }

    fun timetableLines(): List<String> {
        val lines = mutableListOf(
            "TIMETABLE days ${calendar.days} periods ${calendar.periods} open ${openSlots.size} courses ${courses.size} scheduled ${assignment.size} unscheduled ${unscheduled().size} empty ${empty.size}"
        )
        val header = (1..calendar.periods).map { "P$it" } + "TOTAL"
        lines += Report.fixedWidthLine("DAY", header, 4, 10)
        for (day in 1..calendar.days) {
            val cells = mutableListOf<String>()
            var dayExams = 0
            var dayStudents = 0
            for (period in 1..calendar.periods) {
                val slot = (day - 1) * calendar.periods + period
                if (slot in calendar.closed) cells += "closed"
                else {
                    val (exams, students) = slotLoad(slot)
                    cells += "$exams/$students"
                    dayExams += exams
                    dayStudents += students
                }
            }
            cells += "$dayExams/$dayStudents"
            lines += Report.fixedWidthLine("D$day", cells, 4, 10)
        }
        for (slot in calendar.slots()) {
            val prefix = "SLOT $slot ${calendar.name(slot)} minutes ${calendar.length(slot)}"
            if (slot in calendar.closed) {
                lines += "$prefix closed"
                continue
            }
            val (exams, students) = slotLoad(slot)
            val groups = roomGroups(slot)
            val seats = groups.sumOf { it.room.capacity }
            lines += "$prefix exams $exams students $students rooms ${groups.size} seats $seats invigilators ${invigilators(slot)}"
            for (placement in slotPlacements.getValue(slot)) {
                val course = placement.course
                val marker = if (course.id in calendar.fixed) " fixed" else ""
                lines += "  ${course.id} ${course.duration}min students ${course.size} room ${placement.room.id} seats ${placement.firstSeat}-${placement.lastSeat}$marker ${course.name}"
            }
        }
        for (room in rooms) {
            var used = 0
            var exams = 0
            var seated = 0
            for (slot in openSlots)
                for (group in roomGroups(slot))
                    if (group.room == room) {
                        used++
                        exams += group.placements.size
                        seated += group.placements.sumOf { it.course.size }
                    }
            val utilization = Report.roundedPercent(seated, room.capacity * openSlots.size)
            lines += "ROOM ${room.id} capacity ${room.capacity} slots $used exams $exams seated $seated utilization $utilization"
        }
        lines += "INVIGILATORS total ${openSlots.sumOf { invigilators(it) }} ratio ${calendar.ratio}"
        return lines
    }

    fun roomLines(): List<String> = buildList {
        add("slot,room,course,students,first_seat,last_seat")
        for (slot in openSlots)
            for (group in roomGroups(slot))
                for (p in group.placements)
                    add("${calendar.name(slot)},${group.room.id},${p.course.id},${p.course.size},${p.firstSeat},${p.lastSeat}")
    }

    fun penaltyLines(): List<String> {
        val weights = calendar.weights
        val final = breakdown(assignment)
        val lines = mutableListOf(
            "WEIGHTS back_to_back ${weights[0]} same_day ${weights[1]} overnight ${weights[2]} front_load ${weights[3]}",
            "FRONT_LOAD courses ${frontLoad.size} last_slot ${calendar.name(calendar.deadline)}",
            "INITIAL ${initial.text()}"
        )
        lines += exchangeLog
        lines += "EXCHANGED ${exchanged.text()}"
        lines += swapLog
        lines += "FINAL ${final.text()}"
        lines += "SAVED ${initial.total - final.total}"
        val daily = Array(calendar.days + 1) { IntArray(3) }
        for (pair in penaltyPairs(assignment)) {
            val day = calendar.dayOf(minOf(assignment.getValue(pair.first), assignment.getValue(pair.second)))
            daily[day][pair.relation] += pair.shared
        }
        for (day in 1..calendar.days)
            lines += "DAY D$day back_to_back ${daily[day][0]} same_day ${daily[day][1]} overnight ${daily[day][2]}"
        for (id in lateCourses(assignment))
            lines += "LATE $id ${calendar.name(assignment.getValue(id))} students ${courses.getValue(id).size}"
        val contribution = contributions()
        val ranked = contribution.keys.sortedWith(compareByDescending<String> { contribution.getValue(it) }.thenBy { it }).take(10)
        for (id in ranked)
            if (contribution.getValue(id) > 0)
                lines += "COURSE $id ${calendar.name(assignment.getValue(id))} penalty ${contribution.getValue(id)}"
        lines += studentStatistics()
        return lines
    }

    private fun studentStatistics(): List<String> {
        val histogram = sortedMapOf<Int, Int>()
        val gaps = sortedMapOf<Int, Int>()
        val dayLoads = sortedMapOf<Int, Int>()
        val statistics = mutableMapOf<String, StudentPenalty>()
        for (student in studentCourses.keys) {
            val result = studentPenalty(student)
            statistics[student] = result
            histogram[result.total] = histogram.getOrDefault(result.total, 0) + 1
            val slots = assignedCourses(student).map { assignment.getValue(it) }
            for ((low, high) in slots.zipWithNext()) gaps[high - low] = gaps.getOrDefault(high - low, 0) + 1
            if (slots.isNotEmpty()) {
                val maximum = slots.groupingBy { calendar.dayOf(it) }.eachCount().values.max()
                dayLoads[maximum] = dayLoads.getOrDefault(maximum, 0) + 1
            }
        }
        val lines = histogram.map { (value, count) -> "HISTOGRAM $value $count" }.toMutableList()
        lines += gaps.map { (value, count) -> "GAP $value $count" }
        lines += dayLoads.map { (value, count) -> "DAYLOAD $value $count" }
        val ranking = statistics.keys.sortedWith(compareByDescending<String> { statistics.getValue(it).total }.thenBy { it }).take(5)
        for (student in ranking) {
            val result = statistics.getValue(student)
            if (result.total > 0)
                lines += "WORST $student penalty ${result.total} back_to_back ${result.counts[0]} same_day ${result.counts[1]} overnight ${result.counts[2]}"
        }
        return lines
    }

    fun scheduleLines(queries: List<String>): List<String> = buildList {
        for (student in queries) {
            if (student !in studentCourses) {
                add("STUDENT $student not found")
                continue
            }
            val ids = studentCourses.getValue(student)
            val assigned = assignedCourses(student)
            add("STUDENT $student exams ${ids.size} scheduled ${assigned.size} penalty ${studentPenalty(student).total}")
            for (id in assigned) {
                val placement = placements.getValue(id)
                val course = placement.course
                val seat = placement.firstSeat + course.students.indexOf(student)
                add("  ${calendar.name(assignment.getValue(id))} $id room ${placement.room.id} seat $seat ${course.name}")
            }
            for (id in ids)
                if (id !in assignment) add("  UNSCHEDULED $id ${courses.getValue(id).name}")
            for (pair in studentPairs(student))
                add("  ${RELATIONS[pair.relation].uppercase()} ${calendar.name(pair.lowSlot)} ${pair.lowCourse} ${calendar.name(pair.highSlot)} ${pair.highCourse}")
            for (slot in calendar.unavailable[student].orEmpty().sorted()) add("  UNAVAILABLE ${calendar.name(slot)}")
        }
    }

    fun statusLines(): List<String> = buildList {
        val contribution = contributions()
        add("course,status,slot,students,minutes,degree,penalty")
        for (id in ids) {
            val course = courses.getValue(id)
            val status = when (id) {
                in calendar.fixed -> "fixed"
                in assignment -> "scheduled"
                in oversized -> "too_large"
                in empty -> "empty"
                else -> "no_slot"
            }
            val slot = assignment[id]?.let { calendar.name(it) } ?: "-"
            add("$id,$status,$slot,${course.size},${course.duration},${graph.degree(id)},${contribution.getOrDefault(id, 0)}")
        }
    }

    private fun graphLines(): List<String> = buildList {
        val vertices = graph.vertices.size
        val edgeCount = edges.size
        val shared = edges.sumOf { it.shared }
        val density = if (vertices >= 2) 2000 * edgeCount / (vertices * (vertices - 1)) else 0
        add("GRAPH courses $vertices edges $edgeCount shared $shared density $density")
        for (id in byDegree(graph.vertices).take(5))
            add("DEGREE $id neighbours ${graph.degree(id)} shared ${graph.sharedTotal(id)} students ${courses.getValue(id).size}")
        val components = graph.components()
        add("COMPONENTS ${components.size}")
        for ((index, component) in components.withIndex())
            add("COMPONENT ${index + 1} size ${component.size} first ${component.first()}")
        val clique = graph.greedyClique(schedulable)
        add("CLIQUE size ${clique.size}" + if (clique.isNotEmpty()) " " + clique.joinToString(" ") else "")
    }

    private fun capacityLines(): List<String> = buildList {
        val loads = studentCourses.values.map { it.size }
        val maximum = loads.max()
        val demand = schedulable.sumOf { courses.getValue(it).size }
        val capacity = rooms.sumOf { it.capacity }
        add("LOAD max_exams $maximum students ${loads.count { it == maximum }}")
        add("SEATS demand $demand capacity $capacity min_slots ${ceilDiv(demand, capacity)}")
        add("HEURISTIC largest_degree slots ${Coloring.greedyNumbering(byDegree(schedulable), graph)}")
        add("HEURISTIC largest_enrolment slots ${Coloring.greedyNumbering(bySize(schedulable), graph)}")
        val table = bySize(graph.vertices).take(8)
        add(Report.fixedWidthLine("MATRIX", table, 9, 9))
        for (row in table) {
            val cells = table.map { column -> if (row == column) "-" else graph.neighbours(row).getOrDefault(column, 0).toString() }
            add(Report.fixedWidthLine(row, cells, 9, 9))
        }
    }

    fun reportLines(): List<String> = buildList {
        val enrolments = studentCourses.values.sumOf { it.size }
        add("INPUT courses ${courses.size} enrolments $enrolments rooms ${rooms.size} students ${studentCourses.size} errors ${errors.size}")
        addAll(errors.map { "ERROR $it" })
        addAll(graphLines())
        addAll(capacityLines())
        addAll(empty.map { "EMPTY $it" })
        for (id in oversized) add("TOO_LARGE $id students ${courses.getValue(id).size} largest_room $largestRoom")
        for (slot in calendar.closed) add("CLOSED ${calendar.name(slot)}")
        for ((id, slot) in calendar.fixed) add("FIXED $id ${calendar.name(slot)}")
        for ((later, earlier) in calendar.orders) add("AFTER $later $earlier")
        for ((index, attempt) in attempts.withIndex()) {
            val result = attempt.failedCourse?.let { "failed $it" } ?: "success"
            add("ATTEMPT ${index + 1} courses ${attempt.size} backtracks ${attempt.deadEnds} $result")
        }
        for ((index, chosen) in assignmentOrder.withIndex())
            add("ORDER ${index + 1} ${chosen.course} ${calendar.name(chosen.slot)} saturation ${chosen.saturation} degree ${graph.degree(chosen.course)}")
        for ((course, slot, increase) in insertions) add("INSERTED $course ${calendar.name(slot)} penalty $increase")
        for (id in unscheduled()) {
            val reason = if (id in oversized) "too_large" else "no_slot"
            add("UNSCHEDULED $id reason $reason students ${courses.getValue(id).size}")
            for ((index, recorded) in reasons[id].orEmpty().withIndex()) add("  ${calendar.name(index + 1)} $recorded")
        }
        add("SUMMARY scheduled ${assignment.size} unscheduled ${unscheduled().size} slots_used ${assignment.values.toSet().size} penalty $penalty")
    }

    companion object {
        private val RELATIONS = listOf("back_to_back", "same_day", "overnight")
        private val EXCHANGE_VERDICTS = listOf("fixed", "invalid", "worse", "applied")
        private val SWAP_VERDICTS = listOf("fixed", "invalid", "rooms", "worse", "applied")
    }
}

fun main() {
    val errors = mutableListOf<String>()
    val courses = Enrolment.loadCourses("input/courses.csv", errors)
    val students = Enrolment.loadEnrolments("input/enrolments.csv", courses, errors)
    val rooms = Rooms.load("input/rooms.csv", errors)
    val calendarLines = File("input/calendar.txt").readLines(Charsets.US_ASCII)
    val scheduler = Scheduler(courses, students, rooms, ExamCalendar(calendarLines), errors)
    scheduler.validateCalendar(calendarLines)
    scheduler.buildTimetable()
    scheduler.insertExcluded()
    scheduler.exchangeSlots()
    scheduler.swapChains()
    scheduler.assignRooms()
    val queries = File("input/queries.txt").readLines(Charsets.US_ASCII)
    Report.writeFiles("output", mapOf(
        "timetable.txt" to scheduler.timetableLines(),
        "rooms.csv" to scheduler.roomLines(),
        "penalties.txt" to scheduler.penaltyLines(),
        "student_schedules.txt" to scheduler.scheduleLines(queries),
        "course_status.csv" to scheduler.statusLines(),
        "report.txt" to scheduler.reportLines()
    ))
}
