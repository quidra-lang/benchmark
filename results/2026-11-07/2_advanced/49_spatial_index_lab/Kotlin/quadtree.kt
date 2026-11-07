object Quadtree {
    val MARKS=listOf("NW","NE","SW","SE")
    class Node(val x: Int,val y: Int,val size: Int) {
        var points=mutableListOf<Dataset.Obj>();
        var children: Array<Node>?=null
    }
    fun destination(node: Node,point: Dataset.Obj): Int {
        val half=node.size/2;
        return (if(point.box.y1>=node.y+half)2 else 0)+(if(point.box.x1>=node.x+half)1 else 0)
    }
    fun insert(node: Node,point: Dataset.Obj,bucket: Int) {
        val children=node.children;
        if(children!=null) {
            insert(children[destination(node,point)],point,bucket);
            return
        };
        node.points+=point;
        node.points.sortBy {
            it.id
        };
        if(node.points.size>bucket) {
            val half=node.size/2;
            node.children=arrayOf(Node(node.x,node.y,half),Node(node.x+half,node.y,half),Node(node.x,node.y+half,half),Node(node.x+half,node.y+half,half));
            val held=node.points;
            node.points=mutableListOf();
            for(p in held)insert(node,p,bucket)
        }
    }
    fun delete(node: Node,point: Dataset.Obj,bucket: Int) {
        val children=node.children;
        if(children==null) {
            node.points.removeAll {
                it.id==point.id
            };
            return
        };
        delete(children[destination(node,point)],point,bucket);
        var total=0;
        for(child in children) {
            if(child.children!=null)return;
            total+=child.points.size
        };
        if(total<=bucket) {
            for(child in children)node.points+=child.points;
            node.points.sortBy {
                it.id
            };
            node.children=null
        }
    }
}
