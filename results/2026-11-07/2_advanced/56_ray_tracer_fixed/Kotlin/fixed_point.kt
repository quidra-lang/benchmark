object FixedPoint {
    const val S=4096L
    fun divide(a: Long,b: Long)=Math.floorDiv(a,b)
    fun multiply(a: Long,b: Long)=divide(a*b,S)
    fun isqrt(n: Long): Long {
        if(n==0L)return 0L;
        var x=n;
        var y=(x+1)/2;
        while(y<x) {
            x=y;
            y=(x+n/x)/2
        };
        return x
    }
}
