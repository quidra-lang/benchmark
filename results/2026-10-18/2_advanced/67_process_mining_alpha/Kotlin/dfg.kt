object Dfg {
    data class Pair(val first: String,val second: String)
    data class Trace(val activities: List<String>,val weight: Long)
    fun count(counts: Map<Pair,Long>,first: String,second: String)=counts.getOrDefault(Pair(first,
        second),0L)
    fun counts(log: List<Trace>): MutableMap<Pair,Long> {
        val result=mutableMapOf<Pair,Long>();
        for(trace in log)for(i in 1 until trace.activities.size) {
            val pair=Pair(trace.activities[i-1],trace.activities[i]);
            result[pair]=result.getOrDefault(pair,0L)+trace.weight
        };
        return result
    }
    fun basic(counts: Map<Pair,Long>,a: String,b: String): String {
        val forward=count(counts,a,b)>0;
        val reverse=count(counts,b,a)>0;
        return if(forward&&!reverse)"->" else if(reverse&&!forward)"<-" else if(forward)"||" else "#"
    }
    fun compare(a: Pair,b: Pair): Int {
        val order=a.first.compareTo(b.first);
        return if(order!=0)order else a.second.compareTo(b.second)
    }
    fun table(cells: List<List<String>>,width: Int): List<String> {
        val lines=mutableListOf("    "+(1..cells.size).joinToString("") {
            it.toString().padStart(width)
        });
        for((i,row) in cells.withIndex())lines.add((i+1).toString().padStart(4)+row.joinToString("") {
            it.padStart(width)
        });
        return lines
    }
    fun footprint(names: List<String>,relation: Array<Array<String>>): List<String> {
        val lines=names.mapIndexed {
            i,name->"ACTIVITY ${i+1} $name"
        }.toMutableList();
        lines.addAll(table(relation.map {
            it.toList()
        },4));
        return lines
    }
}
