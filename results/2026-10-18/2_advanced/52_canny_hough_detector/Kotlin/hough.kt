import kotlin.math.*

object Hough {
    data class CircleCell(val r: Int,val x: Int,val y: Int,val votes: Int,val total: Int)
    data class LineCell(val t: Int,val r: Int,val votes: Int)
    class CircleVotes {
        val outlines=mutableMapOf<Int,List<PgmIo.Point>>();
        val votes=mutableMapOf<Int,Array<IntArray>>();
        val peaks=mutableListOf<CircleCell>();
        var candidates=0
    }
    class LineVotes(val low: Int,val high: Int) {
        var maximum=0;
        val votes=Array(180) {
            IntArray(high-low+1)
        };
        val peaks=mutableListOf<LineCell>();
        fun count(t: Int,r: Int)=if(t !in 0..179||r<low||r>high)0 else votes[t][r-low]
    }
    fun rho(p: PgmIo.Point,t: Int,trig: Array<IntArray>,step: Int)=Math.floorDiv(p.x*trig[t][0]+p.y*trig[t][1],16384*step)
    fun circlePoints(radius: Int): List<PgmIo.Point> {
        val points=linkedSetOf<PgmIo.Point>();
        var a=radius;
        var b=0;
        var e=1-radius;
        while(a>=b) {
            points.addAll(listOf(PgmIo.Point(a,b),PgmIo.Point(b,a),PgmIo.Point(-b,a),PgmIo.Point(-a,
                b),PgmIo.Point(-a,-b),PgmIo.Point(-b,-a),PgmIo.Point(b,-a),PgmIo.Point(a,-b)));
            b++;
            if(e<0)e+=2*b+1 else {
                a--;
                e+=2*(b-a)+1
            }
        };
        return points.toList()
    }
    fun compare(a: CircleCell,b: CircleCell): Int {
        var c=(b.votes*a.total).compareTo(a.votes*b.total);
        if(c==0)c=a.r.compareTo(b.r);
        if(c==0)c=a.y.compareTo(b.y);
        if(c==0)c=a.x.compareTo(b.x);
        return c
    }
    fun circles(edges: List<PgmIo.Point>,width: Int,height: Int,p: PgmIo.Params): CircleVotes {
        val result=CircleVotes();
        val minimum=p.get("circle_min_radius");
        val maximum=p.get("circle_max_radius");
        for(r in minimum..maximum) {
            val offsets=circlePoints(r);
            result.outlines[r]=offsets;
            val votes=Array(height) {
                IntArray(width)
            };
            for(point in edges)for(o in offsets) {
                val x=point.x+o.x;
                val y=point.y+o.y;
                if(Canny.inside(x,y,width,height))votes[y][x]++
            };
            result.votes[r]=votes
        };
        for(r in minimum..maximum)for(y in 0 until height)for(x in 0 until width) {
            val votes=result.votes.getValue(r)[y][x];
            val total=result.outlines.getValue(r).size;
            if(100*votes<p.get("circle_min_percent")*total)continue;
            result.candidates++;
            var peak=true;
            for(rr in maxOf(minimum,r-2)..minOf(maximum,r+2))for(yy in maxOf(0,y-2)..minOf(height-1,y+2))for(xx in maxOf(0,x-2)..minOf(width-1,x+2)) {
                if(rr==r&&xx==x&&yy==y)continue;
                val left=votes*result.outlines.getValue(rr).size;
                val right=result.votes.getValue(rr)[yy][xx]*total;
                val before=rr<r||rr==r&&(yy<y||yy==y&&xx<x);
                if(left<right||left==right&&before)peak=false
            };
            if(peak)result.peaks+=CircleCell(r,x,y,votes,total)
        };
        result.peaks.sortWith(Comparator(::compare));
        return result
    }
    fun lines(edges: List<PgmIo.Point>,width: Int,height: Int,trig: Array<IntArray>,step: Int,threshold: Int): LineVotes {
        var low=Int.MAX_VALUE;
        var high=Int.MIN_VALUE;
        val corners=listOf(PgmIo.Point(0,0),PgmIo.Point(width-1,0),PgmIo.Point(0,height-1),PgmIo.Point(width-1,height-1));
        for(t in 0..179)for(point in corners) {
            val r=rho(point,t,trig,step);
            low=minOf(low,r);
            high=maxOf(high,r)
        };
        val result=LineVotes(low,high);
        for(point in edges)for(t in 0..179) {
            val r=rho(point,t,trig,step);
            result.votes[t][r-low]++;
            result.maximum=maxOf(result.maximum,result.votes[t][r-low])
        };
        for(t in 0..179)for(r in low..high) {
            val count=result.count(t,r);
            if(count<threshold)continue;
            var peak=true;
            for(tt in t-2..t+2)for(rr in r-2..r+2) {
                if(tt==t&&rr==r)continue;
                val other=result.count(tt,rr);
                if(other>count||other==count&&(tt<t||tt==t&&rr<r))peak=false
            };
            if(peak)result.peaks+=LineCell(t,r,count)
        };
        result.peaks.sortWith(compareByDescending<LineCell> {
            it.votes
        }.thenBy {
            it.t
        }.thenBy {
            it.r
        });
        return result
    }
}
