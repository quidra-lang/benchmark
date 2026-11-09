import kotlin.math.abs

object Filters {
    data class Gradient(val gx: Array<IntArray>,val gy: Array<IntArray>,val magnitude: Array<IntArray>)
    fun clamped(image: Array<IntArray>,x: Int,y: Int)=image[y.coerceIn(0,image.lastIndex)][x.coerceIn(0,image[0].lastIndex)]
    fun smooth(image: Array<IntArray>,p: PgmIo.Params): Array<IntArray> {
        val height=image.size;
        val width=image[0].size;
        val k=p.get("gauss_size");
        val half=k/2;
        val kernel=p.row("gauss_kernel");
        val result=Array(height) {
            IntArray(width)
        };
        for(y in 0 until height)for(x in 0 until width) {
            var sum=0L;
            for(j in 0 until k)for(i in 0 until k)sum+=kernel[j*k+i]*clamped(image,x+i-half,y+j-half);
            result[y][x]=(sum/p.get("gauss_divisor")).toInt()
        };
        return result
    }
    fun gradient(image: Array<IntArray>): Gradient {
        val height=image.size;
        val width=image[0].size;
        val gx=Array(height) {
            IntArray(width)
        };
        val gy=Array(height) {
            IntArray(width)
        };
        val m=Array(height) {
            IntArray(width)
        };
        for(y in 0 until height)for(x in 0 until width) {
            val a=clamped(image,x-1,y-1);
            val b=clamped(image,x,y-1);
            val c=clamped(image,x+1,y-1);
            val d=clamped(image,x-1,y);
            val f=clamped(image,x+1,y);
            val g=clamped(image,x-1,y+1);
            val h=clamped(image,x,y+1);
            val i=clamped(image,x+1,y+1);
            gx[y][x]=c+2*f+i-(a+2*d+g);
            gy[y][x]=g+2*h+i-(a+2*b+c);
            m[y][x]=abs(gx[y][x])+abs(gy[y][x])
        };
        return Gradient(gx,gy,m)
    }
}
