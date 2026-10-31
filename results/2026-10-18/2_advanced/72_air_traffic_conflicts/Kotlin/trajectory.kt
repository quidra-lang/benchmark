import kotlin.math.*
object Trajectory {
    data class Vec(val x: Double,val y: Double,val z: Double) {
        operator fun minus(other: Vec)=Vec(x-other.x,y-other.y,z-other.z);
        fun component(axis: Int)=when(axis) {
            0->x;
            1->y;
            else->z
        }
    }
    data class Segment(val number: Int,val leg: Int,val phase: String,val ts: Double,val te: Double,val start: Vec,
        val velocity: Vec,val end: Vec)
    data class Passing(val time: Double,val level: Int)
    data class Built(val segments: List<Segment>,val arrival: Double,val length: Double,val waypointTimes: List<Passing>)
    data class Observed(val position: Vec,val segment: Segment)
    fun build(plan: FlightPlans.Plan,types: Map<String,FlightPlans.AircraftType>): Built {
        val segments=mutableListOf<Segment>();
        val times=mutableListOf<Passing>();
        var current=(plan.departure+plan.delay).toDouble();
        var length=0.0;
        var level=plan.level+plan.offset;
        times.add(Passing(current,level));
        val type=types.getValue(plan.type);
        for(leg in 1 until plan.waypoints.size) {
            val a=plan.waypoints[leg-1];
            val b=plan.waypoints[leg];
            val dx=b.x-a.x;
            val dy=b.y-a.y;
            val distance=sqrt((dx*dx+dy*dy).toDouble())/10;
            val duration=distance*3600/plan.speed;
            val vx=(dx/10.0)/duration;
            val vy=(dy/10.0)/duration;
            val x=a.x/10.0;
            val y=a.y/10.0;
            length+=distance;
            val target=if(b.level<0)level else b.level+plan.offset;
            val velocity=Vec(vx,vy,0.0);
            val end=Vec(b.x/10.0,b.y/10.0,target*100.0);
            if(target==level)segments.add(Segment(segments.size+1,leg,"LVL",current,current+duration,
                Vec(x,y,level*100.0),velocity,end)) else {
                val climbing=target>level;
                val rate=if(climbing)type.climb else type.descent;
                val vz=if(climbing)rate/60.0 else -(rate/60.0);
                val change=abs(target.toLong()-level)*6000/rate.toDouble();
                val corner=Vec(x+vx*change,y+vy*change,target*100.0);
                segments.add(Segment(segments.size+1,leg,if(climbing)"CLB" else "DES",current,current+change,
                    Vec(x,y,level*100.0),Vec(vx,vy,vz),corner));
                segments.add(Segment(segments.size+1,leg,"LVL",current+change,current+duration,corner,
                    velocity,end))
            };
            current=current+duration;
            level=target;
            times.add(Passing(current,level))
        };
        return Built(segments,current,length,times)
    }
    fun position(segment: Segment,time: Double): Vec {
        val elapsed=time-segment.ts;
        return Vec(segment.start.x+segment.velocity.x*elapsed,segment.start.y+segment.velocity.y*elapsed,
            segment.start.z+segment.velocity.z*elapsed)
    }
    fun active(trajectory: Built,time: Double): Segment? {
        if(!(trajectory.segments.first().ts<=time&&time<trajectory.segments.last().te))return null;
        return trajectory.segments.firstOrNull {
            it.ts<=time&&time<it.te
        }
    }
    fun current(trajectory: Built,time: Double): Observed? {
        val segment=active(trajectory,time)?:return null;
        return Observed(position(segment,time),segment)
    }
}
