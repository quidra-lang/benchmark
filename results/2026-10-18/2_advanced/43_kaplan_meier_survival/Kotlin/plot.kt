import kotlin.math.floor

object Plot {
    fun draw(groups: List<List<Dataset.Subject>>,tables: List<List<Estimators.Row>>,width: Int,height: Int,horizon: Int): List<String> {
        val occupied=Array(height) {
            IntArray(width)
        };
        for(g in groups.indices) {
            val maximum=groups[g].maxOf {
                it.time
            };
            var previous=-1;
            for(col in 0 until width) {
                val time=col*(horizon/width);
                if(time>maximum)break;
                val survival=Estimators.at(tables[g],time).survival;
                val band=minOf(height-1,floor(survival*height).toInt());
                occupied[height-1-band][col]=occupied[height-1-band][col] or (1 shl g);
                if(previous-1>band)for(q in band+1 until previous)occupied[height-1-q][col]=occupied[height-1-q][col] or (1 shl g);
                previous=band
            }
        };
        val border="   +"+"-".repeat(width)+"+";
        val output=mutableListOf(border);
        for(row in 0 until height) {
            val q=height-1-row;
            val line=(100*q/height).toString().padStart(3,' ')+"|"+occupied[row].joinToString("") {
                if(it==0)" " else if(Integer.bitCount(it)==1)('A'.code+Integer.numberOfTrailingZeros(it)).toChar().toString() else "*"
            }
            +"|";
            output+=line
        };
        output+=border;
        return output
    }
}
