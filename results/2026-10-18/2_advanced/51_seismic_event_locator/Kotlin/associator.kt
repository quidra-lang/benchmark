object Associator {
    class Candidate(val number: Int,val first: Picker.Pick,var picks: List<Picker.Pick>) {
        val dropped=mutableListOf<Picker.Pick>();
        val passes=mutableListOf<Locator.Run>();
        var event: Main.Event?=null;
        var rejected=false
    }
    fun associate(picks: List<Picker.Pick>,window: Int,minimum: Int): List<Candidate> {
        val candidates=mutableListOf<Candidate>();
        for(i in picks.indices) {
            val first=picks[i];
            if(first.assigned)continue;
            val seen=mutableSetOf<Int>();
            val selected=mutableListOf<Picker.Pick>();
            for(j in i until picks.size) {
                val pick=picks[j];
                if(pick.sample>first.sample+window)break;
                if(!pick.assigned&&seen.add(pick.station.order))selected+=pick
            };
            if(selected.size<minimum)continue;
            for(pick in selected)pick.assigned=true;
            candidates+=Candidate(candidates.size+1,first,selected)
        };
        return candidates
    }
}
