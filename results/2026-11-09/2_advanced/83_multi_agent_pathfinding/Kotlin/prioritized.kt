object Prioritized {
    data class Attempt(val agent:Int,val search:LowLevel.Search)
    data class Result(val paths:List<List<GridMap.Cell>>?,val attempts:List<Attempt>,val failed:Int?,val aborted:Boolean)
    fun tryOrder(grid:GridMap,agents:List<GridMap.Agent>,distances:List<Map<GridMap.Cell,Int>>,horizon:Int,
        order:List<Int>,budget:LowLevel.Budget):Result {
        val prohibitions=LowLevel.Prohibitions();
        val paths=MutableList<List<GridMap.Cell>?>(agents.size) {
            null
        };
        val attempts=mutableListOf<Attempt>();
        for(id in order) {
            val search=try {
                LowLevel.search(grid,agents[id],distances[id],agents[id].start,0,prohibitions,horizon,budget,false)
            }catch(exception:LowLevel.BudgetExceeded) {
                return Result(null,attempts,null,true)
            };
            attempts.add(Attempt(id,search));
            val path=search.path?:return Result(null,attempts,id,false);
            paths[id]=path;
            LowLevel.reserve(prohibitions,path,0,true)
        }
        return Result(paths.map {
            it!!
        },attempts,null,false)
    }
}
