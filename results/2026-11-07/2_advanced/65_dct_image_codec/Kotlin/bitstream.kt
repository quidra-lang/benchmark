object Bitstream {
    class DecodeError(val kind: String): RuntimeException(kind)
    class Writer {
        val data=mutableListOf<Int>();
        var buffer=0;
        var pending=0;
        var paddingBits=0;
        var stuffedBytes=0
        fun write(value: Int,width: Int) {
            for(shift in width-1 downTo 0) {
                buffer=2*buffer+((value shr shift) and 1);
                pending++;
                if(pending==8) {
                    data.add(buffer);
                    if(buffer==255) {
                        data.add(0);
                        stuffedBytes++
                    };
                    buffer=0;
                    pending=0
                }
            }
        }
        fun pad() {
            if(pending!=0) {
                val width=8-pending;
                paddingBits+=width;
                write((1 shl width)-1,width)
            }
        }
        fun restart(number: Int) {
            pad();
            data.add(255);
            data.add(208+number%8)
        }
    }
    class Reader(val data: IntArray,var position: Int) {
        var buffer=0;
        var remaining=0
        fun bit(): Int {
            if(remaining==0) {
                val value=data[position];
                if(value==255) {
                    if(data[position+1]!=0)throw DecodeError("marker");
                    position+=2
                } else position++;
                buffer=value;
                remaining=8
            };
            remaining--;
            return (buffer shr remaining) and 1
        }
        fun read(width: Int): Int {
            var value=0;
            repeat(width) {
                value=2*value+bit()
            };
            return value
        }
        fun discard() {
            buffer=0;
            remaining=0
        }
    }
    fun resync(data: IntArray,position: Int): Int {
        for(q in position until data.size-1)if(data[q]==255&&(data[q+1] in 208..215||data[q+1]==217))return q;
        error("Missing end marker")
    }
}
