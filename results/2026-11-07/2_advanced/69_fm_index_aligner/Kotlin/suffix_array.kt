object SuffixArray {
    const val SYMBOLS="$#ACGT";
    const val BASES="ACGT"
    data class Built(val suffixes: IntArray,val classes: List<Int>)
    data class Check(val ordered: Int,val lcpSum: Int,val maximum: Int,val row: Int)
    fun counting(positions: IntArray,keys: IntArray,keyCount: Int): IntArray {
        val counts=IntArray(keyCount);
        for(position in positions)counts[keys[position]]++;
        var offset=0;
        for(i in counts.indices) {
            val value=counts[i];
            counts[i]=offset;
            offset+=value
        };
        val result=IntArray(positions.size);
        for(position in positions)result[counts[keys[position]]++]=position;
        return result
    }
    fun build(text: String): Built {
        val size=text.length;
        val positions=IntArray(size) {
            it
        };
        val codes=IntArray(size) {
            SYMBOLS.indexOf(text[it])
        };
        var ranks=IntArray(size);
        var order=counting(positions,codes,6);
        var count=0;
        var previous=-1;
        for(position in order) {
            if(codes[position]!=previous) {
                count++;
                previous=codes[position]
            };
            ranks[position]=count-1
        };
        val classes=mutableListOf(count);
        var width=1;
        while(count<size) {
            val second=IntArray(size) {
                if(it+width<size)ranks[it+width]+1 else 0
            };
            order=counting(counting(positions,second,count+1),ranks,count);
            val updated=IntArray(size);
            count=0;
            var firstKey=-1;
            var secondKey=-1;
            for(position in order) {
                if(ranks[position]!=firstKey||second[position]!=secondKey) {
                    count++;
                    firstKey=ranks[position];
                    secondKey=second[position]
                };
                updated[position]=count-1
            };
            ranks=updated;
            classes.add(count);
            width*=2
        };
        return Built(order,classes)
    }
    fun direct(text: String)=text.indices.sortedWith(Comparator {
        a,b->var i=a;
        var j=b;
        var order=0;
        while(i<text.length&&j<text.length&&order==0)order=text[i++].compareTo(text[j++]);
        if(order!=0)order else (text.length-a).compareTo(text.length-b)
    }).toIntArray()
    fun check(text: String,suffixes: IntArray): Check {
        var ordered=0;
        var sum=0;
        var maximum=-1;
        var longest=1;
        for(row in 1 until suffixes.size) {
            val left=suffixes[row-1];
            val right=suffixes[row];
            var common=0;
            while(text[left+common]==text[right+common])common++;
            if(SYMBOLS.indexOf(text[left+common])<SYMBOLS.indexOf(text[right+common]))ordered++;
            sum+=common;
            if(common>maximum) {
                maximum=common;
                longest=row
            }
        };
        return Check(ordered,sum,maximum,longest)
    }
}
