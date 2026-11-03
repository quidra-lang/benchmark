import java.io.File
import java.util.PriorityQueue
class Network(val count: Int) {
    companion object {
        val types=listOf("RV","RVR","AE","AER","TN");
        val fields=listOf("sent","delivered","inflight","partition","rule","loss","down")
    }
    sealed interface Payload
    data class VoteRequest(val lastIndex: Int,val lastTerm: Int): Payload
    data class VoteResponse(val granted: Boolean): Payload
    data class AppendRequest(val previous: Int,val previousTerm: Int,val entries: List<RaftNode.Entry>,
        val commit: Int): Payload
    data class AppendResponse(val success: Boolean,val match: Int): Payload
    class Immediate: Payload
    data class Message(val kind: String,val source: Int,val destination: Int,val term: Int,val data: Payload)
    data class Drop(val kind: String,val start: Int,val end: Int)
    data class Scheduled(val arrival: Int,val source: Int,val serial: Int,val message: Message)
    class Link(var delay: Int) {
        var loss=0;
        var passed=0;
        val drops=mutableListOf<Drop>();
        val stats=IntArray(7)
    }
    val links=Array(count+1) {
        arrayOfNulls<Link>(count+1)
    };
    val groups=IntArray(count+1);
    val total=IntArray(7);
    val byType=Array(5) {
        IntArray(7)
    };
    var serial=0;
    val queue=PriorityQueue(compareBy<Scheduled> {
        it.arrival
    }.thenBy {
        it.source
    }.thenBy {
        it.serial
    })
    init {
        val lines=File("input/network.txt").readLines();
        val defaultDelay=lines.first().split(' ')[1].toInt();
        for(a in 1..count)for(b in 1..count)if(a!=b)links[a][b]=Link(defaultDelay);
        for(line in lines.drop(1)) {
            val w=line.split(' ');
            for(a in 1..count)for(b in 1..count)if(a!=b&&(w[1]=="*"||w[1].toInt()==a)&&(w[2]=="*"||w[2].toInt()==b)) {
                val link=link(a,b);
                when(w[0]) {
                    "DELAY"->link.delay=w[3].toInt();
                    "LOSS"->link.loss=w[3].toInt();
                    else->link.drops.add(Drop(w[3],w[4].toInt(),w[5].toInt()))
                }
            }
        }
    }
    fun link(a: Int,b: Int)=links[a][b]!!
    fun partition(partitions: List<List<Int>>) {
        for((i,group) in partitions.withIndex())for(node in group)groups[node]=i
    }
    fun heal() {
        groups.fill(0)
    }
    fun separated(a: Int,b: Int)=groups[a]!=groups[b]
    fun count(message: Message,field: Int,amount: Int) {
        total[field]+=amount;
        byType[types.indexOf(message.kind)][field]+=amount;
        link(message.source,message.destination).stats[field]+=amount
    }
    fun send(time: Int,source: Int,destination: Int,term: Int,kind: String,data: Payload) {
        val message=Message(kind,source,destination,term,data);
        serial++;
        count(message,0,1);
        val link=link(source,destination);
        if(separated(source,destination)) {
            count(message,3,1);
            return
        };
        if(link.drops.any {
            (it.kind==kind||it.kind=="ALL")&&it.start<=time&&time<=it.end
        }) {
            count(message,4,1);
            return
        };
        link.passed++;
        if(link.loss>0&&link.passed%link.loss==0) {
            count(message,5,1);
            return
        };
        count(message,2,1);
        queue.add(Scheduled(time+link.delay,source,serial,message))
    }
    fun arrivals(time: Int): List<Message> {
        val result=mutableListOf<Message>();
        while(queue.isNotEmpty()&&queue.peek().arrival==time) {
            val message=queue.remove().message;
            count(message,2,-1);
            result.add(message)
        };
        return result
    }
    fun deliver(message: Message,up: Boolean): Boolean {
        if(!up) {
            count(message,6,1);
            return false
        };
        if(separated(message.source,message.destination)) {
            count(message,3,1);
            return false
        };
        count(message,1,1);
        return true
    }
}
