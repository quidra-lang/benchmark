import kotlin.math.abs
object Stereo {
    val names=arrayOf("sad","ssd","census","sgm","fusion","wta_final","sgm_final");
    val sources=arrayOf("kept","median","background","interpolated","none");
    val reasons=intArrayOf(50,100,150,200,255);
    val reasonNames=arrayOf("textureless","nonunique","outside","mismatch","occluded")
    var w=0;
    var h=0;
    var size=0;
    var min=0;
    var max=0;
    var focal=0L;
    var baseline=0L;
    lateinit var left: IntArray;
    lateinit var right: IntArray;
    lateinit var truth: IntArray;
    lateinit var strengths: LongArray;
    lateinit var params: PgmIo.Parameters;
    lateinit var regions: Evaluation.Regions;
    val methods=Array(7) {
        Method(IntArray(0))
    };
    lateinit var summed: Array<LongArray>;
    val sweeps=mutableListOf<String>()
    class Method(var image: IntArray) {
        var reasons=IntArray(0);
        var lr=IntArray(0);
        var sources=IntArray(0);
        var votes=IntArray(0);
        var margins=LongArray(0);
        var window=0;
        var bounds=0;
        var speckles=0;
        var specklePixels=0;
        var medianChanged=0
    }
    class ObjectInfo {
        var count=0;
        var x0=0;
        var y0=0;
        var x1=0;
        var y1=0;
        var min=0;
        var max=0;
        var median=0;
        var layer=0;
        var hits=0;
        var union=0;
        var first=0;
        var total=0L
    }
    fun p(name: String)=params.integer(name)
    fun two(a: Long,b: Long)=Refinement.two(a,b)
    fun two(a: Long,b: Int)=two(a,b.toLong())
    fun ratio(a: Int,b: Int)=Evaluation.ratio(a.toLong(),b.toLong())
    fun median(values: MutableList<Int>): Int {
        values.sort();
        return values[(values.size-1)/2]
    }
    fun valid(image: IntArray)=image.count {
        it!=0
    }
    fun consistent(pixel: Int,d: Int,rightDisparity: IntArray)=pixel%w>=d&&abs(d-rightDisparity[pixel-d])<=p("lr_max_diff")
    fun select(volume: Array<LongArray>): Method {
        val rightDisparity=IntArray(size);
        for(y in 0 until h)for(x in 0 until w) {
            val pixel=y*w+x;
            var best=Long.MAX_VALUE;
            for(d in min..max)if(x+d<w&&volume[pixel+d][d-min]<best) {
                best=volume[pixel+d][d-min];
                rightDisparity[pixel]=d
            }
        }
        val result=Method(IntArray(size));
        result.reasons=IntArray(size);
        result.margins=LongArray(size);
        result.lr=IntArray(4)
        for(pixel in 0 until size) {
            val row=volume[pixel];
            var d1=min;
            for(d in min+1..max)if(row[d-min]<row[d1-min])d1=d;
            val first=row[d1-min];
            var second=Long.MAX_VALUE;
            for(d in min..max)if(abs(d-d1)>=2)second=minOf(second,row[d-min]);
            if(d1==min||d1==max)result.bounds++;
            var reason=0
            if(strengths[pixel]<p("texture_threshold"))reason=50 else if(100*second<=(100L+p("uniqueness"))*first)reason=100 else if(pixel%w<d1)reason=150 else if(!consistent(pixel,d1,rightDisparity)) {
                var found=false;
                for(d in min..max)if(consistent(pixel,d,rightDisparity))found=true;
                reason=if(found)200 else 255
            } else {
                result.image[pixel]=d1;
                result.margins[pixel]=second-first
            };
            result.reasons[pixel]=reason;
            if(reason==0||reason==200||reason==255)result.lr[minOf(3,abs(d1-rightDisparity[pixel-d1]))]++
        };
        return result
    }
    fun costs(cl: IntArray,cr: IntArray,kind: String,window: Int)=Costs.volume(left,right,cl,cr,w,h,kind,window,min,max)
    fun estimate() {
        val cl=Costs.census(left,w,h);
        val cr=Costs.census(right,w,h)
        for(k in 0..2) {
            var best: Evaluation.Metrics?=null;
            for(window in params.integers(names[k]+"_windows")) {
                val method=select(costs(cl,cr,names[k],window));
                method.window=window;
                val score=Evaluation.evaluate(method.image,truth,regions.nonocc);
                sweeps.add("sweep ${names[k]} window $window valid ${valid(method.image)} bad1 ${ratio(score.bad1,score.pixels)} bad2 ${ratio(score.bad2,score.pixels)}");
                val previous=best;
                if(previous==null||score.bad1<previous.bad1||(score.bad1==previous.bad1&&score.bad2<previous.bad2)) {
                    best=score;
                    methods[k]=method
                }
            }
        }
        val base=costs(cl,cr,params.text("sgm_cost"),p("sgm_window"));
        summed=Array(size) {
            LongArray(max-min+1)
        };
        for(i in 0 until p("sgm_paths")) {
            Aggregation.accumulate(summed,Aggregation.path(base,left,w,h,i,p("p1").toLong(),p("p2").toLong(),p("p2_gamma").toLong()));
            methods[3]=select(summed);
            val score=Evaluation.evaluate(methods[3].image,truth,regions.nonocc);
            sweeps.add("paths ${i+1} valid ${valid(methods[3].image)} bad1 ${ratio(score.bad1,score.pixels)} bad2 ${ratio(score.bad2,score.pixels)}")
        };
        methods[3].window=p("sgm_window")
    }
    fun components(image: IntArray,range: Int): List<List<Int>> {
        val visited=BooleanArray(size);
        val result=mutableListOf<List<Int>>();
        for(start in 0 until size)if(image[start]!=0&&!visited[start]) {
            val part=mutableListOf<Int>();
            val stack=ArrayDeque<Int>();
            stack.addLast(start);
            visited[start]=true;
            while(stack.isNotEmpty()) {
                val pixel=stack.removeLast();
                val x=pixel%w;
                val y=pixel/w;
                part.add(pixel);
                for(k in 0..3) {
                    val xx=x+Aggregation.directions[k][0];
                    val yy=y+Aggregation.directions[k][1];
                    if(xx>=0&&xx<w&&yy>=0&&yy<h) {
                        val q=yy*w+xx;
                        if(!visited[q]&&image[q]!=0&&abs(image[q]-image[pixel])<=range) {
                            visited[q]=true;
                            stack.addLast(q)
                        }
                    }
                }
            };
            result.add(part)
        };
        return result
    }
    fun rays(image: IntArray,pixel: Int,background: Boolean): MutableList<Int> {
        val x=pixel%w;
        val y=pixel/w;
        val result=mutableListOf<Int>();
        val count=if(background)2 else 8;
        for(k in 0 until count) {
            val dx=Aggregation.directions[k][0];
            val dy=Aggregation.directions[k][1];
            var xx=x+dx;
            var yy=y+dy;
            while(xx>=0&&xx<w&&yy>=0&&yy<h) {
                val value=image[yy*w+xx];
                if(value!=0) {
                    result.add(value);
                    break
                };
                xx+=dx;
                yy+=dy
            }
        };
        return result
    }
    fun postprocess(source: Method): Method {
        val original=source.image;
        val filtered=original.copyOf();
        val result=Method(IntArray(size));
        for(part in components(original,p("speckle_range")))if(part.size<p("speckle_size")) {
            result.speckles++;
            result.specklePixels+=part.size;
            for(pixel in part)filtered[pixel]=0
        }
        val medians=IntArray(size);
        for(pixel in 0 until size)if(filtered[pixel]!=0) {
            val x=pixel%w;
            val y=pixel/w;
            val values=mutableListOf<Int>();
            for(yy in maxOf(0,y-1)..minOf(h-1,y+1))for(xx in maxOf(0,x-1)..minOf(w-1,x+1))if(filtered[yy*w+xx]!=0)values.add(filtered[yy*w+xx]);
            medians[pixel]=median(values);
            if(medians[pixel]!=filtered[pixel])result.medianChanged++
        };
        result.image=medians.copyOf();
        result.sources=IntArray(size) {
            4
        }
        for(pixel in 0 until size) {
            if(medians[pixel]!=0) {
                result.sources[pixel]=if(medians[pixel]==original[pixel])0 else 1
            } else {
                val background=source.reasons[pixel]==150||source.reasons[pixel]==255;
                val values=rays(medians,pixel,background);
                if(values.isNotEmpty()) {
                    result.image[pixel]=if(background)values.min() else median(values);
                    result.sources[pixel]=if(background)2 else 3
                }
            }
        };
        return result
    }
    fun fuse() {
        val result=Method(IntArray(size));
        result.votes=IntArray(5);
        for(pixel in 0 until size) {
            val values=mutableListOf<Int>();
            for(k in 0..3)if(methods[k].image[pixel]!=0)values.add(methods[k].image[pixel]);
            result.votes[values.size]++;
            if(values.isNotEmpty()) {
                val median=median(values);
                val agree=values.count {
                    abs(it-median)<=1
                };
                if(agree>=p("fusion_min_votes"))result.image[pixel]=median
            }
        };
        methods[4]=result;
        val selected=names.indexOf(params.text("wta_cost"));
        methods[5]=postprocess(methods[selected]);
        methods[6]=postprocess(methods[3])
    }
    fun objects(): List<String> {
        val objects=mutableListOf<ObjectInfo>();
        var small=0;
        var totalPixels=0;
        val trueCounts=IntArray(max+1);
        for(d in truth)if(d!=0)trueCounts[d]++
        for(part in components(methods[6].image,p("object_range"))) {
            if(part.size<p("object_min_size")) {
                small++;
                continue
            };
            val item=ObjectInfo();
            item.count=part.size;
            item.x0=w;
            item.y0=h;
            item.first=size;
            val disparities=mutableListOf<Int>();
            val counts=IntArray(max+1)
            for(pixel in part) {
                item.x0=minOf(item.x0,pixel%w);
                item.x1=maxOf(item.x1,pixel%w);
                item.y0=minOf(item.y0,pixel/w);
                item.y1=maxOf(item.y1,pixel/w);
                item.first=minOf(item.first,pixel);
                val d=methods[6].image[pixel];
                disparities.add(d);
                item.total+=d;
                if(truth[pixel]!=0)counts[truth[pixel]]++
            };
            item.median=median(disparities);
            item.min=disparities.first();
            item.max=disparities.last();
            for(g in min..max)if(counts[g]>item.hits) {
                item.layer=g;
                item.hits=counts[g]
            };
            if(item.layer!=0)item.union=item.count+trueCounts[item.layer]-item.hits;
            objects.add(item);
            totalPixels+=item.count
        }
        objects.sortWith(compareByDescending<ObjectInfo> {
            it.median
        }.thenByDescending {
            it.count
        }.thenBy {
            it.first
        });
        val lines=mutableListOf("objects ${objects.size} small $small pixels $totalPixels");
        val detected=BooleanArray(max+1)
        for((i,o) in objects.withIndex()) {
            var line="object ${i+1} pixels ${o.count} box ${o.x0} ${o.y0} ${o.x1} ${o.y1} disparity ${o.min} ${o.max} median ${o.median} mean ${two(o.total,o.count)} depth ${two(focal*baseline*o.count,o.total)} size ${two((o.x1-o.x0+1)*baseline,o.median)} ${two((o.y1-o.y0+1)*baseline,o.median)}";
            if(o.layer==0)line+=" truth - iou -" else {
                line+=" truth ${o.layer} iou ${ratio(o.hits,o.union)}";
                if(2*o.hits>o.union)detected[o.layer]=true
            };
            lines.add(line)
        }
        var layerCount=0;
        var detectedCount=0;
        val missed=mutableListOf<String>();
        for(g in min..max)if(trueCounts[g]!=0) {
            layerCount++;
            if(detected[g])detectedCount++ else missed.add(g.toString())
        };
        lines.add("layers $layerCount detected $detectedCount missed "+if(missed.isEmpty())"-" else missed.joinToString(" "));
        return lines
    }
    fun samples(): List<String> {
        val lines=mutableListOf("x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth");
        for(point in params.samples) {
            val pixel=point[1]*w+point[0];
            var line="${point[0]},${point[1]}";
            for(k in 0..3)line+=","+if(methods[k].image[pixel]==0)"-" else methods[k].image[pixel].toString();
            val d=methods[6].image[pixel];
            if(d==0)line+=",-,none,-,-" else {
                val refined=Refinement.subpixel(d,summed[pixel],min,max,focal,baseline);
                line+=",$d,${sources[methods[6].sources[pixel]]},${refined[0]},${refined[1]}"
            };
            line+=if(truth[pixel]==0)",-,-" else ",${truth[pixel]},${two(focal*baseline,truth[pixel])}";
            lines.add(line)
        };
        return lines
    }
    fun imageSummary(name: String,image: IntArray): String {
        var total=0L;
        var low=255;
        var high=0;
        for(value in image) {
            total+=value;
            low=minOf(low,value);
            high=maxOf(high,value)
        };
        return "$name mean ${two(total,size)} min $low max $high"
    }
    fun regionLine(name: String,m: Evaluation.Metrics)="region $name pixels ${m.pixels} valid ${m.valid} bad1 ${ratio(m.bad1,m.pixels)} bad2 ${ratio(m.bad2,m.pixels)} mae ${m.mae()} exact ${m.exact}"
    fun methodLines(k: Int,metrics: Array<Evaluation.Metrics>): List<String> {
        val method=methods[k];
        val image=method.image;
        val values=mutableListOf<Int>();
        val distinct=mutableSetOf<Int>();
        var horizontal=0;
        var vertical=0
        for(pixel in 0 until size)if(image[pixel]!=0) {
            values.add(image[pixel]);
            distinct.add(image[pixel]);
            if(pixel%w+1<w&&image[pixel+1]!=0&&abs(image[pixel]-image[pixel+1])>=2)horizontal++;
            if(pixel/w+1<h&&image[pixel+w]!=0&&abs(image[pixel]-image[pixel+w])>=2)vertical++
        }
        val lines=mutableListOf("method ${names[k]} valid ${values.size} invalid ${size-values.size}");
        if(values.isEmpty())lines.add("disparity min - max - median - distinct 0") else {
            val median=median(values);
            lines.add("disparity min ${values.first()} max ${values.last()} median $median distinct ${distinct.size}")
        };
        lines.add("jumps horizontal $horizontal vertical $vertical")
        if(k<4) {
            lines.add("window ${method.window} bounds ${method.bounds}");
            var reasonsText="reasons";
            for(i in 0..4) {
                val count=method.reasons.count {
                    it==reasons[i]
                };
                reasonsText+=" ${reasonNames[i]} $count"
            };
            lines.add(reasonsText);
            lines.add("lr 0 ${method.lr[0]} 1 ${method.lr[1]} 2 ${method.lr[2]} 3+ ${method.lr[3]}")
        }
        else if(k==4) {
            var votes="votes";
            for(i in 0..4)votes+=" $i ${method.votes[i]}";
            lines.add(votes)
        } else {
            val counts=IntArray(5);
            for(source in method.sources)counts[source]++;
            lines.add("postprocess speckles ${method.speckles} ${method.specklePixels} median ${method.medianChanged} background ${counts[2]} interpolated ${counts[3]} unfilled ${counts[4]}");
            for(source in 0..4) {
                val region=regions.all.filter {
                    method.sources[it]==source
                };
                val m=Evaluation.evaluate(image,truth,region);
                lines.add("source ${sources[source]} pixels ${m.pixels} bad1 ${ratio(m.bad1,m.pixels)}")
            }
        }
        for(i in 0..2)lines.add(regionLine(Evaluation.regionsOrder[i],metrics[i]));
        var count=0;
        var total=0L;
        var maximum=0L;
        for(pixel in regions.nonocc)if(image[pixel]!=0) {
            val error=abs(Refinement.depthHundredths(image[pixel],focal,baseline)-Refinement.depthHundredths(truth[pixel],focal,baseline));
            count++;
            total+=error;
            maximum=maxOf(maximum,error)
        };
        lines.add(if(count==0)"depth_error pixels 0 mean - max -" else "depth_error pixels $count mean ${two(total,100L*count)} max ${two(maximum,100)}");
        val errors=IntArray(6);
        for(pixel in regions.all)errors[if(image[pixel]==0)5 else minOf(4,abs(image[pixel]-truth[pixel]))]++;
        lines.add("errors 0 ${errors[0]} 1 ${errors[1]} 2 ${errors[2]} 3 ${errors[3]} 4+ ${errors[4]} invalid ${errors[5]}");
        return lines
    }
    fun compareMetrics(a: Evaluation.Metrics,b: Evaluation.Metrics): Int {
        var c=a.bad1.compareTo(b.bad1);
        if(c!=0)return c;
        c=a.bad2.compareTo(b.bad2);
        if(c!=0)return c;
        if(a.valid==0||b.valid==0)return if(a.valid==b.valid)0 else if(a.valid==0)1 else -1;
        return (a.error*b.valid).compareTo(b.error*a.valid)
    }
    fun evaluation(): List<String> {
        val lines=mutableListOf("image $w $h","disparities $min $max",imageSummary("left",left),imageSummary("right",right));
        var textureTotal=0L;
        var textureless=0;
        for(value in strengths) {
            textureTotal+=value;
            if(value<p("texture_threshold"))textureless++
        };
        lines.add("texture mean ${two(textureTotal,size)} textureless $textureless");
        lines.add("ground_truth known ${regions.all.size} nonocc ${regions.nonocc.size} occluded ${regions.occluded.size} disc ${regions.disc.size} unknown ${size-regions.all.size}");
        var absolute=0L;
        var biasSum=0L;
        for(pixel in regions.nonocc) {
            val delta=right[pixel-truth[pixel]]-left[pixel];
            absolute+=abs(delta);
            biasSum+=delta
        };
        var bias=two(abs(biasSum),regions.nonocc.size);
        if(biasSum<0&&bias!="0.00")bias="-"+bias;
        lines.add("photometric pixels ${regions.nonocc.size} mean_abs ${two(absolute,regions.nonocc.size)} bias $bias");
        lines.addAll(sweeps)
        val metrics=Array(7) {
            k->Array(3) {
                i->Evaluation.evaluate(methods[k].image,truth,regions.at(i))
            }
        };
        for(k in 0..6)lines.addAll(methodLines(k,metrics[k]));
        for(i in 0..2) {
            val order=(0..6).sortedWith(Comparator {
                a,b->val c=compareMetrics(metrics[a][i],metrics[b][i]);
                if(c!=0)c else a.compareTo(b)
            });
            lines.add("ranking "+Evaluation.regionsOrder[i]+" "+order.joinToString(" ") {
                names[it]
            })
        }
        for(k in 0..3) {
            var tp=0;
            var fp=0;
            for(pixel in regions.occluded)if(methods[k].reasons[pixel]==150||methods[k].reasons[pixel]==255)tp++;
            for(pixel in regions.nonocc)if(methods[k].reasons[pixel]==150||methods[k].reasons[pixel]==255)fp++;
            val fn=regions.occluded.size-tp;
            lines.add("occlusion ${names[k]} tp $tp fp $fp fn $fn precision ${ratio(tp,tp+fp)} recall ${ratio(tp,tp+fn)}")
        }
        for(k in 0..3) {
            val method=methods[k];
            val pixels=regions.nonocc.filter {
                method.image[it]!=0
            }.sortedWith(compareByDescending<Int> {
                method.margins[it]
            }.thenBy {
                it
            });
            for(percentage in intArrayOf(25,50,75,100)) {
                val count=(pixels.size*percentage+99)/100;
                var bad=0;
                for(i in 0 until count) {
                    val pixel=pixels[i];
                    if(abs(method.image[pixel]-truth[pixel])>1)bad++
                };
                val margin=if(count==0)"-" else method.margins[pixels[count-1]].toString();
                lines.add("confidence ${names[k]} $percentage pixels $count margin $margin bad1 ${ratio(bad,count)}")
            }
        }
        for(g in min..max) {
            val count=regions.all.count {
                truth[it]==g
            };
            if(count==0)continue;
            val region=regions.nonocc.filter {
                truth[it]==g
            };
            var line="layer $g pixels $count nonocc ${region.size} bad1";
            for(method in methods)line+=" "+Evaluation.evaluate(method.image,truth,region).bad1;
            lines.add(line)
        };
        for(d in min..max)lines.add("histogram $d "+methods[6].image.count {
            it==d
        });
        return lines
    }
    fun run() {
        val image=PgmIo.read("left.pgm");
        w=image.width;
        h=image.height;
        size=w*h;
        left=image.pixels;
        right=PgmIo.read("right.pgm").pixels;
        truth=PgmIo.read("ground_truth.pgm").pixels;
        params=PgmIo.parameters();
        min=p("disparity_min");
        max=p("disparity_max");
        focal=p("focal_length").toLong();
        baseline=p("baseline").toLong();
        regions=Evaluation.regions(truth,w,h);
        strengths=Costs.texture(left,w,h,p("texture_window"));
        estimate();
        fuse();
        val wta=IntArray(size) {
            8*methods[5].image[it]
        };
        val sgm=IntArray(size) {
            8*methods[6].image[it]
        };
        val errors=IntArray(size) {
            pixel->if(truth[pixel]==0)0 else if(methods[6].image[pixel]==0)255 else 50*(minOf(3,abs(methods[6].image[pixel]-truth[pixel]))+1)
        };
        PgmIo.write("disparity_wta.pgm",w,h,wta);
        PgmIo.write("disparity_sgm.pgm",w,h,sgm);
        PgmIo.write("occlusion.pgm",w,h,methods[3].reasons);
        PgmIo.write("error_sgm.pgm",w,h,errors);
        PgmIo.text("depth.csv",samples());
        PgmIo.text("evaluation.txt",evaluation());
        PgmIo.text("objects.txt",objects())
    }
}
fun main()=Stereo.run()
