object Corners {
    data class Corner(val x: Int,val y: Int,val response: Long)
    data class Result(val candidates: Int,val corners: List<Corner>)
    fun detect(g: Filters.Gradient,window: Int,threshold: Long,maximum: Int): Result {
        val height=g.gx.size;
        val width=g.gx[0].size;
        val half=window/2;
        val response=Array(height) {
            LongArray(width)
        };
        for(y in 0 until height)for(x in 0 until width) {
            var xx=0L;
            var yy=0L;
            var xy=0L;
            for(j in -half..half)for(i in -half..half) {
                val gx=Filters.clamped(g.gx,x+i,y+j).toLong();
                val gy=Filters.clamped(g.gy,x+i,y+j).toLong();
                xx+=gx*gx;
                yy+=gy*gy;
                xy+=gx*gy
            };
            response[y][x]=xx*yy-xy*xy-(xx+yy)*(xx+yy)/25
        };
        val candidates=mutableListOf<Corner>();
        for(y in 0 until height)for(x in 0 until width) {
            val value=response[y][x];
            if(value<threshold)continue;
            var peak=true;
            for(point in Canny.neighbors(PgmIo.Point(x,y),width,height)) {
                val other=response[point.y][point.x];
                if(other>value||other==value&&(point.y<y||point.y==y&&point.x<x))peak=false
            };
            if(peak)candidates+=Corner(x,y,value)
        };
        candidates.sortWith(compareByDescending<Corner> {
            it.response
        }.thenBy {
            it.y
        }.thenBy {
            it.x
        });
        return Result(candidates.size,candidates.take(maximum))
    }
}
