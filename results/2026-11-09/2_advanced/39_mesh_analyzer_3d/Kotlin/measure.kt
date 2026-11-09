import java.util.Locale
import kotlin.math.*

object Measure {
    data class Vec(val x: Long, val y: Long, val z: Long) {
        fun at(i: Int) = if(i==0)x else if(i==1)y else z
        override fun toString() = "$x $y $z"
    }
    fun subtract(a: Vec,b: Vec)=Vec(a.x-b.x,a.y-b.y,a.z-b.z)
    fun add(a: Vec,b: Vec)=Vec(a.x+b.x,a.y+b.y,a.z+b.z)
    fun cross(a: Vec,b: Vec)=Vec(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
    fun dot(a: Vec,b: Vec)=a.x*b.x+a.y*b.y+a.z*b.z
    fun normal(f: ObjIo.Face,p: List<Vec>)=cross(subtract(p[f.v[1]],p[f.v[0]]),subtract(p[f.v[2]],p[f.v[0]]))
    fun determinant(f: ObjIo.Face,p: List<Vec>)=dot(p[f.v[0]],cross(p[f.v[1]],p[f.v[2]]))
    fun length(e: Topology.Edge,p: List<Vec>): Long {
        val d=subtract(p[e.a],p[e.b]);
        return dot(d,d)
    }
    fun area(f: List<ObjIo.Face>,p: List<Vec>): Double {
        var total=0.0;
        for(face in f) {
            val n=normal(face,p);
            total+=sqrt(dot(n,n).toDouble())
        };
        return total/2
    }
    fun volume(ids: List<Int>,f: List<ObjIo.Face>,p: List<Vec>): Long {
        var sum=0L;
        for(i in ids)sum+=determinant(f[i-1],p);
        return sum
    }
    fun fraction(numerator: Long,denominator: Long): String {
        var n=numerator;
        var d=denominator;
        if(d<0) {
            n=-n;
            d=-d
        };
        var a=abs(n);
        var b=d;
        while(b!=0L) {
            val remainder=a%b;
            a=b;
            b=remainder
        };
        n/=a;
        d/=a;
        return if(d==1L)n.toString() else "$n/$d"
    }
    fun real(value: Double)=String.format(Locale.ROOT,"%.3f",if(value==0.0)0.0 else value)
    fun centroid(ids: List<Int>,f: List<ObjIo.Face>,p: List<Vec>,volume: Long): String = (0..2).joinToString(" ") {
        axis->var sum=0L;
        for(i in ids) {
            val face=f[i-1];
            var coordinates=0L;
            for(v in face.v)coordinates+=p[v].at(axis);
            sum+=determinant(face,p)*coordinates
        };
        fraction(sum,4*volume)
    }
    fun angle(f: ObjIo.Face,p: List<Vec>): String {
        var minimum=Long.MAX_VALUE;
        for(k in 0..2) {
            val a=p[f.v[k]];
            val b=p[f.v[(k+1)%3]];
            val c=p[f.v[(k+2)%3]];
            minimum=min(minimum,dot(subtract(b,a),subtract(c,a)))
        };
        return if(minimum<0)"obtuse" else if(minimum==0L)"right" else "acute"
    }
    fun winding(ids: List<Int>,f: List<ObjIo.Face>,p: List<Vec>,point: Vec): Int {
        var total=0.0;
        for(i in ids) {
            val v=f[i-1].v;
            val a=subtract(p[v[0]],point);
            val b=subtract(p[v[1]],point);
            val c=subtract(p[v[2]],point);
            val la=sqrt(dot(a,a).toDouble());
            val lb=sqrt(dot(b,b).toDouble());
            val lc=sqrt(dot(c,c).toDouble());
            val denominator=la*lb*lc+dot(a,b)*lc+dot(b,c)*la+dot(c,a)*lb;
            total+=2*atan2(dot(a,cross(b,c)).toDouble(),denominator)
        };
        return (total/(4*PI)).roundToInt()
    }
    fun bbox(ids: Collection<Int>,p: List<Vec>): LongArray {
        val box=longArrayOf(Long.MAX_VALUE,Long.MAX_VALUE,Long.MAX_VALUE,Long.MIN_VALUE,Long.MIN_VALUE,Long.MIN_VALUE);
        for(i in ids)for(k in 0..2) {
            box[k]=min(box[k],p[i].at(k));
            box[k+3]=max(box[k+3],p[i].at(k))
        };
        return box
    }
}
