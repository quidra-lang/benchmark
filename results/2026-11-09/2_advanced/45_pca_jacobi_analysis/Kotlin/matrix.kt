import kotlin.math.*

object Matrix {
    fun identity(n: Int)=Array(n) {
        i->DoubleArray(n) {
            j->if(i==j)1.0 else 0.0
        }
    }
    fun copy(a: Array<DoubleArray>)=Array(a.size) {
        a[it].copyOf()
    }
    fun column(a: Array<DoubleArray>,k: Int)=DoubleArray(a.size) {
        a[it][k]
    }
    fun sum(x: DoubleArray): Double {
        var result=0.0;
        for(v in x)result+=v;
        return result
    }
    fun dot(a: DoubleArray,b: DoubleArray): Double {
        var result=0.0;
        for(j in a.indices)result+=a[j]*b[j];
        return result
    }
    fun multiply(a: Array<DoubleArray>,x: DoubleArray)=DoubleArray(a.size) {
        dot(a[it],x)
    }
    fun length(x: DoubleArray)=sqrt(dot(x,x))
    fun normalize(x: DoubleArray) {
        val length=length(x);
        for(j in x.indices)x[j]/=length
    }
    fun orient(x: DoubleArray) {
        var largest=0;
        for(j in 1 until x.size)if(abs(x[j])>abs(x[largest]))largest=j;
        if(x[largest]<0)for(j in x.indices)x[j]=-x[j]
    }
    fun difference(a: DoubleArray,b: DoubleArray): Double {
        var result=0.0;
        for(j in a.indices)result=maxOf(result,abs(a[j]-b[j]));
        return result
    }
    fun deflate(a: Array<DoubleArray>,value: Double,x: DoubleArray) {
        for(i in x.indices)for(j in x.indices)a[i][j]-=value*x[i]*x[j]
    }
    data class Inverse(val matrix: Array<DoubleArray>,val determinant: Double)
    fun inverse(a: Array<DoubleArray>): Inverse {
        val n=a.size;
        val augmented=Array(n) {
            DoubleArray(2*n)
        };
        for(i in 0 until n) {
            for(j in 0 until n)augmented[i][j]=a[i][j];
            augmented[i][n+i]=1.0
        };
        var determinant=1.0;
        for(k in 0 until n) {
            val pivot=augmented[k][k];
            determinant*=pivot;
            for(h in 0 until 2*n)augmented[k][h]/=pivot;
            for(i in 0 until n)if(i!=k) {
                val gamma=augmented[i][k];
                for(h in 0 until 2*n)augmented[i][h]-=gamma*augmented[k][h]
            }
        };
        return Inverse(Array(n) {
            i->DoubleArray(n) {
                j->augmented[i][n+j]
            }
        },determinant)
    }
}
