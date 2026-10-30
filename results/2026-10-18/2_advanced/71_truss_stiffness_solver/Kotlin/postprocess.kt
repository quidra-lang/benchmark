import kotlin.math.abs
object Postprocess {
    data class Result(val name: String,val displacement: DoubleArray,val forces: DoubleArray,
        val reactions: DoubleArray,val external: DoubleArray)
    fun forces(geometry: List<Assembly.Geometry>,properties: List<Assembly.Properties>,displacement: DoubleArray,
        temperature: DoubleArray,removed: Int=-1): DoubleArray {
        val forces=DoubleArray(geometry.size);
        for(m in geometry.indices)if(m!=removed) {
            val g=geometry[m];
            val a=g.dofs;
            val extension=(displacement[a[2]]-displacement[a[0]])*g.cosine+(displacement[a[3]]-displacement[a[1]])*g.sine;
            forces[m]=properties[m].stiffness*extension-temperature[m]
        };
        return forces
    }
    fun reactions(matrix: Array<DoubleArray>,displacement: DoubleArray,force: DoubleArray,restrained: IntArray): DoubleArray {
        val result=DoubleArray(force.size);
        for(row in restrained) {
            var value=0.0;
            for(d in force.indices)value+=matrix[row][d]*displacement[d];
            result[row]=value-force[row]
        };
        return result
    }
    fun vectors(result: Result)=arrayOf(result.displacement,result.forces,result.reactions,
        result.external)
    fun superpose(combination: ModelIo.Combination,results: Map<String,Result>): Result {
        val first=combination.terms.first();
        var source=vectors(results.getValue(first.name));
        val values=Array(4) {
            v->DoubleArray(source[v].size) {
                first.factor*source[v][it]
            }
        };
        for(term in combination.terms.drop(1)) {
            source=vectors(results.getValue(term.name));
            for(v in 0..3)for(i in values[v].indices)values[v][i]+=term.factor*source[v][i]
        };
        return Result(combination.name,values[0],values[1],values[2],values[3])
    }
    fun equilibrium(result: Result,geometry: List<Assembly.Geometry>): Double {
        val residual=DoubleArray(result.external.size) {
            result.external[it]+result.reactions[it]
        };
        for(m in geometry.indices) {
            val g=geometry[m];
            val direction=doubleArrayOf(g.cosine,g.sine,-g.cosine,-g.sine);
            for(i in 0..3)residual[g.dofs[i]]+=result.forces[m]*direction[i]
        };
        var maximum=0.0;
        for(value in residual)maximum=maxOf(maximum,abs(value));
        return maximum
    }
}
