import kotlin.math.abs
typealias CodeTables=Array<Array<Entropy.Table?>>
object Entropy {
    val classes=intArrayOf(0,1,0,1);
    val ids=intArrayOf(0,0,1,1);
    val names=arrayOf("dc_luma","ac_luma","dc_chroma","ac_chroma")
    fun category(value: Int): Int {
        var n=0;
        var a=abs(value);
        while(a!=0) {
            n++;
            a=a shr 1
        };
        return n
    }
    fun extra(value: Int)=if(value>=0)value else value+(1 shl category(value))-1
    fun amplitude(bits: Int,n: Int)=if(n==0)0 else if(bits>=(1 shl (n-1)))bits else bits-(1 shl n)+1
    class Table(val counts: IntArray,val symbols: IntArray) {
        val lengths=IntArray(256);
        val codes=IntArray(256);
        val decode=mutableMapOf<Int,Int>();
        init {
            var code=0;
            var offset=0;
            for(length in 1..16) {
                repeat(counts[length-1]) {
                    val symbol=symbols[offset++];
                    lengths[symbol]=length;
                    codes[symbol]=code;
                    decode[(length shl 16) or code]=symbol;
                    code++
                };
                code*=2
            }
        }
    }
    fun optimized(input: IntArray): Table {
        val frequencies=input.copyOf(257);
        val sizes=IntArray(257);
        val others=IntArray(257) {
            -1
        };
        frequencies[256]=1
        while(true) {
            val available=(0..256).filter {
                frequencies[it]>0
            }.sortedWith(compareBy<Int> {
                frequencies[it]
            }.thenByDescending {
                it
            });
            if(available.size<2)break;
            var first=available[0];
            var second=available[1];
            frequencies[first]+=frequencies[second];
            frequencies[second]=0;
            sizes[first]++;
            while(others[first]!=-1) {
                first=others[first];
                sizes[first]++
            };
            others[first]=second;
            sizes[second]++;
            while(others[second]!=-1) {
                second=others[second];
                sizes[second]++
            }
        }
        val counts=IntArray(257);
        var maximum=0;
        for(length in sizes)if(length>0) {
            counts[length]++;
            maximum=maxOf(maximum,length)
        };
        for(length in maximum downTo 17)while(counts[length]>0) {
            var j=length-2;
            while(counts[j]==0)j--;
            counts[length]-=2;
            counts[length-1]++;
            counts[j+1]+=2;
            counts[j]--
        };
        var longest=16;
        while(counts[longest]==0)longest--;
        counts[longest]--;
        val symbols=(0..255).filter {
            sizes[it]>0
        }.sortedWith(compareBy<Int> {
            sizes[it]
        }.thenBy {
            it
        }).toIntArray();
        return Table(counts.copyOfRange(1,17),symbols)
    }
}
