import java.io.File

private val METHODS=listOf("STORE","LZW","LZ77","LZH","ARITH")
private val STATUSES=listOf("ok","repaired","checksum","error","unsupported","truncated","bad_header")
private class Lzh {
    var payload=intArrayOf();
    var dynamic=false;
    var fixedBits=0;
    var tableBits=0;
    var codeBits=0;
    var halvings=0;
    var litUsed=0;
    var litMax=0;
    var offsetUsed=0;
    var offsetMax=0;
    var slots=intArrayOf()
}
private fun fixed(count: Int): IntArray {
    val width=BitIo.bits(count-1);
    val shorter=(1 shl width)-count;
    return IntArray(count) {
        if(it<shorter)width-1 else width
    }
}
private fun writeTable(writer: BitIo.Writer,lengths: IntArray) {
    var s=0;
    while(s<lengths.size) {
        if(lengths[s]>0) {
            writer.write(lengths[s],4);
            s++
        }else {
            var count=1;
            while(count<256&&s+count<lengths.size&&lengths[s+count]==0)count++;
            writer.write(0,4);
            writer.write(count-1,8);
            s+=count
        }
    }
}
private fun readTable(reader: BitIo.Reader,count: Int,position: Int): IntArray {
    val lengths=IntArray(count);
    var s=0;
    while(s<count) {
        val value=reader.read(4,position);
        if(value>0)lengths[s++]=value else {
            val run=reader.read(8,position)+1;
            if(s+run>count)throw BitIo.DecodeError("bad_table",position);
            s+=run
        }
    };
    var used=0;
    var only=0;
    var sum=0;
    for(value in lengths)if(value>0) {
        used++;
        only=value;
        sum+=1 shl (15-value)
    };
    if((used==1&&only!=1)||(used>=2&&sum!=(1 shl 15)))throw BitIo.DecodeError("bad_table",position);
    return lengths
}
private fun symbol(writer: BitIo.Writer,symbol: Int,lengths: IntArray,codes: IntArray) {
    writer.write(codes[symbol],lengths[symbol])
}
private fun readSymbol(reader: BitIo.Reader,lengths: IntArray,codes: IntArray,position: Int): Int {
    val maximum=lengths.max();
    if(maximum==0)throw BitIo.DecodeError("bad_code",position);
    var code=0;
    for(width in 1..maximum) {
        code=(code shl 1) or reader.read(1,position);
        for(s in lengths.indices)if(lengths[s]==width&&codes[s]==code)return s
    };
    throw BitIo.DecodeError("bad_code",position)
}
private fun writeTokens(writer: BitIo.Writer,tokens: List<Lz77.Token>,p: IntArray,q: IntArray) {
    val pc=Huffman.canonical(p);
    val qc=Huffman.canonical(q);
    for(t in tokens) {
        if(t.literal>=0)symbol(writer,t.literal,p,pc)else {
            symbol(writer,256+t.length-3,p,pc);
            val u=t.distance-1;
            val slot=BitIo.bits(u);
            symbol(writer,slot,q,qc);
            if(slot>=2)writer.write(u-(1 shl (slot-1)),slot-1)
        }
    }
}
private fun lzh(tokens: List<Lz77.Token>,b: Int,k: Int,maximum: Int): Lzh {
    val pf=IntArray(256+(1 shl k));
    val qf=IntArray(b+1);
    for(t in tokens)if(t.literal>=0)pf[t.literal]++ else {
        pf[256+t.length-3]++;
        qf[BitIo.bits(t.distance-1)]++
    };
    val p=Huffman.limited(pf,maximum);
    val q=Huffman.limited(qf,maximum);
    val result=Lzh();
    result.slots=qf;
    result.halvings=p.halvings+q.halvings;
    for(value in p.lengths)if(value>0) {
        result.litUsed++;
        result.litMax=maxOf(result.litMax,value)
    };
    for(value in q.lengths)if(value>0) {
        result.offsetUsed++;
        result.offsetMax=maxOf(result.offsetMax,value)
    };
    val fp=fixed(pf.size);
    val fq=fixed(qf.size);
    val fixed=BitIo.Writer();
    writeTokens(fixed,tokens,fp,fq);
    result.fixedBits=fixed.count;
    val tables=BitIo.Writer();
    writeTable(tables,p.lengths);
    writeTable(tables,q.lengths);
    result.tableBits=tables.count;
    val dynamic=BitIo.Writer();
    writeTokens(dynamic,tokens,p.lengths,q.lengths);
    result.codeBits=dynamic.count;
    result.dynamic=result.fixedBits>result.tableBits+result.codeBits;
    val writer=BitIo.Writer();
    writer.write(if(result.dynamic)1 else 0,1);
    if(result.dynamic) {
        writeTable(writer,p.lengths);
        writeTable(writer,q.lengths);
        writeTokens(writer,tokens,p.lengths,q.lengths)
    }else writeTokens(writer,tokens,fp,fq);
    result.payload=writer.finish();
    return result
}
private fun lz77(tokens: List<Lz77.Token>,b: Int,k: Int): IntArray {
    val writer=BitIo.Writer();
    for(t in tokens)if(t.literal>=0) {
        writer.write(0,1);
        writer.write(t.literal,8)
    }else {
        writer.write(1,1);
        writer.write(t.distance-1,b);
        writer.write(t.length-3,k)
    };
    return writer.finish()
}
private fun decode(method: Int,payload: IntArray,size: Long,b: Int,k: Int): IntArray {
    if(method==1)return Lzw.decode(payload,size);
    if(method==4)return ArithCoder.decode(payload,size);
    val output=mutableListOf<Int>();
    if(method==0) {
        for(value in payload) {
            if(output.size.toLong()==size)break;
            output+=value
        };
        if(output.size<size)throw BitIo.DecodeError("end_of_data",output.size);
        return output.toIntArray()
    };
    val reader=BitIo.Reader(payload,false);
    var p=intArrayOf();
    var q=intArrayOf();
    var pc=intArrayOf();
    var qc=intArrayOf();
    if(method==3) {
        if(reader.read(1,0)==1) {
            p=readTable(reader,256+(1 shl k),0);
            q=readTable(reader,b+1,0)
        }else {
            p=fixed(256+(1 shl k));
            q=fixed(b+1)
        };
        pc=Huffman.canonical(p);
        qc=Huffman.canonical(q)
    };
    while(output.size<size) {
        if(method==2) {
            if(reader.read(1,output.size)==0)output+=reader.read(8,output.size) else {
                val distance=reader.read(b,output.size)+1;
                val length=reader.read(k,output.size)+3;
                Lz77.copy(output,distance,length,size)
            }
        }else {
            val t=readSymbol(reader,p,pc,output.size);
            if(t<256)output+=t else {
                val length=t-253;
                val slot=readSymbol(reader,q,qc,output.size);
                val u=if(slot<=1)slot else (1 shl (slot-1))+reader.read(slot-1,output.size);
                Lz77.copy(output,u+1,length,size)
            }
        }
    };
    return output.toIntArray()
}
private class Encoded(val payloads: Array<IntArray>,val best: Int,val lzw: Lzw.Statistics,val tokens: List<Lz77.Token>,
    val lzh: Lzh,val arith: ArithCoder.Encoded)
