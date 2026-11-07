object Decomposition {
    data class Form(val pair: Int,val sets: List<List<Int>>)
    val cache=mutableMapOf<String,List<Form>>()
    val setOrder=compareBy<List<Int>> {
        it.first()
    }.thenBy {
        if(it.first()==it.last())0 else 1
    }
    fun visit(remaining: IntArray,pair: Int,needed: Int,sets: MutableList<List<Int>>,found: MutableSet<Form>) {
        if(sets.size==needed) {
            if(remaining.any {
                it!=0
            })return;
            found.add(Form(pair,sets.sortedWith(setOrder)));
            return
        };
        val first=remaining.indexOfFirst {
            it>0
        };
        if(first<0)return;
        if(remaining[first]>=3) {
            remaining[first]-=3;
            sets.add(listOf(first,first,first));
            visit(remaining,pair,needed,sets,found);
            sets.removeLast();
            remaining[first]+=3
        };
        if(first<27&&first%9<=6&&remaining[first+1]>0&&remaining[first+2]>0) {
            for(i in first..first+2)remaining[i]--;
            sets.add(listOf(first,first+1,first+2));
            visit(remaining,pair,needed,sets,found);
            sets.removeLast();
            for(i in first..first+2)remaining[i]++
        }
    }
    fun standard(counts: IntArray,meldCount: Int): List<Form> {
        val key=Tiles.key(counts)+":$meldCount";
        cache[key]?.let {
            return it
        };
        val needed=4-meldCount;
        if(counts.sum()!=3*needed+2)return emptyList();
        val remaining=counts.copyOf();
        val found=linkedSetOf<Form>();
        for(pair in 0 until 34)if(remaining[pair]>=2) {
            remaining[pair]-=2;
            visit(remaining,pair,needed,mutableListOf(),found);
            remaining[pair]+=2
        };
        val result=found.toList();
        if(cache.size>=16384)cache.clear();
        cache[key]=result;
        return result
    }
    fun sevenPairs(counts: IntArray)=counts.count {
        it==2
    }
    ==7&&counts.all {
        it==0||it==2
    }
    fun thirteenOrphans(counts: IntArray)=counts.sum()==14&&Tiles.yaochuuKinds.all {
        counts[it]>0
    }
    &&counts.indices.all {
        it in Tiles.yaochuuKinds||counts[it]==0
    }
    fun winning(counts: IntArray,meldCount: Int)=standard(counts,meldCount).isNotEmpty()||meldCount==0&&(sevenPairs(counts)||thirteenOrphans(counts))
    fun waitingTiles(hand: IntArray,meld: IntArray,meldCount: Int): List<Int> {
        val waiting=mutableListOf<Int>();
        val concealed=hand.copyOf();
        for(kind in 0 until 34) {
            if(hand[kind]+meld[kind]>=4)continue;
            concealed[kind]++;
            if(winning(concealed,meldCount))waiting.add(kind);
            concealed[kind]--
        };
        return waiting
    }
    fun waitShape(form: String,block: List<Int>?,winning: Int,hand: IntArray): String {
        if(form=="chiitoitsu")return "tanki";
        if(form=="kokushi")return if(Tiles.yaochuuKinds.all {
            hand[it]==1
        })"thirteen" else "single";
        val chosen=block!!;
        if(chosen.size==2)return "tanki";
        if(chosen.first()==chosen.last())return "shanpon";
        val first=chosen.first();
        if(winning==first+1)return "kanchan";
        if(first%9==0&&winning==first+2||first%9==6&&winning==first)return "penchan";
        return "ryanmen"
    }
}
