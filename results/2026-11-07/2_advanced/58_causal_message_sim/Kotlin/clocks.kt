object Clocks {
    fun advance(p: Processes.State,sender: Causal.Event?) {
        if(sender==null)p.lamport++
        else {
            p.lamport=maxOf(p.lamport,sender.lamport)+1;
            for(i in p.vector.indices)p.vector[i]=maxOf(p.vector[i],sender.vector[i])
        }
        p.vector[p.index]++
    }
    fun lessEqual(a: IntArray,b: IntArray)=a.indices.all {
        a[it]<=b[it]
    }
    fun before(a: IntArray,b: IntArray)=!a.contentEquals(b)&&lessEqual(a,b)
    fun relation(a: IntArray,b: IntArray)=if(before(a,b))"->" else if(before(b,a))"<-" else "||"
    fun deliverable(c: Causal.Packet,p: Processes.State): Boolean {
        val stamp=c.message!!.stamp!!
        return stamp.indices.all {
            if(it==c.source)stamp[it]==p.broadcast[it]+1 else stamp[it]<=p.broadcast[it]
        }
    }
    fun missing(c: Causal.Packet,p: Processes.State): IntArray {
        val stamp=c.message!!.stamp!!
        return p.broadcast.indices.filter {
            stamp[it]>p.broadcast[it]+(if(it==c.source)1 else 0)
        }.toIntArray()
    }
    fun vector(values: IntArray)=values.joinToString(",")
}
