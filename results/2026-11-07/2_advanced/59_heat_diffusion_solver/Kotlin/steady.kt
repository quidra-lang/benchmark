import kotlin.math.*

object Steady {
    fun g(s: Heat.Thermal,x: DoubleArray,p: Int): Double {
        var value=0.0;
        for(f in s.faces[p])if(f.neighbor>=0)value+=f.g*x[f.neighbor] else if(f.boundary)value+=f.g*f.theta;
        return value+s.all[p]
    }
    class Iteration(val method: String,val omega: Double) {
        var rate=0.0;
        var error=0.0;
        var residual=0.0;
        lateinit var field: DoubleArray;
        val changes=mutableListOf<Double>();
        val milestones=Array(4) {
            "never"
        };
        var converged=false
    }
    fun iterate(s: Heat.Thermal,settings: Heat.Params,method: String,omega: Double): Iteration {
        val result=Iteration(method,omega);
        val field=DoubleArray(s.mesh.count) {
            settings.initial
        }
        for(k in 1..settings.maximum) {
            val old=field.copyOf()
            if(method=="jacobi")for(p in field.indices)field[p]=g(s,old,p)/s.diagonal[p]
            else for(p in field.indices) {
                val value=g(s,field,p)/s.diagonal[p];
                field[p]=if(method=="gauss_seidel")value else field[p]+omega*(value-field[p])
            }
            var change=0.0;
            for(p in field.indices)change=maxOf(change,abs(field[p]-old[p]));
            result.changes.add(change);
            if(change<settings.tolerance)break
        }
        result.field=field;
        result.converged=result.changes.last()<settings.tolerance
        return result
    }
    fun direct(s: Heat.Thermal,rightSides: List<DoubleArray>): List<DoubleArray> {
        val n=s.mesh.count;
        val w=s.mesh.width;
        val matrix=Array(n) {
            DoubleArray(n)
        };
        val vectors=rightSides.map {
            it.copyOf()
        }
        for(p in 0 until n) {
            matrix[p][p]=s.diagonal[p];
            for(f in s.faces[p])if(f.neighbor>=0)matrix[p][f.neighbor]=-f.g
        }
        for(k in 0 until n)for(i in k+1 until minOf(n,k+w+1)) {
            val f=matrix[i][k]/matrix[k][k];
            matrix[i][k]=0.0;
            for(j in k+1 until minOf(n,k+w+1))matrix[i][j]=matrix[i][j]-f*matrix[k][j];
            for(values in vectors)values[i]=values[i]-f*values[k]
        }
        return vectors.map {
            values->val x=DoubleArray(n);
            for(i in n-1 downTo 0) {
                var value=values[i];
                for(j in i+1 until minOf(n,i+w+1))value-=matrix[i][j]*x[j];
                x[i]=value/matrix[i][i]
            };
            x
        }
    }
    fun residual(s: Heat.Thermal,x: DoubleArray,rhs: DoubleArray): Double {
        var maximum=0.0;
        for(p in x.indices) {
            var value=rhs[p];
            for(f in s.faces[p])if(f.neighbor>=0)value+=f.g*x[f.neighbor];
            value-=s.diagonal[p]*x[p];
            maximum=maxOf(maximum,abs(value))
        };
        return maximum
    }
}
