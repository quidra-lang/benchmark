import kotlin.math.*

typealias Point=PgmIo.Point

object Main {
    var width=0;
    var height=0;
    lateinit var image: Array<IntArray>;
    lateinit var trig: Array<IntArray>;
    lateinit var params: PgmIo.Params;
    lateinit var gradient: Filters.Gradient;
    lateinit var canny: Canny.Result;
    lateinit var circleVotes: Hough.CircleVotes;
    lateinit var lineVotes: Hough.LineVotes;
    lateinit var cornerResult: Corners.Result
    val edges=mutableListOf<Point>();
    val lineEdges=mutableListOf<Point>();
    val circles=mutableListOf<Shape>();
    val polygons=mutableListOf<Shape>();
    val shapes=mutableListOf<Shape>();
    val lines=mutableListOf<Line>();
    val segments=mutableListOf<Segment>();
    val junctions=mutableMapOf<Pair<Int,Int>,Junction>();
    val neighbors=mutableListOf<MutableList<Segment>>();
    lateinit var claimed: Array<BooleanArray>;
    val cornerMatches=mutableListOf<String>()
    class Shape {
        var circle=false;
        var number=0;
        var pixels=0;
        var mean=0;
        var contrast=0;
        var gap=0;
        var arcs=0;
        var sigma=0;
        lateinit var cell: Hough.CircleCell;
        var sides=emptyList<Segment>();
        var vertices=emptyList<Point>();
        var angles=IntArray(0);
        var lengths=IntArray(0);
        var support=IntArray(0);
        var corners=IntArray(0);
        var kind="";
        var enclosing: Shape?=null;
        lateinit var explained: Array<BooleanArray>
    }
    class Line(val cell: Hough.LineCell,val number: Int) {
        val segments=mutableListOf<Segment>()
    }
    class Segment(val number: Int,val t: Int,val start: Point,val end: Point,val length: Int,val pixels: List<Point>)
    data class Junction(val a: Int,val b: Int,val point: Point,val endA: Int,val endB: Int)
    fun distance(a: Point,b: Point)=maxOf(abs(a.x-b.x),abs(a.y-b.y))
    fun difference(a: Point,b: Point)=Point(a.x-b.x,a.y-b.y)
    fun cross(a: Point,b: Point)=a.x*b.y-a.y*b.x
    fun dot(a: Point,b: Point)=a.x*b.x+a.y*b.y
    fun angle(a: Int,b: Int): Int {
        val d=abs(a-b);
        return minOf(d,180-d)
    }
    fun round(numerator: Int,denominator: Int): Int {
        val n=if(denominator<0)-numerator else numerator;
        val d=abs(denominator);
        return Math.floorDiv(2*n+d,2*d)
    }
    fun bresenham(a: Point,b: Point): List<Point> {
        var x=a.x;
        var y=a.y;
        val dx=abs(b.x-x);
        val dy=-abs(b.y-y);
        val sx=if(x<b.x)1 else -1;
        val sy=if(y<b.y)1 else -1;
        var e=dx+dy;
        val result=mutableListOf<Point>();
        while(true) {
            result+=Point(x,y);
            if(x==b.x&&y==b.y)break;
            val e2=2*e;
            if(e2>=dy) {
                e+=dy;
                x+=sx
            };
            if(e2<=dx) {
                e+=dx;
                y+=sy
            }
        };
        return result
    }
    fun edge(point: Point)=Canny.inside(point.x,point.y,width,height)&&canny.edge[point.y][point.x]
    fun nearEdge(point: Point): Boolean {
        for(dy in -1..1)for(dx in -1..1)if(edge(Point(point.x+dx,point.y+dy)))return true;
        return false
    }
    fun half(point: Point)=if(point.y>0||point.y==0&&point.x>0)0 else 1
    fun translate(p: Point,x: Int,y: Int)=Point(p.x+x,p.y+y)
    fun circumference(circle: Shape,point: Point): Boolean {
        val dx=point.x-circle.cell.x;
        val dy=point.y-circle.cell.y;
        val r=circle.cell.r;
        val square=dx*dx+dy*dy;
        return (r-1)*(r-1)<=square&&square<=(r+1)*(r+1)
    }
    fun determineCircles() {
        for(i in 0 until minOf(params.get("circle_max_count"),circleVotes.peaks.size)) {
            val shape=Shape();
            shape.circle=true;
            shape.number=i+1;
            shape.cell=circleVotes.peaks[i];
            val outline=circleVotes.outlines.getValue(shape.cell.r).sortedWith(Comparator {
                a,b->val c=half(a).compareTo(half(b));
                if(c!=0)c else -cross(a,b).sign
            });
            val hit=BooleanArray(outline.size);
            var hits=0;
            for(j in hit.indices) {
                hit[j]=edge(translate(outline[j],shape.cell.x,shape.cell.y));
                if(hit[j])hits++
            };
            if(hits==0)shape.gap=hit.size else if(hits==hit.size)shape.arcs=1 else {
                var run=0;
                for(j in 0 until 2*hit.size)if(hit[j%hit.size])run=0 else {
                    run++;
                    shape.gap=maxOf(shape.gap,run)
                };
                for(j in hit.indices)if(hit[j]&&!hit[(j+hit.size-1)%hit.size])shape.arcs++
            };
            circles+=shape
        };
        for(point in edges)if(circles.none {
            circumference(it,point)
        })lineEdges+=point
    }
    fun projection(p: Point,t: Int)=p.y*trig[t][0]-p.x*trig[t][1]
    fun extract() {
        claimed=Array(height) {
            BooleanArray(width)
        };
        for(cell in lineVotes.peaks) {
            if(lines.size==params.get("hough_max_lines"))break;
            val t=cell.t;
            val selected=lineEdges.filter {
                !claimed[it.y][it.x]&&abs(Hough.rho(it,t,trig,params.get("hough_rho_step"))-cell.r)<=params.get("segment_tolerance")
            }.sortedWith(compareBy<Point> {
                projection(it,t)
            }.thenBy {
                it.x
            }.thenBy {
                it.y
            });
            val line=Line(cell,lines.size+1);
            var start=0;
            while(start<selected.size) {
                var end=start+1;
                while(end<selected.size&&projection(selected[end],t)-projection(selected[end-1],t)<=params.get("segment_max_gap")*16384)end++;
                val a=selected[start];
                val b=selected[end-1];
                val length=distance(a,b)+1;
                if(length>=params.get("segment_min_length")) {
                    val segment=Segment(segments.size+1,t,a,b,length,selected.subList(start,end).toList());
                    line.segments+=segment;
                    segments+=segment;
                    for(point in segment.pixels)claimed[point.y][point.x]=true
                };
                start=end
            };
            if(line.segments.isNotEmpty())lines+=line
        }
    }
    fun junction(a: Segment,b: Segment)=junctions[minOf(a.number,b.number) to maxOf(a.number,b.number)]
    fun end(j: Junction,s: Segment)=if(j.a==s.number)j.endA else j.endB
    fun join() {
        for(segment in segments)neighbors.add(mutableListOf());
        for(a in segments.indices)for(b in a+1 until segments.size) {
            val sa=segments[a];
            val sb=segments[b];
            if(angle(sa.t,sb.t)<params.get("junction_min_angle"))continue;
            val da=difference(sa.end,sa.start);
            val db=difference(sb.end,sb.start);
            val den=cross(da,db);
            if(den==0)continue;
            val lambda=cross(difference(sb.start,sa.start),db);
            val point=Point(round(sa.start.x*den+lambda*da.x,den),round(sa.start.y*den+lambda*da.y,den));
            val ea=if(distance(sa.start,point)<=distance(sa.end,point))0 else 1;
            val eb=if(distance(sb.start,point)<=distance(sb.end,point))0 else 1;
            if(distance(if(ea==0)sa.start else sa.end,point)>params.get("junction_distance")||distance(if(eb==0)sb.start else sb.end,
                point)>params.get("junction_distance"))continue;
            junctions[sa.number to sb.number]=Junction(sa.number,sb.number,point,ea,eb);
            neighbors[a]+=sb;
            neighbors[b]+=sa
        };
        for(adjacent in neighbors)adjacent.sortBy {
            it.number
        }
    }
    fun enumerate(path: MutableList<Segment>,count: Int) {
        val first=path.first();
        val last=path.last();
        if(path.size==count) {
            if(path[1].number>=last.number||junction(first,last)==null)return;
            val vertices=mutableListOf<Point>();
            for(i in 0 until count) {
                val current=path[i];
                val previous=path[(i+count-1)%count];
                val next=path[(i+1)%count];
                val incoming=junction(previous,current)!!;
                val outgoing=junction(current,next)!!;
                if(end(incoming,current)==end(outgoing,current))return;
                vertices+=incoming.point
            };
            var sign=0;
            for(i in 0 until count) {
                val z=cross(difference(vertices[(i+1)%count],vertices[i]),difference(vertices[(i+2)%count],vertices[(i+1)%count]));
                if(z==0||sign!=0&&z.sign!=sign)return;
                sign=z.sign
            };
            val polygon=Shape();
            polygon.number=polygons.size+1;
            polygon.sides=path.toList();
            polygon.vertices=vertices;
            polygons+=polygon;
            return
        };
        for(next in neighbors[last.number-1])if(next.number>first.number&&next !in path) {
            if(path.size>1&&end(junction(path[path.size-2],last)!!,last)==end(junction(last,next)!!,last))continue;
            path+=next;
            enumerate(path,count);
            path.removeLast()
        }
    }
    fun attributes(polygon: Shape) {
        val k=polygon.sides.size;
        val tolerance=params.get("angle_tolerance");
        polygon.angles=IntArray(k);
        polygon.lengths=IntArray(k);
        polygon.support=IntArray(k);
        polygon.corners=IntArray(k);
        var sixty=true;
        var right=false;
        var allRight=true;
        var minimum=Int.MAX_VALUE;
        var maximum=0;
        for(i in 0 until k) {
            val v=polygon.vertices[i];
            val previous=polygon.vertices[(i+k-1)%k];
            val next=polygon.vertices[(i+1)%k];
            val phi=angle(polygon.sides[(i+k-1)%k].t,polygon.sides[i].t);
            val alpha=if(dot(difference(previous,v),difference(next,v))<0)180-phi else phi;
            polygon.angles[i]=alpha;
            sixty=sixty&&abs(alpha-60)<=tolerance;
            right=right||abs(alpha-90)<=tolerance;
            allRight=allRight&&abs(alpha-90)<=tolerance;
            val side=difference(next,v);
            val length=dot(side,side);
            polygon.lengths[i]=length;
            minimum=minOf(minimum,length);
            maximum=maxOf(maximum,length);
            polygon.sigma+=cross(v,next);
            val points=bresenham(v,next);
            polygon.support[i]=100*points.count(::nearEdge)/points.size
        };
        if(k==3)polygon.kind=if(sixty)"equilateral_triangle" else if(right)"right_triangle" else "triangle" else {
            val a=angle(polygon.sides[0].t,polygon.sides[2].t)<=tolerance;
            val b=angle(polygon.sides[1].t,polygon.sides[3].t)<=tolerance;
            polygon.kind=if(!a&&!b)"quadrilateral" else if(a!=b)"trapezoid" else if(!allRight)"parallelogram" else if(100*(maximum-minimum)<=params.get("square_tolerance")*maximum)"square" else "rectangle"
        }
    }
    fun representatives(shape: Shape): List<Point> {
        if(!shape.circle)return shape.vertices;
        val x=shape.cell.x;
        val y=shape.cell.y;
        val r=shape.cell.r;
        return listOf(Point(x+r,y),Point(x,y+r),Point(x-r,y),Point(x,y-r))
    }
    fun contains(shape: Shape,point: Point): Boolean {
        if(shape.circle) {
            val dx=point.x-shape.cell.x;
            val dy=point.y-shape.cell.y;
            return dx*dx+dy*dy<=shape.cell.r*shape.cell.r
        };
        for(i in shape.vertices.indices) {
            val a=shape.vertices[i];
            val b=shape.vertices[(i+1)%shape.vertices.size];
            val z=cross(difference(b,a),difference(point,a));
            if(z!=0&&z.sign!=shape.sigma.sign)return false
        };
        return true
    }
    fun measure() {
        shapes.addAll(polygons);
        shapes.addAll(circles);
        for(shape in shapes) {
            var x0=Int.MAX_VALUE;
            var x1=Int.MIN_VALUE;
            var y0=Int.MAX_VALUE;
            var y1=Int.MIN_VALUE;
            for(point in representatives(shape)) {
                x0=minOf(x0,point.x);
                x1=maxOf(x1,point.x);
                y0=minOf(y0,point.y);
                y1=maxOf(y1,point.y)
            };
            val margin=params.get("contrast_margin");
            x0=maxOf(0,x0-margin);
            x1=minOf(width-1,x1+margin);
            y0=maxOf(0,y0-margin);
            y1=minOf(height-1,y1+margin);
            var inner=0;
            var outer=0;
            var outerCount=0;
            for(y in y0..y1)for(x in x0..x1)if(contains(shape,Point(x,y))) {
                shape.pixels++;
                inner+=image[y][x]
            } else {
                outerCount++;
                outer+=image[y][x]
            };
            shape.mean=if(shape.pixels==0)0 else inner/shape.pixels;
            shape.contrast=shape.mean-if(outerCount==0)0 else outer/outerCount;
            shape.explained=Array(height) {
                BooleanArray(width)
            };
            if(shape.circle) {
                for(point in edges)if(circumference(shape,point))shape.explained[point.y][point.x]=true
            } else for(i in shape.vertices.indices)for(point in bresenham(shape.vertices[i],
                shape.vertices[(i+1)%shape.vertices.size]))for(dy in -1..1)for(dx in -1..1) {
                val x=point.x+dx;
                val y=point.y+dy;
                if(Canny.inside(x,y,width,height))shape.explained[y][x]=true
            }
        };
        for(shape in shapes)for(enclosing in shapes) {
            val old=shape.enclosing;
            if(enclosing===shape||enclosing.pixels<=shape.pixels||old!=null&&enclosing.pixels>=old.pixels)continue;
            if(representatives(shape).all {
                contains(enclosing,it)
            })shape.enclosing=enclosing
        }
    }
    fun label(shape: Shape?)=if(shape==null)"none" else (if(shape.circle)"circle " else "polygon ")+shape.number
    fun matchCorners() {
        val limit=params.get("corner_match_distance");
        for(corner in cornerResult.corners) {
            val point=Point(corner.x,corner.y);
            var best=limit+1;
            var match="none";
            for(polygon in polygons)for(i in polygon.vertices.indices) {
                val distance=distance(point,polygon.vertices[i]);
                if(distance<best) {
                    best=distance;
                    match="polygon ${polygon.number} vertex ${i+1}"
                }
            };
            if(match=="none")for(segment in segments)for(i in 0..1) {
                val distance=distance(point,if(i==0)segment.start else segment.end);
                if(distance<best) {
                    best=distance;
                    match="segment ${segment.number}${if(i==0)" start" else " end"}"
                }
            };
            cornerMatches+=match
        };
        for(polygon in polygons)for(i in polygon.vertices.indices) {
            var best=limit+1;
            for(c in cornerResult.corners.indices) {
                val corner=cornerResult.corners[c];
                val distance=distance(polygon.vertices[i],Point(corner.x,corner.y));
                if(distance<best) {
                    best=distance;
                    polygon.corners[i]=c+1
                }
            }
        }
    }

