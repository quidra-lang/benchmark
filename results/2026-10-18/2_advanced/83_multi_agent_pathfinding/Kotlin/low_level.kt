import java.util.PriorityQueue
object LowLevel {
    data class State(val cell:GridMap.Cell,val time:Int)
    data class Move(val source:GridMap.Cell,val destination:GridMap.Cell,val time:Int)
    class BudgetExceeded:RuntimeException()
    class Budget(val limit:Int?) {
        var searches=0;
        var expansions=0
        fun expand() {
            expansions++;
            if(limit!=null&&expansions>limit)throw BudgetExceeded()
        }
    }
    class Prohibitions {
        val states=mutableSetOf<State>();
        val permanent=mutableSetOf<State>();
        val moves=mutableSetOf<Move>()
        fun copy():Prohibitions {
            val p=Prohibitions();
            p.states.addAll(states);
            p.permanent.addAll(permanent);
            p.moves.addAll(moves);
            return p
        }
        fun stateAllowed(cell:GridMap.Cell,time:Int)=State(cell,time) !in states&&permanent.none {
            it.cell==cell&&it.time<=time
        }
        fun actionAllowed(source:GridMap.Cell,destination:GridMap.Cell,time:Int)=stateAllowed(destination,
            time)&&(source==destination||Move(source,destination,time) !in moves)
        fun arrivalAllowed(goal:GridMap.Cell)=states.filter {
            it.cell==goal
        }.maxOfOrNull {
            it.time+1
        }?:0
    }
    fun reserve(prohibitions:Prohibitions,path:List<GridMap.Cell>,startTime:Int,permanent:Boolean) {
        for((k,cell) in path.withIndex()) {
            val time=startTime+k;
            prohibitions.states.add(State(cell,time));
            if(k>0&&cell!=path[k-1])prohibitions.moves.add(Move(cell,path[k-1],time))
        }
        if(permanent)prohibitions.permanent.add(State(path.last(),startTime+path.size-1))
    }
    data class Entry(val f:Int,val g:Int,val insertion:Int,val state:State)
    data class Search(val path:List<GridMap.Cell>?,val expansions:Int)
    fun search(grid:GridMap,agent:GridMap.Agent,distances:Map<GridMap.Cell,Int>,start:GridMap.Cell,t0:Int,
        prohibitions:Prohibitions,tmax:Int,budget:Budget,window:Boolean):Search {
        budget.searches++;
        val beginning=budget.expansions;
        val arrival=prohibitions.arrivalAllowed(agent.goal);
        var insertion=0;
        val open=PriorityQueue(compareBy<Entry> {
            it.f
        }.thenByDescending {
            it.g
        }.thenBy {
            it.insertion
        });
        val startState=State(start,t0);
        val parents=mutableMapOf<State,State?>(startState to null);
        open.add(Entry(distances.getValue(start),0,0,startState));
        while(open.isNotEmpty()) {
            val state=open.remove().state;
            budget.expand();
            val cell=state.cell;
            val time=state.time;
            if(cell==agent.goal&&time>=arrival||window&&time==tmax) {
                val path=mutableListOf<GridMap.Cell>();
                var current:State?=state;
                while(current!=null) {
                    path.add(current.cell);
                    current=parents[current]
                }
                return Search(path.reversed(),budget.expansions-beginning)
            }
            if(time==tmax)continue;
            for(destination in grid.destinations(cell)) {
                val next=State(destination,time+1);
                if(destination !in distances||next in parents||!prohibitions.actionAllowed(cell,destination,time+1))continue;
                parents[next]=state;
                val g=time+1-t0;
                open.add(Entry(g+distances.getValue(destination),g,++insertion,next))
            }
        }
        return Search(null,budget.expansions-beginning)
    }
}