private fun encode(data: IntArray,b: Int,k: Int,m: Int): Encoded {
    val tokens=Lz77.split(data,b,k);
    val lzw=Lzw.encode(data);
    val lzh=lzh(tokens,b,k,m);
    val arith=ArithCoder.encode(data);
    val payloads=arrayOf(data.copyOf(),lzw.payload,lz77(tokens,b,k),lzh.payload,arith.payload);
    var best=0;
    for(i in 1..4)if(payloads[i].size<payloads[best].size)best=i;
    return Encoded(payloads,best,lzw.stats,tokens,lzh,arith)
}
private fun adler(data: IntArray): Long {
    var s1=1L;
    var s2=0L;
    for(x in data) {
        s1=(s1+x)%65521;
        s2=(s2+s1)%65521
    };
    return s2*65536+s1
}
private fun mod(value: Long)=Math.floorMod(value,65521L)
private fun power(value: Long,exponent: Int): Long {
    var base=value;
    var exp=exponent;
    var result=1L;
    while(exp>0) {
        if((exp and 1)!=0)result=result*base%65521;
        base=base*base%65521;
        exp=exp ushr 1
    };
    return result
}
private data class Repair(val position: Int,val before: Int,val after: Int)
private fun repair(data: IntArray,stored: Long,computed: Long): Repair? {
    val a=mod(stored%65536-computed%65536);
    val b=mod(stored/65536-computed/65536);
    val delta=if(a in 1L..255L)a.toInt() else if(a in 65266L..65520L)a.toInt()-65521 else return null;
    val t=b*power(mod(delta.toLong()),65519)%65521;
    if(t<1||t>data.size)return null;
    val p=data.size-t.toInt();
    val before=data[p];
    val after=before+delta;
    if(after !in 0..255)return null;
    data[p]=after;
    if(adler(data)==stored)return Repair(p,before,after);
    data[p]=before;
    return null
}
private fun integer(output: MutableList<Int>,value: Long,width: Int) {
    for(i in width-1 downTo 0)output+=((value ushr (8*i)) and 255).toInt()
}
private fun integer(data: IntArray,position: Int,width: Int): Long {
    var value=0L;
    for(i in 0 until width)value=value*256+data[position+i];
    return value
}
private fun ascii(text: String)=IntArray(text.length) {
    text[it].code
}
private data class Item(val name: String,val data: IntArray,val encoded: Encoded)
private fun archive(items: List<Item>,b: Int,k: Int): IntArray {
    val output=ascii("TXAR").toMutableList();
    output+=b;
    output+=k;
    integer(output,items.size.toLong(),2);
    for(item in items) {
        val start=output.size;
        val method=item.encoded.best;
        output+=item.name.length;
        output.addAll(ascii(item.name).toList());
        output+=method;
        integer(output,item.data.size.toLong(),4);
        val payload=item.encoded.payloads[method];
        integer(output,payload.size.toLong(),4);
        integer(output,adler(item.data),4);
        var sum=0;
        for(i in start until output.size)sum+=output[i];
        output+=sum%256;
        output.addAll(payload.toList())
    };
    return output.toIntArray()
}
private class Entry(val number: Int,val offset: Long) {
    var method=0;
    var start=0L;
    var original=0L;
    var compressed=0L;
    var stored=0L;
    var computed=0L;
    var name="";
    var status="";
    var detail="";
    var valid=false;
    var headerTruncated=false;
    var data=intArrayOf()
}
private class Parsed(val length: Int) {
    var error: String?=null;
    var b=0;
    var k=0;
    var declared=0;
    var trailing=0;
    var stopped=false;
    val entries=mutableListOf<Entry>()
}
private fun parse(data: IntArray): Parsed {
    val result=Parsed(data.size);
    if(data.size<8||data[0]!='T'.code||data[1]!='X'.code||data[2]!='A'.code||data[3]!='R'.code) {
        result.error="bad_magic";
        return result
    };
    result.b=data[4];
    result.k=data[5];
    if(result.b !in 6..12||result.k !in 2..5) {
        result.error="bad_params";
        return result
    };
    result.declared=integer(data,6,2).toInt();
    var position=8L;
    for(number in 1..result.declared) {
        val e=Entry(number,position);
        result.entries+=e;
        if(position>=data.size||position+15+data[position.toInt()]>data.size) {
            e.status="truncated";
            e.headerTruncated=true;
            result.stopped=true;
            break
        };
        val pos=position.toInt();
        val m=data[pos];
        e.name=buildString {
            for(i in 0 until m)append(data[pos+1+i].toChar())
        };
        var cursor=pos+1+m;
        e.method=data[cursor++];
        e.original=integer(data,cursor,4);
        cursor+=4;
        e.compressed=integer(data,cursor,4);
        cursor+=4;
        e.stored=integer(data,cursor,4);
        cursor+=4;
        var sum=0;
        for(i in pos until cursor)sum+=data[i];
        e.start=(cursor+1).toLong();
        val next=e.start+e.compressed;
        if(sum%256!=data[cursor]||!Regex("[a-z0-9._-]{1,32}").matches(e.name)) {
            e.status="bad_header";
            position=next;
            if(position>data.size) {
                result.stopped=true;
                break
            };
            continue
        };
        e.valid=true;
        if(next>data.size) {
            e.status="truncated";
            result.stopped=true;
            break
        };
        if(e.method>=5)e.status="unsupported" else {
            try {
                e.data=decode(e.method,data.copyOfRange(e.start.toInt(),next.toInt()),e.original,result.b,result.k);
                e.computed=adler(e.data);
                if(e.computed==e.stored)e.status="ok" else {
                    val repaired=repair(e.data,e.stored,e.computed);
                    if(repaired==null) {
                        e.status="checksum";
                        e.detail=" stored ${hex(e.stored,8)} computed ${hex(e.computed,8)}"
                    }else {
                        e.status="repaired";
                        e.detail=" byte ${repaired.position} from ${repaired.before} to ${repaired.after}"
                    }
                }
            }catch(error: BitIo.DecodeError) {
                e.status="error";
                e.detail=" ${error.kind} at ${error.position}"
            }
        };
        position=next
    };
    result.trailing=if(result.stopped)0 else data.size-position.toInt();
    return result
}
private fun verify(parsed: Parsed,items: List<Item>)=parsed.entries.indices.count {
    parsed.entries[it].status=="ok"&&parsed.entries[it].data.contentEquals(items[it].data)
}
private fun hex(value: Long,width: Int)=value.toString(16).padStart(width,'0')
private fun hexadecimal(data: IntArray): List<String> {
    val lines=mutableListOf<String>();
    for(start in data.indices step 32)lines+=buildString {
        for(i in start until minOf(data.size,start+32))append(hex(data[i].toLong(),2))
    };
    return lines
}
private fun ratio(compressed: Long,original: Long)=if(original==0L)"-" else (1000*compressed/original).toString()
private fun method(number: Int)=if(number<5)METHODS[number] else "#$number"
private fun integers(data: IntArray)=data.joinToString(" ")
private fun textLines(data: IntArray): List<String> {
    if(data.isEmpty())return emptyList();
    val text=buildString {
        for(value in data)append(value.toChar())
    };
    return text.dropLast(1).split('\n')
}
private fun write(name: String,lines: List<String>) {
    File("output/$name").writeText(if(lines.isEmpty())"" else lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
}
private fun creation(items: List<Item>,created: IntArray,b: Int,k: Int,m: Int) {
    val sizes=mutableListOf("params offset_bits $b length_bits $k window ${1 shl b} lookahead ${(1 shl k)+2} max_code_length $m");
    val analysis=mutableListOf<String>();
    var original=0L;
    var bestTotal=0L;
    val totals=LongArray(5);
    val chosen=IntArray(5);
    for(item in items) {
        val n=item.data.size;
        val e=item.encoded;
        var line="file ${item.name} original $n";
        original+=n;
        for(i in 0..4) {
            val size=e.payloads[i].size;
            totals[i]+=size.toLong();
            line+=" ${METHODS[i]} $size ${ratio(size.toLong(),n.toLong())}"
        };
        line+=" best ${METHODS[e.best]}";
        sizes+=line;
        bestTotal+=e.payloads[e.best].size;
        chosen[e.best]++;
        val l=e.lzw;
        analysis+="lzw ${item.name} codes ${l.codes} clears ${l.clears} widths ${integers(l.widths)} longest ${l.longest}";
        var literals=0;
        var matches=0;
        var matched=0;
        var longest=0;
        var farthest=0;
        for(token in e.tokens)if(token.literal>=0)literals++ else {
            matches++;
            matched+=token.length;
            longest=maxOf(longest,token.length);
            farthest=maxOf(farthest,token.distance)
        };
        analysis+="lz77 ${item.name} tokens ${e.tokens.size} literals $literals matches $matches matched $matched longest $longest farthest $farthest";
        val h=e.lzh;
        analysis+="lzh ${item.name} mode ${if(h.dynamic)"dynamic" else "fixed"} fixed_bits ${h.fixedBits} table_bits ${h.tableBits} code_bits ${h.codeBits} halvings ${h.halvings} litlen_used ${h.litUsed} litlen_max ${h.litMax} offset_used ${h.offsetUsed} offset_max ${h.offsetMax}";
        analysis+="slots ${item.name} ${integers(h.slots)}";
        analysis+="arith ${item.name} bits ${e.arith.bits} contexts ${e.arith.contexts} rescales ${e.arith.rescales}"
    };
    var line="total original $original";
    for(i in 0..4)line+=" ${METHODS[i]} ${totals[i]} ${ratio(totals[i],original)}";
    sizes+="$line best $bestTotal ${ratio(bestTotal,original)}";
    line="chosen";
    for(i in 0..4)line+=" ${METHODS[i]} ${chosen[i]}";
    sizes+=line;
    sizes+="archive bytes ${created.size} entries ${items.size} ratio ${ratio(created.size.toLong(),original)}";
    val parsed=parse(created);
    sizes+="verify entries ${parsed.entries.size} ok ${verify(parsed,items)}";
    write("sizes.txt",sizes);
    write("analysis.txt",analysis);
    write("archive.hex",hexadecimal(created))
}
private fun listing(p: Parsed): List<String> {
    if(p.error!=null)return listOf("archive bytes ${p.length} error ${p.error}");
    val output=mutableListOf("archive bytes ${p.length} offset_bits ${p.b} length_bits ${p.k} entries ${p.declared}");
    val totals=Array(5) {
        LongArray(3)
    };
    var valid=0;
    for(e in p.entries) {
        val line="entry ${e.number} offset ${e.offset}";
        if(!e.valid) {
            output+=line+if(e.headerTruncated)" truncated header" else " bad_header";
            continue
        };
        valid++;
        output+="$line method ${method(e.method)} original ${e.original} compressed ${e.compressed} ratio ${ratio(e.compressed,e.original)} adler ${hex(e.stored,8)} name ${e.name}";
        if(e.method<5) {
            totals[e.method][0]++;
            totals[e.method][1]+=e.original;
            totals[e.method][2]+=e.compressed
        }
    };
    for(i in 0..4)output+="method ${METHODS[i]} entries ${totals[i][0]} original ${totals[i][1]} compressed ${totals[i][2]} ratio ${ratio(totals[i][2],totals[i][1])}";
    output+="end listed $valid of ${p.declared} stop ${if(p.stopped)"truncated" else "complete"} trailing ${p.trailing}";
    return output
}
private fun testReport(p: Parsed): MutableList<String> {
    val output=mutableListOf<String>();
    if(p.error!=null) {
        output+="archive error ${p.error}";
        return output
    };
    val counts=p.entries.groupingBy {
        it.status
    }.eachCount();
    for(e in p.entries) {
        var line="entry ${e.number} offset ${e.offset}";
        if(!e.valid) {
            line+=" status "+(if(e.headerTruncated)"truncated header" else "bad_header")
        } else {
            line+=" name ${e.name} method ${method(e.method)} status ${e.status}";
            line+=if(e.status=="truncated")" payload have ${p.length-e.start} need ${e.compressed}" else e.detail
        };
        output+=line
    };
    var line="summary entries ${p.declared} checked ${p.entries.size}";
    for(status in STATUSES)line+=" $status ${counts.getOrDefault(status,0)}";
    output+="$line missing ${p.declared-p.entries.size} trailing ${p.trailing}";
    return output
}
private fun compare(name: String,old: List<String>,fresh: List<String>,output: MutableList<String>) {
    if(old==fresh) {
        output+="same $name lines ${old.size}";
        return
    };
    var first=0;
    while(first<minOf(old.size,fresh.size)&&old[first]==fresh[first])first++;
    val a=old.size;
    val b=fresh.size;
    val lcs=Array(a+1) {
        IntArray(b+1)
    };
    for(i in a-1 downTo 0)for(j in b-1 downTo 0)lcs[i][j]=if(old[i]==fresh[j])lcs[i+1][j+1]+1 else maxOf(lcs[i+1][j],lcs[i][j+1]);
    var i=0;
    var j=0;
    var removed=0;
    var added=0;
    val edits=mutableListOf<String>();
    while(i<a||j<b) {
        if(i<a&&j<b&&old[i]==fresh[j]) {
            i++;
            j++
        }else if(j==b||(i<a&&lcs[i+1][j]>=lcs[i][j+1])) {
            edits+="-${i+1}:${old[i]}";
            removed++;
            i++
        }else {
            edits+="+${j+1}:${fresh[j]}";
            added++;
            j++
        }
    };
    output+="differs $name first_line ${first+1} archive_lines $a manifest_lines $b removed $removed added $added";
    output+=edits
}
private fun salvage(parsed: Parsed,originals: Map<String,IntArray>,manifestB: Int,manifestK: Int,maximum: Int) {
    val salvaged=mutableListOf<Item>();
    val extracted=mutableListOf<String>();
    val comparison=mutableListOf<String>();
    val report=testReport(parsed);
    val present=mutableSetOf<String>();
    val b=if(parsed.error==null)parsed.b else manifestB;
    val k=if(parsed.error==null)parsed.k else manifestK;
    var total=0L;
    for(e in parsed.entries)if(e.status=="ok"||e.status=="repaired") {
        present+=e.name;
        val lines=textLines(e.data);
        var words=0;
        var longest=0;
        for(line in lines) {
            longest=maxOf(longest,line.length);
            for(i in line.indices)if(line[i]!=' '&&(i==0||line[i-1]==' '))words++
        };
        extracted+="file ${e.name} bytes ${e.data.size} lines ${lines.size} words $words longest $longest";
        extracted+=lines;
        val fresh=originals[e.name];
        if(fresh==null)comparison+="archive_only ${e.name}" else compare(e.name,lines,textLines(fresh),comparison);
        val encoded=encode(e.data,b,k,maximum);
        salvaged+=Item(e.name,e.data,encoded);
        total+=e.data.size;
        report+="salvage ${e.name} method ${method(encoded.best)} compressed ${encoded.payloads[encoded.best].size} was ${method(e.method)} ${e.compressed}"
    };
    for(name in originals.keys)if(name !in present)comparison+="new $name";
    val archive=archive(salvaged,b,k);
    report+="salvaged entries ${salvaged.size} bytes ${archive.size} original $total verified ${verify(parse(archive),salvaged)}";
    write("test_report.txt",report);
    write("extracted.txt",extracted);
    write("compare.txt",comparison);
    write("salvaged.hex",hexadecimal(archive))
}
fun main() {
    val manifest=File("input/manifest.txt").readLines(Charsets.US_ASCII);
    val b=manifest[0].split(' ')[1].toInt();
    val k=manifest[1].split(' ')[1].toInt();
    val m=manifest[2].split(' ')[1].toInt();
    val originals=linkedMapOf<String,IntArray>();
    val items=mutableListOf<Item>();
    for(line in manifest.drop(3)) {
        val name=line.split(' ')[1];
        val data=File("input/files/$name").readBytes().map {
            it.toInt() and 255
        }.toIntArray();
        originals[name]=data;
        items+=Item(name,data,encode(data,b,k,m))
    };
    File("output").mkdirs();
    creation(items,archive(items,b,k),b,k,m);
    val hex=File("input/archive.hex").readLines(Charsets.US_ASCII).joinToString("");
    val given=IntArray(hex.length/2) {
        hex.substring(2*it,2*it+2).toInt(16)
    };
    val parsed=parse(given);
    write("listing.txt",listing(parsed));
    salvage(parsed,originals,b,k,m)
}
