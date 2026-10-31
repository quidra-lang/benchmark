import java.io.File
object QrProgram {
    val levels=listOf("L","M","Q","H");
    val modes=listOf("NUMERIC","ALPHANUMERIC","BYTE");
    val errorKinds=listOf("level","mode","version","mask","text","charset","capacity")
    data class Segment(val mode: String,val text: String)
    data class Split(val segments: List<Segment>,val bits: Int)
    data class Group(val value: Int,val width: Int,val text: String)
    data class Assembled(val bits: String,val lines: List<String>)
    data class Padding(val bits: String,val terminator: Int,val zeroFill: Int,val padBytes: Int)
    data class Placement(val block: Int,val position: Int)
    data class BlockResult(val status: String,val positions: Int)
    data class Scan(val name: String,val symbol: Array<IntArray>)
    data class Damage(val operation: String,val arguments: IntArray)
    data class Image(val symbol: Array<IntArray>,val line: String)
    data class Damaged(val symbol: Array<IntArray>,val lines: List<String>)
    fun countWidth(mode: String,version: Int)=(if(version==10)intArrayOf(12,11,16) else intArrayOf(10,
        9,8))[modes.indexOf(mode)]
    fun dataWidth(mode: String,count: Int)=when(mode) {
        "NUMERIC"->10*(count/3)+intArrayOf(0,4,7)[count%3];
        "ALPHANUMERIC"->11*(count/2)+6*(count%2);
        else->8*count
    }
    fun indicator(mode: String)=intArrayOf(1,2,4)[modes.indexOf(mode)]
    fun encodable(mode: String,character: Char)=when(mode) {
        "NUMERIC"->character in '0'..'9';
        "ALPHANUMERIC"->character in Bitstream.ALPHANUMERIC;
        else->character.code in 32..126
    }
    fun encodable(mode: String,text: String)=text.all {
        encodable(mode,it)
    }
    fun segmentWidth(mode: String,text: String,version: Int)=4+countWidth(mode,version)+dataWidth(mode,text.length)
    fun groups(mode: String,text: String): List<Group> {
        val step=when(mode) {
            "NUMERIC"->3;
            "ALPHANUMERIC"->2;
            else->1
        };
        val groups=mutableListOf<Group>();
        for(start in text.indices step step) {
            val characters=text.substring(start,minOf(start+step,text.length));
            val value: Int;
            val width: Int;
            if(mode=="NUMERIC") {
                value=characters.toInt();
                width=intArrayOf(0,4,7,10)[characters.length]
            }else if(mode=="ALPHANUMERIC") {
                val first=Bitstream.ALPHANUMERIC.indexOf(characters[0]);
                value=if(characters.length==2)45*first+Bitstream.ALPHANUMERIC.indexOf(characters[1]) else first;
                width=if(characters.length==2)11 else 6
            }else {
                value=characters[0].code;
                width=8
            };
            groups.add(Group(value,width,characters))
        };
        return groups
    }
    fun mixedSegments(text: String,version: Int): Split {
        val length=text.length;
        val invalid=Array(3) {
            IntArray(length+1)
        };
        for(i in text.indices)for(m in modes.indices)invalid[m][i+1]=invalid[m][i]+if(encodable(modes[m],text[i]))0 else 1;
        val costs=IntArray(length+1);
        val starts=IntArray(length+1);
        val selectedModes=IntArray(length+1);
        for(end in 1..length) {
            costs[end]=Int.MAX_VALUE;
            for(start in 0 until end)for(m in modes.indices)if(invalid[m][end]==invalid[m][start]) {
                val mode=modes[m];
                val cost=costs[start]+4+countWidth(mode,version)+dataWidth(mode,end-start);
                if(cost<costs[end]) {
                    costs[end]=cost;
                    starts[end]=start;
                    selectedModes[end]=m
                }
            }
        };
        val segments=mutableListOf<Segment>();
        var end=length;
        while(end>0) {
            segments.add(Segment(modes[selectedModes[end]],text.substring(starts[end],end)));
            end=starts[end]
        };
        segments.reverse();
        return Split(segments,costs[length])
    }
    fun assembleBits(segments: List<Segment>,version: Int): Assembled {
        val writer=Bitstream.Writer();
        val lines=mutableListOf<String>();
        for(segment in segments) {
            val mode=segment.mode;
            val text=segment.text;
            val width=countWidth(mode,version);
            val indicator=indicator(mode);
            writer.write(indicator,4);
            writer.write(text.length,width);
            lines.add("segment $mode indicator ${Bitstream.binary(indicator,4)} count ${text.length} ${Bitstream.binary(text.length,width)}");
            for(group in groups(mode,text)) {
                writer.write(group.value,group.width);
                lines.add("group ${group.value} ${Bitstream.binary(group.value,group.width)} \"${group.text}\"")
            }
        };
        return Assembled(writer.value(),lines)
    }
    fun padBits(bits: String,capacity: Int): Padding {
        val terminator=minOf(4,capacity-bits.length);
        var padded=bits+"0".repeat(terminator);
        val zeroFill=(8-padded.length%8)%8;
        padded+="0".repeat(zeroFill);
        val padBytes=(capacity-padded.length)/8;
        val result=StringBuilder(padded);
        repeat(padBytes) {
            result.append(if(it%2==0)"11101100" else "00010001")
        };
        return Padding(result.toString(),terminator,zeroFill,padBytes)
    }
    class BlockLayout(val degree: Int,firstCount: Int,firstSize: Int,secondCount: Int,secondSize: Int) {
        val count=firstCount+secondCount;
        val lengths=IntArray(count) {
            if(it<firstCount)firstSize else secondSize
        };
        val data=lengths.sum();
        val capacity=8*data;
        val total=data+degree*count;
        val placement=mutableListOf<Placement>();
        init {
            for(position in 0 until maxOf(firstSize,secondSize))for(block in 0 until count)if(position<lengths[block])placement.add(Placement(block,
                position));
            for(offset in 0 until degree)for(block in 0 until count)placement.add(Placement(block,lengths[block]+offset))
        }
        fun encode(data: IntArray): Array<IntArray> {
            var start=0;
            return Array(count) {
                b->val words=data.copyOfRange(start,start+lengths[b]);
                start+=lengths[b];
                words+ReedSolomon.parity(words,degree)
            }
        }
        fun interleave(blocks: Array<IntArray>)=IntArray(total) {
            val p=placement[it];
            blocks[p.block][p.position]
        }
        fun deinterleave(words: IntArray): Array<IntArray> {
            val blocks=Array(count) {
                IntArray(lengths[it]+degree)
            };
            for(i in words.indices) {
                val p=placement[i];
                blocks[p.block][p.position]=words[i]
            };
            return blocks
        }
    }
    class Geometry(version: Int,alignments: IntArray) {
        val size=17+4*version;
        val built=Matrix.build(version,alignments);
        val symbol=built.symbol;
        val areas=built.areas;
        val order=built.order;
        val dataModules=order.size;
        val functionModules=size*size-dataModules;
        val indices=Array(size) {
            IntArray(size)
        };
        init {
            for((i,p) in order.withIndex())indices[p.y][p.x]=i
        }
    }
    class Request(fields: List<String>,val text: String) {
        val identifier=fields[0];
        val levelToken=fields[1];
        val modeToken=fields[2];
        val versionToken=fields[3];
        val maskToken=fields[4];
        var mode="";
        var level="";
        var version=0;
        var bitCount=0;
        var boosted=false;
        var segments: List<Segment> = emptyList();
        val splits=mutableMapOf<Int,Split>()
        fun split(version: Int): Split=splits.getOrPut(if(version==10)10 else 1) {
            if(mode=="MIXED")mixedSegments(text,version) else Split(listOf(Segment(mode,text)),segmentWidth(mode,
                text,version))
        }
        fun prepare(codec: Codec): String? {
            if(levelToken !in levels&&!(levelToken.endsWith('+')&&levelToken.dropLast(1) in levels))return "level $levelToken";
            if(modeToken !in modes&&modeToken !in listOf("AUTO","MIXED"))return "mode $modeToken";
            if(versionToken!="AUTO"&&versionToken !in (1..10).map {
                it.toString()
            })return "version $versionToken";
            if(maskToken!="AUTO"&&maskToken !in (0..7).map {
                it.toString()
            })return "mask $maskToken";
            if(text.isEmpty())return "text";
            if(modeToken in listOf("NUMERIC","ALPHANUMERIC"))for((p,c) in text.withIndex())if(!encodable(modeToken,
                c))return "charset position $p";
            mode=if(modeToken=="AUTO")modes.first {
                encodable(it,text)
            } else modeToken;
            val base=levelToken.take(1);
            val candidates=if(versionToken=="AUTO")1..10 else versionToken.toInt()..versionToken.toInt();
            var bits=0;
            var capacity=0;
            for(v in candidates) {
                bits=split(v).bits;
                capacity=codec.table(v,base).capacity;
                if(bits<=capacity) {
                    version=v;
                    break
                }
            };
            if(version==0)return "capacity bits $bits capacity $capacity";
            val split=split(version);
            segments=split.segments;
            bitCount=split.bits;
            level=base;
            if(levelToken.endsWith('+'))for(index in levels.indexOf(base)..3)if(bitCount<=codec.table(version,
                levels[index]).capacity)level=levels[index];
            boosted=level!=base;
            return null
        }
    }
    class Encoding(val request: Request,codec: Codec) {
        val layout=codec.geometry(request.version);
        val blockLayout=codec.table(request.version,request.level);
        val assembled=assembleBits(request.segments,request.version);
        val rawBits=assembled.bits;
        val trace=assembled.lines;
        val padding=padBits(rawBits,blockLayout.capacity);
        val paddedBits=padding.bits;
        val blocks=blockLayout.encode(Bitstream.toCodewords(paddedBits));
        val codewords=blockLayout.interleave(blocks);
        val penalties=mutableListOf<Masking.Penalty>();
        val mask: Int;
        val symbol: Array<IntArray>;
        val dark: Int
        init {
            val unmasked=Matrix.copy(layout.symbol);
            val bits=Bitstream.fromCodewords(codewords);
            for(i in bits.indices) {
                val p=layout.order[i];
                unmasked[p.y][p.x]=bits[i]-'0'
            };
            val candidates=mutableListOf<Array<IntArray>>();
            for(m in 0..7) {
                val candidate=Masking.apply(unmasked,layout.order,m);
                val positions=Matrix.formatPositions(layout.size);
                val information=Matrix.formatInformation(request.level,m);
                Matrix.writeValue(candidate,positions.first,information);
                Matrix.writeValue(candidate,positions.second,information);
                candidates.add(candidate);
                penalties.add(Masking.penalties(candidate))
            };
            mask=if(request.maskToken=="AUTO")(0..7).minBy {
                penalties[it].total()
            } else request.maskToken.toInt();
            symbol=candidates[mask];
            dark=symbol.sumOf {
                it.sum()
            }
        }
    }
    class Attempt {
        val lines=mutableListOf<String>();
        var text: String?=null;
        val blocks=mutableListOf<BlockResult>()
    }
    fun readSegment(reader: Bitstream.Reader,mode: String,initialCount: Int): String? {
        val text=StringBuilder();
        var count=initialCount;
        while(count>0) {
            val groupSize: Int;
            if(mode=="NUMERIC") {
                groupSize=minOf(3,count);
                val value=reader.read(intArrayOf(0,4,7,10)[groupSize]);
                if(value>=intArrayOf(1,10,100,1000)[groupSize])return null;
                text.append(value.toString().padStart(groupSize,'0'))
            }else if(mode=="ALPHANUMERIC") {
                groupSize=minOf(2,count);
                val value=reader.read(if(groupSize==2)11 else 6);
                if(value>=if(groupSize==2)2025 else 45)return null;
                if(groupSize==2)text.append(Bitstream.ALPHANUMERIC[value/45]);
                text.append(Bitstream.ALPHANUMERIC[value%45])
            }else {
                groupSize=1;
                val value=reader.read(8);
                if(value !in 32..126)return null;
                text.append(value.toChar())
            };
            count-=groupSize
        };
        return text.toString()
    }
    fun parseData(attempt: Attempt,bits: String,version: Int) {
        val reader=Bitstream.Reader(bits);
        val text=StringBuilder();
        var end=0;
        while(reader.remaining()>=4) {
            val indicator=reader.read(4);
            if(indicator==0)break;
            val mode=when(indicator) {
                1->"NUMERIC";
                2->"ALPHANUMERIC";
                4->"BYTE";
                else->null
            };
            if(mode==null) {
                attempt.lines.add("parse failed indicator ${Bitstream.binary(indicator,4)}");
                return
            };
            val width=countWidth(mode,version);
            if(reader.remaining()<width) {
                attempt.lines.add("parse failed length $mode");
                return
            };
            val count=reader.read(width);
            if(reader.remaining()<dataWidth(mode,count)) {
                attempt.lines.add("parse failed length $mode");
                return
            };
            val segment=readSegment(reader,mode,count);
            if(segment==null) {
                attempt.lines.add("parse failed value $mode");
                return
            };
            text.append(segment);
            attempt.lines.add("segment $mode $count");
            end=reader.position
        };
        attempt.lines.add("padding "+if(padBits(bits.substring(0,end),bits.length).bits==bits)"ok" else "bad");
        attempt.text=text.toString();
        attempt.lines.add("text \"${attempt.text}\"")
    }
    fun rotate(symbol: Array<IntArray>): Array<IntArray> {
        val size=symbol.size;
        return Array(size) {
            y->IntArray(size) {
                x->symbol[size-1-x][y]
            }
        }
    }
    fun transpose(symbol: Array<IntArray>): Array<IntArray> {
        val size=symbol.size;
        return Array(size) {
            y->IntArray(size) {
                x->symbol[x][y]
            }
        }
    }
    fun finderRotation(symbol: Array<IntArray>): Int {
        val size=symbol.size;
        val corners=listOf(size-7 to size-7,size-7 to 0,0 to 0,0 to size-7);
        return corners.indices.minBy {
            k->val(left,top)=corners[k];
            var score=0;
            for(y in 0..6)for(x in 0..6)if(symbol[top+y][left+x]==if(maxOf(kotlin.math.abs(x-3),kotlin.math.abs(y-3))!=2)1 else 0)score++;
            score
        }
    }
    class Codec(val tables: Array<Array<BlockLayout?>>,val alignments: Array<IntArray>) {
        val geometries=mutableMapOf<Int,Geometry>();
        fun table(version: Int,level: String)=tables[version][levels.indexOf(level)]!!;
        fun geometry(version: Int)=geometries.getOrPut(version) {
            Geometry(version,alignments[version])
        }
        fun attempt(symbol: Array<IntArray>): Attempt {
            val attempt=Attempt();
            val size=symbol.size;
            val version=(size-17)/4;
            var positions=Matrix.formatPositions(size);
            var first=Matrix.readValue(symbol,positions.first);
            var second=Matrix.readValue(symbol,positions.second);
            var firstDistance=32;
            var secondDistance=32;
            var firstChoice=0;
            var secondChoice=0;
            for(i in 0 until 32) {
                val information=Matrix.formatInformation(levels[i/8],i%8);
                val d1=Integer.bitCount(first xor information);
                val d2=Integer.bitCount(second xor information);
                if(d1<firstDistance) {
                    firstDistance=d1;
                    firstChoice=i
                };
                if(d2<secondDistance) {
                    secondDistance=d2;
                    secondChoice=i
                }
            };
            var prefix="format ${Bitstream.binary(first,15)} ${Bitstream.binary(second,15)} distance $firstDistance $secondDistance";
            if(minOf(firstDistance,secondDistance)>3) {
                attempt.lines.add("$prefix unreadable");
                return attempt
            };
            var chosen=if(secondDistance<firstDistance)secondChoice else firstChoice;
            val mask=chosen%8;
            val level=levels[chosen/8];
            attempt.lines.add("$prefix level $level mask $mask");
            if(version>=7) {
                positions=Matrix.versionPositions(size);
                first=Matrix.readValue(symbol,positions.first);
                second=Matrix.readValue(symbol,positions.second);
                firstDistance=32;
                secondDistance=32;
                firstChoice=7;
                secondChoice=7;
                for(v in 7..40) {
                    val information=Matrix.versionInformation(v);
                    val d1=Integer.bitCount(first xor information);
                    val d2=Integer.bitCount(second xor information);
                    if(d1<firstDistance) {
                        firstDistance=d1;
                        firstChoice=v
                    };
                    if(d2<secondDistance) {
                        secondDistance=d2;
                        secondChoice=v
                    }
                };
                prefix="version ${Bitstream.binary(first,18)} ${Bitstream.binary(second,18)} distance $firstDistance $secondDistance";
                if(minOf(firstDistance,secondDistance)>3) {
                    attempt.lines.add("$prefix unreadable");
                    return attempt
                };
                chosen=if(secondDistance<firstDistance)secondChoice else firstChoice;
                attempt.lines.add("$prefix decoded $chosen");
                if(chosen!=version)return attempt
            };
            val geometry=geometry(version);
            val layout=table(version,level);
            val unmasked=Masking.apply(symbol,geometry.order,mask);
            val bits=buildString {
                for(i in 0 until 8*layout.total) {
                    val p=geometry.order[i];
                    append(unmasked[p.y][p.x])
                }
            };
            val blocks=layout.deinterleave(Bitstream.toCodewords(bits));
            val corrected=arrayOfNulls<IntArray>(layout.count);
            var failed=false;
            for(b in blocks.indices) {
                val result=ReedSolomon.correct(blocks[b],layout.degree);
                prefix="block $b syndromes ${Bitstream.hexadecimal(result.syndromes)}";
                val status=when {
                    result.corrected==null-> {
                        attempt.lines.add("$prefix failed");
                        failed=true;
                        "failed"
                    };
                    result.positions.isNotEmpty()-> {
                        attempt.lines.add("$prefix corrected "+result.positions.joinToString(" "));
                        "corrected"
                    };
                    else-> {
                        attempt.lines.add("$prefix ok");
                        "ok"
                    }
                };
                attempt.blocks.add(BlockResult(status,result.positions.size));
                corrected[b]=result.corrected
            };
            if(failed)return attempt;
            val data=IntArray(layout.data);
            var offset=0;
            for(b in 0 until layout.count) {
                corrected[b]!!.copyInto(data,offset,0,layout.lengths[b]);
                offset+=layout.lengths[b]
            };
            parseData(attempt,Bitstream.fromCodewords(data),version);
            return attempt
        }
        fun decode(symbol: Array<IntArray>): Attempt {
            val rotations=finderRotation(symbol);
            var oriented=symbol;
            repeat(rotations) {
                oriented=rotate(oriented)
            };
            var adopted=attempt(oriented);
            var mirrored=false;
            if(adopted.text==null) {
                val second=attempt(transpose(oriented));
                if(second.text!=null) {
                    adopted=second;
                    mirrored=true
                }
            };
            adopted.lines.add(0,"orientation rotations $rotations mirrored "+if(mirrored)"yes" else "no");
            return adopted
        }
    }
    fun codesLines(encoding: Encoding,codec: Codec): List<String> {
        val request=encoding.request;
        val layout=encoding.layout;
        val blocks=encoding.blockLayout;
        val lines=mutableListOf("symbol version ${request.version} level ${request.level} mask ${encoding.mask} size ${layout.size}");
        lines.add("segments ${request.segments.size} "+request.segments.joinToString(" ") {
            "${it.mode}:${it.text.length}"
        });
        val alternatives=modes.map {
            mode->"$mode "+if(encodable(mode,request.text))segmentWidth(mode,request.text,request.version).toString() else "-"
        }.toMutableList();
        alternatives.add("MIXED "+if(request.mode=="MIXED")request.bitCount else mixedSegments(request.text,
            request.version).bits);
        lines.add("bits data ${request.bitCount} capacity ${blocks.capacity} alternatives "+alternatives.joinToString(" "));
        val fits=levels.map {
            level->"$level "+((1..10).firstOrNull {
                request.split(it).bits<=codec.table(it,level).capacity
            }?.toString()?:"-")
        };
        lines.add("fits "+fits.joinToString(" "));
        lines.add("modules function ${layout.functionModules} data ${layout.dataModules} remainder ${layout.dataModules-8*blocks.total} dark ${encoding.dark}");
        lines.add("format ${Bitstream.binary(Matrix.formatInformation(request.level,encoding.mask),15)} version "+if(request.version>=7)Bitstream.binary(Matrix.versionInformation(request.version),
            18) else "none");
        for(m in 0..7) {
            val p=encoding.penalties[m];
            lines.add("penalty $m n1 ${p.n1} n2 ${p.n2} n3 ${p.n3} n4 ${p.n4} total ${p.total()}")
        };
        lines.addAll(Render.symbolLines(encoding.symbol));
        return lines
    }
    fun codewordLines(encoding: Encoding): List<String> {
        val request=encoding.request;
        val layout=encoding.blockLayout;
        val lines=mutableListOf("request ${request.identifier} version ${request.version} level ${request.level} blocks ${layout.count} data ${layout.data} ec_per_block ${layout.degree} total ${layout.total}");
        for(b in 0 until layout.count) {
            lines.add("block $b data "+Bitstream.hexadecimal(encoding.blocks[b].copyOfRange(0,layout.lengths[b])));
            lines.add("block $b ec "+Bitstream.hexadecimal(encoding.blocks[b].copyOfRange(layout.lengths[b],
                encoding.blocks[b].size)))
        };
        lines.add("interleaved "+Bitstream.hexadecimal(encoding.codewords));
        return lines
    }
    fun bitstreamLines(encoding: Encoding): List<String> {
        val request=encoding.request;
        val lines=mutableListOf("request ${request.identifier} version ${request.version} bits ${request.bitCount} capacity ${encoding.blockLayout.capacity}");
        lines.addAll(encoding.trace);
        val p=encoding.padding;
        lines.add("terminator ${p.terminator} zero_fill ${p.zeroFill} pad_bytes ${p.padBytes}");
        return lines
    }
    fun readImage(path: File): Image {
        val lines=path.readLines(Charsets.US_ASCII);
        val dimensions=lines[1].split(' ');
        val width=dimensions[0].toInt();
        val height=dimensions[1].toInt();
        var left=width;
        var right=0;
        var top=height;
        val pixels=Array(height) {
            y->IntArray(width) {
                x->val value=lines[y+2][x]-'0';
                if(value==1) {
                    left=minOf(left,x);
                    right=maxOf(right,x);
                    top=minOf(top,y)
                };
                value
            }
        };
        var run=0;
        while(left+run<width&&pixels[top][left+run]==1)run++;
        val unit=run/7;
        val size=(right-left+1)/unit;
        val symbol=Array(size) {
            y->IntArray(size) {
                x->pixels[top+unit*y][left+unit*x]
            }
        };
        var wellFormed=true;
        for(y in 0 until height)for(x in 0 until width) {
            val expected=if(x>=left&&x<left+unit*size&&y>=top&&y<top+unit*size)symbol[(y-top)/unit][(x-left)/unit] else 0;
            if(pixels[y][x]!=expected)wellFormed=false
        };
        return Image(symbol,"image $width $height quiet ${left/unit} scale $unit size $size "+if(wellFormed)"ok" else "bad")
    }
    fun damagedSymbol(encoding: Encoding,operations: List<Damage>): Damaged {
        var symbol=Matrix.copy(encoding.symbol);
        for(operation in operations) {
            val a=operation.arguments;
            when(operation.operation) {
                "flip"->symbol[a[1]][a[0]]=symbol[a[1]][a[0]] xor 1;
                "fill"->for(y in a[1] until a[1]+a[3])for(x in a[0] until a[0]+a[2])symbol[y][x]=a[4]
            }
        };
        val counts=IntArray(5);
        val damagedWords=List(encoding.blockLayout.count) {
            mutableSetOf<Int>()
        };
        for(y in symbol.indices)for(x in symbol.indices)if(symbol[y][x]!=encoding.symbol[y][x]) {
            when(encoding.layout.areas[y][x]) {
                Matrix.FUNCTION->counts[0]++;
                Matrix.FORMAT->counts[1]++;
                Matrix.VERSION->counts[2]++;
                else-> {
                    val index=encoding.layout.indices[y][x];
                    if(index<8*encoding.blockLayout.total) {
                        counts[3]++;
                        val p=encoding.blockLayout.placement[index/8];
                        damagedWords[p.block].add(p.position)
                    }else counts[4]++
                }
            }
        };
        for(operation in operations)when(operation.operation) {
            "rotate"->symbol=rotate(symbol);
            "mirror"->symbol=transpose(symbol)
        };
        return Damaged(symbol,listOf("check damaged operations ${operations.size}","damage changed ${counts.sum()} function ${counts[0]} format ${counts[1]} version ${counts[2]} data ${counts[3]} remainder ${counts[4]}",
            "errors "+damagedWords.joinToString(" ") {
            it.size.toString()
        }+" limit ${encoding.blockLayout.degree/2}"))
    }
    fun tolerance(encoding: Encoding,codec: Codec,color: Int): Int {
        val size=encoding.layout.size;
        for(side in 1..size) {
            val symbol=Matrix.copy(encoding.symbol);
            val start=(size-side)/2;
            for(y in start until start+side)for(x in start until start+side)symbol[y][x]=color;
            if(codec.decode(symbol).text!=encoding.request.text)return side-1
        };
        return size
    }
    class Summary {
        val totals=mutableMapOf<String,Int>();
        val errors=mutableMapOf<String,Int>();
        val modes=mutableMapOf<String,Int>();
        val levels=mutableMapOf<String,Int>();
        val checks=mutableMapOf<String,Int>();
        val blocks=mutableMapOf<String,Int>();
        val scans=mutableMapOf<String,Int>();
        val versions=IntArray(11);
        val masks=IntArray(8)
        fun get(map: Map<String,Int>,key: String)=map.getOrDefault(key,0)
        fun add(map: MutableMap<String,Int>,key: String,amount: Int) {
            map[key]=get(map,key)+amount
        }
        fun named(map: Map<String,Int>,names: List<String>)=names.joinToString(" ") {
            "$it ${get(map,it)}"
        }
        fun recordError(error: String) {
            add(errors,error.substringBefore(' '),1)
        }
        fun recordEncoding(encoding: Encoding) {
            val r=encoding.request;
            add(totals,"encoded",1);
            add(modes,r.mode,1);
            add(levels,r.level,1);
            add(totals,"boosted",if(r.boosted)1 else 0);
            versions[r.version]++;
            masks[encoding.mask]++;
            add(totals,"segments",r.segments.size);
            add(totals,"data",encoding.blockLayout.data);
            add(totals,"ec",encoding.blockLayout.degree*encoding.blockLayout.count);
            add(totals,"modules",encoding.layout.size*encoding.layout.size);
            add(totals,"dark",encoding.dark)
        }
        fun recordCheck(attempt: Attempt,text: String): String {
            val result=when(attempt.text) {
                null->"failed";
                text->"ok";
                else->"mismatch"
            };
            add(checks,result,1);
            for(block in attempt.blocks) {
                add(blocks,block.status,1);
                add(totals,"corrected_positions",block.positions)
            };
            return result
        }
        fun lines(requests: Int)=listOf("requests $requests encoded ${get(totals,"encoded")} errors ${errors.values.sum()}",
            "error_kinds "+named(errors,errorKinds),"modes "+named(modes,listOf("NUMERIC","ALPHANUMERIC",
            "BYTE","MIXED")),"levels "+named(levels,QrProgram.levels)+" boosted ${get(totals,"boosted")}",
            "versions "+versions.drop(1).joinToString(" "),"masks "+masks.joinToString(" "),"segments ${get(totals,"segments")} data_codewords ${get(totals,"data")} ec_codewords ${get(totals,"ec")}",
            "modules ${get(totals,"modules")} dark ${get(totals,"dark")}","checks ${checks.values.sum()} "+named(checks,
            listOf("ok","mismatch","failed")),"blocks "+named(blocks,listOf("ok","corrected","failed"))+" codewords ${get(totals,"corrected_positions")}",
            "scans ${scans.values.sum()} decoded ${get(scans,"decoded")} failed ${get(scans,"failed")}")
    }
    fun checkLines(encoding: Encoding,codec: Codec,quiet: Int,scale: Int,operations: List<Damage>,summary: Summary,
        output: File): List<String> {
        val request=encoding.request;
        val path=File(output,"qr_${request.identifier}.pbm");
        path.writeText(Render.pbmText(encoding.symbol,quiet,scale),Charsets.US_ASCII);
        val image=readImage(path);
        val lines=mutableListOf("request ${request.identifier}",image.line,"check clean");
        var attempt=codec.decode(image.symbol);
        lines.addAll(attempt.lines);
        lines.add("result "+summary.recordCheck(attempt,request.text));
        if(operations.isNotEmpty()) {
            val damaged=damagedSymbol(encoding,operations);
            lines.addAll(damaged.lines);
            attempt=codec.decode(damaged.symbol);
            lines.addAll(attempt.lines);
            lines.add("result "+summary.recordCheck(attempt,request.text))
        };
        lines.add("tolerance light ${tolerance(encoding,codec,0)} dark ${tolerance(encoding,codec,1)}");
        return lines
    }
    fun capacityLines(codec: Codec): List<String> {
        val lines=mutableListOf<String>();
        for(v in 1..10) {
            val geometry=codec.geometry(v);
            val total=codec.table(v,"L").total;
            val alignment=codec.alignments[v].joinToString(" ").ifEmpty {
                "none"
            };
            lines.add("version $v size ${geometry.size} data_modules ${geometry.dataModules} codewords $total remainder ${geometry.dataModules-8*total} alignment $alignment");
            for(level in levels) {
                val layout=codec.table(v,level);
                val maxima=IntArray(3);
                for(m in modes.indices)while(4+countWidth(modes[m],v)+dataWidth(modes[m],maxima[m]+1)<=layout.capacity)maxima[m]++;
                lines.add("level $level blocks ${layout.count} data ${layout.data} ec_per_block ${layout.degree} numeric ${maxima[0]} alphanumeric ${maxima[1]} byte ${maxima[2]}")
            }
        };
        return lines
    }
    fun readLines(name: String)=File("input/$name.txt").readLines(Charsets.US_ASCII)
    fun writeLines(output: File,name: String,lines: List<String>) {
        File(output,"$name.txt").writeText(if(lines.isEmpty())"" else lines.joinToString("\n")+"\n",Charsets.US_ASCII)
    }
    fun run() {
        val requests=readLines("requests").map {
            line->val colon=line.indexOf(':');
            Request(line.substring(0,colon).split(' '),line.substring(colon+1))
        };
        val params=readLines("params");
        val quiet=params[0].split(' ')[1].toInt();
        val scale=params[1].split(' ')[1].toInt();
        val tables=Array(11) {
            arrayOfNulls<BlockLayout>(4)
        };
        val alignments=Array(11) {
            IntArray(0)
        };
        for(line in readLines("tables")) {
            val fields=line.split(' ');
            val v=fields[1].toInt();
            if(fields[0]=="block")tables[v][levels.indexOf(fields[2])]=BlockLayout(fields[3].toInt(),
                fields[4].toInt(),fields[5].toInt(),fields[6].toInt(),fields[7].toInt()) else alignments[v]=fields.drop(2).map {
                it.toInt()
            }.toIntArray()
        };
        val damage=mutableMapOf<String,MutableList<Damage>>();
        for(line in readLines("damage")) {
            val fields=line.split(' ');
            val arguments=IntArray(when(fields[1]) {
                "flip"->2;
                "fill"->5;
                else->0
            }) {
                i->if(i==4) {
                    if(fields[i+2]=="dark")1 else 0
                }else fields[i+2].toInt()
            };
            damage.getOrPut(fields[0]) {
                mutableListOf()
            }.add(Damage(fields[1],arguments))
        };
        val scanLines=readLines("scans");
        val scans=mutableListOf<Scan>();
        var index=0;
        while(index<scanLines.size) {
            val name=scanLines[index].split(' ')[1];
            val size=scanLines[index+1].length;
            val symbol=Array(size) {
                y->IntArray(size) {
                    x->if(scanLines[index+1+y][x]=='#')1 else 0
                }
            };
            scans.add(Scan(name,symbol));
            index+=size+1
        };
        val codec=Codec(tables,alignments);
        val summary=Summary();
        val output=File("output");
        output.mkdirs();
        val reports=linkedMapOf<String,MutableList<String>>();
        for(name in listOf("codes","codewords","bitstream","selfcheck","scans"))reports[name]=mutableListOf();
        for(request in requests) {
            reports.getValue("codes").add("request ${request.identifier}");
            val error=request.prepare(codec);
            if(error!=null) {
                reports.getValue("codes").add("error $error");
                summary.recordError(error);
                continue
            };
            val encoding=Encoding(request,codec);
            reports.getValue("codes").addAll(codesLines(encoding,codec));
            reports.getValue("codewords").addAll(codewordLines(encoding));
            reports.getValue("bitstream").addAll(bitstreamLines(encoding));
            summary.recordEncoding(encoding);
            reports.getValue("selfcheck").addAll(checkLines(encoding,codec,quiet,scale,damage[request.identifier]?:emptyList(),
                summary,output))
        };
        for(scan in scans) {
            val lines=reports.getValue("scans");
            lines.add("scan ${scan.name} size ${scan.symbol.size}");
            val attempt=codec.decode(scan.symbol);
            lines.addAll(attempt.lines);
            val result=if(attempt.text==null)"failed" else "decoded";
            lines.add("result $result");
            summary.add(summary.scans,result,1)
        };
        reports["capacity"]=capacityLines(codec).toMutableList();
        reports["summary"]=summary.lines(requests.size).toMutableList();
        for((name,lines) in reports)writeLines(output,name,lines)
    }
}
fun main() {
    QrProgram.run()
}
