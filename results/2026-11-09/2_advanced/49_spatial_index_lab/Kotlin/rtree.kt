import kotlin.math.abs

object Rtree {
    fun area(b: Dataset.Box)=(b.x2-b.x1)*(b.y2-b.y1)
    fun mbr(a: Dataset.Box,b: Dataset.Box)=Dataset.Box(minOf(a.x1,b.x1),minOf(a.y1,b.y1),maxOf(a.x2,b.x2),maxOf(a.y2,b.y2))
    fun enlargement(a: Dataset.Box,b: Dataset.Box)=area(mbr(a,b))-area(a)
    fun contains(a: Dataset.Box,b: Dataset.Box)=a.x1<=b.x1&&b.x2<=a.x2&&a.y1<=b.y1&&b.y2<=a.y2
    fun intersects(a: Dataset.Box,b: Dataset.Box)=a.x1<=b.x2&&b.x1<=a.x2&&a.y1<=b.y2&&b.y1<=a.y2
    fun overlap(a: Dataset.Box,b: Dataset.Box): Long {
        val w=minOf(a.x2,b.x2)-maxOf(a.x1,b.x1);
        val h=minOf(a.y2,b.y2)-maxOf(a.y1,b.y1);
        return if(w>0&&h>0)w*h else 0L
    }
    class Entry(var box: Dataset.Box,val id: Int,val child: Node?) {
        constructor(obj: Dataset.Obj):this(obj.box,obj.id,null);
        constructor(child: Node):this(child.box(),0,child)
    }
    class Node(val level: Int,entries: List<Entry>,var parent: Node?) {
        var entries=entries.toMutableList();
        init {
            adopt()
        };
        fun box(): Dataset.Box {
            var result=entries[0].box;
            for(i in 1 until entries.size)result=mbr(result,entries[i].box);
            return result
        };
        fun adopt() {
            if(level>0)for(entry in entries)entry.child!!.parent=this
        }
    }
    data class Location(val node: Node,val index: Int)
    class Tree(val maximum: Int,val minimum: Int) {
        var root=Node(0,emptyList(),null)
        fun choose(box: Dataset.Box,level: Int): Node {
            var node=root;
            while(node.level>level) {
                var best=node.entries[0];
                for(entry in node.entries) {
                    val a=enlargement(entry.box,box);
                    val b=enlargement(best.box,box);
                    if(a<b||a==b&&area(entry.box)<area(best.box))best=entry
                };
                node=best.child!!
            };
            return node
        }
        fun split(node: Node): Node {
            val entries=node.entries;
            var greatest=Long.MIN_VALUE;
            var first=0;
            var second=1;
            for(i in 0 until entries.size-1)for(j in i+1 until entries.size) {
                val waste=area(mbr(entries[i].box,entries[j].box))-area(entries[i].box)-area(entries[j].box);
                if(waste>greatest) {
                    greatest=waste;
                    first=i;
                    second=j
                }
            };
            val group1=mutableListOf(entries[first]);
            val group2=mutableListOf(entries[second]);
            val rest=entries.indices.filter {
                it!=first&&it!=second
            }.map {
                entries[it]
            }.toMutableList();
            var b1=entries[first].box;
            var b2=entries[second].box;
            while(rest.isNotEmpty()) {
                if(group1.size+rest.size==minimum) {
                    group1+=rest;
                    break
                };
                if(group2.size+rest.size==minimum) {
                    group2+=rest;
                    break
                };
                var selected=0;
                var difference=-1L;
                var d1=0L;
                var d2=0L;
                for(i in rest.indices) {
                    val a=enlargement(b1,rest[i].box);
                    val b=enlargement(b2,rest[i].box);
                    val candidate=abs(a-b);
                    if(candidate>difference) {
                        difference=candidate;
                        selected=i;
                        d1=a;
                        d2=b
                    }
                };
                val entry=rest.removeAt(selected);
                val one=d1<d2||d1==d2&&(area(b1)<area(b2)||area(b1)==area(b2)&&group1.size<=group2.size);
                if(one) {
                    group1+=entry;
                    b1=mbr(b1,entry.box)
                } else {
                    group2+=entry;
                    b2=mbr(b2,entry.box)
                }
            };
            node.entries=group1;
            node.adopt();
            return Node(node.level,group2,node.parent)
        }
        fun insert(entry: Entry,level: Int) {
            var node=choose(entry.box,level);
            node.entries+=entry;
            if(level>0)entry.child!!.parent=node;
            while(true) {
                val sibling=if(node.entries.size>maximum)split(node) else null;
                val parent=node.parent;
                if(parent==null) {
                    if(sibling!=null)root=Node(node.level+1,listOf(Entry(node),Entry(sibling)),null);
                    return
                };
                for(parentEntry in parent.entries)if(parentEntry.child===node) {
                    parentEntry.box=node.box();
                    break
                };
                if(sibling!=null) {
                    parent.entries+=Entry(sibling);
                    sibling.parent=parent
                };
                node=parent
            }
        }
        fun find(node: Node,id: Int,box: Dataset.Box): Location? {
            if(node.level==0) {
                for(i in node.entries.indices)if(node.entries[i].id==id)return Location(node,i)
            } else for(entry in node.entries)if(contains(entry.box,box)) {
                val found=find(entry.child!!,id,box);
                if(found!=null)return found
            };
            return null
        }
        fun delete(point: Dataset.Obj) {
            val found=find(root,point.id,point.box)!!;
            var node=found.node;
            node.entries.removeAt(found.index);
            val removed=mutableListOf<Node>();
            while(node!==root) {
                val parent=node.parent!!;
                for(i in parent.entries.indices)if(parent.entries[i].child===node) {
                    if(node.entries.size<minimum) {
                        parent.entries.removeAt(i);
                        removed+=node;
                        node.parent=null
                    } else parent.entries[i].box=node.box();
                    break
                };
                node=parent
            };
            for(old in removed)for(entry in old.entries)insert(entry,old.level);
            while(root.level>0&&root.entries.size==1) {
                root=root.entries[0].child!!;
                root.parent=null
            }
        }
    }
    data class Numbered(val number: Int,val entry: Entry)
    fun bulk(entries: List<Entry>,maximum: Int): Node {
        var numbered=entries.map {
            Numbered(it.id,it)
        };
        var level=0;
        while(true) {
            val pages=(numbered.size+maximum-1)/maximum;
            var slabs=1;
            while(slabs*slabs<pages)slabs++;
            numbered=numbered.sortedWith(Comparator {
                a,b->compare(a,b,false)
            });
            val nodes=mutableListOf<Node>();
            val slabSize=slabs*maximum;
            for(start in numbered.indices step slabSize) {
                val slab=numbered.subList(start,minOf(start+slabSize,numbered.size)).sortedWith(Comparator {
                    a,b->compare(a,b,true)
                });
                for(offset in slab.indices step maximum) {
                    val group=slab.subList(offset,minOf(offset+maximum,slab.size)).map {
                        it.entry
                    };
                    nodes+=Node(level,group,null)
                }
            };
            if(nodes.size==1)return nodes[0];
            numbered=nodes.mapIndexed {
                i,node->Numbered(i,Entry(node))
            };
            level++
        }
    }
    fun compare(a: Numbered,b: Numbered,swapped: Boolean): Int {
        val x=a.entry.box;
        val y=b.entry.box;
        val ax=if(swapped)x.y1+x.y2 else x.x1+x.x2;
        val bx=if(swapped)y.y1+y.y2 else y.x1+y.x2;
        val ay=if(swapped)x.x1+x.x2 else x.y1+x.y2;
        val by=if(swapped)y.x1+y.x2 else y.y1+y.y2;
        var c=ax.compareTo(bx);
        if(c==0)c=ay.compareTo(by);
        return if(c!=0)c else a.number.compareTo(b.number)
    }
    fun build(objects: List<Dataset.Obj>,maximum: Int,minimum: Int,bulkLoad: Boolean): Tree {
        val tree=Tree(maximum,minimum);
        val entries=objects.map {
            Entry(it)
        };
        if(bulkLoad)tree.root=bulk(entries,maximum) else for(entry in entries)tree.insert(entry,0);
        return tree
    }
}
