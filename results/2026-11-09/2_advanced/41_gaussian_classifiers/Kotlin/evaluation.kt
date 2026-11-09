import kotlin.math.abs

object Evaluation {
    data class Fraction(val n: Long,val d: Long)
    fun fraction(n: Long,d: Long): Fraction? {
        if(d==0L)return null;
        var a=abs(n);
        var b=d;
        while(b!=0L) {
            val remainder=a%b;
            a=b;
            b=remainder
        };
        return Fraction(n/a,d/a)
    }
    fun add(a: Fraction,b: Fraction)=fraction(a.n*b.d+b.n*a.d,a.d*b.d)!!
    class Measures(classes: Int) {
        val matrix=Array(classes) {
            IntArray(classes)
        };
        val support=IntArray(classes);
        val predicted=IntArray(classes);
        var correct=0;
        var accuracy: Fraction?=null;
        var balanced: Fraction?=null;
        var kappa: Fraction?=null;
        val recall=arrayOfNulls<Fraction>(classes);
        val precision=arrayOfNulls<Fraction>(classes);
        val f1=arrayOfNulls<Fraction>(classes);
        var macro=0.0
    }
    fun measures(rows: List<Dataset.Row>,predictions: IntArray,classes: Int): Measures {
        val m=Measures(classes);
        for(i in rows.indices)m.matrix[rows[i].y][predictions[i]]++;
        for(a in 0 until classes)for(b in 0 until classes) {
            m.support[a]+=m.matrix[a][b];
            m.predicted[b]+=m.matrix[a][b]
        };
        var recallSum=Fraction(0,1);
        var expected=0L;
        for(k in 0 until classes) {
            m.correct+=m.matrix[k][k];
            m.recall[k]=fraction(m.matrix[k][k].toLong(),m.support[k].toLong());
            m.precision[k]=fraction(m.matrix[k][k].toLong(),m.predicted[k].toLong());
            m.f1[k]=fraction(2L*m.matrix[k][k],(m.support[k]+m.predicted[k]).toLong());
            recallSum=add(recallSum,m.recall[k]!!);
            expected+=m.support[k].toLong()*m.predicted[k];
            m.macro+=2.0*m.matrix[k][k]/(m.support[k]+m.predicted[k])
        };
        m.macro/=classes.toDouble();
        m.accuracy=fraction(m.correct.toLong(),rows.size.toLong());
        m.balanced=fraction(recallSum.n,recallSum.d*classes);
        m.kappa=fraction(rows.size.toLong()*m.correct-expected,rows.size.toLong()*rows.size-expected);
        return m
    }
    data class McNemar(val b01: Int,val b10: Int,val chi2: Double)
    fun mcnemar(rows: List<Dataset.Row>,a: IntArray,b: IntArray): McNemar {
        var b01=0;
        var b10=0;
        for(i in rows.indices) {
            val ca=a[i]==rows[i].y;
            val cb=b[i]==rows[i].y;
            if(ca&&!cb)b01++;
            if(cb&&!ca)b10++
        };
        val difference=abs(b01-b10).toLong()-1;
        return McNemar(b01,b10,if(b01==b10)0.0 else (difference*difference).toDouble()/(b01+b10))
    }
    class Random(seed: Long) {
        var state=seed;
        fun draw(): Long {
            state=48271*state%2147483647;
            return state
        }
    }
}
