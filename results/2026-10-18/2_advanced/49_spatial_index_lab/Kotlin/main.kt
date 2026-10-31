private val STRUCTURES=listOf("kdtree","quadtree","rtree","str","grid","rtree_rect","str_rect")
private val SEARCHES=listOf("RANGE","RADIUS","KNN","WINDOWCOUNT","CONTAINS","NEAREST","JOIN")
private lateinit var data: Dataset.Data
private val points=sortedMapOf<Int,Dataset.Obj>()
private lateinit var rectangles: List<Dataset.Obj>
private var kd: Kdtree.Node?=null
private lateinit var quad: Quadtree.Node
private lateinit var rt: Rtree.Tree
private lateinit var str: Rtree.Tree
private lateinit var rectRt: Rtree.Tree
private lateinit var rectStr: Rtree.Tree
private lateinit var grid: Grid.Index
private var snapshot=0
private val answers=mutableListOf<String>()
private val visits=mutableListOf("query,command,structure,nodes,tests")
private val joins=mutableListOf("query,rect,point")
private val structures=mutableListOf<String>()
private val stats=mutableListOf<String>()
private val records=mutableListOf<Visit>()
private class View(val type: Int,val mark: String,val region: Dataset.Box,val held: List<Dataset.Obj>,val children: List<View>,val axis: Int,val level: Int) {
    val count: Int=held.size+children.sumOf {
        it.count
    }
}
private fun world()=Dataset.Box(0,0,(data.world-1).toLong(),(data.world-1).toLong())
private fun kdView(node: Kdtree.Node,box: Dataset.Box,mark: String): View {
    val children=mutableListOf<View>();
    val split=if(node.axis==0)node.point.box.x1 else node.point.box.y1;
    node.left?.let {
        val region=if(node.axis==0)Dataset.Box(box.x1,box.y1,split,box.y2) else Dataset.Box(box.x1,box.y1,box.x2,split);
        children+=kdView(it,region,"L")
    };
    node.right?.let {
        val region=if(node.axis==0)Dataset.Box(split,box.y1,box.x2,box.y2) else Dataset.Box(box.x1,split,box.x2,box.y2);
        children+=kdView(it,region,"R")
    };
    return View(0,mark,box,listOf(node.point),children,node.axis,0)
}
private fun quadView(node: Quadtree.Node,mark: String): View {
    val children=mutableListOf<View>();
    node.children?.forEachIndexed {
        i,child->children+=quadView(child,Quadtree.MARKS[i])
    };
    return View(1,mark,Dataset.Box(node.x.toLong(),node.y.toLong(),(node.x+node.size-1).toLong(),(node.y+node.size-1).toLong()),node.points,children,0,0)
}
private fun rView(node: Rtree.Node): View {
    val children=mutableListOf<View>();
    val held=mutableListOf<Dataset.Obj>();
    for(entry in node.entries)if(node.level==0)held+=Dataset.Obj(entry.id,entry.box) else children+=rView(entry.child!!);
    return View(2,"",node.box(),held,children,0,node.level)
}
private fun gridView(): View {
    val children=mutableListOf<View>();
    for(cell in grid.cells) {
        val x=cell.x.toLong()*grid.size;
        val y=cell.y.toLong()*grid.size;
        children+=View(3,"",Dataset.Box(x,y,x+grid.size-1,y+grid.size-1),cell.points,emptyList(),0,0)
    };
    return View(3,"",world(),emptyList(),children,0,0)
}
private fun roots()=listOf(kdView(kd!!,world(),"root"),quadView(quad,"root"),rView(rt.root),rView(str.root),gridView(),rView(rectRt.root),rView(rectStr.root))
private fun distance(x: Long,y: Long,box: Dataset.Box): Long {
    val dx=if(x<box.x1)box.x1-x else if(x>box.x2)x-box.x2 else 0L;
    val dy=if(y<box.y1)box.y1-y else if(y>box.y2)y-box.y2 else 0L;
    return dx*dx+dy*dy
}
private fun window(p: IntArray)=Dataset.Box(p[0].toLong(),p[1].toLong(),p[2].toLong(),p[3].toLong())
private fun condition(command: String,p: IntArray,box: Dataset.Box,region: Boolean): Boolean {
    if(command=="RADIUS")return distance(p[0].toLong(),p[1].toLong(),box)<=p[2].toLong()*p[2];
    if(command=="CONTAINS")return Rtree.contains(box,Dataset.Box(p[0].toLong(),p[1].toLong(),p[0].toLong(),p[1].toLong()));
    return if(region)Rtree.intersects(box,window(p)) else Rtree.contains(window(p),box)
}
private data class Result(val id: Int,val value: Long)
private class Answer {
    var items=mutableListOf<Result>();
    var nodes=0L;
    var tests=0L;
    var count=0
}
private fun conditional(view: View,command: String,p: IntArray,answer: Answer) {
    answer.nodes++;
    answer.tests+=view.held.size;
    for(obj in view.held)if(condition(command,p,obj.box,false))answer.items+=Result(obj.id,0);
    for(child in view.children)if(condition(command,p,child.region,true))conditional(child,command,p,answer)
}
private fun count(view: View,box: Dataset.Box,answer: Answer) {
    answer.nodes++;
    if(Rtree.contains(box,view.region)) {
        answer.count+=view.count;
        return
    };
    answer.tests+=view.held.size;
    for(obj in view.held)if(Rtree.contains(box,obj.box))answer.count++;
    for(child in view.children)if(Rtree.intersects(box,child.region))count(child,box,answer)
}
private data class Element(val distance: Long,val kind: Int,val tie: Long,val node: View?,val obj: Dataset.Obj?): Comparable<Element> {
    override fun compareTo(other: Element): Int {
        var c=distance.compareTo(other.distance);
        if(c==0)c=kind.compareTo(other.kind);
        return if(c!=0)c else tie.compareTo(other.tie)
    }
}
private fun nearest(root: View,p: IntArray): Answer {
    val answer=Answer();
    val queue=sortedSetOf<Element>();
    var serial=0L;
    queue+=Element(distance(p[0].toLong(),p[1].toLong(),root.region),0,serial++,root,null);
    while(answer.items.size<p[2]) {
        val entry=queue.first();
        queue.remove(entry);
        if(entry.kind==1) {
            answer.items+=Result(entry.obj!!.id,entry.distance);
            continue
        };
        val node=entry.node!!;
        answer.nodes++;
        answer.tests+=node.held.size;
        for(obj in node.held)queue+=Element(distance(p[0].toLong(),p[1].toLong(),obj.box),1,obj.id.toLong(),null,obj);
        for(child in node.children)queue+=Element(distance(p[0].toLong(),p[1].toLong(),child.region),0,serial++,child,null)
    };
    return answer
}
private fun join(a: View,b: View,answer: Answer) {
    answer.nodes++;
    if(a.children.isEmpty()&&b.children.isEmpty()) {
        answer.tests+=a.held.size.toLong()*b.held.size;
        for(point in a.held)for(rectangle in b.held)if(Rtree.contains(rectangle.box,point.box))answer.items+=Result(rectangle.id,point.id.toLong())
    } else if(a.children.isEmpty()) {
        for(child in b.children)if(Rtree.intersects(a.region,child.region))join(a,child,answer)
    } else if(b.children.isEmpty()) {
        for(child in a.children)if(Rtree.intersects(child.region,b.region))join(child,b,answer)
    } else for(first in a.children)for(second in b.children)if(Rtree.intersects(first.region,second.region))join(first,second,answer)
}
private fun sortIds(answer: Answer,pairs: Boolean) {
    answer.items.sortWith(Comparator {
        a,b->val c=a.id.compareTo(b.id);
        if(c!=0||!pairs)c else a.value.compareTo(b.value)
    })
}
private fun search(root: View,rectangle: View?,command: String,p: IntArray): Answer {
    val answer=Answer();
    if(command=="KNN"||command=="NEAREST")return nearest(root,p);
    if(command=="JOIN") {
        join(root,rectangle!!,answer);
        sortIds(answer,true)
    } else if(command=="WINDOWCOUNT")count(root,window(p),answer) else {
        conditional(root,command,p,answer);
        sortIds(answer,false)
    };
    return answer
}
private fun brute(command: String,p: IntArray): Answer {
    val answer=Answer();
    if(command=="JOIN") {
        for(rectangle in rectangles)for(point in points.values)if(Rtree.contains(rectangle.box,point.box))answer.items+=Result(rectangle.id,point.id.toLong());
        sortIds(answer,true);
        return answer
    };
    val objects=if(command=="CONTAINS"||command=="NEAREST")rectangles else points.values.toList();
    if(command=="KNN"||command=="NEAREST") {
        for(obj in objects)answer.items+=Result(obj.id,distance(p[0].toLong(),p[1].toLong(),obj.box));
        answer.items.sortWith(compareBy<Result> {
            it.value
        }.thenBy {
            it.id
        });
        answer.items=answer.items.take(p[2]).toMutableList();
        return answer
    };
    for(obj in objects)if(condition(command,p,obj.box,false)) {
        if(command=="WINDOWCOUNT")answer.count++ else answer.items+=Result(obj.id,0)
    };
    sortIds(answer,false);
    return answer
}
private data class Visit(val command: String,val structure: Int,val nodes: Long,val tests: Long)
private fun searches(query: Int,command: Dataset.Command) {
    val name=command.name;
    val p=command.values;
    val expected=brute(name,p);
    val roots=roots();
    val performed=if(name=="JOIN")listOf(2,3) else if(name=="CONTAINS"||name=="NEAREST")listOf(5,6) else listOf(0,1,2,3,4);
    val mismatch=mutableListOf<String>();
    for(index in performed) {
        val rect=if(name=="JOIN")roots[if(index==2)5 else 6] else null;
        val actual=search(roots[index],rect,name,p);
        if(if(name=="WINDOWCOUNT")actual.count!=expected.count else actual.items!=expected.items)mismatch+=STRUCTURES[index];
        visits+="$query,$name,${STRUCTURES[index]},${actual.nodes},${actual.tests}";
        records+=Visit(name,index,actual.nodes,actual.tests)
    };
    val check=if(mismatch.isEmpty())"ok" else "mismatch "+mismatch.joinToString(" ");
    if(name=="JOIN") {
        answers+="$query JOIN count ${expected.items.size} check $check";
        for(result in expected.items)joins+="$query,${result.id},${result.value}"
    } else if(name=="WINDOWCOUNT")answers+="$query WINDOWCOUNT count ${expected.count} check $check" else {
        val nearest=name=="KNN"||name=="NEAREST";
        val ids=expected.items.map {
            it.id.toString()+(if(nearest)":"+it.value else "")
        };
        answers+="$query $name count ${expected.items.size} ids ${if(ids.isEmpty())"-" else ids.joinToString(" ")} check $check"
    }
}
private fun box(b: Dataset.Box)="${b.x1} ${b.y1} ${b.x2} ${b.y2}"
private fun dump(view: View,depth: Int,output: MutableList<String>) {
    var line="  ".repeat(depth+1);
    if(view.type==0) {
        val point=view.held[0];
        line+="${view.mark} ${if(view.axis==0)"x" else "y"} ${point.id} ${point.box.x1} ${point.box.y1} box ${box(view.region)}"
    } else if(view.type==1) {
        line+="${view.mark} ${view.region.x1} ${view.region.y1} ${view.region.x2-view.region.x1+1}";
        line+=if(view.children.isEmpty())" leaf "+Report.ids(view.held) else " node count ${view.count}"
    } else line+=if(view.children.isEmpty())"leaf ${box(view.region)} ids ${Report.ids(view.held)}" else "node ${view.level} ${box(view.region)} entries ${view.children.size}";
    output+=line;
    for(child in view.children)dump(child,depth+1,output)
}
private data class AtDepth(val view: View,val depth: Int)
private fun flatten(view: View,depth: Int,result: MutableList<AtDepth>) {
    result+=AtDepth(view,depth);
    for(child in view.children)flatten(child,depth+1,result)
}
private fun flat(view: View): List<AtDepth> {
    val result=mutableListOf<AtDepth>();
    flatten(view,0,result);
    return result
}
private fun kdStats(root: View) {
    val nodes=flat(root);
    var height=0;
    var leaves=0;
    var one=0;
    var ideal=0;
    var capacity=0;
    var depthSum=0L;
    for(node in nodes) {
        height=maxOf(height,node.depth+1);
        depthSum+=node.depth;
        if(node.view.children.isEmpty())leaves++;
        if(node.view.children.size==1)one++
    };
    while(capacity<nodes.size) {
        capacity=2*capacity+1;
        ideal++
    };
    stats+="kdtree height $height ideal $ideal nodes ${nodes.size} leaves $leaves one_child $one depth_sum $depthSum avg_depth ${Report.fraction(depthSum,nodes.size.toLong())}";
    for(depth in 0 until height) {
        var count=0;
        var leaf=0;
        var single=0;
        for(node in nodes)if(node.depth==depth) {
            count++;
            if(node.view.children.isEmpty())leaf++;
            if(node.view.children.size==1)single++
        };
        stats+="  depth $depth nodes $count leaves $leaf one_child $single"
    }
}
private fun quadStats(root: View) {
    val nodes=flat(root);
    var height=0;
    var internal=0;
    var leaves=0;
    var empty=0;
    var max=0;
    for(node in nodes) {
        height=maxOf(height,node.depth+1);
        if(node.view.children.isEmpty()) {
            leaves++;
            if(node.view.held.isEmpty())empty++;
            max=maxOf(max,node.view.held.size)
        } else internal++
    };
    stats+="quadtree height $height internal $internal leaves $leaves empty $empty max_leaf $max fill ${Report.fraction(points.size.toLong(),leaves.toLong()*data.bucket)}";
    for(depth in 0 until height) {
        var inside=0;
        var leaf=0;
        var held=0;
        for(node in nodes)if(node.depth==depth) {
            if(node.view.children.isEmpty()) {
                leaf++;
                held+=node.view.held.size
            } else inside++
        };
        stats+="  depth $depth internal $inside leaves $leaf points $held"
    }
}
private fun rStats(name: String,root: View) {
    val nodes=flat(root);
    var leaves=0;
    var entries=0;
    for(node in nodes) {
        if(node.view.children.isEmpty())leaves++;
        entries+=if(node.view.children.isEmpty())node.view.held.size else node.view.children.size
    };
    stats+="$name height ${root.level+1} nodes ${nodes.size} leaves $leaves entries $entries fill ${Report.fraction(entries.toLong(),nodes.size.toLong()*data.maximum)}";
    for(level in root.level downTo 0) {
        val group=nodes.filter {
            it.view.level==level
        }.map {
            it.view
        };
        var total=0;
        var min=Int.MAX_VALUE;
        var max=0;
        var under=0;
        var area=0L;
        var overlap=0L;
        for(node in group) {
            val count=if(node.children.isEmpty())node.held.size else node.children.size;
            total+=count;
            min=minOf(min,count);
            max=maxOf(max,count);
            if(count<data.minimum)under++;
            area+=Rtree.area(node.region)
        };
        for(i in group.indices)for(j in i+1 until group.size)overlap+=Rtree.overlap(group[i].region,group[j].region);
        stats+="  level $level nodes ${group.size} entries $total min $min max $max under $under area $area overlap $overlap"
    }
}
private fun gridStats() {
    val occupancy=sortedMapOf<Int,Int>();
    var used=0;
    var max=0;
    for(cell in grid.cells) {
        val count=cell.points.size;
        if(count>0)used++;
        max=maxOf(max,count);
        occupancy[count]=occupancy.getOrDefault(count,0)+1
    };
    stats+="grid cells ${grid.cells.size} used $used max $max";
    var line="  occupancy";
    for(count in occupancy.keys)line+=" $count:${occupancy[count]}";
    stats+=line
}
private fun snapshot(query: Int) {
    if(structures.isNotEmpty()) {
        structures+="";
        stats+=""
    };
    val header="snapshot $snapshot query $query points ${points.size} rects ${rectangles.size}";
    structures+=header;
    stats+=header;
    val roots=roots();
    for(i in listOf(0,1,2,3,5,6)) {
        structures+=STRUCTURES[i];
        dump(roots[i],0,structures)
    };
    kdStats(roots[0]);
    quadStats(roots[1]);
    for(i in listOf(2,3,5,6))rStats(STRUCTURES[i],roots[i]);
    gridStats()
}
private fun rPosition(node: Rtree.Node,id: Int): MutableList<Int>? {
    if(node.level==0) {
        for(i in node.entries.indices)if(node.entries[i].id==id)return mutableListOf(i+1)
    } else for(i in node.entries.indices) {
        val found=rPosition(node.entries[i].child!!,id);
        if(found!=null) {
            found.add(0,i+1);
            return found
        }
    };
    return null
}
private fun positions(positions: List<Int>)=positions.joinToString("/")
private fun locate(point: Dataset.Obj): String {
    var path="";
    var node=kd!!;
    while(node.point.id!=point.id) {
        if(Kdtree.compare(point,node.point,node.axis)<0) {
            path+="L";
            node=node.left!!
        } else {
            path+="R";
            node=node.right!!
        }
    };
    val moves=mutableListOf<String>();
    var q=quad;
    while(q.children!=null) {
        val child=Quadtree.destination(q,point);
        moves+=Quadtree.MARKS[child];
        q=q.children!![child]
    };
    return "kdtree ${path.ifEmpty{"-"}} quadtree ${if(moves.isEmpty())"-" else moves.joinToString("/")} rtree ${positions(rPosition(rt.root,point.id)!!)} str ${positions(rPosition(str.root,point.id)!!)} grid ${point.box.x1/grid.size} ${point.box.y1/grid.size}"
}
private fun process(query: Int,command: Dataset.Command) {
    val name=command.name;
    val p=command.values;
    if(name in SEARCHES) {
        searches(query,command);
        return
    };
    if(name=="DUMP") {
        snapshot++;
        snapshot(query);
        answers+="$query DUMP snapshot $snapshot";
        return
    };
    val id=p[0];
    var point=points[id];
    if(name=="LOCATE") {
        answers+="$query LOCATE $id ${if(point==null)"missing" else locate(point)}";
        return
    };
    if(name=="INSERT") {
        point=Dataset.point(id,p[1],p[2]);
        points[id]=point;
        kd=Kdtree.insert(kd,point,0);
        Quadtree.insert(quad,point,data.bucket);
        rt.insert(Rtree.Entry(point),0);
        str.insert(Rtree.Entry(point),0);
        grid.insert(point);
        answers+="$query INSERT $id inserted points ${points.size}";
        return
    };
    if(point==null)answers+="$query DELETE $id missing points ${points.size}" else {
        kd=Kdtree.delete(kd!!,point);
        Quadtree.delete(quad,point,data.bucket);
        rt.delete(point);
        str.delete(point);
        grid.delete(point);
        points.remove(id);
        answers+="$query DELETE $id deleted points ${points.size}"
    }
}
private class Aggregate {
    var executions=0;
    var nodes=0L;
    var tests=0L;
    var maximum=0L
}
private fun visitSummary() {
    stats+="";
    stats+="visits";
    for(command in SEARCHES) {
        val totals=sortedMapOf<Int,Aggregate>();
        for(visit in records)if(visit.command==command) {
            val aggregate=totals.getOrPut(visit.structure) {
                Aggregate()
            };
            aggregate.executions++;
            aggregate.nodes+=visit.nodes;
            aggregate.tests+=visit.tests;
            aggregate.maximum=maxOf(aggregate.maximum,visit.nodes)
        };
        if(totals.isEmpty())continue;
        for(index in totals.keys) {
            val a=totals.getValue(index);
            stats+="$command ${STRUCTURES[index]} queries ${a.executions} nodes ${a.nodes} tests ${a.tests} max_nodes ${a.maximum} mean_nodes ${Report.fraction(a.nodes,a.executions.toLong())}"
        };
        val ranked=totals.keys.sortedWith(compareBy<Int> {
            totals.getValue(it).nodes
        }.thenBy {
            totals.getValue(it).tests
        }.thenBy {
            it
        });
        var line="rank $command";
        for(index in ranked)line+=" "+STRUCTURES[index];
        stats+=line
    }
}
fun main() {
    data=Dataset.read();
    for(point in data.points)points[point.id]=point;
    rectangles=data.rectangles.sortedBy {
        it.id
    };
    kd=Kdtree.build(data.points,0);
    quad=Quadtree.Node(0,0,data.world);
    grid=Grid.Index(data.world,data.grid);
    for(point in data.points) {
        Quadtree.insert(quad,point,data.bucket);
        grid.insert(point)
    };
    rt=Rtree.build(data.points,data.maximum,data.minimum,false);
    str=Rtree.build(data.points,data.maximum,data.minimum,true);
    rectRt=Rtree.build(data.rectangles,data.maximum,data.minimum,false);
    rectStr=Rtree.build(data.rectangles,data.maximum,data.minimum,true);
    snapshot(0);
    for(q in data.commands.indices)process(q+1,data.commands[q]);
    visitSummary();
    Report.write("answers.txt",answers);
    Report.write("visits.csv",visits);
    Report.write("join.csv",joins);
    Report.write("structures.txt",structures);
    Report.write("stats.txt",stats)
}
