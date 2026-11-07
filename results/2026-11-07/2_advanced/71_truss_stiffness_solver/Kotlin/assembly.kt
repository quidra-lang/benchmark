import kotlin.math.sqrt
object Assembly {
    data class Geometry(val length: Double,val cosine: Double,val sine: Double,val dofs: IntArray)
    data class Properties(val area: Double,val inertia: Double,val young: Double,val yieldStress: Double,
        val density: Double,val expansion: Double,val stiffness: Double)
    data class Loading(val external: DoubleArray,val total: DoubleArray,val temperature: DoubleArray,
        val settlement: Boolean)
    fun geometry(nodes: List<ModelIo.Node>,members: List<ModelIo.Member>,nodeDofs: Array<IntArray>)=members.map {
        member->val a=nodes[member.start];
        val b=nodes[member.end];
        val dx=b.x-a.x;
        val dy=b.y-a.y;
        val length=sqrt((dx*dx+dy*dy).toDouble());
        Geometry(length,dx/length,dy/length,nodeDofs[member.start]+nodeDofs[member.end])
    }
    fun properties(model: ModelIo.Model,choices: IntArray,geometry: List<Geometry>)=model.members.mapIndexed {
        m,member->val section=model.sections[choices[m]];
        val material=model.materials[member.material];
        Properties(section.area,section.inertia,material.young,material.yieldStress,material.density,
            material.expansion,material.young*section.area/geometry[m].length)
    }
    fun weight(p: Properties,g: Geometry)=p.density*9.81*p.area*g.length/1000000000
    fun stiffness(p: Properties,g: Geometry): Array<DoubleArray> {
        val k=p.stiffness;
        val c=g.cosine;
        val s=g.sine;
        val xx=k*(c*c);
        val xy=k*(c*s);
        val yy=k*(s*s);
        return arrayOf(doubleArrayOf(xx,xy,-xx,-xy),doubleArrayOf(xy,yy,-xy,-yy),doubleArrayOf(-xx,
            -xy,xx,xy),doubleArrayOf(-xy,-yy,xy,yy))
    }
    fun assemble(geometry: List<Geometry>,properties: List<Properties>,degrees: Int,removed: Int=-1): Array<DoubleArray> {
        val matrix=Array(degrees) {
            DoubleArray(degrees)
        };
        for(m in geometry.indices)if(m!=removed) {
            val shape=geometry[m];
            val local=stiffness(properties[m],shape);
            for(i in 0..3)for(j in 0..3)matrix[shape.dofs[i]][shape.dofs[j]]+=local[i][j]
        };
        return matrix
    }
    fun loads(loadCase: ModelIo.LoadCase,geometry: List<Geometry>,properties: List<Properties>,
        nodeDofs: Array<IntArray>,degrees: Int,removed: Int=-1): Loading {
        val external=DoubleArray(degrees);
        val thermal=DoubleArray(degrees);
        val temperature=DoubleArray(geometry.size);
        var settlement=false;
        for(load in loadCase.lines)when(load.kind) {
            "FORCE"-> {
                external[nodeDofs[load.index][0]]+=load.first*1000;
                external[nodeDofs[load.index][1]]+=load.second*1000
            };
            "TEMPERATURE"-> {
                val m=load.index;
                if(m!=removed) {
                    val p=properties[m];
                    val g=geometry[m];
                    val force=p.young*p.area*p.expansion*load.first;
                    temperature[m]=force;
                    val direction=doubleArrayOf(-g.cosine,-g.sine,g.cosine,g.sine);
                    for(i in 0..3)thermal[g.dofs[i]]+=force*direction[i]
                }
            };
            "SELFWEIGHT"-> {
                for(m in geometry.indices)if(m!=removed) {
                    val g=geometry[m];
                    val weight=Assembly.weight(properties[m],g);
                    external[g.dofs[1]]-=weight/2;
                    external[g.dofs[3]]-=weight/2
                }
            };
            "SETTLEMENT"->settlement=true
        };
        return Loading(external,DoubleArray(degrees) {
            external[it]+thermal[it]
        },temperature,settlement)
    }
}
