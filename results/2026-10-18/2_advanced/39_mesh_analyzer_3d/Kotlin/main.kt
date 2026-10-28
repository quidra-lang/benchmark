import java.io.File

private class Settings {
    var snap=1;
    var fillHoles=0;
    var merge=true;
    var degenerate=true;
    var duplicates=true;
    var orient=true;
    var outward=true;
    var keepUnused=true;
    var sections=listOf("summary","components");
    val queries=mutableListOf<List<String>>()
}
private fun settings(): Settings {
    val s=Settings();
    for(line in File("input/params.txt").readLines(Charsets.US_ASCII)) {
        if(line.isEmpty()||line.startsWith("#"))continue;
        val w=line.split(' ');
        when(w[0]) {
            "snap"->s.snap=w[1].toInt();
            "fill_holes"->s.fillHoles=w[1].toInt();
            "merge"->s.merge=w[1]=="on";
            "degenerate"->s.degenerate=w[1]=="on";
            "duplicates"->s.duplicates=w[1]=="on";
            "orient"->s.orient=w[1]=="on";
            "outward"->s.outward=w[1]=="on";
            "keep_unused"->s.keepUnused=w[1]=="on";
            "sections"->s.sections=w.drop(1);
            "query"->s.queries+=w.drop(1)
        }
    };
    return s
}
private fun yes(b: Boolean)=if(b)"yes" else "no"
private fun listing(values: Iterable<*>)=values.toList().let {
    if(it.isEmpty())"-" else it.joinToString(" ")
}
private class Description(val c: Topology.Component) {
    var closed=false;
    var manifold=false;
    var consistent=false;
    var solid=false;
    var orientable=false;
    var loops=0;
    var euler=0;
    var genus: Int?=null;
    var crosscaps: Int?=null;
    var volume=0L;
    var area=0.0;
    var normal=Measure.Vec(0,0,0);
    var bbox=LongArray(6);
    var centroid="-";
    val inside=mutableListOf<Int>();
    val shapes=mutableMapOf<String,Int>();
    val angles=mutableMapOf<String,Int>();
    var edgeMin=Long.MAX_VALUE;
    var edgeMax=0L;
    var valenceMin=Int.MAX_VALUE;
    var valenceMax=0
}
private class Analysis(val source: ObjIo.Model,val settings: Settings) {
    val changes=mutableListOf<Repair.Snap>();
    val removed=mutableListOf<Repair.Removed>();
    val snapped=Repair.snap(source.vertices,settings.snap,changes);
    val representatives=Repair.representatives(snapped,settings.merge);
    val triangles=Repair.split(source.polygons);
    val faces=Repair.clean(triangles,snapped,representatives,settings.degenerate,settings.duplicates,removed);
    val points=mutableListOf(Measure.Vec(0,0,0));
    val renumber=sortedMapOf<Int,Int>();
    val merged=sortedMapOf<Int,MutableList<Int>>();
    lateinit var before: Topology.Mesh;
    lateinit var mesh: Topology.Mesh;
    var inconsistentBefore=listOf<Topology.Edge>();
    var inconsistentAfter=listOf<Topology.Edge>();
    var loops=listOf<Topology.Loop>();
    val components=mutableListOf<Description>();
    val initial=faces.size;
    var added=0;
    var flipped=0;
    var outward=0;
    val nonplanar=mutableSetOf<Int>();
    val groups=mutableListOf<String>()
}
private fun increment(m: MutableMap<String,Int>,key: String) {
    m[key]=m.getOrDefault(key,0)+1
}
private fun shape(e: Topology.Edge,a: Analysis): String {
    val ids=a.mesh.edges.getValue(e);
    if(ids.size!=2)return "-";
    val f=a.faces[ids[0]-1];
    val g=a.faces[ids[1]-1];
    if(Orientation.directed(f,e.a,e.b)==Orientation.directed(g,e.a,e.b))return "inconsistent";
    val third=g.v.first {
        it!=e.a&&it!=e.b
    };
    val signed=Measure.dot(Measure.subtract(a.points[third],a.points[f.v[0]]),Measure.normal(f,a.points));
    return if(signed<0)"convex" else if(signed>0)"concave" else "flat"
}
private fun nonplanar(p: ObjIo.Polygon,points: List<Measure.Vec>): Boolean {
    val first=points[p.v[0]];
    var n=Measure.Vec(0,0,0);
    for(i in 1 until p.v.size-1)n=Measure.add(n,Measure.cross(Measure.subtract(points[p.v[i]],first),Measure.subtract(points[p.v[i+1]],first)));
    return p.v.any {
        Measure.dot(Measure.subtract(points[it],first),n)!=0L
    }
}
private fun analyze(source: ObjIo.Model,s: Settings): Analysis {
    val a=Analysis(source,s);
    val present=if(s.keepUnused)(1 until a.representatives.size).filter {
        a.representatives[it]==it
    }.toSortedSet() else a.faces.flatMap {
        it.v.toList()
    }.toSortedSet();
    for(v in present) {
        a.renumber[v]=a.points.size;
        a.points+=a.snapped[v]
    };
    for(f in a.faces)for(k in 0..2)f.v[k]=a.renumber.getValue(f.v[k]);
    val original=a.faces.map {
        it.v.copyOf()
    };
    a.before=Topology.analyze(a.faces);
    a.inconsistentBefore=Orientation.inconsistent(a.faces,a.before.edges);
    if(s.orient)Orientation.repair(a.faces,a.before.edges);
    a.inconsistentAfter=Orientation.inconsistent(a.faces,a.before.edges);
    a.loops=Topology.loops(a.faces,a.before);
    val permitted=a.before.components.filter {
        it.nonmanifold.isEmpty()&&it.edges.none {
            e->e in a.inconsistentAfter
        }
    }.map {
        it.number
    }.toSet();
    a.added=Repair.fill(a.faces,a.loops,s.fillHoles,permitted);
    a.mesh=Topology.analyze(a.faces);
    val inconsistent=Orientation.inconsistent(a.faces,a.mesh.edges)
    for(c in a.mesh.components) {
        val d=Description(c);
        d.closed=c.boundary.isEmpty();
        d.manifold=c.nonmanifold.isEmpty()&&c.nonmanifoldVertices.isEmpty();
        d.consistent=c.edges.none {
            it in inconsistent
        };
        d.solid=d.closed&&d.manifold&&d.consistent;
        a.components+=d
    }
    for(d in a.components)if(d.solid)for(other in a.components)if(other!==d&&other.solid) {
        val vertex=d.c.vertices.firstOrNull {
            it !in other.c.vertices
        };
        if(vertex!=null&&Measure.winding(other.c.faces,a.faces,a.points,a.points[vertex])!=0)d.inside+=other.c.number
    }
    for(d in a.components)if(d.solid&&s.outward) {
        val v=Measure.volume(d.c.faces,a.faces,a.points);
        if(v!=0L&&((d.inside.size%2==0&&v<0)||(d.inside.size%2==1&&v>0))) {
            for(i in d.c.faces)Orientation.flip(a.faces[i-1]);
            a.outward++
        }
    }
    a.flipped=(0 until a.initial).count {
        !original[it].contentEquals(a.faces[it].v)
    };
    val orientable=Orientation.orientable(a.faces,a.mesh);
    val loopCount=Topology.loops(a.faces,a.mesh).groupingBy {
        it.component
    }.eachCount()
    for(d in a.components) {
        val c=d.c;
        d.orientable=orientable[c.number];
        d.loops=loopCount.getOrDefault(c.number,0);
        d.euler=c.vertices.size-c.edges.size+c.faces.size;
        if(d.manifold) {
            if(d.orientable)d.genus=Math.floorDiv(2-d.euler-d.loops,2) else d.crosscaps=2-d.euler-d.loops
        };
        d.volume=Measure.volume(c.faces,a.faces,a.points);
        d.area=Measure.area(c.faces.map {
            a.faces[it-1]
        },a.points);
        for(i in c.faces) {
            val f=a.faces[i-1];
            d.normal=Measure.add(d.normal,Measure.normal(f,a.points));
            increment(d.angles,Measure.angle(f,a.points))
        };
        d.bbox=Measure.bbox(c.vertices,a.points);
        if(d.solid&&d.volume!=0L)d.centroid=Measure.centroid(c.faces,a.faces,a.points,d.volume);
        val degree=mutableMapOf<Int,Int>();
        for(e in c.edges) {
            increment(d.shapes,shape(e,a));
            val length=Measure.length(e,a.points);
            d.edgeMin=minOf(d.edgeMin,length);
            d.edgeMax=maxOf(d.edgeMax,length);
            degree[e.a]=degree.getOrDefault(e.a,0)+1;
            degree[e.b]=degree.getOrDefault(e.b,0)+1
        };
        d.valenceMin=degree.values.min();
        d.valenceMax=degree.values.max()
    }
    for(p in source.polygons) {
        if(nonplanar(p,a.snapped))a.nonplanar+=p.number;
        if(p.group !in a.groups)a.groups+=p.group
    };
    if(a.added>0)a.groups+="fill";
    for(i in 1 until a.representatives.size)a.merged.getOrPut(a.representatives[i]) {
        mutableListOf()
    }
    +=i;
    return a
}
private fun summary(a: Analysis,out: MutableList<String>) {
    val s=a.source;
    val sizes=s.polygons.groupingBy {
        it.v.size
    }.eachCount().toSortedMap();
    val reasons=a.removed.groupingBy {
        it.reason
    }.eachCount();
    val merged=(1 until a.representatives.size).count {
        a.representatives[it]!=it
    };
    out+=listOf("[summary]","lines ${s.lines}","vertices ${s.vertices.size-1}","polygons ${s.polygons.size}","errors ${s.errors.size}","ignored ${s.ignored}","nonplanar_polygons ${a.nonplanar.size}");
    for((size,n) in sizes)out+="polygon_size $size $n";
    out+=listOf("triangles ${a.triangles.size}","snapped ${a.changes.size}","merged $merged","removed_repeated ${reasons.getOrDefault("repeated",0)}","removed_zero_area ${reasons.getOrDefault("zero_area",0)}","removed_duplicate ${reasons.getOrDefault("duplicate",0)}","faces ${a.initial}","inconsistent_before ${a.inconsistentBefore.size}","flipped_faces ${a.flipped}","outward_components ${a.outward}","boundary_loops ${a.loops.size}","holes_filled ${a.loops.count{it.filled}}","fill_faces ${a.added}","final_vertices ${a.points.size-1}","final_faces ${a.faces.size}","components ${a.components.size}","solids ${a.components.count{it.solid}}","total_area ${Measure.real(Measure.area(a.faces,a.points))}","total_volume ${Measure.fraction(a.components.filter{it.solid}.sumOf{it.volume},6)}")
}
private fun cleanup(a: Analysis,out: MutableList<String>) {
    out+=listOf("[cleanup]","snapped ${a.changes.size}");
    for(s in a.changes)out+="snap ${s.number} ${s.before} to ${s.after}";
    out+="merged ${(1 until a.representatives.size).count{a.representatives[it]!=it}}";
    for((r,members) in a.merged)if(members.size>1)out+="merge ${a.renumber[r]?.toString()?:"-"} ${listing(members)}";
    out+="removed ${a.removed.size}";
    for(r in a.removed)out+="remove ${r.face.triangle} polygon ${r.face.polygon} line ${r.face.line} ${r.reason}"
}
private fun components(a: Analysis,out: MutableList<String>) {
    for(d in a.components) {
        val c=d.c;
        val groups=a.groups.filter {
            g->c.faces.any {
                a.faces[it-1].group==g
            }
        };
        out+=listOf("[component ${c.number}]","groups ${listing(groups)}","faces ${c.faces.size}","vertices ${c.vertices.size}","edges ${c.edges.size}","boundary_edges ${c.boundary.size}","nonmanifold_edges ${c.nonmanifold.size}","nonmanifold_vertices ${c.nonmanifoldVertices.size}","boundary_loops ${d.loops}","closed ${yes(d.closed)}","manifold ${yes(d.manifold)}","orientable ${yes(d.orientable)}","consistent ${yes(d.consistent)}","solid ${yes(d.solid)}","euler ${d.euler}",if(d.genus!=null)"genus ${d.genus}" else if(d.crosscaps!=null)"crosscaps ${d.crosscaps}" else "genus -","volume ${if(d.solid)Measure.fraction(d.volume,6) else "-"}","area ${Measure.real(d.area)}","normal_sum ${d.normal}","bbox ${d.bbox.joinToString(" ")}","inside ${listing(d.inside)}","centroid ${d.centroid}");
        for(key in listOf("convex","concave","flat"))out+="$key ${d.shapes.getOrDefault(key,0)}";
        for(key in listOf("acute","right","obtuse"))out+="$key ${d.angles.getOrDefault(key,0)}";
        out+="edge_len2 ${d.edgeMin} ${d.edgeMax}";
        out+="valence ${d.valenceMin} ${d.valenceMax}"
    }
}
private fun groups(a: Analysis,out: MutableList<String>) {
    for(g in a.groups) {
        val p=a.source.polygons.filter {
            it.group==g
        };
        val ids=a.faces.indices.filter {
            a.faces[it].group==g
        };
        out+=listOf("[group $g]","polygons ${p.size}","triangles ${a.triangles.count{it.group==g}}","nonplanar ${p.count{it.number in a.nonplanar}}","faces ${ids.size}","area ${Measure.real(Measure.area(ids.map{a.faces[it]},a.points))}","components ${listing(ids.map{a.mesh.faceComponent[it+1]}.toSortedSet())}")
    }
}
private fun contacts(a: Analysis,out: MutableList<String>) {
    out+="[contacts]";
    for(i in a.components.indices)for(j in i+1 until a.components.size) {
        val f=a.components[i];
        val g=a.components[j];
        if((0..2).any {
            f.bbox[it]>g.bbox[it+3]||g.bbox[it]>f.bbox[it+3]
        })continue;
        val shared=f.c.vertices.count {
            it in g.c.vertices
        };
        var gap=Long.MAX_VALUE;
        for(u in f.c.vertices)for(v in g.c.vertices)if(u!=v)gap=minOf(gap,Measure.length(Topology.edge(u,v),a.points));
        out+="contact ${f.c.number} ${g.c.number} shared $shared gap2 $gap"
    }
}
private fun kind(n: Int)=if(n==1)"boundary" else if(n==2)"manifold" else "nonmanifold"
private fun edges(a: Analysis,out: MutableList<String>) {
    val counts=mutableMapOf<String,Int>();
    var maxFaces=0;
    var shortest: Topology.Edge?=null;
    var longest: Topology.Edge?=null;
    var min=Long.MAX_VALUE;
    var max=-1L;
    for((e,ids) in a.mesh.edges) {
        increment(counts,kind(ids.size));
        increment(counts,shape(e,a));
        maxFaces=maxOf(maxFaces,ids.size);
        val length=Measure.length(e,a.points);
        if(length<min) {
            min=length;
            shortest=e
        };
        if(length>max) {
            max=length;
            longest=e
        }
    };
    out+=listOf("[edges]","edges ${a.mesh.edges.size}","boundary ${counts.getOrDefault("boundary",0)}","manifold ${counts.getOrDefault("manifold",0)}","nonmanifold ${counts.getOrDefault("nonmanifold",0)}","max_faces $maxFaces");
    for(key in listOf("convex","concave","flat","inconsistent"))out+="$key ${counts.getOrDefault(key,0)}";
    out+="shortest $shortest len2 $min";
    out+="longest $longest len2 $max"
}
private fun valence(a: Analysis,out: MutableList<String>) {
    val degrees=a.mesh.neighbors.values.map {
        it.size
    };
    val histogram=degrees.groupingBy {
        it
    }.eachCount().toSortedMap();
    out+=listOf("[valence]","used ${degrees.size}","isolated ${a.points.size-1-degrees.size}","min ${degrees.min()}","max ${degrees.max()}","mean ${Measure.fraction(degrees.sumOf{it.toLong()},degrees.size.toLong())}");
    for((d,n) in histogram)out+="degree $d $n"
}
private fun query(w: List<String>,a: Analysis): String {
    val queryKind=w[0];
    val x=w[1].toInt();
    var prefix="$queryKind $x";
    val nv=a.points.lastIndex
    if(queryKind=="vertex") {
        if(x !in 1..nv)return "$prefix invalid";
        val ids=a.faces.indices.filter {
            x in a.faces[it].v
        };
        val boundary=a.mesh.edges.any {
            (e,f)->(e.a==x||e.b==x)&&f.size==1
        };
        return "$prefix at ${a.points[x]} faces ${ids.size} valence ${a.mesh.neighbors[x]?.size?:0} fans ${a.mesh.fans[x]?.size?:0} boundary ${yes(boundary)} components ${listing(ids.map{a.mesh.faceComponent[it+1]}.toSortedSet())}"
    }
    if(queryKind=="face") {
        if(x !in 1..a.faces.size)return "$prefix invalid";
        val f=a.faces[x-1];
        val neighbors=(0..2).map {
            k->val ids=a.mesh.edges.getValue(Topology.edge(f.v[k],f.v[(k+1)%3]));
            if(ids.size==1)"-" else if(ids.size>=3)"*" else ids.first {
                it!=x
            }.toString()
        };
        return "$prefix vertices ${f.v.joinToString(" ")} group ${f.group} polygon ${if(f.polygon==0)"-" else f.polygon.toString()} line ${if(f.line==0)"-" else f.line.toString()} component ${a.mesh.faceComponent[x]} normal ${Measure.normal(f,a.points)} area ${Measure.real(Measure.area(listOf(f),a.points))} neighbors ${listing(neighbors)}"
    }
    val y=w[2].toInt();
    if(queryKind=="edge") {
        val e=Topology.edge(x,y);
        prefix="edge $e";
        val ids=a.mesh.edges[e]?:return "$prefix none";
        return "$prefix faces ${listing(ids)} kind ${kind(ids.size)} shape ${shape(e,a)} len2 ${Measure.length(e,a.points)}"
    }
    if(queryKind=="path") {
        prefix+=" $y";
        if(x !in 1..nv||y !in 1..nv)return "$prefix invalid";
        val parent=IntArray(nv+1) {
            -1
        };
        parent[x]=0;
        val queue=ArrayDeque<Int>();
        queue.addLast(x);
        while(queue.isNotEmpty()) {
            val v=queue.removeFirst();
            for(n in a.mesh.neighbors[v].orEmpty())if(parent[n]==-1) {
                parent[n]=v;
                queue.addLast(n)
            }
        };
        if(parent[y]==-1)return "$prefix none";
        val path=mutableListOf<Int>();
        var n=y;
        while(n!=0) {
            path+=n;
            n=parent[n]
        };
        path.reverse();
        return "$prefix hops ${path.size-1} vertices ${listing(path)}"
    }
    val z=w[3].toLong();
    val point=Measure.Vec(x.toLong(),y.toLong(),z);
    prefix="$queryKind $point";
    if(queryKind=="point") {
        val inside=mutableListOf<Int>();
        var sum=0;
        for(d in a.components)if(d.solid) {
            val winding=Measure.winding(d.c.faces,a.faces,a.points,point);
            if(winding!=0) {
                inside+=d.c.number;
                sum+=winding
            }
        };
        return "$prefix inside ${listing(inside)} winding $sum"
    }
    val scores=a.faces.map {
        Measure.dot(Measure.normal(it,a.points),point)
    };
    val silhouette=a.mesh.edges.values.count {
        it.size==2&&((scores[it[0]-1]>0&&scores[it[1]-1]<0)||(scores[it[0]-1]<0&&scores[it[1]-1]>0))
    };
    return "$prefix front ${scores.count{it>0}} back ${scores.count{it<0}} side ${scores.count{it==0L}} silhouette $silhouette"
}
private fun boundaries(a: Analysis): List<String> {
    val out=mutableListOf("loops ${a.loops.size}");
    for(l in a.loops)out+="loop ${l.number} component ${l.component} length ${l.length} ${l.kind} ${if(l.filled)"filled" else "kept"} vertices ${listing(l.vertices)}";
    val nonmanifold=a.before.edges.filterValues {
        it.size>=3
    };
    out+="nonmanifold_edges ${nonmanifold.size}";
    for((e,ids) in nonmanifold)out+="edge $e faces ${listing(ids)}";
    out+="nonmanifold_vertices ${a.before.nonmanifoldVertices.size}";
    for(v in a.before.nonmanifoldVertices) {
        val fans=a.before.fans.getValue(v);
        out+="vertex $v fans ${fans.size} components ${listing(fans.flatten().map{a.before.faceComponent[it]}.toSortedSet())}"
    };
    out+="inconsistent_edges ${a.inconsistentAfter.size}";
    for(e in a.inconsistentAfter)out+="edge $e faces ${listing(a.before.edges.getValue(e))}";
    return out
}
private fun write(name: String,lines: List<String>) {
    File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
}
fun main() {
    val a=analyze(ObjIo.read(),settings());
    File("output").mkdirs();
    val out=mutableListOf<String>();
    for(section in a.settings.sections)when(section) {
        "summary"->summary(a,out);
        "warnings"-> {
            out+="[warnings]";
            for(e in a.source.errors)out+="line ${e.line} ${e.kind}"
        };
        "cleanup"->cleanup(a,out);
        "components"->components(a,out);
        "groups"->groups(a,out);
        "contacts"->contacts(a,out);
        "edges"->edges(a,out);
        "valence"->valence(a,out);
        "queries"-> {
            out+="[queries]";
            for(w in a.settings.queries)out+=query(w,a)
        }
    };
    write("report.txt",out);
    val csv=mutableListOf("component,faces,vertices,closed,euler,genus,volume6,area");
    for(d in a.components)csv+="${d.c.number},${d.c.faces.size},${d.c.vertices.size},${yes(d.closed)},${d.euler},${d.genus?.toString()?:"-"},${if(d.solid)d.volume.toString() else "-"},${Measure.real(d.area)}";
    write("components.csv",csv);
    write("boundaries.txt",boundaries(a));
    write("repaired.obj",ObjIo.repaired(a.points,a.faces))
}
