import kotlin.math.exp

object Kernels {
    data class Point(val x: Double,val y: Double)
    data class Kernel(val name: String,val kind: String,val degree: Int,val gamma: Double,val offset: Double) {
        fun value(a: Point,b: Point): Double {
            if(kind=="linear")return a.x*b.x+a.y*b.y
            if(kind=="poly") {
                val s=gamma*(a.x*b.x+a.y*b.y)+offset;
                var value=1.0;
                repeat(degree) {
                    value*=s
                };
                return value
            }
            val e1=a.x-b.x;
            val e2=a.y-b.y;
            return exp(-gamma*(e1*e1+e2*e2))
        }
        fun description()=if(kind=="linear")"linear" else if(kind=="poly")"poly degree $degree gamma ${Evaluation.fixed(gamma,4)} coef0 ${Evaluation.fixed(offset,4)}" else "rbf gamma ${Evaluation.fixed(gamma,4)}"
        fun matrix(points: List<Point>)=Array(points.size) {
            i->DoubleArray(points.size) {
                j->value(points[i],points[j])
            }
        }
    }
    fun submatrix(matrix: Array<DoubleArray>,indices: List<Int>)=Array(indices.size) {
        i->DoubleArray(indices.size) {
            j->matrix[indices[i]][indices[j]]
        }
    }
}
