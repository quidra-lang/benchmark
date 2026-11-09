object Report {
    fun div(a: Long,b: Long)=Math.floorDiv(a,b)
    fun rdiv(a: Long,b: Long)=div(2*a+b,2*b)
    fun root(p: Long,q: Long): Long {
        val value=div(40000*p,q);
        var low=0L;
        var high=value+1;
        while(high-low>1) {
            val middle=(low+high)/2;
            if(middle<=value/middle)low=middle else high=middle
        };
        return (low+1)/2
    }
    fun pad(s: String,width: Int)=" ".repeat(maxOf(0,width-s.length))+s
    fun two(h: Long): String {
        val a=kotlin.math.abs(h);
        return (if(h<0)"-" else "")+"${a/100}."+(a%100).toString().padStart(2,'0')
    }
    fun four(h: Long)="${h/10000}."+(h%10000).toString().padStart(4,'0')
    fun fraction(a: Long,b: Long): String {
        var x=a;
        var y=b;
        while(y!=0L) {
            val remainder=x%y;
            x=y;
            y=remainder
        };
        return "${a/x}/${b/x}"
    }
    fun ratio(a: Long,b: Long)="$a/$b"+(if(b==0L)" none" else " reduced=${fraction(a,b)} percent=${two(rdiv(10000*a,b))}")
    fun maybe(value: Long)=if(value<0)"none" else two(value)
    fun dash(value: Any?)=value?.toString()?:"-"
}
