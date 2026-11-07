object Lz77 {
    data class Token(val literal: Int,val distance: Int,val length: Int)
    fun split(data: IntArray,b: Int,k: Int): List<Token> {
        val result=mutableListOf<Token>();
        var i=0;
        val window=1 shl b;
        val limit=(1 shl k)+2;
        while(i<data.size) {
            var distance=0;
            var length=0;
            for(d in 1..minOf(window,i)) {
                var match=0;
                while(match<minOf(limit,data.size-i)&&data[i+match]==data[i+match-d])match++;
                if(match>length) {
                    length=match;
                    distance=d
                }
            };
            if(length>=3) {
                result+=Token(-1,distance,length);
                i+=length
            }else {
                result+=Token(data[i],0,0);
                i++
            }
        };
        return result
    }
    fun copy(output: MutableList<Int>,distance: Int,length: Int,size: Long) {
        if(distance>output.size)throw BitIo.DecodeError("bad_offset",output.size);
        if(output.size.toLong()+length>size)throw BitIo.DecodeError("overrun",output.size);
        repeat(length) {
            output+=output[output.size-distance]
        }
    }
}
