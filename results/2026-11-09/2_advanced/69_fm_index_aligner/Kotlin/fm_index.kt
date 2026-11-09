class FmIndex(text: String,suffixes: IntArray,val interval: Int,sampleInterval: Int=0) {
    data class Interval(val lower: Int,val upper: Int) {
        fun empty()=lower>=upper
    }
    data class Location(val position: Int,val steps: Int)
    val size=text.length;
    val bwt=suffixes.map {
        text[if(it==0)size-1 else it-1]
    }.joinToString("");
    val c=IntArray(6);
    val samples=IntArray(size) {
        -1
    };
    val checkpoints=Array(size/interval+1) {
        IntArray(6)
    };
    var sampleCount=0
    init {
        val frequencies=IntArray(6);
        for(symbol in text)frequencies[SuffixArray.SYMBOLS.indexOf(symbol)]++;
        var total=0;
        for(i in 0..5) {
            c[i]=total;
            total+=frequencies[i]
        };
        val counts=IntArray(6);
        for(i in 0 until size) {
            counts[SuffixArray.SYMBOLS.indexOf(bwt[i])]++;
            if((i+1)%interval==0)checkpoints[(i+1)/interval]=counts.copyOf()
        };
        if(sampleInterval>0)for(row in 0 until size)if(suffixes[row]%sampleInterval==0) {
            samples[row]=suffixes[row];
            sampleCount++
        }
    }
    fun occurrence(symbol: Char,position: Int): Int {
        val checkpoint=position/interval;
        val start=checkpoint*interval;
        var count=checkpoints[checkpoint][SuffixArray.SYMBOLS.indexOf(symbol)];
        for(i in start until position)if(bwt[i]==symbol)count++;
        return count
    }
    fun lf(row: Int): Int {
        val symbol=bwt[row];
        return c[SuffixArray.SYMBOLS.indexOf(symbol)]+occurrence(symbol,row)
    }
    fun extend(lower: Int,upper: Int,base: Char): Interval {
        if(base=='N')return Interval(0,0);
        val start=c[SuffixArray.SYMBOLS.indexOf(base)];
        return Interval(start+occurrence(base,lower),start+occurrence(base,upper))
    }
    fun locate(start: Int): Location {
        var row=start;
        var steps=0;
        while(samples[row]<0) {
            row=lf(row);
            steps++
        };
        return Location(samples[row]+steps,steps)
    }
    fun inverse(): String {
        val result=CharArray(size);
        result[size-1]='$';
        var row=0;
        for(i in size-2 downTo 0) {
            result[i]=bwt[row];
            row=lf(row)
        };
        return result.concatToString()
    }
    fun backward(sequence: String): Interval {
        var range=Interval(0,size);
        for(base in sequence.reversed()) {
            range=extend(range.lower,range.upper,base);
            if(range.empty())break
        };
        return range
    }
}
