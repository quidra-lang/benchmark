import java.io.File

object Processes {
    data class Action(val kind: String,val argument: String,val value: String="")
    data class Scheduled(val first: Int,val period: Int,val action: Action)
    data class Rule(val tag: String,val action: Action)
    data class Planned(val time: Int,val process: Int,val action: Action)
    class State(val index: Int,val initial: Int,size: Int) {
        var balance=initial;
        var lamport=0;
        var incoming=0;
        var outgoing=0;
        var refused=0;
        var minimum=initial;
        var maxHeld=0
        val vector=IntArray(size);
        val broadcast=IntArray(size);
        val next=IntArray(size) {
            1
        };
        val counts=IntArray(5)
        val scheduled=mutableListOf<Scheduled>();
        val rules=mutableListOf<Rule>()
        val events=mutableListOf<Causal.Event>();
        val hold=mutableListOf<Causal.Packet>();
        val delivered=mutableListOf<Causal.Packet>()
        val reorder=List(size) {
            mutableMapOf<Int,Causal.Packet>()
        }
        fun held()=hold.size+reorder.sumOf {
            it.size
        }
        fun balanceAt(count: Int)=if(count==0)initial else events[count-1].balance
    }
    fun action(w: List<String>,start: Int)=Action(w[start],w[start+1],w.getOrElse(start+2) {
        ""
    })
    fun read(names: List<String>): List<State> {
        val result=mutableListOf<State>();
        var current: State?=null
        for(line in File("input/programs.txt").readLines()) {
            val w=line.split(' ')
            when(w[0]) {
                "PROCESS"-> {
                    val p=State(names.indexOf(w[1]),w[3].toInt(),names.size);
                    current=p;
                    result.add(p)
                }
                "AT"-> {
                    val every=w[2]=="EVERY";
                    current!!.scheduled.add(Scheduled(w[1].toInt(),if(every)w[3].toInt() else 0,action(w,if(every)4 else 2)))
                }
                "ON"->current!!.rules.add(Rule(w[1],action(w,2)))
            }
        }
        return result
    }
    fun expand(states: List<State>,end: Int): List<Planned> {
        val result=mutableListOf<Planned>()
        for(p in states)for(s in p.scheduled) {
            var time=s.first;
            while(time<=end) {
                result.add(Planned(time,p.index,s.action));
                if(s.period==0)break;
                time+=s.period
            }
        }
        return result
    }
}
