import java.io.File
class Policy {
    data class Community(val first:Int,val second:Int):Comparable<Community> {
        override fun compareTo(other:Community):Int {
            val c=first.compareTo(other.first);
            return if(c!=0)c else second.compareTo(other.second)
        }
        override fun toString()=if(this==NO_EXPORT)"NO_EXPORT" else "$first:$second"
    }
    data class Entry(val permit:Boolean,val base:Topology.Prefix,val low:Int,val high:Int)
    data class Condition(val kind:String,val text:String,val low:Int=0,val high:Int=0,val community:Community?=null)
    data class Action(val kind:String,val value:Int=0,val community:Community?=null)
    class Rule(f:List<String>,val conditions:List<Condition>,val actions:List<Action>) {
        val name=f[1];
        var active=f[2]=="ON";
        val owner=f[3].toInt();
        val direction=f[4];
        val target=f[5];
        var hits=0
        fun has(kind:String)=actions.any {
            it.kind==kind
        }
        fun value(kind:String,fallback:Int)=actions.firstOrNull {
            it.kind==kind
        }?.value?:fallback
    }
    val lists=mutableMapOf<String,MutableList<Entry>>();
    val rules=mutableListOf<Rule>();
    val byName=mutableMapOf<String,Rule>()
    init {
        for(line in File("input/policies.txt").readLines(Charsets.US_ASCII)) {
            val f=line.split(' ');
            if(f[0]=="PLIST") {
                val p=Topology.prefix(f[3]);
                var low=p.length;
                var high=p.length;
                for(i in 4 until f.size step 2)if(f[i]=="GE") {
                    low=f[i+1].toInt();
                    high=32
                };
                for(i in 4 until f.size step 2)if(f[i]=="LE")high=f[i+1].toInt();
                lists.getOrPut(f[1]) {
                    mutableListOf()
                }.add(Entry(f[2]=="PERMIT",p,low,high));
                continue
            }
            val separator=f.indexOf("THEN");
            val conditions=mutableListOf<Condition>();
            for(i in 6 until separator step 2) {
                val kind=f[i];
                val value=f[i+1];
                val condition=when(kind) {
                    "CONTAINS","ORIGINAS"->Condition(kind,value,value.toInt());
                    "LENGTH"-> {
                        val bounds=value.split('-');
                        Condition(kind,value,bounds[0].toInt(),bounds[1].toInt())
                    };
                    "COMMUNITY"->Condition(kind,value,community=community(value));
                    else->Condition(kind,value)
                };
                conditions.add(condition)
            }
            val actions=mutableListOf<Action>();
            var i=separator+1;
            while(i<f.size) {
                val kind=f[i++];
                actions.add(when(kind) {
                    "DENY","ALLOW"->Action(kind);
                    "ADD","REMOVE"->Action(kind,community=community(f[i++]));
                    else->Action(kind,f[i++].toInt())
                })
            }
            val rule=Rule(f,conditions,actions);
            rules.add(rule);
            byName[rule.name]=rule
        }
    }
    fun permitted(name:String,prefix:Topology.Prefix):Boolean {
        for(entry in lists.getValue(name))if(prefix.length in entry.low..entry.high&&entry.base.contains(prefix.address))return entry.permit;
        return false
    }
    fun matches(rule:Rule,owner:Int,link:Topology.Link,prefix:Topology.Prefix,path:List<Int>,communities:List<Community>):Boolean {
        if(!rule.active||rule.owner!=owner)return false;
        if(rule.target!="*"&&rule.target!=link.other(owner).toString()&&rule.target!=link.name)return false;
        for(c in rule.conditions) {
            val match=when(c.kind) {
                "PREFIX"->permitted(c.text,prefix);
                "CONTAINS"->c.low in path;
                "ORIGINAS"->(path.lastOrNull()?:owner)==c.low;
                "LENGTH"->path.size in c.low..c.high;
                else->c.community in communities
            };
            if(!match)return false
        };
        return true
    }
    fun applied(direction:String,owner:Int,link:Topology.Link,prefix:Topology.Prefix,path:List<Int>,communities:List<Community>)=rules.firstOrNull {
        it.direction==direction&&matches(it,owner,link,prefix,path,communities)
    }
    companion object {
        val NO_EXPORT=Community(65535,65281)
        fun community(text:String):Community {
            if(text=="NO_EXPORT")return NO_EXPORT;
            val f=text.split(':');
            return Community(f[0].toInt(),f[1].toInt())
        }
        fun communities(values:List<String>)=values.map {
            community(it)
        }.distinct().sorted()
        fun communityText(values:List<Community>)=if(values.isEmpty())"-" else values.joinToString(",")
        fun edit(communities:List<Community>,rule:Rule):List<Community> {
            val result=communities.toSortedSet();
            for(action in rule.actions)when(action.kind) {
                "ADD"->result.add(action.community!!);
                "REMOVE"->result.remove(action.community!!)
            };
            return result.toList()
        }
    }
}
