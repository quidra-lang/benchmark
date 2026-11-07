import kotlin.math.abs

object Plot {
    data class Cell(val col: Int,val row: Int)
    fun canvas(width: Int,height: Int)=Array(height) {
        CharArray(width) {
            ' '
        }
    }
    fun map(point: Predicates.Point,width: Int,height: Int)=Cell(((2*point.x*(width-1)+1000)/2000).toInt(),height-1-((2*point.y*(height-1)+1000)/2000).toInt())
    fun center(point: Predicates.Center,width: Int,height: Int)=Cell(((2*point.x*(width-1)+1000*point.d)/(2000*point.d)).toInt(),
        height-1-((2*point.y*(height-1)+1000*point.d)/(2000*point.d)).toInt())
    fun line(grid: Array<CharArray>,from: Cell,to: Cell,ch: Char) {
        var x=from.col;
        var y=from.row;
        val dx=abs(to.col-x);
        val dy=-abs(to.row-y);
        val sx=if(x<to.col)1 else -1;
        val sy=if(y<to.row)1 else -1;
        var e=dx+dy;
        while(true) {
            grid[y][x]=ch;
            if(x==to.col&&y==to.row)break;
            val e2=2*e;
            if(e2>=dy) {
                e+=dy;
                x+=sx
            };
            if(e2<=dx) {
                e+=dx;
                y+=sy
            }
        }
    }
    fun frame(grid: Array<CharArray>): List<String> {
        val border="+"+"-".repeat(grid[0].size)+"+";
        val result=mutableListOf(border);
        for(row in grid)result+="|"+row.concatToString()+"|";
        result+=border;
        return result
    }
    fun voronoi(points: List<Predicates.Point>,width: Int,height: Int): Array<CharArray> {
        val grid=canvas(width,height);
        val owners=Array(height) {
            IntArray(width)
        };
        for(row in 0 until height)for(col in 0 until width) {
            var best=Long.MAX_VALUE;
            var owner=0;
            for(site in 1 until points.size) {
                val p=points[site];
                val x=(col*1000-p.x*(width-1))*(height-1);
                val y=((height-1-row)*1000-p.y*(height-1))*(width-1);
                val delta=x*x+y*y;
                if(delta<best) {
                    best=delta;
                    owner=site
                }
            };
            owners[row][col]=owner
        };
        for(row in 0 until height)for(col in 0 until width)if(col+1<width&&owners[row][col]!=owners[row][col+1]||row+1<height&&owners[row][col]!=owners[row+1][col])grid[row][col]='#';
        for(site in 1 until points.size) {
            val cell=map(points[site],width,height);
            grid[cell.row][cell.col]='o'
        };
        return grid
    }
}
