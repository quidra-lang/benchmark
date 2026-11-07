import java.io.File
import java.util.Locale
import kotlin.math.*

private val points=mutableListOf<Predicates.Point>()
private val rejects=mutableListOf<String>()
private val queries=mutableListOf<String>()
private var requested=listOf("summary")
private var layers=listOf("edges","hull","sites")
private val alphas=mutableListOf<Int>()
private var width=61
private var height=31
private var n=0
private var lineCount=0
private lateinit var model: Triangulation.Model
private lateinit var triangles: List<Triangulation.Triangle>
private lateinit var edges: List<Triangulation.Edge>
private lateinit var mst: List<Triangulation.Edge>
private val directed=mutableMapOf<Triangulation.Edge,Int>()
private val next=mutableMapOf<Int,Int>()
private val previous=mutableMapOf<Int,Int>()
private val hull=mutableListOf<Int>()
private val neighbors=mutableListOf<List<Int>>()
private val cells=mutableListOf<List<Int>>()
private lateinit var components: List<List<Int>>
private val convexLayers=mutableListOf<List<Int>>()
private val insertions=mutableListOf<Triangulation.Insertion>()
private val vertices=mutableListOf<Voronoi.Vertex>()
private val kinds=mutableListOf<String>()
private lateinit var minAngles: DoubleArray
private lateinit var maxAngles: DoubleArray
private lateinit var cellAreas: DoubleArray
private lateinit var clipped: DoubleArray
private lateinit var areas: LongArray
private lateinit var nearest: IntArray
private lateinit var component: IntArray
private lateinit var depth: IntArray
private val gabriel=mutableSetOf<Triangulation.Edge>()
private val rng=mutableSetOf<Triangulation.Edge>()
private lateinit var mstSet: Set<Triangulation.Edge>
private lateinit var paths: List<Proximity.Paths>
private var empty=0
private lateinit var enclosingCenter: Predicates.Center
private var enclosingRadius2=0.0
private lateinit var enclosingSites: List<Int>
private val sections=mutableMapOf<String,List<String>>()
private fun real(value: Double)=String.format(Locale.ROOT,"%.3f",value)
private fun numbers(values: List<Int>)=values.joinToString(" ")
private fun sites(t: Triangulation.Triangle)="${t.a} ${t.b} ${t.c}"
private fun direction(p: Predicates.Point)="${p.x} ${p.y}"
private fun center(c: Predicates.Center)=Predicates.fraction(c.x,c.d)+" "+Predicates.fraction(c.y,c.d)
private fun number(value: Int)=if(value==0)"-" else value.toString()
private fun length2(e: Triangulation.Edge)=Predicates.d2(points[e.a],points[e.b])
private fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
private fun read() {
    points+=Predicates.Point(0,0);
    val source=lines("points.txt");
    lineCount=source.size;
    val integerWord=Regex("-?[0-9]+");
    for(i in source.indices) {
        val line=source[i];
        if(line.isEmpty()||line.startsWith('#'))continue;
        val words=line.split(' ');
        val prefix="reject ${i+1} ";
        if(words.size!=2||!integerWord.matches(words[0])||!integerWord.matches(words[1])) {
            rejects+=prefix+"format";
            continue
        };
        val x=words[0].toLong();
        val y=words[1].toLong();
        if(x<0||x>1000||y<0||y>1000) {
            rejects+=prefix+"range";
            continue
        };
        val point=Predicates.Point(x,y);
        var duplicate=0;
        for(s in 1 until points.size)if(points[s]==point) {
            duplicate=s;
            break
        };
        if(duplicate>0)rejects+=prefix+"duplicate $duplicate" else points+=point
    };
    n=points.size-1;
    for(line in lines("params.txt")) {
        if(line.isEmpty()||line.startsWith('#'))continue;
        val words=line.split(' ');
        when(words[0]) {
            "plot"-> {
                width=words[1].toInt();
                height=words[2].toInt()
            };
            "plot_layers"->layers=words.drop(1);
            "sections"->requested=words.drop(1);
            "alpha"->alphas+=words.drop(1).map(String::toInt);
            "query"->queries+=line.substring(6)
        }
    }
}
private fun organize() {
    model=Triangulation.Model(points);
    for(s in 4..n)insertions+=model.insert(s);
    triangles=model.triangles();
    val all=sortedSetOf<Triangulation.Edge>();
    for(k in triangles.indices) {
        val a=triangles[k].sites();
        for(j in 0 until 3) {
            val u=a[j];
            val v=a[(j+1)%3];
            directed[Triangulation.Edge(u,v)]=k+1;
            all+=Triangulation.key(u,v)
        }
    };
    edges=all.toList();
    for(e in model.hullEdges()) {
        next[e.a]=e.b;
        previous[e.b]=e.a
    };
    val start=next.keys.min();
    var current=start;
    do {
        hull+=current;
        current=next.getValue(current)
    }
    while(current!=start);
    val adjacent=List(n+1) {
        mutableListOf<Int>()
    };
    for(e in edges) {
        adjacent[e.a]+=e.b;
        adjacent[e.b]+=e.a
    };
    neighbors+=emptyList<Int>();
    for(s in 1..n)neighbors+=Voronoi.neighbors(s,adjacent[s],model.directed,next[s]);
    val count=triangles.size;
    minAngles=DoubleArray(count);
    maxAngles=DoubleArray(count);
    areas=LongArray(count);
    for(k in 0 until count) {
        val t=triangles[k];
        val a=t.sites();
        val area=Predicates.orient(points[t.a],points[t.b],points[t.c]);
        areas[k]=area;
        var right=false;
        var obtuse=false;
        var minimum=180.0;
        var maximum=0.0;
        for(j in 0 until 3) {
            val dot=Predicates.dot(points[a[j]],points[a[(j+1)%3]],points[a[(j+2)%3]]);
            if(dot==0L)right=true;
            if(dot<0)obtuse=true;
            val angle=atan2(area.toDouble(),dot.toDouble())*180/PI;
            minimum=minOf(minimum,angle);
            maximum=maxOf(maximum,angle)
        };
        minAngles[k]=minimum;
        maxAngles[k]=maximum;
        kinds+=if(right)"right" else if(obtuse)"obtuse" else "acute";
        val center=Predicates.center(points[t.a],points[t.b],points[t.c]);
        vertices+=Voronoi.Vertex(center,Voronoi.radius2(points[t.a],points[t.b],points[t.c]),Voronoi.position(center,hull,points))
    };
    cells+=emptyList<Int>();
    cellAreas=DoubleArray(n+1);
    clipped=DoubleArray(n+1);
    for(s in 1..n) {
        val ids=mutableListOf<Int>();
        for(neighbor in neighbors[s])directed[Triangulation.Edge(s,neighbor)]?.let {
            ids+=it
        };
        cells+=ids;
        if(s !in next)cellAreas[s]=Voronoi.area(s,ids,vertices,points);
        clipped[s]=Voronoi.clipped(s,neighbors[s],points)
    };
    nearest=Proximity.nearest(points,neighbors);
    components=Proximity.components(nearest);
    component=IntArray(n+1);
    for(c in components.indices)for(s in components[c])component[s]=c+1;
    mst=Proximity.mst(points,edges);
    mstSet=mst.toSet();
    for(e in edges) {
        if(Proximity.gabriel(points,e,model.directed))gabriel+=e;
        if(Proximity.rng(points,e))rng+=e
    };
    for(k in vertices.indices)if(vertices[k].position=="inside"&&(empty==0||vertices[k].r2>vertices[empty-1].r2))empty=k+1;
    paths=List(n+1) {
        if(it==0)Proximity.Paths(doubleArrayOf(),intArrayOf()) else Proximity.dijkstra(points,neighbors,it)
    };
    computeLayers();
    enclosing()
}
private fun convex(sites: List<Int>): List<Int> {
    if(sites.size<=2)return sites.sorted();
    val sorted=sites.sortedWith(compareBy<Int> {
        points[it].x
    }.thenBy {
        points[it].y
    });
    val lower=mutableListOf<Int>();
    val upper=mutableListOf<Int>();
    for(s in sorted) {
        while(lower.size>=2&&Predicates.orient(points[lower[lower.size-2]],points[lower.last()],points[s])<=0)lower.removeAt(lower.lastIndex);
        lower+=s
    };
    for(i in sorted.size-1 downTo 0) {
        val s=sorted[i];
        while(upper.size>=2&&Predicates.orient(points[upper[upper.size-2]],points[upper.last()],points[s])<=0)upper.removeAt(upper.lastIndex);
        upper+=s
    };
    lower.removeAt(lower.lastIndex);
    upper.removeAt(upper.lastIndex);
    lower+=upper;
    val smallest=lower.indexOf(lower.min());
    return lower.indices.map {
        lower[(smallest+it)%lower.size]
    }
}
private fun computeLayers() {
    depth=IntArray(n+1);
    val remaining=(1..n).toMutableList();
    while(remaining.isNotEmpty()) {
        val layer=convex(remaining);
        convexLayers+=layer;
        for(s in layer)depth[s]=convexLayers.size;
        remaining.removeAll(layer.toSet())
    }
}
private fun circleTest(support: List<Int>,site: Int): Long {
    val p=points[site];
    if(support.size==1)return -Predicates.d2(p,points[support[0]]);
    if(support.size==2)return -Predicates.dot(p,points[support[0]],points[support[1]]);
    val a=points[support[0]];
    val b=points[support[1]];
    val c=points[support[2]];
    return if(Predicates.orient(a,b,c)>0)Predicates.incircle(a,b,c,p) else Predicates.incircle(a,c,b,p)
}
private fun enclosing() {
    var support=emptyList<Int>();
    for(i in hull.indices) {
        val a=hull[i];
        if(support.isEmpty()||circleTest(support,a)<0) {
            support=listOf(a);
            for(j in 0 until i) {
                val b=hull[j];
                if(circleTest(support,b)<0) {
                    support=listOf(a,b);
                    for(k in 0 until j) {
                        val c=hull[k];
                        if(circleTest(support,c)<0)support=listOf(a,b,c)
                    }
                }
            }
        }
    };
    enclosingSites=(1..n).filter {
        circleTest(support,it)==0L
    };
    for(i in enclosingSites.indices)for(j in i+1 until enclosingSites.size) {
        val a=enclosingSites[i];
        val b=enclosingSites[j];
        var diameter=true;
        for(s in enclosingSites)if(Predicates.dot(points[s],points[a],points[b])!=0L)diameter=false;
        if(diameter) {
            enclosingCenter=Predicates.Center(points[a].x+points[b].x,points[a].y+points[b].y,2);
            enclosingRadius2=Predicates.d2(points[a],points[b])/4.0;
            return
        }
    };
    val a=enclosingSites[0];
    var b=enclosingSites[1];
    var c=enclosingSites[2];
    if(Predicates.orient(points[a],points[b],points[c])<0) {
        val swap=b;
        b=c;
        c=swap
    };
    enclosingCenter=Predicates.center(points[a],points[b],points[c]);
    enclosingRadius2=Voronoi.radius2(points[a],points[b],points[c])
}
private fun dual(e: Triangulation.Edge): String {
    val left=directed[e]?:0;
    val right=directed[Triangulation.Edge(e.b,e.a)]?:0;
    if(left>0&&right>0)return "segment $left $right";
    val normal=if(left>0)Voronoi.outward(points[e.a],points[e.b]) else Voronoi.outward(points[e.b],points[e.a]);
    return "ray ${if(left>0)left else right} "+direction(normal)
}
private fun triangulationSections() {
    var output=mutableListOf("lines $lineCount","accepted $n","rejected ${rejects.size}");
    output+=rejects;
    sections["input"]=output;
    var flips=0;
    var outside=0;
    var maxFlips=-1;
    var maxSite=0;
    var acute=0;
    var right=0;
    var obtuse=0;
    for(i in insertions.indices) {
        val insertion=insertions[i];
        flips+=insertion.flips;
        if(insertion.kind=="outside")outside++;
        if(insertion.flips>maxFlips) {
            maxFlips=insertion.flips;
            maxSite=i+4
        }
    };
    for(kind in kinds)if(kind=="acute")acute++ else if(kind=="right")right++ else obtuse++;
    sections["summary"]=listOf("sites $n","triangles ${triangles.size}","edges ${edges.size}",
        "hull_vertices ${hull.size}","interior_sites ${n-hull.size}","euler ${n-edges.size+triangles.size}",
        "flips $flips","outside_insertions $outside","max_flips ${if(maxSite==0)"none" else "$maxSite $maxFlips"}",
        "acute $acute","right $right","obtuse $obtuse");
    output=mutableListOf("init "+sites(model.initial));
    for(i in insertions.indices) {
        val insertion=insertions[i];
        output+="insert ${i+4} ${insertion.kind} ${insertion.containing?.let{sites(it)}?:insertion.visible.toString()} flips ${insertion.flips} triangles ${insertion.triangles} hull ${insertion.hull}"
    };
    sections["insertions"]=output;
    output=mutableListOf();
    for(k in triangles.indices) {
        val t=triangles[k];
        output+="tri ${k+1} ${sites(t)} area2 ${areas[k]} ${kinds[k]} adj ${number(directed[Triangulation.Edge(t.c,t.b)]?:0)} ${number(directed[Triangulation.Edge(t.a,t.c)]?:0)} ${number(directed[Triangulation.Edge(t.b,t.a)]?:0)}"
    };
    sections["triangles"]=output;
    output=mutableListOf();
    for(e in edges) {
        val left=directed[e]?:0;
        val rightId=directed[Triangulation.Edge(e.b,e.a)]?:0;
        output+="edge ${e.a} ${e.b} ${if(left>0&&rightId>0)"inner" else "hull"} len2 ${length2(e)} left ${number(left)} right ${number(rightId)}"
    };
    sections["edges"]=output;
    var perimeter=0.0;
    var area=0L;
    for(i in hull.indices) {
        val a=points[hull[i]];
        val b=points[hull[(i+1)%hull.size]];
        perimeter+=sqrt(Predicates.d2(a,b).toDouble());
        area+=a.x*b.y-b.x*a.y
    };
    sections["hull"]=listOf("hull_vertices ${hull.size}","order "+numbers(hull),"perimeter ${real(perimeter)}","area2 $area");
    output=mutableListOf("layers ${convexLayers.size}");
    for(i in convexLayers.indices)output+="layer ${i+1} size ${convexLayers[i].size} sites ${numbers(convexLayers[i])}";
    sections["convex_layers"]=output;
    var min=0;
    var max=0;
    var total=0.0;
    val histogram=IntArray(6);
    for(k in triangles.indices) {
        if(minAngles[k]<minAngles[min])min=k;
        if(maxAngles[k]>maxAngles[max])max=k;
        total+=minAngles[k];
        histogram[(minAngles[k]/10).toInt()]++
    };
    output=mutableListOf("min_angle ${real(minAngles[min])} tri ${min+1}","max_angle ${real(maxAngles[max])} tri ${max+1}",
        "mean_min_angle ${real(total/triangles.size)}");
    for(bin in 0 until 6)output+="bin ${10*bin} ${10*(bin+1)} ${histogram[bin]}";
    sections["quality"]=output
}
private fun voronoiSections() {
    var inside=0;
    var on=0;
    var outside=0;
    for(vertex in vertices)if(vertex.position=="inside")inside++ else if(vertex.position=="on")on++ else outside++;
    var output=mutableListOf("inside $inside","on $on","outside $outside");
    for(k in vertices.indices) {
        val v=vertices[k];
        output+="v ${k+1} ${center(v.center)} r ${real(sqrt(v.r2))} ${v.position}"
    };
    sections["vertices"]=output;
    output=mutableListOf("segments ${edges.size-hull.size}","rays ${hull.size}");
    for(e in edges)output+="ve ${e.a} ${e.b} ${dual(e)}";
    sections["voronoi_edges"]=output;
    var total=0.0;
    var clipTotal=0.0;
    var largest=0;
    for(s in 1..n) {
        clipTotal+=clipped[s];
        if(s !in next) {
            total+=cellAreas[s];
            if(largest==0||cellAreas[s]>cellAreas[largest])largest=s
        }
    };
    output=mutableListOf("bounded ${n-hull.size}","unbounded ${hull.size}","total_area ${real(total)}",
        "clip_total ${real(clipTotal)}",if(largest==0)"largest none" else "largest $largest area ${real(cellAreas[largest])}");
    for(s in 1..n) {
        var line="cell $s ";
        if(s !in next)line+="bounded ${cells[s].size} area ${real(cellAreas[s])} clip ${real(clipped[s])} vertices ${numbers(cells[s])}" else {
            val incoming=Voronoi.outward(points[s],points[next.getValue(s)]);
            val outgoing=Voronoi.outward(points[previous.getValue(s)],points[s]);
            line+="unbounded ${cells[s].size} clip ${real(clipped[s])} from ${direction(incoming)} vertices ${numbers(cells[s])} to ${direction(outgoing)}"
        };
        output+=line
    };
    sections["cells"]=output
}
private fun derivedSections() {
    var mutual=0;
    for(s in 1..n)if(nearest[nearest[s]]==s&&s<nearest[s])mutual++;
    var closest=edges[0];
    for(e in edges)if(length2(e)<length2(closest))closest=e;
    var output=mutableListOf("mutual_pairs $mutual","closest_pair ${closest.a} ${closest.b} d2 ${length2(closest)}");
    for(s in 1..n)output+="nn $s ${nearest[s]} d2 ${Predicates.d2(points[s],points[nearest[s]])} ${if(nearest[nearest[s]]==s)"mutual" else "-"}";
    sections["nearest"]=output;
    output=mutableListOf("components ${components.size}");
    for(c in components.indices) {
        val sites=components[c];
        var pair=0;
        for(s in sites)if(s<nearest[s]&&nearest[nearest[s]]==s) {
            pair=s;
            break
        };
        output+="component ${c+1} size ${sites.size} pair $pair ${nearest[pair]} sites ${numbers(sites)}"
    };
    sections["components"]=output;
    var length=0.0;
    for(e in mst)length+=sqrt(length2(e).toDouble());
    val longest=mst.last();
    output=mutableListOf("edges ${n-1}","total_length ${real(length)}","longest ${longest.a} ${longest.b} len2 ${length2(longest)}");
    for(e in mst)output+="mst ${e.a} ${e.b} len2 ${length2(e)}";
    sections["mst"]=output;
    output=mutableListOf("delaunay ${edges.size}","gabriel ${gabriel.size}","rng ${rng.size}","mst ${n-1}","nn ${n-mutual}");
    for(e in edges)if(e in rng&&e !in mstSet)output+="rng_extra ${e.a} ${e.b} len2 ${length2(e)}";
    sections["proximity"]=output;
    val degreeCounts=sortedMapOf<Int,Int>();
    for(s in 1..n) {
        val degree=neighbors[s].size;
        degreeCounts[degree]=degreeCounts.getOrDefault(degree,0)+1
    };
    output=mutableListOf("min ${degreeCounts.keys.min()}","max ${degreeCounts.keys.max()}");
    for(degree in degreeCounts.keys)output+="degree $degree count ${degreeCounts[degree]}";
    sections["degrees"]=output;
    var candidates=0;
    for(v in vertices)if(v.position=="inside")candidates++;
    output=mutableListOf("candidates $candidates");
    if(empty==0)output+="none" else {
        val v=vertices[empty-1];
        output+="vertex $empty";
        output+="center "+center(v.center);
        output+="radius ${real(sqrt(v.r2))}";
        output+="sites "+sites(triangles[empty-1])
    };
    sections["empty_circle"]=output;
    var diameterA=1;
    var diameterB=2;
    var diameter=Predicates.d2(points[1],points[2]);
    for(i in 1..n)for(j in i+1..n) {
        val distance=Predicates.d2(points[i],points[j]);
        if(distance>diameter) {
            diameter=distance;
            diameterA=i;
            diameterB=j
        }
    };
    var width=Double.POSITIVE_INFINITY;
    var edgeAt=0;
    for(t in hull.indices) {
        val a=points[hull[t]];
        val b=points[hull[(t+1)%hull.size]];
        var farthest=0L;
        for(s in hull)farthest=maxOf(farthest,Predicates.orient(a,b,points[s]));
        val candidate=farthest/sqrt(Predicates.d2(a,b).toDouble());
        if(candidate<width) {
            width=candidate;
            edgeAt=t
        }
    };
    sections["extent"]=listOf("diameter $diameterA $diameterB d2 $diameter","width ${real(width)} edge ${hull[edgeAt]} ${hull[(edgeAt+1)%hull.size]}",
        "enclosing_center "+center(enclosingCenter),"enclosing_radius ${real(sqrt(enclosingRadius2))}",
        "enclosing_sites "+numbers(enclosingSites));
    var totalStretch=0.0;
    var maxStretch=0.0;
    var maxLength=0.0;
    var maxDistance=0.0;
    var pairA=0;
    var pairB=0;
    for(i in 1..n)for(j in i+1..n) {
        val distance=sqrt(Predicates.d2(points[i],points[j]).toDouble());
        val path=paths[i].distance[j];
        val stretch=path/distance;
        totalStretch+=stretch;
        if(stretch>maxStretch) {
            maxStretch=stretch;
            pairA=i;
            pairB=j;
            maxLength=path;
            maxDistance=distance
        }
    };
    val pairs=n*(n-1)/2;
    sections["spanner"]=listOf("pairs $pairs","max_stretch ${real(maxStretch)} pair $pairA $pairB length ${real(maxLength)} distance ${real(maxDistance)}",
        "mean_stretch ${real(totalStretch/pairs)}");
    output=mutableListOf();
    for(alpha in alphas) {
        val selected=mutableSetOf<Triangulation.Edge>();
        val selectedCounts=mutableMapOf<Triangulation.Edge,Int>();
        var faces=0;
        var area2=0L;
        for(k in triangles.indices)if(vertices[k].r2<=alpha) {
            faces++;
            area2+=areas[k];
            val sites=triangles[k].sites();
            for(j in 0 until 3) {
                val e=Triangulation.key(sites[j],sites[(j+1)%3]);
                selected+=e;
                selectedCounts[e]=selectedCounts.getOrDefault(e,0)+1
            }
        };
        for(e in edges)if(e in gabriel&&length2(e)<=4L*alpha)selected+=e;
        val sets=Proximity.Sets(n);
        var boundary=0;
        var dangling=0;
        val used=mutableSetOf<Int>();
        for(e in edges)if(e in selected) {
            sets.union(e.a,e.b);
            used+=e.a;
            used+=e.b;
            val count=selectedCounts.getOrDefault(e,0);
            if(count==1)boundary++;
            if(count==0)dangling++
        };
        output+="alpha $alpha triangles $faces edges ${selected.size} boundary $boundary dangling $dangling isolated ${n-used.size} components ${sets.count} holes ${sets.count-(n-selected.size+faces)} area2 $area2"
    };
    sections["alpha"]=output;
    output=mutableListOf();
    val gg=IntArray(n+1);
    val rg=IntArray(n+1);
    val mt=IntArray(n+1);
    for(e in edges) {
        if(e in gabriel) {
            gg[e.a]++;
            gg[e.b]++
        };
        if(e in rng) {
            rg[e.a]++;
            rg[e.b]++
        };
        if(e in mstSet) {
            mt[e.a]++;
            mt[e.b]++
        }
    };
    for(s in 1..n)output+="site $s ${direction(points[s])} ${if(s in next)"hull" else "inner"} dt ${neighbors[s].size} gg ${gg[s]} rng ${rg[s]} mst ${mt[s]} nn ${nearest[s]} comp ${component[s]} depth ${depth[s]}";
    sections["sites"]=output
}
private fun locate(query: Predicates.Point): String {
    for(s in 1..n)if(points[s]==query)return "vertex $s";
    for(e in edges)if(Predicates.orient(points[e.a],points[e.b],query)==0L&&Predicates.dot(query,points[e.a],points[e.b])<0)return "edge ${e.a} ${e.b}";
    for(t in triangles)if(Predicates.orient(points[t.a],points[t.b],query)>0&&Predicates.orient(points[t.b],
        points[t.c],query)>0&&Predicates.orient(points[t.c],points[t.a],query)>0)return "triangle "+sites(t);
    return "outside"
}
private fun query(line: String): String {
    val w=line.split(' ');
    val type=w[0];
    val i=w[1].toInt();
    val j=if(w.size==3)w[2].toInt() else 0;
    if(type in listOf("locate","walk","natural")) {
        val point=Predicates.Point(i.toLong(),j.toLong());
        if(type=="locate") {
            var nearest=1;
            var distance=Predicates.d2(points[1],point);
            for(s in 2..n) {
                val d=Predicates.d2(points[s],point);
                if(d<distance) {
                    nearest=s;
                    distance=d
                }
            };
            return locate(point)+" nearest $nearest d2 $distance"
        };
        if(type=="walk") {
            val walk=Triangulation.walk(point,points,triangles,directed);
            val stop=walk.outside?.let {
                "outside ${it.a} ${it.b}"
            }
            ?:"triangle ${walk.path.last()}";
            return "steps ${walk.path.size-1} $stop path ${numbers(walk.path)}"
        };
        var count=0;
        val selected=sortedSetOf<Int>();
        for(t in triangles)if(Predicates.incircle(points[t.a],points[t.b],points[t.c],point)>0) {
            count++;
            selected+=t.a;
            selected+=t.b;
            selected+=t.c
        };
        return "triangles $count sites ${if(selected.isEmpty())"-" else numbers(selected.toList())}"
    };
    if(i<1||i>n||w.size==3&&(j<1||j>n))return "error unknown_site";
    if(type=="neighbors")return "degree ${neighbors[i].size} sites ${numbers(neighbors[i])}";
    if(type=="route") {
        val route=Proximity.route(points,neighbors,i,j);
        return "hops ${route.sites.size-1} length ${real(route.length)} path ${numbers(route.sites)}"
    };
    if(type=="path") {
        val path=paths[i].path(j);
        val length=paths[i].distance[j];
        return "length ${real(length)} stretch ${if(i==j)"-" else real(length/sqrt(Predicates.d2(points[i],points[j]).toDouble()))} hops ${path.size-1} sites ${numbers(path)}"
    };
    if(i==j)return "error same_site";
    val e=Triangulation.key(i,j);
    if(e in directed||Triangulation.Edge(e.b,e.a) in directed)return "delaunay len2 ${length2(e)} gabriel ${if(e in gabriel)"yes" else "no"} rng ${if(e in rng)"yes" else "no"} mst ${if(e in mstSet)"yes" else "no"} dual ${dual(e)}";
    val crossing=mutableListOf<String>();
    for(edge in edges)if(Predicates.orient(points[i],points[j],points[edge.a])*Predicates.orient(points[i],
        points[j],points[edge.b])<0&&Predicates.orient(points[edge.a],points[edge.b],points[i])*Predicates.orient(points[edge.a],
        points[edge.b],points[j])<0)crossing+="${edge.a}-${edge.b}";
    return "missing crossings ${crossing.size}"+(if(crossing.isEmpty())"" else " "+crossing.joinToString(" "))
}
private fun querySections() {
    sections["queries"]=queries.map {
        it+" "+query(it)
    }
}
private fun plotSections() {
    val canvas=Plot.canvas(width,height);
    for(layer in layers)when(layer) {
        "edges"->for(e in edges)Plot.line(canvas,Plot.map(points[e.a],width,height),Plot.map(points[e.b],width,height),'.');
        "mst"->for(e in mst)Plot.line(canvas,Plot.map(points[e.a],width,height),Plot.map(points[e.b],width,height),'*');
        "hull"->for(t in hull.indices)Plot.line(canvas,Plot.map(points[hull[t]],width,height),Plot.map(points[hull[(t+1)%hull.size]],width,height),'#');
        "sites"->for(s in 1..n) {
            val c=Plot.map(points[s],width,height);
            canvas[c.row][c.col]='o'
        };
        "circle"->if(empty>0) {
            val c=Plot.center(vertices[empty-1].center,width,height);
            canvas[c.row][c.col]='@'
        }
    };
    sections["delaunay_plot"]=Plot.frame(canvas);
    sections["voronoi_plot"]=Plot.frame(Plot.voronoi(points,width,height))
}
private fun write() {
    val files=listOf("triangulation.txt","voronoi.txt","derived.txt","plot.txt");
    val names=listOf(listOf("input","summary","insertions","triangles","edges","hull","convex_layers",
        "quality"),listOf("vertices","voronoi_edges","cells"),listOf("nearest","components",
        "mst","proximity","degrees","empty_circle","extent","spanner","alpha","sites","queries"),
        listOf("delaunay_plot","voronoi_plot"));
    for(f in files.indices) {
        val output=mutableListOf<String>();
        for(section in requested)if(section in names[f]) {
            output+="[$section]";
            output+=sections.getValue(section)
        };
        File("output/${files[f]}").writeText(if(output.isEmpty())"" else output.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
}
fun main() {
    read();
    organize();
    triangulationSections();
    voronoiSections();
    derivedSections();
    querySections();
    plotSections();
    write()
}
