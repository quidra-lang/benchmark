class RaftNode(val number: Int) {
    enum class Role {
        FOLLOWER,CANDIDATE,LEADER
    }
    data class Entry(val term: Int,val command: String,val request: Int)
    class Statistics {
        var elections=0;
        var leaderTerms=0;
        var votesGranted=0;
        var leaderTicks=0;
        var aeOk=0;
        var aeFail=0;
        var appended=0;
        var truncated=0;
        var applies=0
    }
    var term=0;
    var votedFor=0;
    val log=mutableListOf<Entry>();
    var up=true;
    val stats=Statistics();
    var role=Role.FOLLOWER;
    var commit=0;
    var applied=0;
    var knownLeader=0;
    var electionDeadline=-1;
    var electionRecord=-1;
    var heartbeatDeadline=-1;
    var quorumDeadline=-1;
    var transferTarget=0;
    var transferDeadline=-1;
    var transferSent=false;
    var store=sortedMapOf<String,Int>();
    var votes=mutableSetOf<Int>();
    var heard=mutableSetOf<Int>();
    var next=IntArray(0);
    var match=IntArray(0)
    val lastIndex get()=log.size;
    val lastTerm get()=log.lastOrNull()?.term?:0
    fun reset() {
        role=Role.FOLLOWER;
        commit=0;
        applied=0;
        knownLeader=0;
        store=sortedMapOf();
        votes=mutableSetOf();
        heard=mutableSetOf();
        electionDeadline=-1;
        electionRecord=-1;
        heartbeatDeadline=-1;
        quorumDeadline=-1;
        next=IntArray(0);
        match=IntArray(0);
        cancelTransfer()
    }
    fun cancelTransfer() {
        transferTarget=0;
        transferSent=false;
        transferDeadline=-1
    }
    fun crash() {
        up=false;
        reset()
    }
    fun termAt(index: Int)=if(index==0)0 else log[index-1].term
    fun acceptsLog(index: Int,term: Int)=term>lastTerm||term==lastTerm&&index>=lastIndex
    companion object {
        fun applyCommand(store: MutableMap<String,Int>,command: String): String? {
            val fields=command.split(' ');
            if(fields[0]=="NOOP")return null;
            val key=fields[1];
            return when(fields[0]) {
                "SET"-> {
                    store[key]=fields[2].toInt();
                    "ok"
                };
                "ADD"-> {
                    val value=store.getOrDefault(key,0)+fields[2].toInt();
                    store[key]=value;
                    value.toString()
                };
                "DEL"->if(store.remove(key)!=null)"deleted" else "missing";
                else->store[key]?.toString()?:"missing"
            }
        }
    }
}
