import kotlin.math.abs

object Canny {
    class Result(height: Int,width: Int) {
        val direction=Array(height) {
            IntArray(width)
        };
        val nms=Array(height) {
            IntArray(width)
        };
        val edge=Array(height) {
            BooleanArray(width)
        };
        val components=mutableListOf<List<PgmIo.Point>>();
        var strong=0;
        var weak=0;
        var weakKept=0
    }
    fun inside(x: Int,y: Int,width: Int,height: Int)=x>=0&&x<width&&y>=0&&y<height
    fun neighbors(p: PgmIo.Point,width: Int,height: Int): List<PgmIo.Point> {
        val result=mutableListOf<PgmIo.Point>();
        for(dy in -1..1)for(dx in -1..1)if((dx!=0||dy!=0)&&inside(p.x+dx,p.y+dy,width,height))result+=PgmIo.Point(p.x+dx,p.y+dy);
        return result
    }
    fun process(g: Filters.Gradient,low: Int,high: Int): Result {
        val m=g.magnitude;
        val height=m.size;
        val width=m[0].size;
        val result=Result(height,width);
        val queue=ArrayDeque<PgmIo.Point>();
        for(y in 0 until height)for(x in 0 until width) {
            val gx=g.gx[y][x];
            val gy=g.gy[y][x];
            val ax=abs(gx);
            val ay=abs(gy);
            val direction=if(29*ay<=12*ax)0 else if(29*ay>=70*ax)90 else if(gx*gy<0)45 else 135;
            result.direction[y][x]=direction;
            if(x==0||y==0||x==width-1||y==height-1)continue;
            val dx=if(direction==90)0 else if(direction==45)1 else -1;
            val dy=if(direction==0)0 else -1;
            if(m[y][x]>m[y+dy][x+dx]&&m[y][x]>=m[y-dy][x-dx])result.nms[y][x]=m[y][x];
            if(result.nms[y][x]>=high) {
                result.strong++;
                result.edge[y][x]=true;
                queue.addLast(PgmIo.Point(x,y))
            } else if(result.nms[y][x]>=low)result.weak++
        };
        while(queue.isNotEmpty()) {
            val point=queue.removeFirst();
            for(next in neighbors(point,width,height))if(!result.edge[next.y][next.x]&&result.nms[next.y][next.x]>=low) {
                result.edge[next.y][next.x]=true;
                queue.addLast(next)
            }
        };
        val seen=Array(height) {
            BooleanArray(width)
        };
        for(y in 0 until height)for(x in 0 until width) {
            if(result.edge[y][x]&&result.nms[y][x]<high)result.weakKept++;
            if(!result.edge[y][x]||seen[y][x])continue;
            val component=mutableListOf<PgmIo.Point>();
            queue.addLast(PgmIo.Point(x,y));
            seen[y][x]=true;
            while(queue.isNotEmpty()) {
                val point=queue.removeFirst();
                component+=point;
                for(next in neighbors(point,width,height))if(result.edge[next.y][next.x]&&!seen[next.y][next.x]) {
                    seen[next.y][next.x]=true;
                    queue.addLast(next)
                }
            };
            result.components.add(component)
        };
        return result
    }
}
