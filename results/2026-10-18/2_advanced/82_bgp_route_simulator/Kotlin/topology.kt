import java.io.File
class Topology {
    data class Prefix(val address:Long,val length:Int):Comparable<Prefix> {
        override fun compareTo(other:Prefix):Int {
            val c=address.compareTo(other.address);
            return if(c!=0)c else length.compareTo(other.length)
        }
        override fun toString()="${addressText(address)}/$length"
        fun contains(value:Long):Boolean {
            val shift=32-length;
            return address shr shift==value shr shift
        }
    }
    class Link(val number:Int,f:List<String>) {
        val name=f[1];
        val first=f[2].toInt();
        val second=f[3].toInt();
        val relationship=f[4];
        val delay=f[5].toInt();
        val mrai=f[6].toInt();
        var downCount=0;
        var up=true
        fun other(owner:Int)=if(owner==first)second else first
        fun role(owner:Int)=if(relationship=="P2P")"peer" else if(owner==first)"customer" else "provider"
        fun direction(owner:Int)=when(role(owner)) {
            "customer"->'D';
            "peer"->'P';
            else->'U'
        }
    }
    data class Initial(val owner:Int,val prefix:Prefix,val origin:String,val communities:List<Policy.Community>)
    val routerIds=sortedMapOf<Int,Long>();
    val links=mutableListOf<Link>();
    val byName=mutableMapOf<String,Link>();
    val atAs=sortedMapOf<Int,MutableList<Link>>();
    val initial=mutableListOf<Initial>()
    init {
        for(line in File("input/topology.txt").readLines(Charsets.US_ASCII)) {
            val f=line.split(' ');
            when(f[0]) {
                "AS"->routerIds[f[1].toInt()]=addressValue(f[2]);
                "LINK"-> {
                    val link=Link(links.size,f);
                    links.add(link);
                    byName[link.name]=link
                };
                else->initial.add(Initial(f[1].toInt(),prefix(f[2]),f[3],Policy.communities(f.drop(4))))
            }
        }
        for(owner in routerIds.keys)atAs[owner]=mutableListOf();
        for(link in links) {
            atAs.getValue(link.first).add(link);
            atAs.getValue(link.second).add(link)
        }
    }
    fun connecting(first:Int,second:Int)=atAs.getValue(first).first {
        it.other(first)==second
    }
    companion object {
        fun addressValue(text:String):Long {
            var value=0L;
            for(octet in text.split('.'))value=(value shl 8)+octet.toInt();
            return value
        }
        fun addressText(value:Long)="${(value shr 24) and 255}.${(value shr 16) and 255}.${(value shr 8) and 255}.${value and 255}"
        fun prefix(text:String):Prefix {
            val f=text.split('/');
            return Prefix(addressValue(f[0]),f[1].toInt())
        }
    }
}