    fun lineReport(): List<String> {
        val out=mutableListOf("lines ${lines.size}");
        for(line in lines) {
            out+="line ${line.number} theta ${line.cell.t} rho ${line.cell.r} votes ${line.cell.votes} segments ${line.segments.size}";
            for(segment in line.segments)out+="segment ${segment.number} start ${segment.start.x} ${segment.start.y} end ${segment.end.x} ${segment.end.y} length ${segment.length} pixels ${segment.pixels.size}"
        };
        return out
    }
    fun circleReport(): List<String> {
        val out=mutableListOf("circles ${circles.size}");
        for(c in circles)out+="circle ${c.number} center ${c.cell.x} ${c.cell.y} radius ${c.cell.r} votes ${c.cell.votes} points ${c.cell.total} gap ${c.gap} arcs ${c.arcs} pixels ${c.pixels} mean ${c.mean} contrast ${c.contrast} inside ${label(c.enclosing)}";
        return out
    }
    fun polygonReport(): List<String> {
        val out=mutableListOf("polygons ${polygons.size}");
        for(p in polygons) {
            val area=abs(p.sigma);
            out+="polygon ${p.number} ${p.kind} segments ${p.sides.joinToString(" "){it.number.toString()}} area ${area/2}.${if(area%2==0)0 else 5} pixels ${p.pixels} mean ${p.mean} contrast ${p.contrast} inside ${label(p.enclosing)}";
            for(i in p.vertices.indices) {
                val point=p.vertices[i];
                out+="vertex ${i+1} ${point.x} ${point.y} angle ${p.angles[i]} corner ${if(p.corners[i]==0)"none" else p.corners[i].toString()}"
            };
            for(i in p.sides.indices)out+="side ${i+1} segment ${p.sides[i].number} length2 ${p.lengths[i]} support ${p.support[i]}"
        };
        return out
    }
    fun cornerReport(): List<String> {
        val out=mutableListOf("corners ${cornerResult.corners.size}");
        for(i in cornerResult.corners.indices) {
            val c=cornerResult.corners[i];
            out+="corner ${i+1} ${c.x} ${c.y} response ${c.response} match ${cornerMatches[i]}"
        };
        return out
    }
    fun componentReport(): List<String> {
        val out=mutableListOf("components ${canny.components.size}");
        for(i in canny.components.indices) {
            val component=canny.components[i];
            var x0=width;
            var x1=0;
            var y0=height;
            var y1=0;
            var ends=0;
            var strength=0;
            val directions=IntArray(4);
            for(point in component) {
                x0=minOf(x0,point.x);
                x1=maxOf(x1,point.x);
                y0=minOf(y0,point.y);
                y1=maxOf(y1,point.y);
                val adjacent=Canny.neighbors(point,width,height).count(::edge);
                if(adjacent==1)ends++;
                strength+=gradient.magnitude[point.y][point.x];
                directions[canny.direction[point.y][point.x]/45]++
            };
            var main=0;
            for(d in 1..3)if(directions[d]>directions[main])main=d;
            var best: Shape?=null;
            var maximum=0;
            for(shape in shapes) {
                val count=component.count {
                    shape.explained[it.y][it.x]
                };
                if(count>maximum) {
                    best=shape;
                    maximum=count
                }
            };
            out+="component ${i+1} pixels ${component.size} box $x0 $y0 $x1 $y1 ends $ends strength ${strength/component.size} direction ${main*45} shape ${label(best)} explained $maximum"
        };
        return out
    }
    fun report(): List<String> {
        val out=mutableListOf("image $width $height");
        var nonzero=0;
        var maximum=0;
        var kept=0;
        var claimedCount=0;
        val directions=IntArray(4);
        for(y in 0 until height)for(x in 0 until width) {
            val m=gradient.magnitude[y][x];
            if(m>0)nonzero++;
            maximum=maxOf(maximum,m);
            if(canny.nms[y][x]>0)kept++;
            if(claimed[y][x])claimedCount++;
            if(canny.edge[y][x])directions[canny.direction[y][x]/45]++
        };
        out+="gradient_nonzero $nonzero";
        out+="gradient_max $maximum";
        out+="nms_kept $kept";
        out+="strong ${canny.strong}";
        out+="weak ${canny.weak}";
        out+="edges ${edges.size}";
        out+="weak_kept ${canny.weakKept}";
        out+="weak_dropped ${canny.weak-canny.weakKept}";
        out+="edge_components ${canny.components.size}";
        for(i in 0..3)out+="direction_${i*45} ${directions[i]}";
        out+="circle_candidates ${circleVotes.candidates}";
        out+="circle_peaks ${circleVotes.peaks.size}";
        out+="circles ${circles.size}";
        out+="circle_edge_pixels ${edges.size-lineEdges.size}";
        out+="line_edge_pixels ${lineEdges.size}";
        out+="hough_max_votes ${lineVotes.maximum}";
        out+="hough_peaks ${lineVotes.peaks.size}";
        out+="lines ${lines.size}";
        out+="segments ${segments.size}";
        out+="claimed_pixels $claimedCount";
        out+="junctions ${junctions.size}";
        out+="polygons ${polygons.size}";
        for(kind in listOf("equilateral_triangle","right_triangle","triangle","square","rectangle",
            "parallelogram","trapezoid","quadrilateral"))out+="$kind ${polygons.count{it.kind==kind}}";
        var vertices=0;
        for(polygon in polygons)for(corner in polygon.corners)if(corner!=0)vertices++;
        val onVertices=cornerMatches.count {
            it.startsWith("polygon")
        };
        val onSegments=cornerMatches.count {
            it.startsWith("segment")
        };
        out+="corner_candidates ${cornerResult.candidates}";
        out+="corners ${cornerResult.corners.size}";
        out+="corners_on_vertices $onVertices";
        out+="corners_on_segments $onSegments";
        out+="corners_unmatched ${cornerMatches.size-onVertices-onSegments}";
        out+="vertices_with_corner $vertices";
        return out
    }
    fun mark(overlay: Array<IntArray>,point: Point) {
        if(Canny.inside(point.x,point.y,width,height))overlay[point.y][point.x]=255
    }
    fun images() {
        val edgeImage=Array(height) {
            IntArray(width)
        };
        val overlay=Array(height) {
            IntArray(width)
        };
        for(y in 0 until height)for(x in 0 until width) {
            edgeImage[y][x]=if(canny.edge[y][x])255 else 0;
            overlay[y][x]=image[y][x]/params.get("overlay_divisor")
        };
        for(segment in segments)for(point in bresenham(segment.start,segment.end))mark(overlay,point);
        for(circle in circles)for(point in circleVotes.outlines.getValue(circle.cell.r))mark(overlay,translate(point,circle.cell.x,circle.cell.y));
        for(c in cornerResult.corners)for(e in -2..2) {
            mark(overlay,Point(c.x+e,c.y));
            mark(overlay,Point(c.x,c.y+e))
        };
        val votes=Array(lineVotes.high-lineVotes.low+1) {
            IntArray(180)
        };
        for(r in lineVotes.low..lineVotes.high)for(t in 0..179)votes[r-lineVotes.low][t]=if(lineVotes.maximum==0)0 else 255*lineVotes.count(t,
            r)/lineVotes.maximum;
        PgmIo.pgm("edges.pgm",edgeImage);
        PgmIo.pgm("hough.pgm",votes);
        PgmIo.pgm("overlay.pgm",overlay)
    }
    @JvmStatic fun main(args: Array<String>) {
        val data=PgmIo.read();
        image=data.image;
        trig=data.trig;
        params=data.params;
        height=image.size;
        width=image[0].size;
        gradient=Filters.gradient(Filters.smooth(image,params));
        canny=Canny.process(gradient,params.get("canny_low"),params.get("canny_high"));
        for(y in 0 until height)for(x in 0 until width)if(canny.edge[y][x])edges+=Point(x,y);
        circleVotes=Hough.circles(edges,width,height,params);
        determineCircles();
        lineVotes=Hough.lines(lineEdges,width,height,trig,params.get("hough_rho_step"),params.get("hough_threshold"));
        extract();
        join();
        for(k in 3..4)for(first in segments)enumerate(mutableListOf(first),k);
        for(polygon in polygons)attributes(polygon);
        measure();
        cornerResult=Corners.detect(gradient,params.get("harris_window"),params.value("harris_threshold"),params.get("harris_max_count"));
        matchCorners();
        images();
        PgmIo.write("lines.txt",lineReport());
        PgmIo.write("circles.txt",circleReport());
        PgmIo.write("polygons.txt",polygonReport());
        PgmIo.write("corners.txt",cornerReport());
        PgmIo.write("components.txt",componentReport());
        PgmIo.write("report.txt",report())
    }
}
