import kotlin.math.*
object Conflict {
    data class AircraftPair(val first: String,val second: String) {
        val name get()="$first-$second";
        companion object {
            fun of(a: String,b: String)=if(a<b)AircraftPair(a,b) else AircraftPair(b,a)
        }
    }
    data class Loss(val lo: Double,val hi: Double,val tc: Double,val distance: Double,val vertical: Double)
    data class Piece(val a: Trajectory.Segment,val b: Trajectory.Segment,val loss: Loss)
    class Event(val pair: AircraftPair,piece: Piece) {
        var start=piece.loss.lo;
        var end=piece.loss.hi;
        val pieces=mutableListOf(piece);
        var closest=piece;
        var levelA=0.0;
        var levelB=0.0;
        var trackA=0.0;
        var trackB=0.0;
        var angle=0.0;
        var geometry="";
        var severity="";
        var sector="";
        var outcome=""
    }
    val order=compareBy<Event> {
        it.start
    }.thenBy {
        it.pair.first
    }.thenBy {
        it.pair.second
    }
    fun loss(position: Trajectory.Vec,velocity: Trajectory.Vec,t1: Double,t2: Double,horizontal: Double,
        vertical: Double): Loss? {
        val px=position.x;
        val py=position.y;
        val pz=position.z;
        val wx=velocity.x;
        val wy=velocity.y;
        val wz=velocity.z;
        val qa=wx*wx+wy*wy;
        val qb=2*(px*wx+py*wy);
        val qc=(px*px+py*py)-horizontal*horizontal;
        var lo=t1;
        var hi=t2;
        if(qa<1e-12) {
            if(qc>=0)return null
        } else {
            val d=qb*qb-4*qa*qc;
            if(d<=0)return null;
            val root=sqrt(d);
            lo=max(lo,t1+(-qb-root)/(2*qa));
            hi=min(hi,t1+(-qb+root)/(2*qa))
        };
        if(wz==0.0) {
            if(abs(pz)>=vertical)return null
        } else {
            val r1=(-vertical-pz)/wz;
            val r2=(vertical-pz)/wz;
            lo=max(lo,t1+min(r1,r2));
            hi=min(hi,t1+max(r1,r2))
        };
        if(hi-lo<=1e-6)return null;
        var tc=if(qa>=1e-12)t1+(-qb/(2*qa)) else t1;
        tc=min(max(tc,lo),hi);
        val elapsed=tc-t1;
        val ex=px+wx*elapsed;
        val ey=py+wy*elapsed;
        return Loss(lo,hi,tc,sqrt(ex*ex+ey*ey),abs(pz+wz*elapsed))
    }
    fun pair(nameA: String,first: Trajectory.Built,nameB: String,second: Trajectory.Built,dh: Double,
        dv: Double): List<Event> {
        val pieces=mutableListOf<Piece>();
        for(a in first.segments)for(b in second.segments) {
            val t1=max(a.ts,b.ts);
            val t2=min(a.te,b.te);
            if(t1>=t2)continue;
            val loss=loss(Trajectory.position(a,t1)-Trajectory.position(b,t1),a.velocity-b.velocity,t1,
                t2,dh,dv);
            if(loss!=null)pieces.add(Piece(a,b,loss))
        };
        pieces.sortBy {
            it.loss.lo
        };
        val conflicts=mutableListOf<Event>();
        val pair=AircraftPair(nameA,nameB);
        for(piece in pieces) {
            if(conflicts.isEmpty()||piece.loss.lo-conflicts.last().end>1e-6)conflicts.add(Event(pair,
                piece)) else {
                val conflict=conflicts.last();
                conflict.pieces.add(piece);
                conflict.end=piece.loss.hi;
                if(piece.loss.distance<conflict.closest.loss.distance-1e-9)conflict.closest=piece
            }
        };
        return conflicts
    }
    fun all(trajectories: Map<String,Trajectory.Built>,dh: Double,dv: Double): List<Event> {
        val names=trajectories.keys.sorted();
        val result=mutableListOf<Event>();
        for(i in names.indices)for(j in i+1 until names.size) {
            val a=names[i];
            val b=names[j];
            result.addAll(pair(a,trajectories.getValue(a),b,trajectories.getValue(b),dh,dv))
        };
        return result.sortedWith(order)
    }
}
