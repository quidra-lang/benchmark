import java.io.File
object Report {
    class Rational(n:Long,d:Long=1):Comparable<Rational> {
        val numerator:Long;
        val denominator:Long
        init {
            val sign=if(d<0)-1 else 1;
            val a=n*sign;
            val b=d*sign;
            val divisor=gcd(a,b);
            numerator=a/divisor;
            denominator=b/divisor
        }
        constructor(value:Int):this(value.toLong())
        operator fun plus(other:Rational)=Rational(numerator*other.denominator+other.numerator*denominator,
            denominator*other.denominator)
        operator fun minus(other:Rational)=Rational(numerator*other.denominator-other.numerator*denominator,
            denominator*other.denominator)
        operator fun times(value:Long)=Rational(numerator*value,denominator)
        operator fun div(other:Rational)=Rational(numerator*other.denominator,denominator*other.numerator)
        override fun compareTo(other:Rational)=(numerator*other.denominator).compareTo(other.numerator*denominator)
        override fun toString()=if(denominator==1L)numerator.toString() else "$numerator/$denominator"
        companion object {
            fun gcd(first:Long,second:Long):Long {
                var a=kotlin.math.abs(first);
                var b=second;
                while(b!=0L) {
                    val r=a%b;
                    a=b;
                    b=r
                }
                return a
            }
        }
    }
    fun bundle(mask:Int,items:List<BidsIo.Item>):String {
        val names=items.indices.filter {
            (mask and (1 shl it))!=0
        }.map {
            items[it].name
        };
        return if(names.isEmpty())"-" else names.joinToString("+")
    }
    fun write(name:String,lines:List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(if(lines.isEmpty())"" else lines.joinToString("\n")+"\n",Charsets.US_ASCII)
    }
}
