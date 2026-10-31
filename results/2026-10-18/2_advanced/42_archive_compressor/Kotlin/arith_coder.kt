object ArithCoder {
    class Table {
        val frequencies=IntArray(257) {
            1
        };
        var total=257;
        var rescales=0
        fun cumulative(symbol: Int): Int {
            var sum=0;
            for(i in 0 until symbol)sum+=frequencies[i];
            return sum
        }
        fun locate(value: Int): IntArray {
            var cumulative=0;
            for(symbol in 0 until 257) {
                if(value<cumulative+frequencies[symbol])return intArrayOf(symbol,cumulative,frequencies[symbol]);
                cumulative+=frequencies[symbol]
            };
            error("arithmetic interval")
        }
        fun update(symbol: Int) {
            frequencies[symbol]+=32;
            total+=32;
            if(total>=8192) {
                total=0;
                for(i in frequencies.indices) {
                    frequencies[i]=(frequencies[i]+1)/2;
                    total+=frequencies[i]
                };
                rescales++
            }
        }
    }
    data class Encoded(val payload: IntArray,val bits: Int,val contexts: Int,val rescales: Int)
    class Encoder {
        val writer=BitIo.Writer();
        var follow=0;
        fun emit(bit: Int) {
            writer.write(bit,1);
            repeat(follow) {
                writer.write(1-bit,1)
            };
            follow=0
        }
    }
    fun encode(data: IntArray): Encoded {
        val e=Encoder();
        val tables=mutableMapOf<Int,Table>();
        var low=0;
        var high=65535;
        var context=10;
        for(index in 0..data.size) {
            val symbol=if(index==data.size)256 else data[index];
            val table=tables.getOrPut(context) {
                Table()
            };
            val cumulative=table.cumulative(symbol);
            val span=high-low+1;
            high=low+span*(cumulative+table.frequencies[symbol])/table.total-1;
            low+=span*cumulative/table.total;
            while(true) {
                if(high<32768)e.emit(0) else if(low>=32768) {
                    e.emit(1);
                    low-=32768;
                    high-=32768
                }else if(low>=16384&&high<49152) {
                    e.follow++;
                    low-=16384;
                    high-=16384
                }else break;
                low*=2;
                high=2*high+1
            };
            if(symbol!=256) {
                table.update(symbol);
                context=symbol
            }
        };
        e.follow++;
        e.emit(if(low<16384)0 else 1);
        return Encoded(e.writer.finish(),e.writer.count,tables.size,tables.values.sumOf {
            it.rescales
        })
    }
    fun decode(payload: IntArray,size: Long): IntArray {
        val reader=BitIo.Reader(payload,true);
        val tables=mutableMapOf<Int,Table>();
        val output=mutableListOf<Int>();
        var low=0;
        var high=65535;
        var value=reader.read(16,0);
        var context=10;
        while(true) {
            val table=tables.getOrPut(context) {
                Table()
            };
            val span=high-low+1;
            val quantile=((value-low+1)*table.total-1)/span;
            val found=table.locate(quantile);
            val symbol=found[0];
            val cumulative=found[1];
            val frequency=found[2];
            high=low+span*(cumulative+frequency)/table.total-1;
            low+=span*cumulative/table.total;
            while(true) {
                if(high<32768) {
                }else if(low>=32768) {
                    low-=32768;
                    high-=32768;
                    value-=32768
                }else if(low>=16384&&high<49152) {
                    low-=16384;
                    high-=16384;
                    value-=16384
                }else break;
                low*=2;
                high=2*high+1;
                value=2*value+reader.read(1,output.size)
            };
            if(symbol==256) {
                if(output.size<size)throw BitIo.DecodeError("early_end",output.size);
                return output.toIntArray()
            };
            if(output.size.toLong()==size)throw BitIo.DecodeError("overrun",output.size);
            output+=symbol;
            table.update(symbol);
            context=symbol
        }
    }
}
