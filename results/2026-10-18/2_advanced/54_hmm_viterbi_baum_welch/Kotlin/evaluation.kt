import kotlin.math.abs

object Evaluation {
    data class Run(val state: Int,val start: Int,val end: Int)
    data class Interval(val start: Int,val end: Int) {
        fun length()=end-start+1
    }
    fun fraction(numerator0: Long,denominator0: Long): String {
        if(denominator0==0L)return "-";
        val numerator=if(denominator0<0)-numerator0 else numerator0;
        val denominator=abs(denominator0);
        var a=abs(numerator);
        var b=denominator;
        while(b!=0L) {
            val r=a%b;
            a=b;
            b=r
        };
        return "${numerator/a}/${denominator/a}"
    }
    fun fraction(n: Int,d: Int)=fraction(n.toLong(),d.toLong())
    fun accumulate(matrix: Array<IntArray>,truth: IntArray,prediction: IntArray) {
        for(i in truth.indices)matrix[truth[i]][prediction[i]]++
    }
    fun correct(a: IntArray,b: IntArray)=a.indices.count {
        a[it]==b[it]
    }
    fun matrix(states: CharArray,matrix: Array<IntArray>): List<String> {
        val width=matrix.maxOf {
            row->row.maxOf {
                it.toString().length
            }
        };
        val out=mutableListOf(" "+states.joinToString("") {
            " "+it.toString().padStart(width)
        });
        for(i in states.indices)out+=states[i].toString()+matrix[i].joinToString("") {
            " "+it.toString().padStart(width)
        };
        return out
    }
    fun metrics(states: CharArray,matrix: Array<IntArray>): List<String> {
        val k=states.size;
        val rows=LongArray(k);
        val columns=LongArray(k);
        var total=0L;
        var correct=0L;
        var expected=0L;
        for(i in 0 until k)for(j in 0 until k) {
            rows[i]+=matrix[i][j];
            columns[j]+=matrix[i][j];
            total+=matrix[i][j]
        };
        for(i in 0 until k) {
            correct+=matrix[i][i];
            expected+=rows[i]*columns[i]
        };
        val out=mutableListOf("ACCURACY ${fraction(correct,total)}","KAPPA ${fraction(total*correct-expected,total*total-expected)}");
        for(i in 0 until k)out+="STATE ${states[i]} precision ${fraction(matrix[i][i].toLong(),columns[i])} recall ${fraction(matrix[i][i].toLong(),rows[i])} f1 ${fraction(2L*matrix[i][i],columns[i]+rows[i])}";
        return out
    }
    fun runs(path: IntArray): List<Run> {
        val result=mutableListOf<Run>();
        var start=0;
        for(t in 1..path.size)if(t==path.size||path[t]!=path[start]) {
            result+=Run(path[start],start+1,t);
            start=t
        };
        return result
    }
    fun overlap(a: Interval,b: Interval)=a.start<=b.end&&b.start<=a.end
    fun regions(predicted: List<Interval>,truth: List<Interval>)=intArrayOf(predicted.size,truth.size,predicted.count {
        p->truth.any {
            overlap(p,it)
        }
    },truth.count {
        q->predicted.any {
            overlap(it,q)
        }
    })
    fun boundaries(path: IntArray)=(1 until path.size).filter {
        path[it]!=path[it-1]
    }.map {
        it+1
    }
    fun boundaryMatches(predicted: IntArray,truth: IntArray,tolerance: Int): IntArray {
        val a=boundaries(predicted);
        val b=boundaries(truth);
        return intArrayOf(a.size,b.size,a.count {
            p->b.any {
                abs(p-it)<=tolerance
            }
        },b.count {
            q->a.any {
                abs(it-q)<=tolerance
            }
        })
    }
}
