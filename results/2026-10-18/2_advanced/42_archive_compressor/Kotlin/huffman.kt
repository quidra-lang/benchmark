import java.util.PriorityQueue

object Huffman {
    class Node(val weight: Int,val minimum: Int,val symbol: Int,val left: Node?=null,val right: Node?=null)
    private fun depths(n: Node,depth: Int,lengths: IntArray) {
        if(n.symbol>=0) {
            lengths[n.symbol]=maxOf(1,depth);
            return
        };
        depths(n.left!!,depth+1,lengths);
        depths(n.right!!,depth+1,lengths)
    }
    fun lengths(frequencies: IntArray): IntArray {
        val result=IntArray(frequencies.size);
        val nodes=PriorityQueue(compareBy<Node> {
            it.weight
        }.thenBy {
            it.minimum
        });
        for(i in frequencies.indices)if(frequencies[i]>0)nodes+=Node(frequencies[i],i,i);
        if(nodes.isEmpty())return result;
        while(nodes.size>1) {
            val a=nodes.remove();
            val b=nodes.remove();
            nodes+=Node(a.weight+b.weight,minOf(a.minimum,b.minimum),-1,a,b)
        };
        depths(nodes.remove(),0,result);
        return result
    }
    data class Limited(val lengths: IntArray,val halvings: Int)
    fun limited(frequencies: IntArray,maximum: Int): Limited {
        val current=frequencies.copyOf();
        var halves=0;
        while(true) {
            val lengths=lengths(current);
            if(lengths.max()<=maximum)return Limited(lengths,halves);
            for(i in current.indices)current[i]=(current[i]+1)/2;
            halves++
        }
    }
    fun canonical(lengths: IntArray): IntArray {
        val order=lengths.indices.filter {
            lengths[it]>0
        }.sortedWith(compareBy<Int> {
            lengths[it]
        }.thenBy {
            it
        });
        val codes=IntArray(lengths.size);
        var code=0;
        var previous=0;
        for(symbol in order) {
            code=code shl (lengths[symbol]-previous);
            codes[symbol]=code;
            code++;
            previous=lengths[symbol]
        };
        return codes
    }
}
