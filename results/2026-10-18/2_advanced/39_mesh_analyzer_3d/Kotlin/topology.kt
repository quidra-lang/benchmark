import java.util.TreeMap
import java.util.TreeSet

object Topology {
    data class Edge(val a: Int,val b: Int): Comparable<Edge> {
        override fun compareTo(other: Edge): Int {
            val c=a.compareTo(other.a);
            return if(c!=0)c else b.compareTo(other.b)
        }
        override fun toString()="$a $b"
    }
    fun edge(a: Int,b: Int)=Edge(minOf(a,b),maxOf(a,b))
    class Component(val number: Int,val faces: List<Int>) {
        val vertices=sortedSetOf<Int>();
        val edges=mutableListOf<Edge>();
        val boundary=mutableListOf<Edge>();
        val nonmanifold=mutableListOf<Edge>();
        val nonmanifoldVertices=mutableListOf<Int>()
    }
    class Mesh(val faceComponent: IntArray) {
        val edges=sortedMapOf<Edge,MutableList<Int>>();
        val components=mutableListOf<Component>();
        val fans=sortedMapOf<Int,List<List<Int>>>();
        val nonmanifoldVertices=mutableListOf<Int>();
        val neighbors=sortedMapOf<Int,java.util.SortedSet<Int>>()
    }
    fun parts(remaining: java.util.SortedSet<Int>,neighbors: Map<Int,java.util.SortedSet<Int>>): List<List<Int>> {
        val result=mutableListOf<List<Int>>();
        while(remaining.isNotEmpty()) {
            val seed=remaining.first();
            remaining.remove(seed);
            val queue=ArrayDeque<Int>();
            queue.addLast(seed);
            val part=mutableListOf<Int>();
            while(queue.isNotEmpty()) {
                val f=queue.removeFirst();
                part+=f;
                for(n in neighbors[f].orEmpty())if(remaining.remove(n))queue.addLast(n)
            };
            result+=part.sorted()
        };
        return result
    }
    fun analyze(faces: List<ObjIo.Face>): Mesh {
        val mesh=Mesh(IntArray(faces.size+1));
        val adjacency=mutableMapOf<Int,java.util.SortedSet<Int>>();
        val remaining=sortedSetOf<Int>()
        for(i in 1..faces.size) {
            remaining+=i;
            adjacency[i]=sortedSetOf();
            val v=faces[i-1].v;
            for(k in 0..2)mesh.edges.getOrPut(edge(v[k],v[(k+1)%3])) {
                mutableListOf()
            }
            +=i
        }
        for((e,ids) in mesh.edges) {
            mesh.neighbors.getOrPut(e.a) {
                sortedSetOf()
            }
            +=e.b;
            mesh.neighbors.getOrPut(e.b) {
                sortedSetOf()
            }
            +=e.a;
            for(i in ids)adjacency.getValue(i).addAll(ids)
        }
        for(ids in parts(remaining,adjacency)) {
            val c=Component(mesh.components.size+1,ids);
            for(i in ids) {
                mesh.faceComponent[i]=c.number;
                c.vertices.addAll(faces[i-1].v.toList())
            };
            for((e,adjacent) in mesh.edges)if(adjacent[0] in ids) {
                c.edges+=e;
                if(adjacent.size==1)c.boundary+=e;
                if(adjacent.size>=3)c.nonmanifold+=e
            };
            mesh.components+=c
        }
        for(v in mesh.neighbors.keys) {
            val links=mutableMapOf<Int,java.util.SortedSet<Int>>();
            val incident=sortedSetOf<Int>();
            for(i in 1..faces.size)if(v in faces[i-1].v) {
                incident+=i;
                links[i]=sortedSetOf()
            };
            for((e,ids) in mesh.edges)if(e.a==v||e.b==v)for(i in ids)links.getValue(i).addAll(ids);
            val fans=parts(incident,links);
            mesh.fans[v]=fans;
            if(fans.size>=2)mesh.nonmanifoldVertices+=v
        }
        for(c in mesh.components)for(v in c.vertices)if(mesh.fans.getValue(v).count {
            mesh.faceComponent[it[0]]==c.number
        }
        >=2)c.nonmanifoldVertices+=v
        return mesh
    }
    class Loop(val number: Int,val component: Int,val length: Int,val kind: String,val vertices: MutableList<Int>) {
        var filled=false
    }
    fun loops(faces: List<ObjIo.Face>,mesh: Mesh): List<Loop> {
        val result=mutableListOf<Loop>();
        for(c in mesh.components) {
            val unused=TreeSet(c.boundary);
            while(unused.isNotEmpty()) {
                val first=unused.first();
                unused.remove(first);
                val sequence=mutableListOf(first.a,first.b);
                var current=first.b
                while(current!=first.a) {
                    var chosen: Edge?=null;
                    var other=Int.MAX_VALUE;
                    for(e in unused) {
                        val n=if(e.a==current)e.b else if(e.b==current)e.a else Int.MAX_VALUE;
                        if(n<other) {
                            other=n;
                            chosen=e
                        }
                    };
                    if(chosen==null)break;
                    unused.remove(chosen);
                    sequence+=other;
                    current=other
                }
                var kind="open";
                var length=sequence.size-1;
                if(current==first.a) {
                    sequence.removeAt(sequence.lastIndex);
                    length=sequence.size;
                    var forward=0;
                    for(i in 0 until length) {
                        val a=sequence[i];
                        val b=sequence[(i+1)%length];
                        val f=mesh.edges.getValue(edge(a,b))[0];
                        if(Orientation.directed(faces[f-1],a,b))forward++
                    };
                    kind=if(forward==0||forward==length)"coherent" else "mixed";
                    if(forward==0)sequence.subList(1,sequence.size).reverse()
                };
                result+=Loop(result.size+1,c.number,length,kind,sequence)
            }
        };
        return result
    }
}
