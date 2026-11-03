object Predictors {
    class BTB(entries: Int) {
        val pcs=IntArray(entries) {
            -1
        };
        val targets=IntArray(entries)
        fun lookup(pc: Int): Int {
            val i=pc/4%pcs.size;
            return if(pcs[i]==pc)targets[i] else -1
        }
        fun insert(pc: Int,target: Int) {
            val i=pc/4%pcs.size;
            pcs[i]=pc;
            targets[i]=target
        }
    }
    class RAS(val depth: Int) {
        val stack=mutableListOf<Int>()
        fun push(address: Int) {
            if(depth==0)return;
            if(stack.size==depth)stack.removeAt(0);
            stack.add(address)
        }
        fun pop()=if(stack.isEmpty())-1 else stack.removeAt(stack.lastIndex)
    }
    fun updated(counter: Int,taken: Boolean)=if(taken)minOf(3,counter+1) else maxOf(0,counter-1)
    class Direction(definition: TraceIO.Predictor) {
        val scheme=definition.scheme;
        val parameters=definition.parameters
        var history=0;
        var table=IntArray(0);
        var local=IntArray(0);
        var global=IntArray(0);
        var chooser=IntArray(0)
        init {
            if(scheme=="TOURNAMENT") {
                local=IntArray(parameters[0]) {
                    1
                };
                global=IntArray(parameters[1]) {
                    1
                };
                chooser=IntArray(parameters[3]) {
                    1
                }
            }
            else if(parameters.isNotEmpty())table=IntArray(parameters[0]) {
                if(scheme=="ONEBIT")0 else 1
            }
        }
        fun prediction(pc: Int,target: Int): Boolean {
            val q=pc/4
            return when(scheme) {
                "STATIC_NT","PERFECT"->false
                "BTFN"->target<pc
                "ONEBIT"->table[q%table.size]==1
                "TWOBIT"->table[q%table.size]>=2
                "GSHARE"->table[(q xor history)%table.size]>=2
                else->if(chooser[q%chooser.size]>=2)global[(q xor history)%global.size]>=2 else local[q%local.size]>=2
            }
        }
        fun update(pc: Int,taken: Boolean) {
            val q=pc/4
            if(scheme=="TOURNAMENT") {
                val l=q%local.size;
                val g=(q xor history)%global.size;
                val c=q%chooser.size
                val lp=local[l]>=2;
                val gp=global[g]>=2
                if(lp!=gp)chooser[c]=updated(chooser[c],gp==taken)
                local[l]=updated(local[l],taken);
                global[g]=updated(global[g],taken)
                history=(2*history+(if(taken)1 else 0))%(1 shl parameters[2])
            } else if(table.isNotEmpty()) {
                val i=(if(scheme=="GSHARE")q xor history else q)%table.size
                table[i]=if(scheme=="ONEBIT")(if(taken)1 else 0) else updated(table[i],taken)
                if(scheme=="GSHARE")history=(2*history+(if(taken)1 else 0))%(1 shl parameters[1])
            }
        }
        fun bits()=when(scheme) {
            "ONEBIT"->parameters[0]
            "TWOBIT"->2*parameters[0]
            "GSHARE"->2*parameters[0]+parameters[1]
            "TOURNAMENT"->2*(parameters[0]+parameters[1]+parameters[3])+parameters[2]
            else->0
        }
    }
}
