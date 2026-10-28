object Lzw {
    class Statistics {
        var codes=0;
        var clears=0;
        var longest=0;
        val widths=IntArray(4)
    }
    data class Encoded(val payload: IntArray,val stats: Statistics)
    private fun initialDictionary()=(0 until 256).associate {
        it.toChar().toString() to it
    }.toMutableMap()
    class Encoder {
        val writer=BitIo.Writer();
        val stats=Statistics();
        var since=0
        fun emit(code: Int,length: Int) {
            val width=minOf(12,BitIo.bits(258+since));
            writer.write(code,width);
            stats.codes++;
            stats.widths[width-9]++;
            stats.longest=maxOf(stats.longest,length);
            if(code==256) {
                stats.clears++;
                since=0
            }else since++
        }
    }
    fun encode(data: IntArray): Encoded {
        val e=Encoder();
        var dictionary=initialDictionary();
        var next=258;
        e.emit(256,0);
        var sequence="";
        for(value in data) {
            val character=value.toChar().toString();
            val extended=sequence+character;
            if(extended in dictionary) {
                sequence=extended;
                continue
            };
            e.emit(dictionary.getValue(sequence),sequence.length);
            dictionary[extended]=next++;
            if(next==4096) {
                e.emit(256,0);
                dictionary=initialDictionary();
                next=258
            };
            sequence=character
        };
        if(sequence.isNotEmpty())e.emit(dictionary.getValue(sequence),sequence.length);
        e.emit(257,0);
        return Encoded(e.writer.finish(),e.stats)
    }
    private fun decodedDictionary(): MutableList<String?> {
        val result=(0 until 256).map<Int,String?> {
            it.toChar().toString()
        }.toMutableList();
        result+=null;
        result+=null;
        return result
    }
    fun decode(payload: IntArray,size: Long): IntArray {
        val reader=BitIo.Reader(payload,false);
        var dictionary=decodedDictionary();
        val output=mutableListOf<Int>();
        var previous=-1;
        var since=0;
        while(true) {
            val count=since;
            val code=reader.read(minOf(12,BitIo.bits(258+count)),output.size);
            if(code==256) {
                dictionary=decodedDictionary();
                previous=-1;
                since=0;
                continue
            };
            since++;
            if(code==257) {
                if(output.size<size)throw BitIo.DecodeError("early_end",output.size);
                return output.toIntArray()
            };
            if(count==3838)throw BitIo.DecodeError("bad_code",output.size);
            val sequence=if(previous==-1) {
                if(code>=256)throw BitIo.DecodeError("bad_code",output.size);
                dictionary[code]!!
            }else if(code<dictionary.size)dictionary[code]!! else if(code==dictionary.size)dictionary[previous]!!+dictionary[previous]!![0] else throw BitIo.DecodeError("bad_code",
                output.size);
            if(output.size.toLong()+sequence.length>size)throw BitIo.DecodeError("overrun",output.size);
            for(character in sequence)output+=character.code;
            if(previous!=-1)dictionary+=dictionary[previous]!!+sequence[0];
            previous=code
        }
    }
}
