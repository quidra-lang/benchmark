import java.io.File
import java.util.Locale
object TreeIo {
    fun real(value: Double,places: Int): String {
        val text=String.format(Locale.ROOT,"%.${places}f",value);
        return if(text.startsWith('-')&&text.toDouble()==0.0)text.substring(1) else text
    }
    fun symbols(mask: Int,count: Int)=(0 until count).joinToString("") {
        if((mask and (1 shl it))!=0)"*" else "."
    }
    fun childOrder(rooted: TreeBuilding.Rooted,names: List<String>): List<List<Int>> {
        val minimum=Array(rooted.tree.nextNode) {
            ""
        };
        val children=List(rooted.tree.nextNode) {
            mutableListOf<Int>()
        };
        for(node in rooted.order.asReversed())if(node<rooted.tree.size)minimum[node]=names[node] else {
            children[node].addAll(rooted.children[node].sortedBy {
                minimum[it]
            });
            minimum[node]=minimum[children[node].first()]
        };
        return children
    }
    fun nodeText(node: Int,rooted: TreeBuilding.Rooted,children: List<List<Int>>,names: List<String>,
        lengths: Boolean,support: Map<Int,Int>?): String {
        var text=if(node<rooted.tree.size)names[node] else "("+children[node].joinToString(",") {
            nodeText(it,rooted,children,names,lengths,support)
        }+")";
        if(node>=rooted.tree.size&&support!=null&&node!=rooted.root)text+=support.getOrDefault(rooted.masks[node],
            0);
        if(lengths&&node!=rooted.root)text+=":"+real(rooted.tree.adjacent[node].getValue(rooted.parents[node]),
            5);
        return text
    }
    fun newick(tree: TreeBuilding.Tree,names: List<String>,outgroup: Int,lengths: Boolean=false,
        support: Map<Int,Int>?=null): String {
        val rooted=tree.rooted(outgroup);
        return nodeText(rooted.root,rooted,childOrder(rooted,names),names,lengths,support)+";"
    }
    fun descend(node: Int,prefix: String,rooted: TreeBuilding.Rooted,children: List<List<Int>>,
        names: List<String>,support: Map<Int,Int>,lines: MutableList<String>) {
        val list=children[node];
        for((i,child) in list.withIndex()) {
            val last=i==list.lastIndex;
            val label=if(child<rooted.tree.size)names[child] else "[${support.getOrDefault(rooted.masks[child],0)}]";
            lines.add(prefix+(if(last)"`-- " else "|-- ")+label);
            descend(child,prefix+(if(last)"    " else "|   "),rooted,children,names,support,
                lines)
        }
    }
    fun cladogram(tree: TreeBuilding.Tree,names: List<String>,outgroup: Int,support: Map<Int,
        Int>): List<String> {
        val rooted=tree.rooted(outgroup);
        val lines=mutableListOf("*");
        descend(rooted.root,"",rooted,childOrder(rooted,names),names,support,lines);
        return lines
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
}
