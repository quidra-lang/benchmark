object AlphaMiner {
    data class Candidate(val left: Int,val right: Int)
    fun extend(pair: Candidate,activity: Int,side: Int,relation: Array<Array<String>>): Candidate? {
        val mask=1 shl activity;
        val group=if(side==0)pair.left else pair.right;
        val other=if(side==0)pair.right else pair.left;
        if((group and mask)!=0||relation[activity][activity]!="#")return null;
        for(i in relation.indices) {
            if((group and (1 shl i))!=0&&relation[activity][i]!="#")return null;
            if((other and (1 shl i))!=0&&(if(side==0)relation[activity][i] else relation[i][activity])!="->")return null
        };
        return if(side==0)Candidate(group or mask,other) else Candidate(other,group or mask)
    }
    fun compareMask(first: Int,second: Int): Int {
        var a=first;
        var b=second;
        while(a!=0&&b!=0) {
            val i=Integer.numberOfTrailingZeros(a);
            val j=Integer.numberOfTrailingZeros(b);
            if(i!=j)return i.compareTo(j);
            a=a and (a-1);
            b=b and (b-1)
        };
        return if(a==b)0 else if(a==0)-1 else 1
    }
    fun compare(a: Candidate,b: Candidate): Int {
        val order=compareMask(a.left,b.left);
        return if(order!=0)order else compareMask(a.right,b.right)
    }
    fun triangles(log: List<Dfg.Trace>): MutableMap<Dfg.Pair,Long> {
        val result=mutableMapOf<Dfg.Pair,Long>();
        for(trace in log)for(i in 2 until trace.activities.size) {
            val a=trace.activities[i-2];
            val b=trace.activities[i-1];
            if(a==trace.activities[i]&&a!=b) {
                val pair=Dfg.Pair(a,b);
                result[pair]=result.getOrDefault(pair,0L)+trace.weight
            }
        };
        return result
    }
    fun plus(counts: Map<Dfg.Pair,Long>,triangles: Map<Dfg.Pair,Long>,a: String,b: String): String {
        val forward=Dfg.count(counts,a,b)>0;
        val reverse=Dfg.count(counts,b,a)>0;
        val loop=a!=b&&Dfg.count(triangles,a,b)>0&&Dfg.count(triangles,b,a)>0;
        return if(forward&&(!reverse||loop))"->" else if(reverse&&(!forward||loop))"<-" else if(forward&&reverse)"||" else "#"
    }
}
