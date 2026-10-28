object BitIo {
    class DecodeError(val kind: String,val position: Int): RuntimeException()
    fun bits(value: Int): Int {
        var x=value;
        var count=0;
        while(x!=0) {
            count++;
            x=x ushr 1
        };
        return count
    }
    class Writer {
        val bytes=mutableListOf<Int>();
        var current=0;
        var used=0;
        var count=0
        fun write(value: Int,width: Int) {
            for(i in width-1 downTo 0) {
                current=(current shl 1) or ((value ushr i) and 1);
                used++;
                count++;
                if(used==8) {
                    bytes+=current;
                    current=0;
                    used=0
                }
            }
        }
        fun finish(): IntArray {
            val result=bytes.toMutableList();
            if(used>0)result+=current shl (8-used);
            return result.toIntArray()
        }
    }
    class Reader(val data: IntArray,val zero: Boolean) {
        var position=0
        fun read(width: Int,output: Int): Int {
            if(!zero&&position.toLong()+width>8L*data.size)throw DecodeError("end_of_data",output);
            var result=0;
            for(i in 0 until width) {
                val bit=if(position<8L*data.size)(data[position/8] ushr (7-position%8)) and 1 else 0;
                position++;
                result=(result shl 1) or bit
            };
            return result
        }
    }
}
