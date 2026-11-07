object Refinement {
    fun hundredths(value: Long)= (value/100).toString()+"."+(if(value%100<10)"0" else "")+(value%100).toString()
    fun two(a: Long,b: Long)=hundredths((200*a+b)/(2*b))
    fun depthHundredths(disparity: Int,focal: Long,baseline: Long)=(200*focal*baseline+disparity)/(2*disparity)
    fun subpixel(d: Int,costs: LongArray,min: Int,max: Int,focal: Long,baseline: Long): Array<String> {
        val index=d-min;
        var a=0L;
        var b=1L;
        if(min<d&&d<max&&costs[index-1]>costs[index]&&costs[index+1]>=costs[index]) {
            a=costs[index-1]-costs[index+1];
            b=2*(costs[index-1]-2*costs[index]+costs[index+1])
        };
        val q=(200*(d*b+a)+b)/(2*b);
        return arrayOf(hundredths(q),two(100*focal*baseline,q))
    }
}
