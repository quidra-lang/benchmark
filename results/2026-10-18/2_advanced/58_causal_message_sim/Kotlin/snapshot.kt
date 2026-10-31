object Snapshot {
    data class LocalRecord(val time: Int,val reason: String,val balance: Int,val lamport: Int,val vector: IntArray,val pending: List<Causal.Packet>)
    data class Ignored(val process: Int,val time: Int)
    class State(val name: String,val start: Int,size: Int) {
        var complete=0;
        var finished=0;
        val records=arrayOfNulls<LocalRecord>(size)
        val channels=List(size) {
            List(size) {
                mutableListOf<Causal.Packet>()
            }
        }
        val sent=Array(size) {
            IntArray(size) {
                -1
            }
        };
        val accepted=Array(size) {
            IntArray(size) {
                -1
            }
        }
        val ignored=mutableListOf<Ignored>()
        fun recordState(p: Processes.State,time: Int,reason: String) {
            records[p.index]=LocalRecord(time,reason,p.balance,p.lamport,p.vector.copyOf(),p.hold.toList())
        }
        fun accept(source: Int,destination: Int,time: Int) {
            accepted[source][destination]=time;
            finished++;
            if(finished==records.size*(records.size-1))complete=time
        }
        fun cut()=IntArray(records.size) {
            records[it]!!.vector[it]
        }
    }
    class Cut {
        val orphans=mutableListOf<Causal.Packet>();
        val transit=mutableListOf<Causal.Packet>();
        var balances=0;
        var money=0
    }
    fun inspect(cut: IntArray,sim: Causal.Simulation): Cut {
        val result=Cut()
        for(c in sim.copies) {
            val sent=c.message!!.send.local<=cut[c.source];
            val recv=c.recv;
            val received=recv!=null&&recv.local<=cut[c.destination];
            if(received&&!sent)result.orphans.add(c);
            if(sent&&!received)result.transit.add(c)
        }
        for(i in cut.indices)result.balances+=sim.processes[i].balanceAt(cut[i]);
        result.money=result.balances
        for(c in result.transit)result.money+=c.message!!.amount
        return result
    }
    fun match(recorded: List<Causal.Packet>,transit: List<Causal.Packet>): Boolean {
        if(recorded.size!=transit.size)return false
        val counts=recorded.groupingBy {
            it
        }.eachCount().toMutableMap()
        for(c in transit) {
            val value=counts.getOrDefault(c,0);
            if(value==0)return false;
            counts[c]=value-1
        }
        return true
    }
}
