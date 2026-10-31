object Orientation {
    fun directed(f: ObjIo.Face,a: Int,b: Int)=(0..2).any {
        f.v[it]==a&&f.v[(it+1)%3]==b
    }
    fun flip(f: ObjIo.Face) {
        val t=f.v[1];
        f.v[1]=f.v[2];
        f.v[2]=t
    }
    fun inconsistent(faces: List<ObjIo.Face>,edges: Map<Topology.Edge,List<Int>>): List<Topology.Edge> = edges.filter {
        (e,ids)->ids.size==2&&directed(faces[ids[0]-1],e.a,e.b)==directed(faces[ids[1]-1],e.a,e.b)
    }.keys.toList()
    fun repair(faces: List<ObjIo.Face>,edges: Map<Topology.Edge,List<Int>>) {
        val visited=BooleanArray(faces.size+1);
        for(seed in 1..faces.size) {
            if(visited[seed])continue;
            visited[seed]=true;
            val queue=ArrayDeque<Int>();
            queue.addLast(seed);
            while(queue.isNotEmpty()) {
                val current=queue.removeFirst();
                val f=faces[current-1];
                for(k in 0..2) {
                    val a=f.v[k];
                    val b=f.v[(k+1)%3];
                    val ids=edges.getValue(Topology.edge(a,b));
                    if(ids.size!=2)continue;
                    val other=if(ids[0]==current)ids[1] else ids[0];
                    if(visited[other])continue;
                    if(directed(faces[other-1],a,b))flip(faces[other-1]);
                    visited[other]=true;
                    queue.addLast(other)
                }
            }
        }
    }
    fun orientable(faces: List<ObjIo.Face>,mesh: Topology.Mesh): BooleanArray {
        val copied=faces.map {
            it.duplicate()
        };
        repair(copied,mesh.edges);
        val result=BooleanArray(mesh.components.size+1) {
            true
        };
        for(e in inconsistent(copied,mesh.edges))result[mesh.faceComponent[mesh.edges.getValue(e)[0]]]=false;
        return result
    }
}
