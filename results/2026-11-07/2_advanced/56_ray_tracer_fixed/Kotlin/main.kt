import java.io.File
import kotlin.math.abs

object Main {
    const val S=FixedPoint.S
    val KINDS=listOf("primary","reflection","refraction","shadow")
    lateinit var scene: Scene.Data;
    var width=0;
    var height=0;
    var contrastThreshold=0;
    var depthLimit=0;
    var supersampled=0;
    var far=0L;
    var epsilon=0L;
    var pad=0L;
    var root: Node?=null;
    lateinit var pixels: Array<Array<Pixel>>;
    lateinit var stats: Stats;
    val BLACK=Scene.Color(0,0,0);
    val ZERO=Vector3(0,0,0)
    class Node(val bounds: Intersect.Bounds,val depth: Int) {
        var left: Node?=null;
        var right: Node?=null;
        var objects: List<Scene.Obj>?=null;
        var visits=0L
    }
    class LightStats {
        var shadow=0L;
        var blocked=0L;
        var attenuated=0L;
        var backfacing=0L;
        var outside=0L;
        var pixels=0L
    }
    class Stats(d: Int,objectCount: Int,lightCount: Int) {
        val rays=LongArray(4);
        val misses=LongArray(3);
        val depth=LongArray(d+1);
        val nodes=LongArray(4);
        val objects=LongArray(4);
        val primary=LongArray(objectCount);
        val secondary=LongArray(objectCount);
        val shadow=LongArray(objectCount);
        val lights=Array(lightCount) {
            LightStats()
        };
        var totalInternal=0L;
        var clamped=0L
    }
    class Pixel {
        lateinit var center: TraceResult;
        lateinit var color: Scene.Color;
        var rays=0L;
        var depth=0;
        var samples=1
    }
    class Context(val counted: Boolean,val pixel: Pixel?,val record: MutableList<String>?) {
        fun line(text: String) {
            record?.add(text)
        }
    }
    data class Hit(val obj: Scene.Obj,val candidate: Intersect.Candidate)
    class Search {
        var best: Hit?=null
    }
    data class Sample(val direction: Vector3,val distance: Long,val intensity: Long)
    data class Local(val color: Scene.Color,val illumination: Int,val lit: BooleanArray)
    data class TraceResult(val color: Scene.Color,val hit: Hit?,val point: Vector3,val normal: Vector3,
        val base: Scene.Color,val illumination: Int,val lit: BooleanArray)
    fun div(a: Long,b: Long)=FixedPoint.divide(a,b)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(if(lines.isEmpty())"" else lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
    fun union(objects: List<Scene.Obj>): Intersect.Bounds {
        val lo=LongArray(3) {
            Long.MAX_VALUE
        };
        val hi=LongArray(3) {
            Long.MIN_VALUE
        };
        for(obj in objects)for(a in 0..2) {
            lo[a]=minOf(lo[a],obj.bounds!!.lo.coordinate(a));
            hi[a]=maxOf(hi[a],obj.bounds!!.hi.coordinate(a))
        };
        return Intersect.Bounds(Vector3(lo[0],lo[1],lo[2]),Vector3(hi[0],hi[1],hi[2]))
    }
    fun area(bounds: Intersect.Bounds): Long {
        val d=bounds.hi.subtract(bounds.lo);
        return d.x*d.y+d.y*d.z+d.z*d.x
    }
    fun build(group: List<Scene.Obj>,depth: Int): Node {
        val node=Node(union(group),depth);
        if(group.size<=2) {
            val objects=group.sortedBy {
                it.number
            };
            node.objects=objects;
            for(obj in objects)obj.leafDepth=depth;
            return node
        };
        var best=Long.MAX_VALUE;
        var chosen=emptyList<Scene.Obj>();
        var split=0;
        for(axis in 0..2) {
            val sorted=group.sortedWith(Comparator {
                x,y->val cx=div(x.bounds!!.lo.coordinate(axis)+x.bounds!!.hi.coordinate(axis),2);
                val cy=div(y.bounds!!.lo.coordinate(axis)+y.bounds!!.hi.coordinate(axis),2);
                val c=cx.compareTo(cy);
                if(c!=0)c else x.number.compareTo(y.number)
            });
            for(i in 1 until sorted.size) {
                val cost=area(union(sorted.take(i)))*i+area(union(sorted.drop(i)))*(sorted.size-i);
                if(cost<best) {
                    best=cost;
                    chosen=sorted;
                    split=i
                }
            }
        };
        node.left=build(chosen.take(split),depth+1);
        node.right=build(chosen.drop(split),depth+1);
        return node
    }
    fun prepare() {
        val settings=lines("render.txt").map {
            it.split(' ')
        };
        width=settings[0][1].toInt();
        height=settings[0][2].toInt();
        contrastThreshold=settings[1][1].toInt();
        depthLimit=settings[2][1].toInt();
        far=settings[3][1].toLong();
        epsilon=settings[4][1].toLong();
        pad=settings[5][1].toLong();
        val bounded=mutableListOf<Scene.Obj>();
        for(obj in scene.objects)if(obj.kind!="plane") {
            obj.bounds=Intersect.bounds(obj,pad);
            bounded+=obj
        };
        if(bounded.isNotEmpty())root=build(bounded,0);
        stats=Stats(depthLimit,scene.objects.size,scene.lights.size)
    }
    fun test(obj: Scene.Obj,origin: Vector3,direction: Vector3,kind: Int,context: Context): Intersect.Candidate? {
        if(context.counted)stats.objects[kind]++;
        return Intersect.test(obj,origin,direction,epsilon)
    }
    fun test(node: Node,origin: Vector3,direction: Vector3,kind: Int,context: Context): Intersect.Slab? {
        if(context.counted) {
            stats.nodes[kind]++;
            node.visits++
        };
        return Intersect.slab(node.bounds,origin,direction)
    }
    fun consider(obj: Scene.Obj,origin: Vector3,direction: Vector3,kind: Int,context: Context,search: Search) {
        val candidate=test(obj,origin,direction,kind,context);
        val best=search.best;
        if(candidate!=null&&candidate.distance<=far&&(best==null||candidate.distance<best.candidate.distance||candidate.distance==best.candidate.distance&&obj.number<best.obj.number))search.best=Hit(obj,
            candidate)
    }
    fun nearest(node: Node,origin: Vector3,direction: Vector3,kind: Int,context: Context,search: Search) {
        val slab=test(node,origin,direction,kind,context)?:return;
        val best=search.best;
        if(slab.far<=epsilon||slab.near>far||best!=null&&slab.near>best.candidate.distance)return;
        val objects=node.objects;
        if(objects!=null)for(obj in objects)consider(obj,origin,direction,kind,context,search) else {
            nearest(node.left!!,origin,direction,kind,context,search);
            nearest(node.right!!,origin,direction,kind,context,search)
        }
    }
    fun nearest(origin: Vector3,direction: Vector3,kind: Int,context: Context): Hit? {
        val search=Search();
        for(obj in scene.objects)if(obj.kind=="plane")consider(obj,origin,direction,kind,context,search);
        root?.let {
            nearest(it,origin,direction,kind,context,search)
        };
        return search.best
    }
    fun occluders(node: Node,origin: Vector3,direction: Vector3,distance: Long,context: Context,result: MutableList<Scene.Obj>) {
        val slab=test(node,origin,direction,3,context)?:return;
        if(slab.far<=epsilon||slab.near>=distance)return;
        val objects=node.objects;
        if(objects!=null)for(obj in objects) {
            val candidate=test(obj,origin,direction,3,context);
            if(candidate!=null&&candidate.distance<distance)result+=obj
        } else {
            occluders(node.left!!,origin,direction,distance,context,result);
            occluders(node.right!!,origin,direction,distance,context,result)
        }
    }
    fun occluders(origin: Vector3,direction: Vector3,distance: Long,context: Context): List<Scene.Obj> {
        val result=mutableListOf<Scene.Obj>();
        for(obj in scene.objects)if(obj.kind=="plane") {
            val candidate=test(obj,origin,direction,3,context);
            if(candidate!=null&&candidate.distance<distance)result+=obj
        };
        root?.let {
            occluders(it,origin,direction,distance,context,result)
        };
        result.sortBy {
            it.number
        };
        return result
    }
    fun camera(qx: Long,qy: Long): Vector3 {
        val u=div((qx-2L*width)*scene.hw,2L*width);
        val v=div((2L*height-qy)*scene.hh,2L*height);
        return scene.forward.add(scene.right.scale(u)).add(scene.up.scale(v)).normalize()
    }
    fun samples(light: Scene.Light,point: Vector3): List<Sample> {
        val result=mutableListOf<Sample>();
        if(light.kind=="sun") {
            result+=Sample(light.direction,far,light.intensity);
            return result
        };
        if(light.kind=="area") {
            val k=light.divisions;
            for(j in 0 until k)for(i in 0 until k) {
                val coordinates=LongArray(3) {
                    a->light.position.coordinate(a)+div((2L*i+1)*light.u.coordinate(a),2L*k)+div((2L*j+1)*light.v.coordinate(a),2L*k)
                };
                val relative=Vector3(coordinates[0],coordinates[1],coordinates[2]).subtract(point);
                result+=Sample(relative.normalize(),relative.length(),div(light.intensity,light.samples().toLong()))
            }
        } else {
            val relative=light.position.subtract(point);
            result+=Sample(relative.normalize(),relative.length(),light.intensity)
        };
        return result
    }
    fun cone(light: Scene.Light,direction: Vector3): Long {
        if(light.kind!="spot")return S;
        val cosine=-direction.dot(light.direction);
        if(cosine<=light.outer)return 0;
        if(cosine>=light.inner)return S;
        return div((cosine-light.outer)*S,light.inner-light.outer)
    }
    fun local(hit: Hit,point: Vector3,normal: Vector3,base: Scene.Color,direction: Vector3,context: Context): Local {
        var diffuseSum=0L;
        var specularSum=0L;
        val lit=BooleanArray(scene.lights.size);
        var illumination=0;
        for(light in scene.lights) {
            var diffuse=0L;
            var specular=0L;
            var count=0;
            val lightStats=stats.lights[light.number-1];
            for(sample in samples(light,point)) {
                val ndl=normal.dot(sample.direction);
                if(ndl<=0) {
                    if(context.counted)lightStats.backfacing++;
                    continue
                };
                var factor=cone(light,sample.direction);
                if(factor==0L) {
                    if(context.counted)lightStats.outside++;
                    continue
                };
                if(context.counted) {
                    stats.rays[3]++;
                    lightStats.shadow++;
                    context.pixel!!.rays++
                };
                val blockers=occluders(point,sample.direction,sample.distance,context);
                for(obj in blockers) {
                    factor=FixedPoint.multiply(factor,obj.material.kt);
                    if(context.counted)stats.shadow[obj.number-1]++
                };
                if(factor==0L) {
                    if(context.counted)lightStats.blocked++;
                    continue
                };
                if(blockers.isNotEmpty()&&context.counted)lightStats.attenuated++;
                count++;
                val phong=Shading.phong(hit.obj.material,normal,sample.direction,direction.negate(),ndl,sample.intensity,factor);
                diffuse+=phong.diffuse;
                specular+=phong.specular
            };
            if(count>0) {
                lit[light.number-1]=true;
                illumination++
            };
            diffuseSum+=diffuse;
            specularSum+=specular;
            context.line("light ${light.number} lit $count of ${light.samples()} diffuse $diffuse specular $specular")
        };
        val color=LongArray(3);
        for(c in 0..2) {
            val raw=div(base.component(c)*(scene.ambient+diffuseSum),S)+div(255*specularSum,S);
            if(raw>255&&context.counted)stats.clamped++;
            color[c]=minOf(raw,255L)
        };
        val result=Scene.Color.of(color);
        context.line("local $result");
        return Local(result,illumination,lit)
    }
    fun trace(origin: Vector3,direction: Vector3,kind: Int,depth: Int,context: Context): TraceResult {
        if(context.counted) {
            stats.rays[kind]++;
            stats.depth[depth]++;
            val pixel=context.pixel!!;
            pixel.rays++;
            pixel.depth=maxOf(pixel.depth,depth)
        };
        context.line("ray ${KINDS[kind]} $depth origin $origin direction $direction");
        val hit=nearest(origin,direction,kind,context);
        if(hit==null) {
            if(context.counted)stats.misses[kind]++;
            context.line("miss");
            context.line("color ${scene.background}");
            return TraceResult(scene.background,null,ZERO,ZERO,BLACK,0,BooleanArray(scene.lights.size))
        };
        if(context.counted) {
            if(kind==0)stats.primary[hit.obj.number-1]++ else stats.secondary[hit.obj.number-1]++
        };
        val point=origin.add(direction.scale(hit.candidate.distance));
        val outward=Intersect.outward(hit.obj,hit.candidate,point,direction);
        val front=outward.dot(direction)<=0;
        val normal=if(front)outward else outward.negate();
        val base=Shading.base(hit.obj.material,point);
        context.line("hit ${hit.obj.label} t ${hit.candidate.distance} point $point normal $normal base $base");
        val local=local(hit,point,normal,base,direction,context);
        var color=local.color;
        val material=hit.obj.material;
        if(depth<depthLimit&&(material.kr!=0L||material.kt!=0L)) {
            val refraction=Shading.refracted(material,direction,normal,front);
            if(refraction.totalInternal) {
                if(context.counted)stats.totalInternal++;
                context.line("total_internal_reflection")
            };
            context.line("weights ${S-material.kr-material.kt} ${refraction.reflected} ${refraction.transmitted}");
            var reflected=BLACK;
            var transmitted=BLACK;
            if(refraction.reflected>0)reflected=trace(point,Shading.reflected(direction,normal),1,depth+1,context).color;
            if(refraction.transmitted>0)transmitted=trace(point,refraction.direction!!,2,depth+1,context).color;
            color=Shading.mix(listOf(color,reflected,transmitted),longArrayOf(S-material.kr-material.kt,refraction.reflected,refraction.transmitted))
        };
        val fog=scene.fog;
        if(fog!=null) {
            val t=hit.candidate.distance;
            val factor=if(t<=scene.fogStart)0L else if(t>=scene.fogEnd)S else div((t-scene.fogStart)*S,scene.fogEnd-scene.fogStart);
            color=Shading.mix(listOf(color,fog),longArrayOf(S-factor,factor))
        };
        context.line("color $color");
        return TraceResult(color,hit,point,normal,base,local.illumination,local.lit)
    }

    var minimumDistance=Long.MAX_VALUE;
    var maximumDistance=Long.MIN_VALUE;
    var maxPixelRays=0L
    fun label(pixel: Pixel)=pixel.center.hit?.obj?.label?:'.'
    fun contrast(a: Scene.Color,b: Scene.Color): Long {
        var maximum=0L;
        for(c in 0..2)maximum=maxOf(maximum,abs(a.component(c)-b.component(c)));
        return maximum
    }
    fun render() {
        pixels=Array(height) {
            Array(width) {
                Pixel()
            }
        };
        for(y in 0 until height)for(x in 0 until width) {
            val pixel=pixels[y][x];
            val context=Context(true,pixel,null);
            pixel.center=trace(scene.eye,camera(4L*x+2,4L*y+2),0,0,context);
            pixel.color=pixel.center.color;
            if(pixel.center.hit!=null)for(l in scene.lights.indices)if(pixel.center.lit[l])stats.lights[l].pixels++
        };
        for(y in 0 until height)for(x in 0 until width) {
            val pixel=pixels[y][x];
            var adaptive=false;
            for(offset in listOf(intArrayOf(-1,0),intArrayOf(1,0),intArrayOf(0,-1),intArrayOf(0,1))) {
                val xx=x+offset[0];
                val yy=y+offset[1];
                if(xx>=0&&xx<width&&yy>=0&&yy<height) {
                    val neighbor=pixels[yy][xx];
                    if(label(pixel)!=label(neighbor)||contrast(pixel.center.color,neighbor.center.color)>contrastThreshold)adaptive=true
                }
            };
            if(adaptive) {
                supersampled++;
                pixel.samples=4;
                val sum=LongArray(3);
                val context=Context(true,pixel,null);
                for(dy in 1..3 step 2)for(dx in 1..3 step 2) {
                    val color=trace(scene.eye,camera(4L*x+dx,4L*y+dy),0,0,context).color;
                    for(c in 0..2)sum[c]+=color.component(c)
                };
                pixel.color=Scene.Color(div(sum[0],4),div(sum[1],4),div(sum[2],4))
            };
            val hit=pixel.center.hit;
            if(hit!=null) {
                val t=hit.candidate.distance;
                minimumDistance=minOf(minimumDistance,t);
                maximumDistance=maxOf(maximumDistance,t)
            };
            maxPixelRays=maxOf(maxPixelRays,pixel.rays)
        }
    }
    fun clamp(value: Long)=value.coerceIn(0,255)
    fun header(kind: String)=mutableListOf(kind,"$width $height","255")
    fun images() {
        val image=header("P3");
        val depth=header("P2");
        val normal=header("P3");
        val albedo=header("P3");
        val cost=header("P2");
        val objects=mutableListOf<String>();
        val lights=mutableListOf<String>();
        val rayDepth=mutableListOf<String>();
        for(y in 0 until height) {
            val colors=mutableListOf<String>();
            val distances=mutableListOf<String>();
            val normals=mutableListOf<String>();
            val bases=mutableListOf<String>();
            val costs=mutableListOf<String>();
            val labels=StringBuilder();
            val illumination=StringBuilder();
            val depths=StringBuilder();
            for(x in 0 until width) {
                val pixel=pixels[y][x];
                colors+=pixel.color.toString();
                costs+=div(255*pixel.rays,maxPixelRays).toString();
                labels.append(label(pixel));
                depths.append(('0'.code+pixel.depth).toChar());
                val hit=pixel.center.hit;
                if(hit==null) {
                    distances+="0";
                    normals+=BLACK.toString();
                    bases+=BLACK.toString();
                    illumination.append('.')
                } else {
                    val t=hit.candidate.distance;
                    distances+=(if(maximumDistance==minimumDistance)255L else 255-div(235*(t-minimumDistance),maximumDistance-minimumDistance)).toString();
                    val n=pixel.center.normal;
                    val color=Scene.Color(clamp(div((n.x+S)*255,2*S)),clamp(div((n.y+S)*255,2*S)),clamp(div((n.z+S)*255,2*S)));
                    normals+=color.toString();
                    bases+=pixel.center.base.toString();
                    illumination.append(('0'.code+pixel.center.illumination).toChar())
                }
            };
            image+=colors.joinToString(" ");
            depth+=distances.joinToString(" ");
            normal+=normals.joinToString(" ");
            albedo+=bases.joinToString(" ");
            cost+=costs.joinToString(" ");
            objects+=labels.toString();
            lights+=illumination.toString();
            rayDepth+=depths.toString()
        };
        write("image.ppm",image);
        write("depth.pgm",depth);
        write("normal.ppm",normal);
        write("albedo.ppm",albedo);
        write("cost.pgm",cost);
        write("object_map.txt",objects);
        write("light_map.txt",lights);
        write("ray_depth.txt",rayDepth)
    }
    fun labels(objects: List<Scene.Obj>)=objects.joinToString("") {
        it.label.toString()
    }
    fun nodes(node: Node,out: MutableList<String>) {
        val objects=node.objects;
        val description=if(objects==null)"inner" else "leaf ${labels(objects)}";
        out+="node ${node.depth} $description box ${node.bounds.lo} ${node.bounds.hi} visits ${node.visits}";
        if(objects==null) {
            nodes(node.left!!,out);
            nodes(node.right!!,out)
        }
    }
    fun statistics(): List<String> {
        val out=mutableListOf("image $width $height","supersampled $supersampled");
        var total=0L;
        for(value in stats.rays)total+=value;
        out+="rays primary ${stats.rays[0]} reflection ${stats.rays[1]} refraction ${stats.rays[2]} shadow ${stats.rays[3]} total $total";
        out+="misses primary ${stats.misses[0]} reflection ${stats.misses[1]} refraction ${stats.misses[2]}";
        out+="depth ${stats.depth.joinToString(" ")}";
        for(kind in 0..3)out+="tests ${KINDS[kind]} nodes ${stats.nodes[kind]} objects ${stats.objects[kind]}";
        out+="total_internal_reflection ${stats.totalInternal}";
        out+="clamped ${stats.clamped}";
        out+=if(minimumDistance==Long.MAX_VALUE)"distance none" else "distance $minimumDistance $maximumDistance";
        out+="max_pixel_rays $maxPixelRays";
        val sum=LongArray(3);
        val histogram=LongArray(8);
        for(row in pixels)for(pixel in row) {
            for(c in 0..2)sum[c]+=pixel.color.component(c);
            val brightness=div(299*pixel.color.r+587*pixel.color.g+114*pixel.color.b,1000);
            histogram[div(brightness,32).toInt()]++
        };
        out+="mean ${Scene.Color(div(sum[0],(width*height).toLong()),div(sum[1],(width*height).toLong()),div(sum[2],(width*height).toLong()))}";
        out+="histogram ${histogram.joinToString(" ")}";
        root?.let {
            nodes(it,out)
        };
        for(obj in scene.objects) {
            var count=0;
            var x0=width;
            var y0=height;
            var x1=-1;
            var y1=-1;
            sum.fill(0);
            for(y in 0 until height)for(x in 0 until width)if(label(pixels[y][x])==obj.label) {
                count++;
                x0=minOf(x0,x);
                y0=minOf(y0,y);
                x1=maxOf(x1,x);
                y1=maxOf(y1,y);
                for(c in 0..2)sum[c]+=pixels[y][x].color.component(c)
            };
            val box=if(count==0)"none" else "$x0 $y0 $x1 $y1";
            val color=if(count==0)"none" else Scene.Color(div(sum[0],count.toLong()),div(sum[1],count.toLong()),div(sum[2],count.toLong())).toString();
            val i=obj.number-1;
            out+="object ${obj.label} ${obj.kind} primary ${stats.primary[i]} secondary ${stats.secondary[i]} shadow ${stats.shadow[i]} pixels $count box $box color $color"
        };
        for(light in scene.lights) {
            val s=stats.lights[light.number-1];
            out+="light ${light.number} ${light.kind} samples ${light.samples()} pixels ${s.pixels} shadow_rays ${s.shadow} blocked ${s.blocked} attenuated ${s.attenuated} backfacing ${s.backfacing} outside ${s.outside}"
        };
        return out
    }
    fun queries(): List<String> {
        val out=mutableListOf<String>();
        val queries=lines("queries.txt");
        val context=Context(false,null,null);
        for(q in queries.indices) {
            val line=queries[q];
            out+="query ${q+1} $line";
            val words=line.split(' ');
            when(words[0]) {
                "pixel"-> {
                    val x=words[1].toInt();
                    val y=words[2].toInt();
                    val pixel=pixels[y][x];
                    out+="label ${label(pixel)} distance ${pixel.center.hit?.candidate?.distance?.toString()?:"none"} color ${pixel.color} samples ${pixel.samples} rays ${pixel.rays}"
                };
                "trace"-> {
                    val x=words[1].toInt();
                    val y=words[2].toInt();
                    trace(scene.eye,camera(4L*x+2,4L*y+2),0,0,Context(false,null,out))
                };
                "ray"->trace(Scene.vector(words,1),Scene.vector(words,4).normalize(),0,0,Context(false,null,out));
                "object"-> {
                    val obj=scene.objects.first {
                        it.label==words[1][0]
                    };
                    val bounds=if(obj.kind=="plane")"none leaf none" else "${obj.bounds!!.lo} ${obj.bounds!!.hi} leaf ${obj.leafDepth}";
                    out+="${obj.kind} material ${obj.material.name} bounds $bounds"
                };
                "visible"-> {
                    val relative=Scene.vector(words,1).subtract(scene.eye);
                    val direction=relative.normalize();
                    val visible=occluders(scene.eye,direction,relative.length()-epsilon,context).isEmpty();
                    val first=nearest(scene.eye,direction,0,context);
                    out+="${if(visible)"yes" else "no"} first ${if(first==null)"none" else "${first.obj.label} t ${first.candidate.distance}"}"
                };
                "shadow"-> {
                    val point=Scene.vector(words,1);
                    for(light in scene.lights) {
                        val seen=mutableSetOf<Scene.Obj>();
                        var transmittance=0L;
                        for(sample in samples(light,point)) {
                            var factor=cone(light,sample.direction);
                            val blockers=occluders(point,sample.direction,sample.distance,context);
                            seen.addAll(blockers);
                            for(obj in blockers)factor=FixedPoint.multiply(factor,obj.material.kt);
                            transmittance+=factor
                        };
                        val blockers=scene.objects.filter {
                            it in seen
                        };
                        out+="light ${light.number} factor $transmittance occluders ${if(blockers.isEmpty())"none" else labels(blockers)}"
                    }
                };
                "region"-> {
                    val x0=words[1].toInt();
                    val y0=words[2].toInt();
                    val x1=words[3].toInt();
                    val y1=words[4].toInt();
                    val count=(x1-x0+1)*(y1-y0+1);
                    val sum=LongArray(3);
                    val counts=mutableMapOf<Char,Int>();
                    for(y in y0..y1)for(x in x0..x1) {
                        val pixel=pixels[y][x];
                        val label=label(pixel);
                        counts[label]=counts.getOrDefault(label,0)+1;
                        for(c in 0..2)sum[c]+=pixel.color.component(c)
                    };
                    out+="pixels $count mean ${Scene.Color(div(sum[0],count.toLong()),div(sum[1],count.toLong()),div(sum[2],count.toLong()))}";
                    for(obj in scene.objects)if(counts.getOrDefault(obj.label,0)>0)out+="label ${obj.label} ${counts.getValue(obj.label)}";
                    if(counts.getOrDefault('.',0)>0)out+="label . ${counts.getValue('.')}"
                }
            }
        };
        return out
    }
    @JvmStatic fun main(args: Array<String>) {
        scene=Scene.read();
        prepare();
        render();
        images();
        write("stats.txt",statistics());
        write("queries.txt",queries())
    }
}
