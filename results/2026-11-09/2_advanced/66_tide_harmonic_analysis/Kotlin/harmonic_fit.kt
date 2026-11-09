import kotlin.math.*
object HarmonicFit {
    const val PI=3.141592653589793
    data class Constant(val a: Double,val b: Double,val amplitude: Double,val phase: Double)
    data class Model(val selected: List<Records.Constituent>,val coefficients: DoubleArray,val inverse: Array<DoubleArray>,val constants: List<Constant>)
    fun angle(speed: Double,time: Double): Double {
        val d=speed*time;
        val d2=d-360*floor(d/360);
        return d2*PI/180
    }
    fun regressors(t: Double,selected: List<Records.Constituent>): DoubleArray {
        val x=DoubleArray(2*selected.size+1);
        x[0]=1.0;
        for(k in selected.indices) {
            val angle=angle(selected[k].speed,t);
            x[2*k+1]=cos(angle);
            x[2*k+2]=sin(angle)
        };
        return x
    }
    fun fit(values: DoubleArray,times: List<Int>,selected: List<Records.Constituent>): Model {
        val p=2*selected.size+1;
        val a=Array(p) {
            DoubleArray(p)
        };
        val y=DoubleArray(p);
        for(t in times) {
            val x=regressors(t.toDouble(),selected);
            for(i in 0 until p) {
                y[i]+=x[i]*values[t];
                for(j in 0 until p)a[i][j]+=x[i]*x[j]
            }
        };
        val m=Array(p) {
            DoubleArray(2*p+1)
        };
        for(i in 0 until p) {
            a[i].copyInto(m[i]);
            m[i][p]=y[i];
            m[i][p+1+i]=1.0
        };
        for(j in 0 until p) {
            var pivot=j;
            for(i in j+1 until p)if(abs(m[i][j])>abs(m[pivot][j]))pivot=i;
            if(pivot!=j) {
                val row=m[j];
                m[j]=m[pivot];
                m[pivot]=row
            };
            for(i in j+1 until p) {
                val f=m[i][j]/m[j][j];
                for(c in j..2*p)m[i][c]-=f*m[j][c]
            }
        };
        val solutions=Array(p+1) {
            DoubleArray(p)
        };
        for(c in p..2*p) {
            val sol=solutions[c-p];
            for(i in p-1 downTo 0) {
                var sum=m[i][c];
                for(j in i+1 until p)sum-=m[i][j]*sol[j];
                sol[i]=sum/m[i][i]
            }
        };
        val inverse=Array(p) {
            i->DoubleArray(p) {
                j->solutions[j+1][i]
            }
        };
        val coefficients=solutions[0];
        val constants=mutableListOf<Constant>();
        for(k in selected.indices) {
            val aa=coefficients[2*k+1];
            val bb=coefficients[2*k+2];
            val amplitude=sqrt(aa*aa+bb*bb);
            var phase=atan2(bb,aa)*180/PI;
            if(phase<0)phase+=360;
            constants.add(Constant(aa,bb,amplitude,phase))
        };
        return Model(selected,coefficients,inverse,constants)
    }
}
