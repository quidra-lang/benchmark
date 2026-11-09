import java.io.File
import java.util.ArrayDeque
class GridMap {
    data class Cell(val x:Int,val y:Int) {
        override fun toString()=Report.cell(this)
    }
    data class Agent(val id:Int,val start:Cell,val goal:Cell) {
        val name get()=('A'.code+id).toChar()
    }
    val width:Int;
    val height:Int;
    val rows:List<String>;
    val free=mutableSetOf<Cell>()
    init {
        val lines=File("input/map.txt").readLines(Charsets.US_ASCII);
        val f=lines.first().split(' ');
        width=f[0].toInt();
        height=f[1].toInt();
        rows=lines.drop(1);
        for(y in 0 until height)for(x in 0 until width)if(rows[y][x]=='.')free.add(Cell(x,y))
    }
    fun destinations(cell:Cell):List<Cell> {
        val result=mutableListOf<Cell>();
        for((dx,dy) in directions) {
            val next=Cell(cell.x+dx,cell.y+dy);
            if(next in free)result.add(next)
        }
        return result
    }
    fun neighbors(cell:Cell)=destinations(cell).filter {
        it!=cell
    }
    fun distances(goal:Cell):Map<Cell,Int> {
        val distances=mutableMapOf(goal to 0);
        val queue=ArrayDeque<Cell>();
        queue.add(goal);
        while(queue.isNotEmpty()) {
            val cell=queue.remove();
            for(next in neighbors(cell))if(next !in distances) {
                distances[next]=distances.getValue(cell)+1;
                queue.add(next)
            }
        }
        return distances
    }
    companion object {
        val directions=listOf(0 to 0,0 to -1,1 to 0,0 to 1,-1 to 0)
        fun agents()=File("input/agents.csv").readLines(Charsets.US_ASCII).drop(1).map {
            val f=it.split(',');
            Agent(f[0].toInt(),Cell(f[1].toInt(),f[2].toInt()),Cell(f[3].toInt(),f[4].toInt()))
        }
    }
}
