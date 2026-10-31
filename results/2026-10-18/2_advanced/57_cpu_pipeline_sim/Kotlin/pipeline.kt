object Pipeline {
    val CAUSES=arrayOf("control","structural","load_use","raw")
    val STAGES=arrayOf("IF","ID","EX","MEM","WB")
    data class Time(val f: Int,val d: Int,val x: Int,val m: Int,val w: Int)
    data class Stall(val cause: Int,val cycles: Int,val responsible: Int,val waiting: Int,val producer: Int)
    class Run(val variant: TraceIO.Variant) {
        var predictor=""
        val times=mutableListOf<Time>();
        val records=mutableListOf<Stall>()
        val cycles=IntArray(4);
        val events=IntArray(4);
        val lengths=IntArray(6);
        var total=0
    }
    fun simulate(instructions: List<CPU.Instruction>,sources: List<List<Hazards.Source>>,variant: TraceIO.Variant,misses: BooleanArray): Run {
        val run=Run(variant)
        for(i in instructions.indices) {
            val t=instructions[i];
            var f=1;
            var d=2;
            var x=3
            if(i>0) {
                val p=run.times[i-1]
                f=if(misses[i-1])p.x+(if(Hazards.idResolved(instructions[i-1],variant))0 else 1) else p.d
                d=maxOf(f+1,p.x);
                val ideal=p.x+1
                val bounds=intArrayOf(d+1,p.m,ideal,ideal);
                val producers=IntArray(4) {
                    -1
                }
                for(source in sources[i])if(source.producer>=0) {
                    val j=source.producer;
                    val ready=Hazards.ready(t,instructions[j],run.times[j],variant)
                    val cause=if(instructions[j].kind==2)2 else 3
                    if(ready>bounds[cause]) {
                        bounds[cause]=ready;
                        producers[cause]=j
                    }
                }
                x=ideal
                for(cause in 0..3)if(bounds[cause]>x) {
                    run.records.add(Stall(cause,bounds[cause]-x,if(cause<2)i-1 else i,i,producers[cause]))
                    x=bounds[cause]
                }
                if(x>ideal)run.lengths[minOf(5,x-ideal)]++
            }
            val m=x+(if(t.kind==1)variant.latency else 1);
            run.times.add(Time(f,d,x,m,m+1))
        }
        val n=instructions.size
        if(instructions[n-1].kind==1&&variant.latency>1)run.records.add(Stall(1,variant.latency-1,n-1,-1,-1))
        for(stall in run.records) {
            run.cycles[stall.cause]+=stall.cycles;
            run.events[stall.cause]++
        }
        run.total=run.times.last().w
        return run
    }
}
