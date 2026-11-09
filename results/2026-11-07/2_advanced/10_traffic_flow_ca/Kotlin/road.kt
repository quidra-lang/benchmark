class Turn(val target: Segment, val weight: Int) { var vehicles = 0 }
class BusStop(val segment: Segment, val cell: Int, val dwell: Int) { var buses = 0 }
class Segment(val id: String, val start: String, val end: String, val length: Int, val lanes: Int, val limit: Int) {
    val cells = Array(lanes) { IntArray(length) }
    var junction: Junction? = null
    val turns = mutableListOf<Turn>()
    var stop: BusStop? = null
    var entered = 0
    var vehicleSum = 0L
    var speedSum = 0L
    var maxVehicles = 0
    var greenSteps = 0
    var queueSum = 0L
    var maxQueue = 0
    var failures = 0
    var passed = 0
    var blocked = 0
    val changes = IntArray(3)
    fun put(lane: Int, cell: Int, value: Int) { cells[lane - 1][cell] = value }
    fun free(lane: Int, cell: Int, cap: Int): Int {
        var count = 0
        while (count < cap && cell + count + 1 < length && cells[lane - 1][cell + count + 1] == 0) count++
        return count
    }
    fun first(lane: Int): Int = cells[lane - 1].indexOfFirst { it != 0 }.let { if (it < 0) length else it }
    fun safe(lane: Int, cell: Int): Boolean = (maxOf(0, cell - limit)..cell).all { cells[lane - 1][it] == 0 }
    fun vehicleNumbers(lane: Int): List<Int> = cells[lane - 1].filter { it > 0 }
    fun cellsText(lane: Int, vehicles: List<Vehicle>): String = cells[lane - 1].joinToString("") { if (it == 0) "." else if (it == -1) "#" else vehicles[it - 1].speed.toString() }
}
class Incident(val segment: Segment, val lane: Int, val cell: Int, val start: Long, val end: Long) {
    var state = "planned"
    var activeStart = 0
    var activeEnd = 0
    fun update(step: Int): String? {
        var event: String? = null
        if (state == "active" && step > end) { state = "cleared"; segment.put(lane, cell, 0); event = "INCIDENT_END" }
        else if (state == "planned" && step > end) state = "cancelled"
        else if (state == "planned" && step >= start && segment.cells[lane - 1][cell] == 0) { state = "active"; segment.put(lane, cell, -1); activeStart = step; event = "INCIDENT_START" }
        if (state == "active") activeEnd = step
        return event
    }
}
