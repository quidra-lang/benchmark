object Kdtree {
    class Node(var point: Dataset.Obj,depth: Int) {
        val axis=depth%2;
        var left: Node?=null;
        var right: Node?=null
    }
    fun compare(a: Dataset.Obj,b: Dataset.Obj,axis: Int): Int {
        val first=if(axis==0)a.box.x1 else a.box.y1;
        val second=if(axis==0)b.box.x1 else b.box.y1;
        var result=first.compareTo(second);
        if(result==0)result=(if(axis==0)a.box.y1 else a.box.x1).compareTo(if(axis==0)b.box.y1 else b.box.x1);
        return if(result!=0)result else a.id.compareTo(b.id)
    }
    fun build(points: List<Dataset.Obj>,depth: Int): Node? {
        if(points.isEmpty())return null;
        val sorted=points.sortedWith(Comparator {
            a,b->compare(a,b,depth%2)
        });
        val middle=sorted.size/2;
        val node=Node(sorted[middle],depth);
        node.left=build(sorted.subList(0,middle),depth+1);
        node.right=build(sorted.subList(middle+1,sorted.size),depth+1);
        return node
    }
    fun insert(node: Node?,point: Dataset.Obj,depth: Int): Node {
        if(node==null)return Node(point,depth);
        if(compare(point,node.point,node.axis)<0)node.left=insert(node.left,point,depth+1) else node.right=insert(node.right,point,depth+1);
        return node
    }
    fun minimum(node: Node,axis: Int): Dataset.Obj {
        if(node.axis==axis)return node.left?.let {
            minimum(it,axis)
        }
        ?:node.point;
        var best=node.point;
        node.left?.let {
            val candidate=minimum(it,axis);
            if(compare(candidate,best,axis)<0)best=candidate
        };
        node.right?.let {
            val candidate=minimum(it,axis);
            if(compare(candidate,best,axis)<0)best=candidate
        };
        return best
    }
    fun delete(node: Node,point: Dataset.Obj): Node? {
        if(node.point.id==point.id) {
            val right=node.right;
            val left=node.left;
            if(right!=null) {
                val replacement=minimum(right,node.axis);
                node.point=replacement;
                node.right=delete(right,replacement);
                return node
            };
            if(left!=null) {
                val replacement=minimum(left,node.axis);
                node.point=replacement;
                node.right=delete(left,replacement);
                node.left=null;
                return node
            };
            return null
        };
        if(compare(point,node.point,node.axis)<0)node.left=delete(node.left!!,point) else node.right=delete(node.right!!,point);
        return node
    }
}
