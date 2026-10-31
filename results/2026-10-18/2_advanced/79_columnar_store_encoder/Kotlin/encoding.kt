object Encoding {
    val methods=listOf("PLAIN","DICTIONARY","RLE","DELTA_BINARY_PACKED","DELTA_LENGTH_BYTE_ARRAY")
    data class Bounds(val low: SchemaIo.Value,val high: SchemaIo.Value)
    fun candidates(kind: String)=when(kind) {
        "BOOL"->listOf(0,2);
        "STRING"->listOf(0,1,4);
        else->listOf(0,1,3)
    }
    fun deltaEncode(values: List<Long>): ByteArray {
        val writer=Bitstream.Writer();
        writer.uleb(128);
        writer.uleb(4);
        writer.uleb(values.size.toLong());
        writer.zigzag(values.firstOrNull()?:0L);
        val deltas=(1 until values.size).map {
            values[it]-values[it-1]
        };
        for(start in deltas.indices step 128) {
            val block=deltas.subList(start,minOf(start+128,deltas.size));
            val minimum=block.min();
            writer.zigzag(minimum);
            val miniblocks=mutableListOf<MutableList<Long>>();
            val widths=IntArray(4);
            for(t in 0..3) {
                val mini=(32*t until minOf(32*(t+1),block.size)).map {
                    block[it]-minimum
                }.toMutableList();
                widths[t]=Bitstream.bits(mini.maxOrNull()?:0L);
                writer.byteValue(widths[t]);
                miniblocks.add(mini)
            };
            for(t in 0..3)if(miniblocks[t].isNotEmpty()) {
                val mini=miniblocks[t];
                while(mini.size<32)mini.add(0L);
                writer.bytes(Bitstream.pack(mini,widths[t]))
            }
        };
        return writer.value()
    }
    fun deltaDecode(reader: Bitstream.Reader): List<Long> {
        val blockSize=reader.uleb().toInt();
        val miniblockCount=reader.uleb().toInt();
        val count=reader.uleb().toInt();
        val first=reader.zigzag();
        val values=mutableListOf<Long>();
        if(count>0)values.add(first);
        val miniblockSize=blockSize/miniblockCount;
        while(values.size<count) {
            val minimum=reader.zigzag();
            val widths=IntArray(miniblockCount) {
                reader.byteValue()
            };
            for(width in widths) {
                if(values.size==count)break;
                val differences=Bitstream.unpack(reader,width,miniblockSize);
                val remaining=minOf(miniblockSize,count-values.size);
                for(i in 0 until remaining)values.add(values.last()+minimum+differences[i])
            }
        };
        return values
    }
    fun encodeValues(kind: String,method: Int,values: List<SchemaIo.Value>,dictionary: List<SchemaIo.Value>?): ByteArray {
        val writer=Bitstream.Writer();
        when(method) {
            0-> {
                when(kind) {
                    "INT","DATE"->for(value in values)writer.integer((value as SchemaIo.NumberValue).value);
                    "STRING"->for(value in values) {
                        val text=(value as SchemaIo.TextValue).value;
                        writer.integer(text.length.toLong());
                        writer.bytes(text.toByteArray(Charsets.US_ASCII))
                    };
                    else-> {
                        val bits=values.map {
                            if((it as SchemaIo.BoolValue).value)1L else 0L
                        }.toMutableList();
                        while(bits.size%8!=0)bits.add(0L);
                        writer.bytes(Bitstream.pack(bits,1))
                    }
                }
            };
            1-> {
                val entries=dictionary!!;
                val ranks=entries.withIndex().associate {
                    it.value to it.index
                };
                val width=Bitstream.bits(entries.size.toLong()-1);
                writer.byteValue(width);
                writer.bytes(Bitstream.hybridEncode(values.map {
                    ranks.getValue(it).toLong()
                },width))
            };
            2-> {
                val bits=values.map {
                    if((it as SchemaIo.BoolValue).value)1L else 0L
                };
                val encoded=Bitstream.hybridEncode(bits,1);
                writer.integer(encoded.size.toLong());
                writer.bytes(encoded)
            };
            3->writer.bytes(deltaEncode(values.map {
                (it as SchemaIo.NumberValue).value
            }));
            else-> {
                writer.bytes(deltaEncode(values.map {
                    (it as SchemaIo.TextValue).value.length.toLong()
                }));
                for(value in values)writer.bytes((value as SchemaIo.TextValue).value.toByteArray(Charsets.US_ASCII))
            }
        };
        return writer.value()
    }
    fun decodeValues(reader: Bitstream.Reader,kind: String,method: Int,count: Int,dictionary: List<SchemaIo.Value>?): List<SchemaIo.Value> {
        val values=mutableListOf<SchemaIo.Value>();
        when(method) {
            0-> {
                when(kind) {
                    "INT","DATE"->repeat(count) {
                        values.add(SchemaIo.NumberValue(reader.integer(true)))
                    };
                    "STRING"->repeat(count) {
                        values.add(SchemaIo.TextValue(reader.read(reader.integer().toInt()).toString(Charsets.US_ASCII)))
                    };
                    else-> {
                        val bits=Bitstream.unpack(reader,1,(count+7)/8*8);
                        for(i in 0 until count)values.add(SchemaIo.BoolValue(bits[i]!=0L))
                    }
                }
            };
            1-> {
                val width=reader.byteValue();
                for(index in Bitstream.hybridDecode(reader,width,count))values.add(dictionary!![index.toInt()])
            };
            2-> {
                val encoded=Bitstream.Reader(reader.read(reader.integer().toInt()));
                for(value in Bitstream.hybridDecode(encoded,1,count))values.add(SchemaIo.BoolValue(value!=0L))
            };
            3->for(value in deltaDecode(reader))values.add(SchemaIo.NumberValue(value));
            else->for(length in deltaDecode(reader))values.add(SchemaIo.TextValue(reader.read(length.toInt()).toString(Charsets.US_ASCII)))
        };
        return values
    }
    fun encodeStatistics(kind: String,bounds: Bounds?): ByteArray {
        val writer=Bitstream.Writer();
        writer.byteValue(if(bounds==null)0 else 1);
        if(bounds!=null)for(value in listOf(bounds.low,bounds.high))when(kind) {
            "INT","DATE"->writer.zigzag((value as SchemaIo.NumberValue).value);
            "STRING"-> {
                val text=(value as SchemaIo.TextValue).value;
                writer.uleb(text.length.toLong());
                writer.bytes(text.toByteArray(Charsets.US_ASCII))
            };
            else->writer.byteValue(if((value as SchemaIo.BoolValue).value)1 else 0)
        };
        return writer.value()
    }
    fun decodeStatistics(reader: Bitstream.Reader,kind: String): Bounds? {
        if(reader.byteValue()==0)return null;
        val values=List<SchemaIo.Value>(2) {
            when(kind) {
                "INT","DATE"->SchemaIo.NumberValue(reader.zigzag());
                "STRING"->SchemaIo.TextValue(reader.read(reader.uleb().toInt()).toString(Charsets.US_ASCII));
                else->SchemaIo.BoolValue(reader.byteValue()!=0)
            }
        };
        return Bounds(values[0],values[1])
    }
}
