class Checker {
    companion object {
        val properties=listOf("ELECTION_SAFETY","LEADER_COMPLETENESS","LOG_MATCHING","STATE_MACHINE_SAFETY",
            "COMMITTED_KEPT")
    }
    data class Committed(val term: Int,val time: Int)
    data class Applied(val entry: RaftNode.Entry,val result: String?)
    val violations=IntArray(5);
    val leaders=mutableMapOf<Int,Int>();
    val committed=sortedMapOf<Int,Committed>();
    val applied=sortedMapOf<Int,Applied>();
    var elected=0;
    var logChecks=0;
    var pairChecks=0;
    var applies=0;
    var truncations=0;
    var removed=0
    fun leader(node: RaftNode) {
        elected++;
        val old=leaders[node.term];
        if(old==null)leaders[node.term]=node.number else if(old!=node.number)violations[0]++;
        if(committed.any {
            it.key>node.lastIndex||node.termAt(it.key)!=it.value.term
        })violations[1]++
    }
    fun commit(index: Int,term: Int,time: Int) {
        committed.putIfAbsent(index,Committed(term,time))
    }
    fun apply(index: Int,entry: RaftNode.Entry,result: String?) {
        applies++;
        val old=applied[index];
        if(old==null)applied[index]=Applied(entry,result) else if(old.entry!=entry)violations[3]++
    }
    fun truncate(first: Int,entries: List<RaftNode.Entry>) {
        truncations++;
        removed+=entries.size;
        for((i,entry) in entries.withIndex())if(committed[first+i]?.term==entry.term)violations[4]++
    }
    fun checkLogs(nodes: List<RaftNode>) {
        logChecks++;
        for(a in nodes.indices)for(b in a+1 until nodes.size) {
            pairChecks++;
            val first=nodes[a];
            val second=nodes[b];
            val limit=minOf(first.lastIndex,second.lastIndex);
            var greatest=0;
            for(k in limit downTo 1)if(first.termAt(k)==second.termAt(k)) {
                greatest=k;
                break
            };
            if((0 until greatest).any {
                first.log[it]!=second.log[it]
            })violations[2]++
        }
    }
    fun lines(maximumTerm: Int): List<String> {
        val details=listOf("terms $maximumTerm leaders ${leaders.size} elected $elected","checks $elected committed ${committed.size}",
            "checks $logChecks pairs $pairChecks","applies $applies indices ${applied.size}","truncations $truncations removed $removed");
        return properties.indices.map {
            "${properties[it]} ${if(violations[it]==0)"OK" else "FAIL"} violations ${violations[it]} ${details[it]}"
        }
    }
}
