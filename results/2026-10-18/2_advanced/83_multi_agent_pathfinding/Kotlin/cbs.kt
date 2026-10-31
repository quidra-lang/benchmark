object Cbs {
    data class Conflict(val kind:String,val time:Int,val a:Int,val b:Int,val u:GridMap.Cell,val v:GridMap.Cell)
    data class Constraint(val agent:Int,val time:Int,val kind:String,val u:GridMap.Cell,val v:GridMap.Cell)
    fun position(path:List<GridMap.Cell>,time:Int)=path[minOf(time,path.size-1)]
    fun conflicts(paths:List<List<GridMap.Cell>>):List<Conflict> {
        val result=mutableListOf<Conflict>();
        val horizon=paths.maxOf {
            it.size-1
        };
        for(time in 1..horizon)for(a in paths.indices)for(b in a+1 until paths.size) {
            val currentA=position(paths[a],time);
            val currentB=position(paths[b],time);
            if(currentA==currentB)result.add(Conflict("vertex",time,a,b,currentA,currentA))else if(currentA==position(paths[b],
                time-1)&&currentB==position(paths[a],time-1))result.add(Conflict("edge",time,a,b,position(paths[a],
                time-1),currentA))
        }
        return result
    }
    fun split(conflict:Conflict)=listOf(Constraint(conflict.a,conflict.time,conflict.kind,conflict.u,
        conflict.v),Constraint(conflict.b,conflict.time,conflict.kind,conflict.v,conflict.u))
    fun cost(paths:List<List<GridMap.Cell>>,function:String)=if(function=="SOC")paths.sumOf {
        it.size-1
    } else paths.maxOf {
        it.size-1
    }
    class Node(val paths:List<List<GridMap.Cell>>,val constraints:List<LowLevel.Prohibitions>,val number:Int,
        val depth:Int,val parent:Int?,function:String) {
        val conflicts=Cbs.conflicts(paths);
        val cost=Cbs.cost(paths,function)
    }
    val order=compareBy<Node> {
        it.cost
    }.thenBy {
        it.conflicts.size
    }.thenBy {
        it.number
    }
    fun orderedConstraints(node:Node):List<Constraint> {
        val result=mutableListOf<Constraint>();
        for((i,p) in node.constraints.withIndex()) {
            for(state in p.states)result.add(Constraint(i,state.time,"vertex",state.cell,state.cell));
            for(move in p.moves)result.add(Constraint(i,move.time,"edge",move.source,move.destination))
        }
        return result.sortedWith(compareBy<Constraint> {
            it.agent
        }.thenBy {
            it.time
        }.thenBy {
            if(it.kind=="vertex")0 else 1
        }.thenBy {
            it.u.x
        }.thenBy {
            it.u.y
        }.thenBy {
            it.v.x
        }.thenBy {
            it.v.y
        })
    }
}
