import java.io.File
import kotlin.math.abs
object Report {
    class Fraction(n: Number,d: Number): Comparable<Fraction> {
        val numerator: Long;
        val denominator: Long;
        init {
            var a=n.toLong();
            var b=d.toLong();
            if(b<0) {
                a=-a;
                b=-b
            };
            val divisor=gcd(abs(a),b);
            numerator=a/divisor;
            denominator=b/divisor
        };
        fun subtract(other: Fraction)=Fraction(numerator*other.denominator-other.numerator*denominator,
            denominator*other.denominator);
        override fun compareTo(other: Fraction)=(numerator*other.denominator).compareTo(other.numerator*denominator)
    }
    fun gcd(first: Long,second: Long): Long {
        var a=first;
        var b=second;
        while(b!=0L) {
            val t=a%b;
            a=b;
            b=t
        };
        return a
    }
    fun parse(value: String): Fraction {
        val w=value.split('/');
        return Fraction(w[0].toLong(),if(w.size==1)1L else w[1].toLong())
    }
    fun fraction(value: Fraction): String {
        val n=abs(value.numerator);
        val d=value.denominator;
        val scaled=10000*n/d;
        val sign=if(value.numerator<0)"-" else "";
        val decimalSign=if(scaled==0L)"" else sign;
        return sign+n+"/"+d+"="+decimalSign+scaled/10000+"."+(scaled%10000).toString().padStart(4,
            '0')
    }
    fun fraction(n: Number,d: Number)=fraction(Fraction(n,d))
    fun percentage(a: Number,b: Number): String {
        val scaled=10000*a.toLong()/b.toLong();
        return "${scaled/100}.${(scaled%100).toString().padStart(2,'0')}%"
    }
    fun names(values: Collection<String>)=if(values.isEmpty())"-" else values.joinToString(",")
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
}
