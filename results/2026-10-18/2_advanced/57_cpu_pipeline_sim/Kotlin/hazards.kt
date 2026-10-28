object Hazards {
    data class Source(val register: Int,val producer: Int)
    fun dependencies(instructions: List<CPU.Instruction>): List<List<Source>> {
        val writers=IntArray(32) {
            -1
        }
        return instructions.mapIndexed {
            i,t->
            val current=listOf(t.rs1,t.rs2).filter {
                it>0
            }.map {
                Source(it,writers[it])
            }
            if(t.rd>0)writers[t.rd]=i
            current
        }
    }
    fun idResolved(t: CPU.Instruction,v: TraceIO.Variant)=t.kind==5&&t.rs1<0||t.control()&&v.stage=="ID"
    fun ready(t: CPU.Instruction,producer: CPU.Instruction,p: Pipeline.Time,v: TraceIO.Variant): Int {
        if(!v.forwarding)return p.w+1
        return (if(producer.kind==2)p.w else p.m)+(if(idResolved(t,v))1 else 0)
    }
    fun path(t: CPU.Instruction,producer: Pipeline.Time?,time: Pipeline.Time,v: TraceIO.Variant): Int {
        if(producer==null||!v.forwarding)return 0
        val early=idResolved(t,v);
        val use=time.x-(if(early)1 else 0)
        if(producer.m==use)return 1
        if(!early&&producer.w==use)return 2
        return 0
    }
}
