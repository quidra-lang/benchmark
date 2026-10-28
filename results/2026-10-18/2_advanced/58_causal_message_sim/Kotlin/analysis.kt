import java.util.ArrayDeque

object Analysis {
    fun graph(sim: Causal.Simulation): List<MutableList<Int>> {
        val edges=sim.events.map {
            e->val row=mutableListOf<Int>();
            val local=sim.processes[e.process].events;
            if(e.local<local.size)row.add(local[e.local].number-1);
            row
        }
        for(c in sim.copies) {
            val recv=c.recv;
            if(recv!=null)edges[c.message!!.send.number-1].add(recv.number-1)
        }
        return edges
    }
    fun path(source: Int,target: Int,edges: List<List<Int>>): List<Int>? {
        val parent=IntArray(edges.size) {
            -1
        };
        parent[source]=source;
        val queue=ArrayDeque<Int>();
        queue.add(source)
        while(queue.isNotEmpty()&&parent[target]<0) {
            val current=queue.removeFirst();
            for(next in edges[current])if(parent[next]<0) {
                parent[next]=current;
                queue.add(next)
            }
        }
        if(parent[target]<0)return null
        val result=mutableListOf<Int>();
        var current=target
        while(true) {
            result.add(current);
            if(current==source)break;
            current=parent[current]
        }
        result.reverse();
        return result
    }
    class Concurrency(size: Int) {
        var ordered=0;
        var concurrent=0;
        var same=0;
        var inversions=0;
        val pairs=Array(size) {
            IntArray(size)
        }
    }
    fun concurrency(sim: Causal.Simulation): Concurrency {
        val result=Concurrency(sim.names.size)
        for(i in sim.events.indices)for(j in i+1 until sim.events.size) {
            val a=sim.events[i];
            val b=sim.events[j]
            if(Clocks.relation(a.vector,b.vector)=="||") {
                result.concurrent++;
                if(a.lamport==b.lamport)result.same++;
                result.pairs[minOf(a.process,b.process)][maxOf(a.process,b.process)]++
            } else result.ordered++
            if((a.time-b.time)*(a.lamport-b.lamport)<0)result.inversions++
        }
        return result
    }
    data class Relation(val process: Int,val first: Causal.Packet,val second: Causal.Packet)
    fun relations(sim: Causal.Simulation,races: Boolean): List<Relation> {
        val result=mutableListOf<Relation>()
        for(p in sim.processes)for(i in p.delivered.indices) {
            val a=p.delivered[i];
            val end=if(races)minOf(i+2,p.delivered.size) else p.delivered.size
            for(j in i+1 until end) {
                val b=p.delivered[j];
                if(if(races)Clocks.relation(a.message!!.send.vector,b.message!!.send.vector)=="||" else Clocks.before(b.message!!.send.vector,
                    a.message!!.send.vector))result.add(Relation(p.index,a,b))
            }
        }
        return result
    }
    fun consistent(cut: IntArray,processes: List<Processes.State>)=cut.indices.all {
        cut[it]==0||Clocks.lessEqual(processes[it].events[cut[it]-1].vector,cut)
    }
    data class Predicate(val cuts: Int,val definitely: Boolean)
    class Enumeration(val limits: IntArray,val levels: IntArray,val product: Int) {
        var consistent=0;
        val predicates=mutableListOf<Predicate>()
    }
    fun enumerate(sim: Causal.Simulation,time: Int,thresholds: List<Int>): Enumeration {
        val n=sim.names.size;
        val limits=IntArray(n);
        val stride=IntArray(n);
        var product=1;
        var total=0
        for(i in 0 until n) {
            limits[i]=sim.processes[i].events.count {
                it.time<=time
            };
            stride[i]=product;
            product*=limits[i]+1;
            total+=limits[i]
        }
        val result=Enumeration(limits,IntArray(total+1),product);
        val good=BooleanArray(product);
        val amount=IntArray(product)
        for(id in 0 until product) {
            val cut=IntArray(n);
            var level=0;
            var balance=0
            for(i in 0 until n) {
                cut[i]=id/stride[i]%(limits[i]+1);
                level+=cut[i];
                balance+=sim.processes[i].balanceAt(cut[i])
            }
            good[id]=consistent(cut,sim.processes);
            amount[id]=sim.initial()-balance;
            if(good[id]) {
                result.consistent++;
                result.levels[level]++
            }
        }
        for(threshold in thresholds) {
            var count=0;
            val reachable=BooleanArray(product)
            for(id in 0 until product)if(good[id]) {
                if(amount[id]>=threshold) {
                    count++;
                    continue
                }
                if(id==0)reachable[id]=true
                else for(i in 0 until n)if(id/stride[i]%(limits[i]+1)>0&&reachable[id-stride[i]]) {
                    reachable[id]=true;
                    break
                }
            }
            result.predicates.add(Predicate(count,!reachable[product-1]))
        }
        return result
    }
}
