import java.io.File
object FlightPlans {
    data class AircraftType(val climb: Int,val descent: Int,val minimum: Int)
    data class Sector(val name: String,val x1: Int,val y1: Int,val x2: Int,val y2: Int,val lower: Int,
        val upper: Int,val capacity: Int,val index: Int)
    data class Waypoint(val x: Int,val y: Int,val level: Int=-1)
    class Plan(val callsign: String,val type: String,val departure: Int,val level: Int,val speedInitial: Int,
        val waypoints: List<Waypoint>,var speed: Int=speedInitial,var delay: Long=0,var offset: Int=0,
        val history: MutableList<String> = mutableListOf()) {
        fun copy()=Plan(callsign,type,departure,level,speedInitial,waypoints,speed,delay,offset,history.toMutableList())
        fun levels()=listOf(level+offset)+waypoints.drop(1).filter {
            it.level>=0
        }.map {
            it.level+offset
        }
    }
    data class Settings(val dh: Int,val dv: Int,val lookahead: Int,val maxDelay: Int,val levelMin: Int,
        val levelMax: Int,val sampleStart: Int,val sampleEnd: Int,val radar: List<Int>,val snapshots: List<Int>,
        val leader: Int,val alert: Int)
    data class Input(val plans: Map<String,Plan>,val types: Map<String,AircraftType>,val sectors: List<Sector>,
        val settings: Settings)
    fun read(): Input {
        val types=File("input/aircraft.txt").readLines().associate {
            val w=it.split(' ');
            w[0] to AircraftType(w[1].toInt(),w[2].toInt(),w[3].toInt())
        };
        val sectors=File("input/sectors.txt").readLines().mapIndexed {
            i,line->val w=line.split(' ');
            Sector(w[0],w[1].toInt(),w[2].toInt(),w[3].toInt(),w[4].toInt(),w[5].toInt(),w[6].toInt(),
                w[7].toInt(),i)
        };
        val parameters=File("input/params.txt").readLines().associate {
            val w=it.split(' ');
            w[0] to w.drop(1).map(String::toInt)
        };
        val separation=parameters.getValue("separation");
        val levels=parameters.getValue("levels");
        val sampling=parameters.getValue("sampling");
        val settings=Settings(separation[0],separation[1],parameters.getValue("lookahead")[0],parameters.getValue("max_delay")[0],
            levels[0],levels[1],sampling[0],sampling[1],parameters.getValue("radar"),parameters.getValue("snapshots"),
            parameters.getValue("leader")[0],parameters.getValue("alert")[0]);
        val plans=sortedMapOf<String,Plan>();
        for(line in File("input/flights.csv").readLines().drop(1)) {
            val w=line.split(',');
            val waypoints=w[5].split(' ').map {
                val a=it.split(':');
                Waypoint(a[0].toInt(),a[1].toInt(),if(a.size==3)a[2].toInt() else -1)
            };
            plans[w[0]]=Plan(w[0],w[1],w[2].toInt(),w[3].toInt(),w[4].toInt(),waypoints)
        };
        return Input(plans,types,sectors,settings)
    }
}
