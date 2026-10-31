object Table {
    class Production(val number: Int,val lhs: String,val rhs: List<String>) {
        val predict=mutableMapOf<String,String>();
        fun notation()=GrammarParser.production(lhs,rhs)
    }
    data class Cell(val lhs: String,val terminal: String)
    data class Conflict(val cell: Cell,val kind: String,val chosen: Int)
    class Result {
        val productions=mutableListOf<Production>();
        val cells=mutableMapOf<Cell,MutableList<Int>>();
        val choices=mutableMapOf<Cell,Int>();
        val conflicts=mutableListOf<Conflict>()
    }
    fun build(g: GrammarParser.Grammar,sets: FirstFollow.Sets): Result {
        val result=Result();
        for(lhs in g.order)for(rhs in g.rules.getValue(lhs))result.productions+=Production(result.productions.size+1,lhs,rhs);
        val terminals=sets.terminals+"$";
        for(lhs in g.order)for(t in terminals)result.cells[Cell(lhs,t)]=mutableListOf();
        for(p in result.productions) {
            val direct=FirstFollow.sequence(p.rhs,sets);
            for(t in direct.first)p.predict[t]="FIRST";
            if(direct.empty)for(t in sets.follow.getValue(p.lhs))p.predict.putIfAbsent(t,"FOLLOW");
            for(t in FirstFollow.terminalOrder(p.predict.keys))result.cells.getValue(Cell(p.lhs,t)).add(p.number)
        };
        for(lhs in g.order)for(t in terminals) {
            val cell=Cell(lhs,t);
            val entries=result.cells.getValue(cell);
            if(entries.isEmpty())continue;
            val chosen=entries.firstOrNull {
                result.productions[it-1].predict[t]=="FIRST"
            }
            ?:entries[0];
            result.choices[cell]=chosen;
            if(entries.size>1) {
                val kinds=entries.map {
                    result.productions[it-1].predict.getValue(t)
                }.toSet();
                val kind=if(kinds.size==2)"FIRST/FOLLOW" else if("FIRST" in kinds)"FIRST/FIRST" else "FOLLOW/FOLLOW";
                result.conflicts+=Conflict(cell,kind,chosen)
            }
        };
        return result
    }
}
