import kotlin.math.abs
object Costs {
    fun clamp(v: Int,size: Int)=minOf(maxOf(v,0),size-1)
    fun at(image: IntArray,w: Int,h: Int,x: Int,y: Int)=image[clamp(y,h)*w+clamp(x,w)]
    fun box(image: LongArray,w: Int,h: Int,window: Int): LongArray {
        val radius=window/2;
        val pw=w+2*radius;
        val ph=h+2*radius;
        val integral=Array(ph+1) {
            LongArray(pw+1)
        };
        for(y in 0 until ph) {
            var row=0L;
            for(x in 0 until pw) {
                row+=image[clamp(y-radius,h)*w+clamp(x-radius,w)];
                integral[y+1][x+1]=integral[y][x+1]+row
            }
        };
        val result=LongArray(w*h);
        for(y in 0 until h)for(x in 0 until w)result[y*w+x]=integral[y+window][x+window]-integral[y][x+window]-integral[y+window][x]+integral[y][x];
        return result
    }
    fun census(image: IntArray,w: Int,h: Int): IntArray {
        val result=IntArray(image.size);
        for(y in 0 until h)for(x in 0 until w) {
            var code=0;
            for(dy in -2..2)for(dx in -2..2)if(dx!=0||dy!=0)code=(code shl 1) or if(at(image,w,h,x+dx,y+dy)<image[y*w+x])1 else 0;
            result[y*w+x]=code
        };
        return result
    }
    fun texture(image: IntArray,w: Int,h: Int,window: Int): LongArray {
        val gradient=LongArray(image.size);
        for(y in 0 until h)for(x in 0 until w)gradient[y*w+x]=abs(at(image,w,h,x+1,y)-at(image,w,h,x-1,y)).toLong();
        return box(gradient,w,h,window)
    }
    fun volume(left: IntArray,right: IntArray,cl: IntArray,cr: IntArray,w: Int,h: Int,kind: String,window: Int,min: Int,max: Int): Array<LongArray> {
        val volume=Array(left.size) {
            LongArray(max-min+1)
        };
        for(d in min..max) {
            val pixels=LongArray(left.size);
            for(y in 0 until h)for(x in 0 until w) {
                val p=y*w+x;
                val q=y*w+maxOf(x-d,0);
                val difference=left[p]-right[q];
                pixels[p]=(if(kind=="census")(cl[p] xor cr[q]).countOneBits() else if(kind=="sad")abs(difference) else difference*difference).toLong()
            };
            val totals=box(pixels,w,h,window);
            for(p in left.indices)volume[p][d-min]=totals[p]
        };
        return volume
    }
}
