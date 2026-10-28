object Voronoi {
    data class Vertex(val center: Predicates.Center,val r2: Double,val position: String)
    data class RealPoint(val x: Double,val y: Double)
    fun radius2(a: Predicates.Point,b: Predicates.Point,c: Predicates.Point): Double {
        val area=Predicates.orient(a,b,c);
        return ((Predicates.d2(a,b).toDouble()*Predicates.d2(b,c))*Predicates.d2(c,a))/((4.0*area)*area)
    }
    fun position(v: Predicates.Center,hull: List<Int>,points: List<Predicates.Point>): String {
        var on=false;
        for(i in hull.indices) {
            val a=points[hull[i]];
            val b=points[hull[(i+1)%hull.size]];
            val sigma=(b.x-a.x)*(v.y-a.y*v.d)-(b.y-a.y)*(v.x-a.x*v.d);
            if(sigma<0)return "outside";
            if(sigma==0L)on=true
        };
        return if(on)"on" else "inside"
    }
    fun outward(a: Predicates.Point,b: Predicates.Point)=Predicates.reduce(b.y-a.y,a.x-b.x)
    fun neighbors(site: Int,adjacent: List<Int>,directed: Map<Triangulation.Edge,Int>,next: Int?): List<Int> {
        val start=next?:adjacent.min();
        val result=mutableListOf<Int>();
        var current=start;
        while(true) {
            result+=current;
            val following=directed[Triangulation.Edge(site,current)];
            if(following==null||following==start)break;
            current=following
        };
        return result
    }
    fun area(site: Int,vertexIds: List<Int>,vertices: List<Vertex>,points: List<Predicates.Point>): Double {
        val origin=points[site];
        var sum=0.0;
        for(i in vertexIds.indices) {
            val a=vertices[vertexIds[i]-1].center;
            val b=vertices[vertexIds[(i+1)%vertexIds.size]-1].center;
            val u=a.x.toDouble()/a.d-origin.x;
            val w=a.y.toDouble()/a.d-origin.y;
            val un=b.x.toDouble()/b.d-origin.x;
            val wn=b.y.toDouble()/b.d-origin.y;
            sum+=u*wn-un*w
        };
        return sum/2
    }
    fun clipped(site: Int,neighbors: List<Int>,points: List<Predicates.Point>): Double {
        var polygon=listOf(RealPoint(0.0,0.0),RealPoint(1000.0,0.0),RealPoint(1000.0,1000.0),RealPoint(0.0,1000.0));
        val s=points[site];
        for(neighbor in neighbors) {
            val t=points[neighbor];
            val c1=2*(t.x-s.x);
            val c2=2*(t.y-s.y);
            val c3=t.x*t.x+t.y*t.y-s.x*s.x-s.y*s.y;
            val next=mutableListOf<RealPoint>();
            for(i in polygon.indices) {
                val a=polygon[i];
                val b=polygon[(i+1)%polygon.size];
                val fa=c1*a.x+c2*a.y-c3;
                val fb=c1*b.x+c2*b.y-c3;
                if(fa<=0)next+=a;
                if(fa<0&&fb>0||fb<0&&fa>0) {
                    val lambda=fa/(fa-fb);
                    next+=RealPoint(a.x+(b.x-a.x)*lambda,a.y+(b.y-a.y)*lambda)
                }
            };
            polygon=next
        };
        var sum=0.0;
        for(i in polygon.indices) {
            val a=polygon[i];
            val b=polygon[(i+1)%polygon.size];
            sum+=a.x*b.y-b.x*a.y
        };
        return sum/2
    }
}
