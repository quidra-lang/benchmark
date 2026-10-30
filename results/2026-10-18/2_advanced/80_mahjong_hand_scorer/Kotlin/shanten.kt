object Shanten {
    data class State(val sets: Int,val partial: Int,val pair: Int)
    data class Key(val sets: Int,val pair: Int)
    data class Choice(val removed: IntArray,val sets: Int,val partial: Int,val pair: Int)
    val patternCache=mutableMapOf<String,List<State>>();
    val numberCache=mutableMapOf<String,IntArray>()
    fun patterns(counts: IntArray,suited: Boolean): List<State> {
        val key=Tiles.key(counts)+if(suited)"s" else "h";
        patternCache[key]?.let {
            return it
        };
        val first=counts.indexOfFirst {
            it>0
        };
        if(first<0)return listOf(State(0,0,0));
        val choices=mutableListOf(Choice(intArrayOf(first),0,0,0));
        if(counts[first]>=3)choices.add(Choice(intArrayOf(first,first,first),1,0,0));
        if(counts[first]>=2) {
            choices.add(Choice(intArrayOf(first,first),0,1,0));
            choices.add(Choice(intArrayOf(first,first),0,0,1))
        };
        if(suited) {
            if(first<=6&&counts[first+1]>0&&counts[first+2]>0)choices.add(Choice(intArrayOf(first,first+1,first+2),1,0,0));
            for(difference in 1..2)if(first+difference<9&&counts[first+difference]>0)choices.add(Choice(intArrayOf(first,
                first+difference),0,1,0))
        };
        val best=mutableMapOf<Key,Int>();
        for(choice in choices) {
            val remaining=counts.copyOf();
            for(kind in choice.removed)remaining[kind]--;
            for(local in patterns(remaining,suited)) {
                val sets=local.sets+choice.sets;
                val pair=local.pair+choice.pair;
                if(sets>4||pair>1)continue;
                val partial=minOf(4,local.partial+choice.partial);
                val stateKey=Key(sets,pair);
                best[stateKey]=maxOf(best.getOrDefault(stateKey,-1),partial)
            }
        };
        val result=best.map {
            (k,v)->State(k.sets,v,k.pair)
        };
        if(patternCache.size>=65536)patternCache.clear();
        patternCache[key]=result;
        return result
    }
    fun standard(counts: IntArray): Int {
        var states=mapOf(Key(0,0) to 0);
        for(start in intArrayOf(0,9,18,27)) {
            val local=patterns(counts.copyOfRange(start,if(start==27)34 else start+9),start<27);
            val combined=mutableMapOf<Key,Int>();
            for((key,value) in states)for(part in local) {
                val sets=key.sets+part.sets;
                val pair=key.pair+part.pair;
                if(sets>4||pair>1)continue;
                val partial=minOf(4,value+part.partial);
                val combinedKey=Key(sets,pair);
                combined[combinedKey]=maxOf(combined.getOrDefault(combinedKey,-1),partial)
            };
            states=combined
        };
        return states.minOf {
            (key,value)->8-2*key.sets-minOf(value,4-key.sets)-key.pair
        }
    }
    fun numbers(counts: IntArray): IntArray {
        val key=Tiles.key(counts);
        numberCache[key]?.let {
            return it
        };
        val pairs=counts.count {
            it>=2
        };
        val kinds=counts.count {
            it>0
        };
        var orphans=13-Tiles.yaochuuKinds.count {
            counts[it]>0
        };
        if(Tiles.yaochuuKinds.any {
            counts[it]>=2
        })orphans--;
        val result=intArrayOf(standard(counts),6-pairs+maxOf(0,7-kinds),orphans);
        if(numberCache.size>=8192)numberCache.clear();
        numberCache[key]=result;
        return result
    }
}
