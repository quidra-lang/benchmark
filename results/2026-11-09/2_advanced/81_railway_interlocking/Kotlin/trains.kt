import java.io.File
object Trains {
    data class PathPart(val section: String,val start: Int)
    data class Request(val time: Int,val train: String,val route: String)
    data class Plans(val trains: Map<String,Train>,val requests: List<Request>)
    class Stop(f: List<String>) {
        val kind=f[0];
        val section=f[2];
        val dwell=f[3].toInt();
        val scheduledArrival=f[4].toInt();
        val scheduledDeparture=f[5].toInt();
        var arrival: Int?=null;
        var departure: Int?=null
    }
    class Train(f: List<String>,val symbol: Char) {
        val name=f[1];
        val length=f[2].toInt();
        val acceleration=f[3].toInt();
        val deceleration=f[4].toInt();
        val maxSpeed=f[5].toInt();
        val entry=f[6];
        val entryTime=f[7].toInt();
        val entrySpeed=f[8].toInt();
        var exit="";
        var scheduledExit=0;
        var state="WAITING";
        var direction="";
        var boundary: String?=null;
        var stopIndex=0;
        var head=0;
        var speed=0;
        var boundaryCoordinate=0;
        var distance=0;
        var maximumSpeed=0;
        var standing=0;
        var passes=0;
        var entered: Int?=null;
        var exited: Int?=null;
        var dwelling=false;
        var emergency=false;
        var awaitingDeparture: Stop?=null;
        val stops=mutableListOf<Stop>();
        var path=mutableListOf<PathPart>();
        fun nextStop()=stops.getOrNull(stopIndex)
    }
    fun readTrains(): Plans {
        val trains=linkedMapOf<String,Train>();
        val requests=mutableListOf<Request>();
        for(line in File("input/trains.txt").readLines(Charsets.US_ASCII)) {
            val f=line.split(' ');
            when(f[0]) {
                "TRAIN"-> {
                    val train=Train(f,('a'.code+trains.size).toChar());
                    trains[train.name]=train
                };
                "REQUEST"->requests.add(Request(f[3].toInt(),f[1],f[2]));
                "STOP","TURN"->trains.getValue(f[1]).stops.add(Stop(f));
                "EXIT"-> {
                    trains.getValue(f[1]).exit=f[2];
                    trains.getValue(f[1]).scheduledExit=f[3].toInt()
                }
            }
        };
        return Plans(trains,requests)
    }
    fun brakingDistance(speed: Int,deceleration: Int): Int {
        val count=speed/deceleration;
        return count*speed-deceleration*count*(count+1)/2
    }
    fun selectSpeed(train: Train,distance: Int?): Int {
        val low=maxOf(train.speed-train.deceleration,0);
        if(!train.emergency)for(speed in minOf(train.speed+train.acceleration,train.maxSpeed) downTo low)if(distance==null||speed+brakingDistance(speed,
            train.deceleration)<=distance)return speed;
        return low
    }
}
