class Bus(val latency: Int) {
    data class Eviction(val block: Int,val copies: List<String>,val dirty: Boolean)
    class Transaction(val number: Int,val start: Int,val core: Int,val kind: String,val block: Int) {
        var snoopHits=0;
        var invalidations=0;
        var supplier: Int?=null;
        var l2="";
        var source="";
        var flush=false;
        val snoop=mutableListOf<String>();
        var eviction: Eviction?=null
    }
    var free=0;
    var wait=0;
    val transactions=mutableListOf<Transaction>()
    fun assign(core: Int,kind: String,block: Int,requested: Int): Transaction {
        val start=maxOf(requested,free);
        wait+=start-requested;
        free=start+latency;
        val tx=Transaction(transactions.size+1,start,core,kind,block);
        transactions.add(tx);
        return tx
    }
    fun line(tx: Transaction,lineSize: Int): String {
        var output="${tx.number} ${tx.start} c${tx.core} ${tx.kind} ${ConfigIo.hexAddress(tx.block*lineSize)}";
        if(tx.kind=="WB")return output;
        output+=" snoop "+tx.snoop.joinToString(" ").ifEmpty {
            "none"
        };
        if(tx.kind=="BusUpgr")return output;
        if(tx.kind=="BusRd"||tx.kind=="BusRdX")output+=" data ${tx.source}";
        output+=" l2 ${tx.l2}";
        val e=tx.eviction;
        if(e!=null)output+=" evict ${ConfigIo.hexAddress(e.block*lineSize)} "+e.copies.joinToString(" ").ifEmpty {
            "none"
        }+" "+if(e.dirty)"dirty" else "clean";
        return output
    }
}
