import kotlin.math.sqrt
object Solver {
    data class Factorization(val lower: Array<DoubleArray>?,val unstable: Int)
    fun cholesky(matrix: Array<DoubleArray>,free: IntArray): Factorization {
        val size=matrix.size;
        val lower=Array(size) {
            DoubleArray(size)
        };
        for(i in 0 until size)for(j in 0..i) {
            var value=matrix[i][j];
            for(h in 0 until j)value-=lower[i][h]*lower[j][h];
            if(j<i)lower[i][j]=value/lower[j][j] else {
                if(value<=0.000000001*matrix[i][i])return Factorization(null,free[i]);
                lower[i][i]=sqrt(value)
            }
        };
        return Factorization(lower,-1)
    }
    fun solve(lower: Array<DoubleArray>,right: DoubleArray): DoubleArray {
        val size=right.size;
        val intermediate=DoubleArray(size);
        val result=DoubleArray(size);
        for(i in 0 until size) {
            var value=right[i];
            for(h in 0 until i)value-=lower[i][h]*intermediate[h];
            intermediate[i]=value/lower[i][i]
        };
        for(i in size-1 downTo 0) {
            var value=intermediate[i];
            for(h in i+1 until size)value-=lower[h][i]*result[h];
            result[i]=value/lower[i][i]
        };
        return result
    }
}
