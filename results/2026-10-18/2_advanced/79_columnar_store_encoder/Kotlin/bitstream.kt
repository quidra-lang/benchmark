import java.io.ByteArrayOutputStream
object Bitstream {
    class Writer {
        private val output=ByteArrayOutputStream();
        fun byteValue(value: Int) {
            output.write(value)
        };
        fun bytes(values: ByteArray) {
            output.writeBytes(values)
        };
        fun uleb(initial: Long) {
            var value=initial;
            while(value>=128) {
                byteValue((value%128).toInt()+128);
                value/=128
            };
            byteValue(value.toInt())
        };
        fun zigzag(value: Long) {
            uleb(if(value>=0)2*value else -2*value-1)
        };
        fun integer(value: Long) {
            for(i in 0..3)byteValue(((value ushr (8*i)) and 255).toInt())
        };
        fun size()=output.size();
        fun value()=output.toByteArray()
    }
    class Reader(val data: ByteArray,var position: Int=0) {
        fun read(count: Int): ByteArray {
            val value=data.copyOfRange(position,position+count);
            position+=count;
            return value
        };
        fun byteValue()=data[position++].toInt() and 255;
        fun uleb(): Long {
            var value=0L;
            var shift=0;
            while(true) {
                val b=byteValue();
                value=value or ((b and 127).toLong() shl shift);
                if(b<128)return value;
                shift+=7
            }
        };
        fun zigzag(): Long {
            val value=uleb();
            return if(value%2==0L)value/2 else -(value+1)/2
        };
        fun integer(signed: Boolean=false): Long {
            var value=0L;
            for(i in 0..3)value=value or (byteValue().toLong() shl (8*i));
            return if(signed&&value>=0x80000000L)value-0x100000000L else value
        }
    }
    fun bits(value: Long)=if(value==0L)0 else 64-java.lang.Long.numberOfLeadingZeros(value)
    fun pack(values: List<Long>,width: Int): ByteArray {
        val writer=Writer();
        var buffer=0L;
        var occupied=0;
        for(value in values) {
            buffer=buffer or (value shl occupied);
            occupied+=width;
            while(occupied>=8) {
                writer.byteValue((buffer and 255).toInt());
                buffer=buffer ushr 8;
                occupied-=8
            }
        };
        return writer.value()
    }
    fun unpack(reader: Reader,width: Int,count: Int): List<Long> {
        val values=mutableListOf<Long>();
        var buffer=0L;
        val mask=(1L shl width)-1;
        var occupied=0;
        repeat(count) {
            while(occupied<width) {
                buffer=buffer or (reader.byteValue().toLong() shl occupied);
                occupied+=8
            };
            values.add(buffer and mask);
            buffer=buffer ushr width;
            occupied-=width
        };
        return values
    }
    fun adler32(data: ByteArray): Long {
        var first=1L;
        var second=0L;
        for(value in data) {
            first=(first+(value.toInt() and 255))%65521;
            second=(second+first)%65521
        };
        return second*65536+first
    }
    fun hybridEncode(values: List<Long>,width: Int): ByteArray {
        val count=values.size;
        val runs=IntArray(count);
        for(i in count-1 downTo 0) {
            runs[i]=1;
            if(i+1<count&&values[i]==values[i+1])runs[i]+=runs[i+1]
        };
        val writer=Writer();
        var i=0;
        while(i<count) {
            if(runs[i]>=8) {
                writer.uleb(2L*runs[i]);
                for(j in 0 until (width+7)/8)writer.byteValue(((values[i] ushr (8*j)) and 255).toInt());
                i+=runs[i]
            }else {
                var end=i;
                var groups=0;
                do {
                    end+=8;
                    groups++
                }
                while(end<count&&groups<63&&runs[end]<8);
                writer.uleb(2L*groups+1);
                val block=values.subList(i,minOf(end,count)).toMutableList();
                while(block.size<end-i)block.add(0L);
                writer.bytes(pack(block,width));
                i=end
            }
        };
        return writer.value()
    }
    fun hybridDecode(reader: Reader,width: Int,count: Int): List<Long> {
        val values=mutableListOf<Long>();
        while(values.size<count) {
            val header=reader.uleb();
            if(header%2==0L) {
                var value=0L;
                for(i in 0 until (width+7)/8)value=value or (reader.byteValue().toLong() shl (8*i));
                repeat((header/2).toInt()) {
                    values.add(value)
                }
            }else values.addAll(unpack(reader,width,((header-1)/2).toInt()*8))
        };
        return values.take(count)
    }
}
