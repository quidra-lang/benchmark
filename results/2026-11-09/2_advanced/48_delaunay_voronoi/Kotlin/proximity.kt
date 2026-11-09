import kotlin.math.sqrt

object Proximity {
    class Sets(n: Int) {
        val parent=IntArray(n+1) {
            it
        };
        val size=IntArray(n+1) {
            1
        };
        var count=n;
        fun find(i0: Int): Int {
            var i=i0;
            while(parent[i]!=i) {
                parent[i]=parent[parent[i]];
                i=parent[i]
            };
            return i
        };
        fun union(a0: Int,b0: Int): Boolean {
            var a=find(a0);
            var b=find(b0);
            if(a==b)return false;
            if(size[a]<size[b]) {
                val swap=a;
                a=b;
                b=swap
            };
            parent[b]=a;
            size[a]+=size[b];
            count--;
            return true
        }
    }
    fun nearest(points: List<Predicates.Point>,neighbors: List<List<Int>>): IntArray {
        val result=IntArray(points.size);
        for(s in 1 until points.size) {
            var best=0;
            var distance=Long.MAX_VALUE;
            for(t in neighbors[s]) {
                val candidate=Predicates.d2(points[s],points[t]);
                if(candidate<distance||candidate==distance&&t<best) {
                    best=t;
                    distance=candidate
                }
            };
            result[s]=best
        };
        return result
    }
    fun components(nearest: IntArray): List<List<Int>> {
        val sets=Sets(nearest.size-1)
        for(s in 1 until nearest.size)sets.union(s,nearest[s])
        val groups=mutableMapOf<Int,MutableList<Int>>()
        for(s in 1 until nearest.size) {
            val group=groups.getOrPut(sets.find(s)) { mutableListOf() }
            group.add(s)
        }
        return groups.values.sortedBy { it[0] }
    }
    fun mst(points: List<Predicates.Point>,edges: List<Triangulation.Edge>): List<Triangulation.Edge> {
        val ordered=edges.sortedWith(compareBy<Triangulation.Edge> {
            Predicates.d2(points[it.a],points[it.b])
        }.thenBy {
            it
        });
        val sets=Sets(points.size-1);
        return ordered.filter {
            sets.union(it.a,it.b)
        }
    }
    fun gabriel(points: List<Predicates.Point>,edge: Triangulation.Edge,directed: Map<Triangulation.Edge,Int>): Boolean {
        for(e in listOf(edge,Triangulation.Edge(edge.b,edge.a))) {
            val q=directed[e];
            if(q!=null&&Predicates.dot(points[q],points[edge.a],points[edge.b])<=0)return false
        };
        return true
    }
    fun rng(points: List<Predicates.Point>,edge: Triangulation.Edge): Boolean {
        val length=Predicates.d2(points[edge.a],points[edge.b]);
        for(k in 1 until points.size)if(Predicates.d2(points[edge.a],points[k])<length&&Predicates.d2(points[edge.b],points[k])<length)return false;
        return true
    }
    data class Route(val sites: List<Int>,val length: Double)
    fun route(points: List<Predicates.Point>,neighbors: List<List<Int>>,start: Int,target: Int): Route {
        val path=mutableListOf(start);
        var length=0.0;
        var current=start;
        while(current!=target) {
            var best=0;
            var distance=Long.MAX_VALUE;
            for(t in neighbors[current]) {
                val candidate=Predicates.d2(points[t],points[target]);
                if(candidate<distance||candidate==distance&&t<best) {
                    best=t;
                    distance=candidate
                }
            };
            length+=sqrt(Predicates.d2(points[current],points[best]).toDouble());
            path+=best;
            current=best
        };
        return Route(path,length)
    }
    data class Paths(val distance: DoubleArray,val previous: IntArray) {
        fun path(target: Int): List<Int> {
            val result=mutableListOf<Int>();
            var current=target;
            while(current!=0) {
                result+=current;
                current=previous[current]
            };
            result.reverse();
            return result
        }
    }
    fun dijkstra(points: List<Predicates.Point>,neighbors: List<List<Int>>,start: Int): Paths {
        val n=points.size-1;
        val distance=DoubleArray(n+1) {
            Double.POSITIVE_INFINITY
        };
        val previous=IntArray(n+1);
        val done=BooleanArray(n+1);
        distance[start]=0.0;
        for(step in 0 until n) {
            var site=0;
            for(s in 1..n)if(!done[s]&&(site==0||distance[s]<distance[site]))site=s;
            done[site]=true;
            for(t in neighbors[site]) {
                val candidate=distance[site]+sqrt(Predicates.d2(points[site],points[t]).toDouble());
                if(candidate<distance[t]) {
                    distance[t]=candidate;
                    previous[t]=site
                }
            }
        };
        return Paths(distance,previous)
    }
}
