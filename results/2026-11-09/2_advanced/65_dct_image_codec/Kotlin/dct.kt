import kotlin.math.abs
object Dct {
    val zigzagIndices=buildZigzag()
    fun buildZigzag(): IntArray {
        val result=IntArray(64);
        var k=0;
        for(sum in 0..14)for(j in 0..7) {
            val u=if(sum%2==1)j else 7-j;
            val v=sum-u;
            if(v>=0&&v<8)result[k++]=8*u+v
        };
        return result
    }
    fun rounded(value: Int,shift: Int)=(value+(1 shl (shift-1))) shr shift
    fun forward(pixels: IntArray,c: IntArray): IntArray {
        val e=IntArray(64);
        val f=IntArray(64);
        for(u in 0..7)for(x in 0..7) {
            var sum=0;
            for(y in 0..7)sum+=c[8*u+y]*(pixels[8*y+x]-128);
            e[8*u+x]=rounded(sum,11)
        };
        for(u in 0..7)for(v in 0..7) {
            var sum=0;
            for(x in 0..7)sum+=e[8*u+x]*c[8*v+x];
            f[8*u+v]=rounded(sum,15)
        };
        return f
    }
    fun inverse(coefficients: IntArray,c: IntArray): IntArray {
        val s=IntArray(64);
        val g=IntArray(64);
        for(y in 0..7)for(v in 0..7) {
            var sum=0;
            for(u in 0..7)sum+=c[8*u+y]*coefficients[8*u+v];
            s[8*y+v]=rounded(sum,11)
        };
        for(y in 0..7)for(x in 0..7) {
            var sum=0;
            for(v in 0..7)sum+=s[8*y+v]*c[8*v+x];
            g[8*y+x]=Color.clamp(rounded(sum,15)+128)
        };
        return g
    }
    fun tables(basic: Array<IntArray>,quality: Int): Array<IntArray> {
        val scale=if(quality<50)5000/quality else 200-2*quality;
        return Array(4) {
            t->if(t<2)IntArray(64) {
                i->minOf(maxOf((basic[t][i]*scale+50)/100,1),255)
            } else IntArray(0)
        }
    }
    fun quantize(values: IntArray,table: IntArray)=IntArray(64) {
        i->val magnitude=(abs(values[i])+table[i]/2)/table[i];
        if(values[i]<0)-magnitude else magnitude
    }
    fun zigzag(values: IntArray)=IntArray(64) {
        values[zigzagIndices[it]]
    }
    fun unzigzag(values: IntArray): IntArray {
        val result=IntArray(64);
        for(i in 0..63)result[zigzagIndices[i]]=values[i];
        return result
    }
    fun dequantize(sequence: IntArray,table: IntArray,keep: Int): IntArray {
        val result=IntArray(64);
        for(i in 0 until keep)result[zigzagIndices[i]]=sequence[i]*table[zigzagIndices[i]];
        return result
    }
}
