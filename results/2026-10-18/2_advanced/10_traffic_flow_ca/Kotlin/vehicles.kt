data class VehicleClass(val name: String, val vmax: Int, val weight: Int, val overtakes: Boolean, val stops: Boolean)
class Vehicle(val number: Int, val vehicleClass: VehicleClass, val source: String, val arrival: Int) {
    var inserted = 0
    var exited = 0
    var sink = "-"
    var segment: Segment? = null
    var lane = 0
    var cell = 0
    var speed = 0
    var turn: Turn? = null
    val route = mutableListOf<String>()
    var steps = 0L
    var distance = 0L
    var stoppedSteps = 0L
    var stopCount = 0L
    var laneChanges = 0L
    var dwell = 0
    val completedStops = mutableSetOf<String>()
    fun maxSpeed(): Int = minOf(vehicleClass.vmax, segment!!.limit)
    fun place(destination: Segment, lane: Int, cell: Int) { segment?.put(this.lane, this.cell, 0); destination.put(lane, cell, number); segment = destination; this.lane = lane; this.cell = cell }
    fun leave() { segment!!.put(lane, cell, 0); segment = null }
    fun headingForStop(): Boolean { val road = segment ?: return false; val stop = road.stop ?: return false; return vehicleClass.stops && road.id !in completedStops && cell <= stop.cell }
    val travelTime: Int get() = exited - inserted + 1
}
fun randomSlowdown(speed: Int, previous: Int, random: Long, moving: Int, stopped: Int): Int = if (speed > 0 && random % 1000 < (if (previous == 0) stopped else moving)) speed - 1 else speed
