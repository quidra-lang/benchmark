class Cache(val numberSets: Int,val ways: Int,val replacement: String) {
    class Line(val block: Int,var state: String)
    data class Location(val row: Int,val way: Int)
    var clock=0;
    val entries=Array(numberSets) {
        arrayOfNulls<Line>(ways)
    };
    val touched=Array(numberSets) {
        IntArray(ways)
    };
    val bits=Array(numberSets) {
        IntArray(ways)
    };
    val fills=IntArray(numberSets);
    val evictions=IntArray(numberSets)
    fun locate(block: Int): Location? {
        val row=block%numberSets;
        for(way in 0 until ways)if(entries[row][way]?.block==block)return Location(row,way);
        return null
    }
    fun state(block: Int): String {
        val p=locate(block)?:return "I";
        return entries[p.row][p.way]!!.state
    }
    fun change(block: Int,state: String) {
        val p=locate(block)?:return;
        entries[p.row][p.way]!!.state=state
    }
    fun touchWay(row: Int,way: Int,fill: Boolean) {
        if(replacement=="LRU"||replacement=="FIFO"&&fill)touched[row][way]=++clock else if(replacement=="PLRU") {
            var low=0;
            var high=ways;
            var node=1;
            while(high-low>1) {
                val mid=(low+high)/2;
                if(way<mid) {
                    bits[row][node]=1;
                    high=mid;
                    node*=2
                }else {
                    bits[row][node]=0;
                    low=mid;
                    node=2*node+1
                }
            }
        }
    }
    fun touch(block: Int) {
        val p=locate(block)?:return;
        touchWay(p.row,p.way,false)
    }
    fun victim(row: Int): Int {
        if(replacement=="PLRU") {
            var low=0;
            var high=ways;
            var node=1;
            while(high-low>1) {
                val mid=(low+high)/2;
                if(bits[row][node]==0) {
                    high=mid;
                    node*=2
                }else {
                    low=mid;
                    node=2*node+1
                }
            };
            return low
        };
        return (0 until ways).minBy {
            touched[row][it]
        }
    }
    fun fill(block: Int,state: String): Line? {
        val row=block%numberSets;
        val way=(0 until ways).firstOrNull {
            entries[row][it]==null
        }?:victim(row);
        val old=entries[row][way];
        if(old!=null)evictions[row]++;
        entries[row][way]=Line(block,state);
        fills[row]++;
        touchWay(row,way,true);
        return old
    }
    fun remove(block: Int): Line? {
        val p=locate(block)?:return null;
        val old=entries[p.row][p.way];
        entries[p.row][p.way]=null;
        return old
    }
    fun order(row: Int): String {
        if(replacement=="PLRU")return if(ways==1)"-" else (1 until ways).joinToString("") {
            bits[row][it].toString()
        };
        return (0 until ways).filter {
            entries[row][it]!=null
        }.sortedWith(compareByDescending<Int> {
            touched[row][it]
        }.thenBy {
            it
        }).joinToString(" ").ifEmpty {
            "-"
        }
    }
    fun lines()=entries.flatMap {
        it.filterNotNull()
    }
}
