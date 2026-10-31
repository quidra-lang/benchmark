object HeuristicMiner {
    fun dependency(counts: Map<Dfg.Pair,Long>,a: String,b: String): Report.Fraction {
        val forward=Dfg.count(counts,a,b);
        val reverse=Dfg.count(counts,b,a);
        return Report.Fraction(forward-reverse,forward+reverse+1)
    }
    fun loop(count: Long)=Report.Fraction(count,count+1)
    fun split(counts: Map<Dfg.Pair,Long>,a: String,b: String,c: String)=Report.Fraction(Dfg.count(counts,
        b,c)+Dfg.count(counts,c,b),Dfg.count(counts,a,b)+Dfg.count(counts,a,c)+1)
    fun join(counts: Map<Dfg.Pair,Long>,a: String,b: String,c: String)=Report.Fraction(Dfg.count(counts,
        b,c)+Dfg.count(counts,c,b),Dfg.count(counts,b,a)+Dfg.count(counts,c,a)+1)
}
