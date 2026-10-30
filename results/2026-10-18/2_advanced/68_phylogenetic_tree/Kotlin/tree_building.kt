import java.util.TreeMap
object TreeBuilding {
    data class Edge(val first: Int,val second: Int,val length: Double)
    class Tree(val size: Int) {
        var nextNode=size;
        var negative=0;
        val adjacent=List(2*size+1) {
            TreeMap<Int,Double>()
        };
        fun internal()=nextNode++;
        fun connect(a: Int,b: Int,length: Double=0.0) {
            adjacent[a][b]=length;
            adjacent[b][a]=length
        };
        fun disconnect(a: Int,b: Int): Double {
            val length=adjacent[a].remove(b)!!;
            adjacent[b].remove(a);
            return length
        };
        fun copy(): Tree {
            val copy=Tree(size);
            copy.nextNode=nextNode;
            copy.negative=negative;
            for(i in adjacent.indices)copy.adjacent[i].putAll(adjacent[i]);
            return copy
        };
        fun taxa()=(0 until size).filter {
            adjacent[it].isNotEmpty()
        };
        fun internals()=(size until nextNode).toList();
        fun edges(): List<Edge> {
            val result=mutableListOf<Edge>();
            for(a in 0 until nextNode)for((b,length) in adjacent[a])if(a<b)result.add(Edge(a,
                b,length));
            return result
        };
        fun rooted(outgroup: Int)=Rooted(this,outgroup)
    }
    class Rooted(val tree: Tree,val outgroup: Int) {
        val root=tree.adjacent[outgroup].firstKey();
        val parents=IntArray(tree.nextNode) {
            -1
        };
        val masks=IntArray(tree.nextNode);
        val children=List(tree.nextNode) {
            mutableListOf<Int>()
        };
        val order=mutableListOf<Int>();
        val ingroup: Int;
        init {
            visit(root,-1);
            ingroup=masks[root] xor (1 shl outgroup)
        };
        fun visit(node: Int,parent: Int) {
            parents[node]=parent;
            order.add(node);
            var mask=if(node<tree.size)1 shl node else 0;
            for(child in tree.adjacent[node].keys)if(child!=parent) {
                children[node].add(child);
                visit(child,node);
                mask=mask or masks[child]
            };
            masks[node]=mask
        };
        fun splits()=tree.internals().filter {
            it!=root
        }.map {
            masks[it]
        }.toSet();
        fun branchLengths()=order.filter {
            it!=root
        }.associate {
            (if(it==outgroup)ingroup else masks[it]) to tree.adjacent[it].getValue(parents[it])
        }
    }
    fun star(size: Int,taxa: List<Int>): Tree {
        val tree=Tree(size);
        val root=tree.internal();
        for(taxon in taxa)tree.connect(root,taxon);
        return tree
    }
    fun nj(matrix: Array<DoubleArray>,taxa: List<Int>): Tree {
        var active=taxa.toList();
        val tree=Tree(matrix.size);
        val distances=Array(2*matrix.size+1) {
            DoubleArray(2*matrix.size+1)
        };
        for(i in taxa)for(j in taxa)distances[i][j]=matrix[i][j];
        while(active.size>=4) {
            val r=active.size;
            val totals=DoubleArray(distances.size);
            for(a in active)for(b in active)if(a!=b)totals[a]+=distances[a][b];
            var best=Double.POSITIVE_INFINITY;
            var first=-1;
            var second=-1;
            for(i in active.indices)for(j in i+1 until r) {
                val a=active[i];
                val b=active[j];
                val q=(r-2)*distances[a][b]-totals[a]-totals[b];
                if(q<best) {
                    best=q;
                    first=a;
                    second=b
                }
            };
            val u=tree.internal();
            val distance=distances[first][second];
            val left=distance/2+(totals[first]-totals[second])/(2*(r-2));
            tree.connect(first,u,left);
            tree.connect(second,u,distance-left);
            val remaining=active.filter {
                it!=first&&it!=second
            };
            for(k in remaining) {
                val value=(distances[first][k]+distances[second][k]-distance)/2;
                distances[u][k]=value;
                distances[k][u]=value
            };
            active=remaining+u
        };
        val a=active[0];
        val b=active[1];
        val c=active[2];
        val u=tree.internal();
        val ab=distances[a][b];
        val ac=distances[a][c];
        val bc=distances[b][c];
        tree.connect(a,u,(ab+ac-bc)/2);
        tree.connect(b,u,(ab+bc-ac)/2);
        tree.connect(c,u,(ac+bc-ab)/2);
        for(edge in tree.edges())if(edge.length<0) {
            tree.connect(edge.first,edge.second,0.0);
            tree.negative++
        };
        return tree
    }
    fun paths(tree: Tree,node: Int,parent: Int,unit: Boolean,distances: DoubleArray) {
        for((neighbor,length) in tree.adjacent[node])if(neighbor!=parent) {
            distances[neighbor]=distances[node]+if(unit)1.0 else length;
            paths(tree,neighbor,node,unit,distances)
        }
    }
    fun paths(tree: Tree,start: Int,unit: Boolean=false)=DoubleArray(tree.nextNode).also {
        paths(tree,start,-1,unit,it)
    }
    fun patristic(tree: Tree): Array<DoubleArray> {
        val result=Array(tree.size) {
            DoubleArray(tree.size)
        };
        val taxa=tree.taxa();
        for((i,first) in taxa.withIndex()) {
            val pathValues=paths(tree,first);
            for(second in taxa.drop(i+1)) {
                result[first][second]=pathValues[second];
                result[second][first]=pathValues[second]
            }
        };
        return result
    }
}
