import kotlin.math.abs

object Predicates {
    data class Point(val x: Long,val y: Long)
    data class Center(val x: Long,val y: Long,val d: Long)
    fun orient(p: Point,q: Point,r: Point)=(q.x-p.x)*(r.y-p.y)-(q.y-p.y)*(r.x-p.x)
    fun d2(p: Point,q: Point): Long {
        val x=p.x-q.x;
        val y=p.y-q.y;
        return x*x+y*y
    }
    fun dot(o: Point,p: Point,q: Point)=(p.x-o.x)*(q.x-o.x)+(p.y-o.y)*(q.y-o.y)
    fun incircle(a: Point,b: Point,c: Point,d: Point): Long {
        val ax=a.x-d.x;
        val ay=a.y-d.y;
        val bx=b.x-d.x;
        val by=b.y-d.y;
        val cx=c.x-d.x;
        val cy=c.y-d.y;
        val aa=ax*ax+ay*ay;
        val bb=bx*bx+by*by;
        val cc=cx*cx+cy*cy;
        return ax*(by*cc-bb*cy)-ay*(bx*cc-bb*cx)+aa*(bx*cy-by*cx)
    }
    fun center(a: Point,b: Point,c: Point): Center {
        val bx=b.x-a.x;
        val by=b.y-a.y;
        val cx=c.x-a.x;
        val cy=c.y-a.y;
        val bb=bx*bx+by*by;
        val cc=cx*cx+cy*cy;
        val d=2*(bx*cy-by*cx);
        return Center(a.x*d+cy*bb-by*cc,a.y*d+bx*cc-cx*bb,d)
    }
    fun gcd(a0: Long,b0: Long): Long {
        var a=abs(a0);
        var b=abs(b0);
        while(b!=0L) {
            val rest=a%b;
            a=b;
            b=rest
        };
        return a
    }
    fun fraction(n0: Long,d0: Long): String {
        val g=gcd(n0,d0);
        val n=n0/g;
        val d=d0/g;
        return if(d==1L)n.toString() else "$n/$d"
    }
    fun reduce(x: Long,y: Long): Point {
        val g=gcd(x,y);
        return Point(x/g,y/g)
    }
}
