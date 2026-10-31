import java.util.Locale
import kotlin.math.*
object Codec {
    lateinit var transform: IntArray;
    lateinit var basic: Array<IntArray>;
    lateinit var standard: CodeTables;
    lateinit var params: ImageIo.Parameters;
    lateinit var original: ImageIo.Image;
    lateinit var originalPlanes: Array<ImageIo.Plane>;
    var quality=0;
    var restart=0;
    var sampling="";
    var mode="";
    val componentNames=arrayOf("Y","Cb","Cr")
    class Component(val identifier: Int,val h: Int,val v: Int,val tq: Int,var td: Int,var ta: Int)
    data class Block(val mcu: Int,val component: Int,val bx: Int,val by: Int)
    data class Interval(val first: Int,val count: Int)
    data class EncodedInterval(val first: Int,val count: Int,val position: Int,val length: Int)
    data class Segment(val position: Int,val name: String,val length: Int)
    data class Symbol(val tableClass: Int,val tableId: Int,val value: Int,val extra: Int,val width: Int)
    class Frame(val width: Int,val height: Int,val components: Array<Component>,val restart: Int) {
        val hmax=components.maxOf {
            it.h
        };
        val vmax=components.maxOf {
            it.v
        };
        val factors=Array(3) {
            intArrayOf(components[it].h,components[it].v)
        };
        val mx=(width+8*hmax-1)/(8*hmax);
        val my=(height+8*vmax-1)/(8*vmax);
        val mcus=mx*my;
        val blocksPerMcu=components.sumOf {
            it.h*it.v
        };
        val blocks=mutableListOf<Block>();
        val intervals=mutableListOf<Interval>()
        init {
            for(mcu in 0 until mcus)for(k in 0..2)for(v in 0 until components[k].v)for(x in 0 until components[k].h)blocks.add(Block(mcu,
                k,components[k].h*(mcu%mx)+x,components[k].v*(mcu/mx)+v));
            val step=if(restart==0)mcus else restart;
            for(first in 0 until mcus step step)intervals.add(Interval(first,minOf(step,mcus-first)))
        }
    }
    data class Prepared(val frame: Frame,val planes: Array<ImageIo.Plane>?,val quant: Array<IntArray>,val coefficients: Array<IntArray>)
    class Encoding {
        lateinit var prepared: Prepared;
        lateinit var tables: CodeTables;
        lateinit var frequencies: Array<Array<IntArray>>;
        lateinit var differences: IntArray;
        lateinit var blockBits: IntArray;
        lateinit var data: IntArray;
        var headerBytes=0;
        var scanBytes=0;
        var paddingBits=0;
        var stuffedBytes=0;
        val intervals=mutableListOf<EncodedInterval>()
    }
    class Decoded {
        lateinit var frame: Frame;
        val quant=Array(4) {
            IntArray(0)
        };
        val tables: CodeTables=Array(2) {
            arrayOfNulls<Entropy.Table>(16)
        };
        val segments=mutableListOf<Segment>();
        var scanStart=0;
        var scanBytes=0;
        lateinit var coefficients: Array<IntArray>;
        lateinit var states: Array<String>;
        lateinit var planes: Array<ImageIo.Plane>;
        lateinit var expanded: Array<ImageIo.Plane>;
        lateinit var image: ImageIo.Image
    }
    data class Key(val quality: Int,val sampling: String,val mode: String)
    val encodings=mutableMapOf<Key,Encoding>();
    val decodings=mutableMapOf<Key,Decoded>()
    fun components(h: Int,v: Int)=arrayOf(Component(1,h,v,0,0,0),Component(2,1,1,1,1,1),Component(3,1,1,1,1,1))
    fun append(output: MutableList<Int>,vararg values: Int) {
        for(v in values)output.add(v)
    }
    fun word(output: MutableList<Int>,v: Int)=append(output,v/256,v%256)
    fun wordAt(data: IntArray,p: Int)=256*data[p]+data[p+1]
    fun segment(output: MutableList<Int>,marker: Int,contents: List<Int>) {
        append(output,255,marker);
        word(output,contents.size+2);
        output.addAll(contents)
    }
    fun prepare(image: ImageIo.Image,q: Int,sampling: String,restart: Int): Prepared {
        val hs=if(sampling=="444")1 else 2;
        val vs=if(sampling=="420")2 else 1;
        val f=Frame(image.width,image.height,components(hs,vs),restart);
        val planes=Color.components(Color.split(image),f.factors,f.mx,f.my);
        val quant=Dct.tables(basic,q);
        val coefficients=Array(f.blocks.size) {
            IntArray(64)
        }
        for(n in f.blocks.indices) {
            val block=f.blocks[n];
            val plane=planes[block.component];
            val pixels=IntArray(64);
            for(y in 0..7)for(x in 0..7)pixels[8*y+x]=plane.pixels[(8*block.by+y)*plane.width+8*block.bx+x];
            coefficients[n]=Dct.zigzag(Dct.quantize(Dct.forward(pixels,transform),quant[f.components[block.component].tq]))
        };
        return Prepared(f,planes,quant,coefficients)
    }
    fun header(f: Frame,quant: Array<IntArray>,tables: CodeTables): IntArray {
        val output=mutableListOf<Int>();
        append(output,255,216);
        var contents=mutableListOf<Int>();
        for(t in 0..1) {
            contents.add(t);
            append(contents,*Dct.zigzag(quant[t]))
        };
        segment(output,219,contents);
        contents=mutableListOf();
        contents.add(8);
        word(contents,f.height);
        word(contents,f.width);
        contents.add(3);
        for(c in f.components)append(contents,c.identifier,16*c.h+c.v,c.tq);
        segment(output,192,contents);
        contents=mutableListOf()
        for(t in 0..3) {
            val c=Entropy.classes[t];
            val id=Entropy.ids[t];
            val table=tables[c][id]!!;
            contents.add(16*c+id);
            append(contents,*table.counts);
            append(contents,*table.symbols)
        };
        segment(output,196,contents);
        if(f.restart>0) {
            contents=mutableListOf();
            word(contents,f.restart);
            segment(output,221,contents)
        };
        contents=mutableListOf();
        contents.add(3);
        for(c in f.components)append(contents,c.identifier,16*c.td+c.ta);
        append(contents,0,63,0);
        segment(output,218,contents);
        return output.toIntArray()
    }
    fun encodePrepared(prepared: Prepared,mode: String): Encoding {
        val result=Encoding();
        result.prepared=prepared;
        val f=prepared.frame;
        result.frequencies=Array(2) {
            Array(16) {
                IntArray(256)
            }
        };
        result.differences=IntArray(f.blocks.size);
        result.blockBits=IntArray(f.blocks.size);
        val allSymbols=mutableListOf<List<Symbol>>()
        for(interval in f.intervals) {
            val predictors=IntArray(3);
            for(n in interval.first*f.blocksPerMcu until (interval.first+interval.count)*f.blocksPerMcu) {
                val block=f.blocks[n];
                val c=f.components[block.component];
                val z=prepared.coefficients[n];
                val difference=z[0]-predictors[block.component];
                predictors[block.component]=z[0];
                result.differences[n]=difference;
                var category=Entropy.category(difference);
                val symbols=mutableListOf(Symbol(0,c.td,category,Entropy.extra(difference),category));
                var run=0
                for(i in 1..63) {
                    val value=z[i];
                    if(value==0) {
                        run++;
                        continue
                    };
                    while(run>=16) {
                        symbols.add(Symbol(1,c.ta,240,0,0));
                        run-=16
                    };
                    category=Entropy.category(value);
                    symbols.add(Symbol(1,c.ta,16*run+category,Entropy.extra(value),category));
                    run=0
                };
                if(run>0)symbols.add(Symbol(1,c.ta,0,0,0));
                for(symbol in symbols)result.frequencies[symbol.tableClass][symbol.tableId][symbol.value]++;
                allSymbols.add(symbols)
            }
        }
        result.tables=standard;
        if(mode=="optimized") {
            result.tables=Array(2) {
                arrayOfNulls<Entropy.Table>(16)
            };
            for(t in 0..3) {
                val c=Entropy.classes[t];
                val id=Entropy.ids[t];
                result.tables[c][id]=Entropy.optimized(result.frequencies[c][id])
            }
        };
        val header=header(f,prepared.quant,result.tables);
        val writer=Bitstream.Writer()
        for(j in f.intervals.indices) {
            val interval=f.intervals[j];
            if(j>0)writer.restart(j-1);
            val start=writer.data.size;
            for(n in interval.first*f.blocksPerMcu until (interval.first+interval.count)*f.blocksPerMcu)for(symbol in allSymbols[n]) {
                val table=result.tables[symbol.tableClass][symbol.tableId]!!;
                val length=table.lengths[symbol.value];
                writer.write(table.codes[symbol.value],length);
                writer.write(symbol.extra,symbol.width);
                result.blockBits[n]+=length+symbol.width
            };
            writer.pad();
            result.intervals.add(EncodedInterval(interval.first,interval.count,header.size+start,writer.data.size-start))
        }
        val data=mutableListOf<Int>();
        append(data,*header);
        data.addAll(writer.data);
        append(data,255,217);
        result.data=data.toIntArray();
        result.headerBytes=header.size;
        result.scanBytes=writer.data.size;
        result.paddingBits=writer.paddingBits;
        result.stuffedBytes=writer.stuffedBytes;
        return result
    }
    fun encode(image: ImageIo.Image,q: Int,sampling: String,mode: String,restart: Int)=encodePrepared(prepare(image,q,sampling,restart),mode)
    fun segmentName(marker: Int)=if(marker in 224..239)"APP${marker-224}" else when(marker) {
        192->"SOF0";
        196->"DHT";
        219->"DQT";
        221->"DRI";
        218->"SOS";
        else->"COM"
    }
    fun parse(data: IntArray): Decoded {
        val d=Decoded();
        var position=2;
        var width=0;
        var height=0;
        var restart=0;
        val components=arrayOfNulls<Component>(3);
        d.segments.add(Segment(0,"SOI",0))
        while(true) {
            val marker=data[position+1];
            val length=wordAt(data,position+2);
            val contents=data.copyOfRange(position+4,position+length+2);
            d.segments.add(Segment(position,segmentName(marker),length));
            position+=length+2
            if(marker==219) {
                for(offset in contents.indices step 65)d.quant[contents[offset]]=Dct.unzigzag(contents.copyOfRange(offset+1,offset+65))
            }
            else if(marker==196) {
                var offset=0;
                while(offset<contents.size) {
                    val c=contents[offset]/16;
                    val id=contents[offset]%16;
                    val counts=contents.copyOfRange(offset+1,offset+17);
                    var count=0;
                    for(value in counts)count+=value;
                    d.tables[c][id]=Entropy.Table(counts,contents.copyOfRange(offset+17,offset+17+count));
                    offset+=17+count
                }
            }
            else if(marker==192) {
                height=wordAt(contents,1);
                width=wordAt(contents,3);
                for(k in 0..2) {
                    val offset=6+3*k;
                    val factor=contents[offset+1];
                    components[k]=Component(contents[offset],factor/16,factor%16,contents[offset+2],0,0)
                }
            }
            else if(marker==221)restart=wordAt(contents,0)
            else if(marker==218) {
                for(k in 0..2) {
                    val table=contents[2+2*k];
                    components[k]!!.td=table/16;
                    components[k]!!.ta=table%16
                };
                break
            }
        }
        d.frame=Frame(width,height,components.map {
            it!!
        }.toTypedArray(),restart);
        d.scanStart=position;
        d.scanBytes=data.size-2-position;
        d.segments.add(Segment(data.size-2,"EOI",0));
        return d
    }
    fun readSymbol(reader: Bitstream.Reader,table: Entropy.Table): Int {
        var code=0;
        for(length in 1..16) {
            code=2*code+reader.bit();
            val symbol=table.decode[(length shl 16) or code];
            if(symbol!=null)return symbol
        };
        throw Bitstream.DecodeError("code")
    }
    fun decodeBlock(reader: Bitstream.Reader,k: Int,c: Component,tables: CodeTables,predictors: IntArray): IntArray {
        val z=IntArray(64);
        var n=readSymbol(reader,tables[0][c.td]!!);
        predictors[k]+=Entropy.amplitude(reader.read(n),n);
        z[0]=predictors[k];
        var index=1;
        while(index<=63) {
            val symbol=readSymbol(reader,tables[1][c.ta]!!);
            if(symbol==0)break;
            val run=symbol/16;
            n=symbol%16;
            index+=run;
            if(index>63)throw Bitstream.DecodeError("index");
            if(n>0)z[index]=Entropy.amplitude(reader.read(n),n);
            index++
        };
        return z
    }
    fun reconstruct(f: Frame,k: Int,coefficients: Array<IntArray>,quant: Array<IntArray>,keep: Int): ImageIo.Plane {
        val c=f.components[k];
        val w=8*c.h*f.mx;
        val h=8*c.v*f.my;
        val plane=IntArray(w*h) {
            128
        };
        for(n in f.blocks.indices) {
            val b=f.blocks[n];
            if(b.component!=k)continue;
            val pixels=Dct.inverse(Dct.dequantize(coefficients[n],quant[c.tq],keep),transform);
            for(y in 0..7)pixels.copyInto(plane,(8*b.by+y)*w+8*b.bx,8*y,8*y+8)
        };
        return ImageIo.Plane(w,h,plane)
    }
    fun decode(data: IntArray): Decoded {
        val d=parse(data);
        val f=d.frame;
        d.coefficients=Array(f.blocks.size) {
            IntArray(64)
        };
        d.states=Array(f.intervals.size) {
            "lost"
        };
        val reader=Bitstream.Reader(data,d.scanStart);
        var j=0
        while(j<f.intervals.size) {
            val interval=f.intervals[j];
            val predictors=IntArray(3);
            val pending=mutableListOf<IntArray>();
            var currentMcu=interval.first
            try {
                for(n in interval.first*f.blocksPerMcu until (interval.first+interval.count)*f.blocksPerMcu) {
                    val b=f.blocks[n];
                    currentMcu=b.mcu;
                    pending.add(decodeBlock(reader,b.component,f.components[b.component],d.tables,predictors))
                };
                reader.discard();
                val expected=if(j<f.intervals.size-1)208+j%8 else 217;
                if(data[reader.position]!=255||data[reader.position+1]!=expected)throw Bitstream.DecodeError("sync");
                val first=interval.first*f.blocksPerMcu;
                for(n in pending.indices)d.coefficients[first+n]=pending[n];
                d.states[j]="ok";
                reader.position+=2;
                j++
            }
            catch(error: Bitstream.DecodeError) {
                val offset=reader.position;
                reader.discard();
                val resync=Bitstream.resync(data,offset);
                d.states[j]="damaged ${error.kind} mcu $currentMcu offset $offset resync $resync";
                val marker=data[resync+1];
                if(marker==217)break;
                j=j+1+(marker-208-j).mod(8);
                reader.position=resync+2
            }
        }
        d.planes=Array(3) {
            k->reconstruct(f,k,d.coefficients,d.quant,64)
        };
        d.expanded=Color.upsample(d.planes,f.factors,f.width,f.height);
        d.image=Color.combine(d.expanded);
        return d
    }
    fun repair(d: Decoded): Encoding {
        val source=d.frame;
        val f=Frame(source.width,source.height,components(source.components[0].h,source.components[0].v),source.restart);
        val q=Array(4) {
            IntArray(0)
        };
        q[0]=d.quant[source.components[0].tq];
        q[1]=d.quant[source.components[1].tq];
        return encodePrepared(Prepared(f,null,q,d.coefficients),"optimized")
    }
    fun encoding(q: Int,sampling: String,mode: String)=encodings.getOrPut(Key(q,sampling,mode)) {
        encode(original,q,sampling,mode,restart)
    }
    fun decoding(q: Int,sampling: String)=decodings.getOrPut(Key(q,sampling,mode)) {
        decode(encoding(q,sampling,mode).data)
    }
    fun psnr(first: IntArray,second: IntArray): String {
        var error=0L;
        for(i in first.indices) {
            val delta=first[i]-second[i];
            error+=delta.toLong()*delta
        };
        return if(error==0L)"inf" else String.format(Locale.ROOT,"%.2f",10*log10(65025.0*first.size/error))
    }
    fun metrics(d: Decoded): Array<String> {
        val result=Array(4) {
            ""
        };
        for(k in 0..2)result[k]=psnr(originalPlanes[k].pixels,d.expanded[k].pixels);
        result[3]=psnr(original.pixels,d.image.pixels);
        return result
    }
    fun gcd(first: Long,second: Long): Long {
        var a=first;
        var b=second;
        while(b!=0L) {
            val t=a%b;
            a=b;
            b=t
        };
        return a
    }
    fun bpp(bytes: Int): String {
        val a=8L*bytes;
        val b=original.width.toLong()*original.height;
        val d=gcd(a,b);
        return "${a/d}/${b/d}"
    }
    fun integers(values: IntArray)=values.joinToString(" ")
    fun rateDistortion(): List<String> {
        val lines=mutableListOf("quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error");
        for(q in params.integers("qualities")) {
            val a=encoding(q,sampling,"standard");
            val b=encoding(q,sampling,"optimized");
            val selected=encoding(q,sampling,mode);
            val d=decoding(q,sampling);
            var maximum=0;
            for(i in original.pixels.indices)maximum=maxOf(maximum,abs(original.pixels[i]-d.image.pixels[i]));
            lines.add("$q,${a.data.size},${b.data.size},${bpp(selected.data.size)},"+metrics(d).joinToString(",")+",$maximum")
        };
        return lines
    }
    fun blockErrors(e: Encoding,d: Decoded,lines: MutableList<String>): IntArray {
        val f=e.prepared.frame;
        val errors=IntArray(f.blocks.size);
        lines.add("blocks ${errors.size}");
        for(n in errors.indices) {
            val b=f.blocks[n];
            val source=e.prepared.planes!![b.component];
            val restored=d.planes[b.component];
            var error=0;
            for(y in 8*b.by until 8*b.by+8)for(x in 8*b.bx until 8*b.bx+8) {
                val delta=source.pixels[y*source.width+x]-restored.pixels[y*restored.width+x];
                error+=delta*delta
            };
            errors[n]=error;
            val z=e.prepared.coefficients[n];
            var nonzero=0;
            var last=0;
            for(k in 0..63)if(z[k]!=0) {
                last=k;
                if(k>0)nonzero++
            };
            lines.add("block $n ${componentNames[b.component]} ${b.bx} ${b.by} dc ${z[0]} diff ${e.differences[n]} nonzero $nonzero last $last bits ${e.blockBits[n]} sse $error")
        };
        return errors
    }
    fun huffmanLines(e: Encoding): List<String> {
        val lines=mutableListOf<String>();
        for(t in 0..3) {
            val c=Entropy.classes[t];
            val id=Entropy.ids[t];
            val table=e.tables[c][id]!!;
            val frequencies=e.frequencies[c][id];
            var coded=0;
            var bits=0;
            for(symbol in 0..255) {
                coded+=frequencies[symbol];
                bits+=frequencies[symbol]*table.lengths[symbol]
            };
            lines.add("table ${Entropy.names[t]} class $c id $id symbols ${table.symbols.size} coded $coded bits $bits");
            lines.add("counts "+integers(table.counts));
            for(symbol in table.symbols) {
                val length=table.lengths[symbol];
                val binary=table.codes[symbol].toString(2).padStart(length,'0');
                lines.add("symbol "+String.format(Locale.ROOT,"%02x",symbol)+" length $length code $binary count ${frequencies[symbol]}")
            }
        };
        return lines
    }
    fun thumbnail(d: Decoded): ImageIo.Image {
        val f=d.frame;
        val w=(f.width+7)/8;
        val h=(f.height+7)/8;
        val image=IntArray(3*w*h);
        for(y in 0 until h)for(x in 0 until w) {
            val values=IntArray(3);
            for(k in 0..2) {
                val c=f.components[k];
                val bx=x*c.h/f.hmax;
                val by=y*c.v/f.vmax;
                var dc=0;
                for(n in f.blocks.indices) {
                    val b=f.blocks[n];
                    if(b.component==k&&b.bx==bx&&b.by==by) {
                        dc=d.coefficients[n][0];
                        break
                    }
                };
                values[k]=Color.clamp((dc*d.quant[c.tq][0]+4).floorDiv(8)+128)
            };
            Color.toRgb(values[0],values[1],values[2]).copyInto(image,3*(y*w+x))
        };
        return ImageIo.Image(w,h,image)
    }
    fun referenceReport(e: Encoding,d: Decoded,errors: IntArray): MutableList<String> {
        val f=e.prepared.frame;
        val lines=mutableListOf("image ${f.width} ${f.height}","sampling $sampling mcu ${8*f.hmax} ${8*f.vmax} grid ${f.mx} ${f.my}",
            "padded ${8*f.hmax*f.mx} ${8*f.vmax*f.my}");
        val counts=IntArray(3) {
            f.components[it].h*f.components[it].v*f.mcus
        };
        lines.add("blocks "+integers(counts));
        lines.add("restart_interval $restart markers ${f.intervals.size-1}");
        lines.add("huffman $mode");
        lines.add("quality $quality");
        for(t in 0..1)lines.add("quant $t "+integers(Dct.zigzag(e.prepared.quant[t])));
        val symbolCounts=IntArray(4);
        for(t in 0..3)for(count in e.frequencies[Entropy.classes[t]][Entropy.ids[t]])symbolCounts[t]+=count;
        lines.add("symbols "+integers(symbolCounts));
        lines.add("eob ${e.frequencies[1][0][0]+e.frequencies[1][1][0]} zrl ${e.frequencies[1][0][240]+e.frequencies[1][1][240]}")
        var zero=0;
        val nonzero=IntArray(64);
        for(z in e.prepared.coefficients) {
            var any=false;
            for(k in 0..63)if(z[k]!=0) {
                nonzero[k]++;
                if(k>0)any=true
            };
            if(!any)zero++
        };
        lines.add("zero_ac_blocks $zero");
        lines.add("nonzero "+integers(nonzero));
        for(k in 0..2) {
            var bits=0;
            var nz=0;
            var error=0;
            for(n in f.blocks.indices)if(f.blocks[n].component==k) {
                bits+=e.blockBits[n];
                error+=errors[n];
                for(value in e.prepared.coefficients[n])if(value!=0)nz++
            };
            lines.add("component ${componentNames[k]} bits $bits nonzero $nz sse $error")
        };
        lines.add("padding_bits ${e.paddingBits}");
        lines.add("stuffed_bytes ${e.stuffedBytes}");
        lines.add("header_bytes ${e.headerBytes}");
        lines.add("scan_bytes ${e.scanBytes}");
        lines.add("total_bytes ${e.data.size}");
        for((j,interval) in e.intervals.withIndex())lines.add("interval $j ${interval.first} ${interval.count} ${interval.position} ${interval.length}")
        val histogram=IntArray(8);
        val edges=intArrayOf(1,2,4,8,16,32,64);
        for(i in original.pixels.indices) {
            val error=abs(original.pixels[i]-d.image.pixels[i]);
            var bin=0;
            while(bin<7&&error>=edges[bin])bin++;
            histogram[bin]++
        };
        lines.add("error_histogram "+integers(histogram));
        for(keep in params.integers("truncate")) {
            val plane=reconstruct(d.frame,0,d.coefficients,d.quant,keep);
            val cropped=IntArray(f.width*f.height);
            for(y in 0 until f.height)plane.pixels.copyInto(cropped,y*f.width,y*plane.width,y*plane.width+f.width);
            lines.add("truncate $keep "+psnr(originalPlanes[0].pixels,cropped))
        };
        return lines
    }
    fun comparisons(reference: Encoding,decoded: Decoded): List<String> {
        val lines=mutableListOf<String>();
        for(s in arrayOf("444","422","420")) {
            val e=encoding(quality,s,mode);
            val values=metrics(decoding(quality,s));
            lines.add("sampling_compare $s ${e.data.size} ${values[1]} ${values[2]} ${values[3]}")
        };
        var previous=original
        for(g in 1..params.integer("generations")) {
            val e=if(g==1)reference else encode(previous,quality,sampling,mode,restart);
            val d=if(g==1)decoded else decode(e.data);
            var changed=0;
            for(p in 0 until previous.width*previous.height) {
                var different=false;
                for(c in 0..2)if(previous.pixels[3*p+c]!=d.image.pixels[3*p+c])different=true;
                if(different)changed++
            };
            lines.add("generation $g ${e.data.size} ${psnr(original.pixels,d.image.pixels)} $changed");
            previous=d.image
        }
        var lo=1;
        var hi=100;
        val target=params.integer("target_bytes");
        while(lo<hi) {
            val mid=(lo+hi+1)/2;
            val b=encoding(mid,sampling,mode).data.size;
            lines.add("rate_control_step $mid $b");
            if(b<=target)lo=mid else hi=mid-1
        };
        val bytes=encoding(lo,sampling,mode).data.size;
        val fits=if(bytes<=target)"yes" else "no";
        lines.add("rate_control $lo $bytes $fits "+psnr(original.pixels,decoding(lo,sampling).image.pixels));
        return lines
    }
    fun streamReport(d: Decoded,repaired: Encoding,redone: Decoded): List<String> {
        val lines=mutableListOf<String>();
        for(s in d.segments)lines.add("stream_segment ${s.position} ${s.name} ${s.length}");
        val f=d.frame;
        lines.add("stream_image ${f.width} ${f.height}");
        for(c in f.components)lines.add("stream_component ${c.identifier} ${c.h} ${c.v} ${c.tq} ${c.td} ${c.ta}");
        for(t in 0..3)if(d.quant[t].isNotEmpty())lines.add("stream_quant $t "+integers(Dct.zigzag(d.quant[t])))
        for(c in 0..1)for(id in 0..15) {
            val table=d.tables[c][id]?:continue;
            var longest=16;
            while(table.counts[longest-1]==0)longest--;
            lines.add("stream_huffman $c $id symbols ${table.symbols.size} longest $longest")
        };
        var ok=0;
        var damaged=0;
        var lost=0;
        for(state in d.states) {
            if(state=="ok")ok++ else if(state=="lost")lost++ else damaged++
        };
        lines.add("stream_restart ${f.restart} intervals ${f.intervals.size} ok $ok damaged $damaged lost $lost");
        for((j,interval) in f.intervals.withIndex())lines.add("stream_interval $j ${interval.first} ${interval.count} ${d.states[j]}");
        lines.add("stream_scan_bytes ${d.scanBytes}");
        val identical=if(d.image.pixels.contentEquals(redone.image.pixels))"yes" else "no";
        lines.add("repair ${repaired.data.size} ${repaired.headerBytes} ${repaired.scanBytes} identical $identical");
        return lines
    }
    fun run() {
        original=ImageIo.readImage();
        originalPlanes=Color.split(original);
        params=ImageIo.parameters();
        val tables=ImageIo.tables();
        transform=tables.transform;
        basic=tables.basic;
        standard=tables.huffman;
        quality=params.integers("qualities")[0];
        sampling=params.text("sampling");
        mode=params.text("huffman");
        restart=params.integer("restart_interval");
        val rate=rateDistortion();
        val reference=encoding(quality,sampling,mode);
        val decoded=decoding(quality,sampling);
        val blocks=mutableListOf<String>();
        val errors=blockErrors(reference,decoded,blocks);
        val report=referenceReport(reference,decoded,errors);
        report.addAll(comparisons(reference,decoded));
        val stream=decode(ImageIo.readHex());
        val repaired=repair(stream);
        report.addAll(streamReport(stream,repaired,decode(repaired.data)));
        ImageIo.text("rate_distortion.csv",rate);
        ImageIo.writeImage("decoded.ppm",decoded.image);
        ImageIo.writeHex("bitstream.hex",reference.data);
        ImageIo.writeImage("thumbnail.ppm",thumbnail(decoded));
        ImageIo.text("huffman_tables.txt",huffmanLines(reference));
        ImageIo.text("blocks.txt",blocks);
        ImageIo.writeImage("stream_decoded.ppm",stream.image);
        ImageIo.writeHex("repaired.hex",repaired.data);
        ImageIo.text("report.txt",report)
    }
}
fun main()=Codec.run()
