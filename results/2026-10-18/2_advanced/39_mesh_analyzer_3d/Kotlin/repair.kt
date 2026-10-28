object Repair {
    data class Snap(val number: Int,val before: Measure.Vec,val after: Measure.Vec)
    data class Removed(val face: ObjIo.Face,val reason: String)
    fun split(polygons: List<ObjIo.Polygon>): List<ObjIo.Face> {
        val result=mutableListOf<ObjIo.Face>();
        for(p in polygons)for(i in 1 until p.v.size-1)result+=ObjIo.Face(result.size+1,p.number,p.line,p.group,intArrayOf(p.v[0],p.v[i],p.v[i+1]));
        return result
    }
    fun snap(vertices: List<Measure.Vec>,spacing: Int,changes: MutableList<Snap>): List<Measure.Vec> {
        val result=mutableListOf(vertices[0]);
        for(i in 1 until vertices.size) {
            val p=vertices[i];
            val q=Measure.Vec(spacing*Math.floorDiv(2*p.x+spacing,2L*spacing),spacing*Math.floorDiv(2*p.y+spacing,2L*spacing),spacing*Math.floorDiv(2*p.z+spacing,2L*spacing));
            result+=q;
            if(p!=q)changes+=Snap(i,p,q)
        };
        return result
    }
    fun representatives(points: List<Measure.Vec>,merge: Boolean): IntArray {
        val owner=mutableMapOf<Measure.Vec,Int>();
        return IntArray(points.size) {
            i->if(i==0)0 else if(merge)owner.getOrPut(points[i]) {
                i
            } else i
        }
    }
    fun clean(triangles: List<ObjIo.Face>,points: List<Measure.Vec>,representatives: IntArray,zero: Boolean,duplicate: Boolean,removed: MutableList<Removed>): MutableList<ObjIo.Face> {
        val result=mutableListOf<ObjIo.Face>();
        val seen=mutableSetOf<List<Int>>();
        for(t in triangles) {
            val f=t.copy(v=t.v.map {
                representatives[it]
            }.toIntArray());
            var reason: String?=null;
            if(f.v.toSet().size<3)reason="repeated" else if(zero&&Measure.normal(f,points)==Measure.Vec(0,0,0))reason="zero_area";
            if(reason==null) {
                val key=f.v.sorted();
                if(duplicate&&key in seen)reason="duplicate" else seen+=key
            };
            if(reason!=null)removed+=Removed(t,reason) else result+=f
        };
        return result
    }
    fun fill(faces: MutableList<ObjIo.Face>,loops: List<Topology.Loop>,maximum: Int,permitted: Set<Int>): Int {
        var count=0;
        for(l in loops) {
            if(l.kind!="coherent"||l.length !in 3..maximum||l.vertices.toSet().size!=l.length||l.component !in permitted)continue;
            l.filled=true;
            for(i in 2 until l.length) {
                faces+=ObjIo.Face(0,0,0,"fill",intArrayOf(l.vertices[0],l.vertices[i],l.vertices[i-1]));
                count++
            }
        };
        return count
    }
}
