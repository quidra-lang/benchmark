object Triangulation {
    data class Edge(val a: Int,val b: Int): Comparable<Edge> {
        override fun compareTo(other: Edge): Int {
            val c=a.compareTo(other.a);
            return if(c!=0)c else b.compareTo(other.b)
        }
    }
    data class Triangle(val a: Int,val b: Int,val c: Int): Comparable<Triangle> {
        override fun compareTo(other: Triangle): Int {
            var result=a.compareTo(other.a);
            if(result==0)result=b.compareTo(other.b);
            return if(result!=0)result else c.compareTo(other.c)
        };
        fun sites()=intArrayOf(a,b,c)
    }
    fun key(a: Int,b: Int)=Edge(minOf(a,b),maxOf(a,b))
    fun canonical(a: Int,b: Int,c: Int)=if(a<b&&a<c)Triangle(a,b,c) else if(b<c)Triangle(b,c,a) else Triangle(c,a,b)
    data class Insertion(val kind: String,val containing: Triangle?,val visible: Int,val flips: Int,val triangles: Int,val hull: Int)
    class Model(val points: List<Predicates.Point>) {
        val directed=mutableMapOf<Edge,Int>();
        val initial=if(Predicates.orient(points[1],points[2],points[3])>0)Triangle(1,2,3) else Triangle(1,3,2)
        init {
            add(initial.a,initial.b,initial.c)
        }
        fun add(a: Int,b: Int,c: Int) {
            directed[Edge(a,b)]=c;
            directed[Edge(b,c)]=a;
            directed[Edge(c,a)]=b
        }
        fun remove(a: Int,b: Int,c: Int) {
            directed.remove(Edge(a,b));
            directed.remove(Edge(b,c));
            directed.remove(Edge(c,a))
        }
        fun triangles()=directed.map {
            (edge,opposite)->canonical(edge.a,edge.b,opposite)
        }.toSortedSet().toList()
        fun hullEdges()=directed.keys.filter {
            Edge(it.b,it.a) !in directed
        }.sorted()
        fun insert(site: Int): Insertion {
            val containing=triangles().firstOrNull {
                t->Predicates.orient(points[t.a],points[t.b],points[site])>0&&Predicates.orient(points[t.b],
                    points[t.c],points[site])>0&&Predicates.orient(points[t.c],points[t.a],
                    points[site])>0
            };
            val check=sortedSetOf<Edge>();
            var visible=0;
            if(containing!=null) {
                val a=containing.a;
                val b=containing.b;
                val c=containing.c;
                remove(a,b,c);
                check+=Edge(a,b);
                check+=Edge(b,c);
                check+=Edge(c,a)
            } else {
                for(e in hullEdges())if(Predicates.orient(points[e.a],points[e.b],points[site])<0)check+=Edge(e.b,e.a);
                visible=check.size
            };
            for(e in check)add(e.a,e.b,site);
            var flips=0;
            while(check.isNotEmpty()) {
                val edge=check.first();
                check.remove(edge);
                val a=edge.a;
                val b=edge.b;
                val q=directed[Edge(b,a)];
                if(q!=null&&Predicates.incircle(points[a],points[b],points[site],points[q])>0) {
                    remove(a,b,site);
                    remove(b,a,q);
                    add(a,q,site);
                    add(q,b,site);
                    check+=Edge(a,q);
                    check+=Edge(q,b);
                    flips++
                }
            };
            return Insertion(if(containing==null)"outside" else "inside",containing,visible,flips,directed.size/3,hullEdges().size)
        }
    }
    data class Walk(val path: List<Int>,val outside: Edge?)
    fun walk(query: Predicates.Point,points: List<Predicates.Point>,triangles: List<Triangle>,directed: Map<Edge,Int>): Walk {
        val path=mutableListOf(1);
        while(true) {
            val t=triangles[path.last()-1];
            var moved=false;
            for(e in listOf(Edge(t.a,t.b),Edge(t.b,t.c),Edge(t.c,t.a)))if(Predicates.orient(points[e.a],points[e.b],query)<0) {
                val next=directed[Edge(e.b,e.a)]?:return Walk(path,key(e.a,e.b));
                path+=next;
                moved=true;
                break
            };
            if(!moved)return Walk(path,null)
        }
    }
}
