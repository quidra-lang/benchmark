object Stats {
    val transactions=listOf("BusRd","BusRdX","BusUpgr","BusWr","WB");
    val services=listOf("l1","upgrade","through","cache","l2","memory");
    val misses=listOf("compulsory","capacity","conflict","coherence");
    val snoopCounters=listOf("invalidations_sent","invalidations_received","supplied","back_invalidations")
    class Counts {
        val values=mutableMapOf<String,Int>();
        fun get(key: String)=values.getOrDefault(key,0);
        fun add(key: String,amount: Int) {
            values[key]=get(key)+amount
        };
        fun named(keys: List<String>)=keys.joinToString(" ") {
            "$it ${get(it)}"
        }
    }
    class Core {
        val simple=Counts();
        val misses=Counts();
        val service=Counts();
        val bus=Counts();
        val snoop=Counts();
        var finish=0
    }
    fun total(cores: List<Core>): Core {
        val total=Core();
        for(core in cores) {
            val source=listOf(core.simple,core.misses,core.service,core.bus,core.snoop);
            val destination=listOf(total.simple,total.misses,total.service,total.bus,total.snoop);
            for(i in source.indices)for((key,value) in source[i].values)destination[i].add(key,value);
            total.finish=maxOf(total.finish,core.finish)
        };
        return total
    }
    fun fraction(p: Int,q: Int): String {
        var a=p;
        var b=q;
        while(b!=0) {
            val next=a%b;
            a=b;
            b=next
        };
        return "${p/a}/${q/a}"
    }
    fun decimal(p: Int,q: Int): String {
        val value=(2*p*100+q)/(2*q);
        return "${value/100}."+(value%100).toString().padStart(2,'0')
    }
    fun coreString(cores: Collection<Int>)=cores.toSortedSet().joinToString("").ifEmpty {
        "-"
    }
    fun ranges(counts: IntArray,labels: List<String>)=counts.indices.joinToString(" ") {
        "${labels[it]}:${counts[it]}"
    }
    fun sixLines(label: String,entry: Core): List<String> {
        val s=entry.simple;
        val length=s.get("latency");
        val accesses=s.get("accesses");
        return listOf("$label "+s.named(listOf("accesses","reads","writes","hits","misses","fences")),
            "$label misses "+entry.misses.named(listOf("compulsory","capacity","conflict","coherence",
            "true_sharing","false_sharing")),"$label service "+entry.service.named(services),"$label bus "+entry.bus.named(transactions),
            "$label snoop "+entry.snoop.named(snoopCounters),"$label time latency $length amat ${fraction(length,accesses)} ${decimal(length,accesses)} fence_stall ${s.get("fence_stall")} finish ${entry.finish}")
    }
}
