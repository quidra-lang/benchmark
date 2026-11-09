import java.io.File

class Mesh {
    data class FaceRef(val point: Int,val direction: Int)
    val width: Int;
    val height: Int;
    val count: Int;
    val dx: Double;
    val thickness: Double;
    val codes: CharArray;
    val neighbors: Array<IntArray>
    init {
        val lines=File("input/plate.txt").readLines();
        val w=lines[0].split(' ');
        width=w[0].toInt();
        height=w[1].toInt();
        dx=w[2].toDouble();
        thickness=w[3].toDouble();
        count=width*height
        codes=CharArray(count);
        neighbors=Array(count) {
            IntArray(4)
        }
        for(r in 0 until height)for(c in 0 until width) {
            val p=cell(r,c);
            codes[p]=lines[r+1][c];
            neighbors[p]=intArrayOf(if(c>0)p-1 else -1,if(c+1<width)p+1 else -1,if(r>0)p-width else -1,if(r+1<height)p+width else -1)
        }
    }
    fun cell(row: Int,column: Int)=row*width+column
    fun coordinates(p: Int)="${p/width} ${p%width}"
    fun segment(edge: String,start: Int,end: Int): List<FaceRef> {
        val direction=when(edge) {
            "left"->0;
            "right"->1;
            "top"->2;
            else->3
        }
        return (start..end).map {
            i->val p=when(direction) {
                0->cell(i,0);
                1->cell(i,width-1);
                2->cell(0,i);
                else->cell(height-1,i)
            };
            FaceRef(p,direction)
        }
    }
    fun source(r1: Int,c1: Int,r2: Int,c2: Int): List<Int> {
        val cells=mutableListOf<Int>();
        for(r in r1..r2)for(c in c1..c2)cells.add(cell(r,c));
        return cells
    }
}
