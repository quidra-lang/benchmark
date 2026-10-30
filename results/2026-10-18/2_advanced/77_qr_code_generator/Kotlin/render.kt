object Render {
    fun symbolLines(symbol: Array<IntArray>)=symbol.map {
        row->row.joinToString("") {
            if(it==1)"#" else "."
        }
    }
    fun pbmText(symbol: Array<IntArray>,quiet: Int,scale: Int): String {
        val size=symbol.size;
        val width=(size+2*quiet)*scale;
        return buildString {
            append("P1\n$width $width\n");
            for(y in 0 until width) {
                for(x in 0 until width) {
                    val mx=x/scale-quiet;
                    val my=y/scale-quiet;
                    append(if(mx in 0 until size&&my in 0 until size)symbol[my][mx] else 0)
                };
                append('\n')
            }
        }
    }
}
