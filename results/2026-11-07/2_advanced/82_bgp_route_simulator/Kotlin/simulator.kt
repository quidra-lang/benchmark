import java.io.File
import java.util.PriorityQueue
object Simulator {
    data class Message(val serial:Int,val sender:Int,val receiver:Int,val link:Topology.Link,val prefix:Topology.Prefix,
        val content:Decision.Attribute?,val arrival:Int)
    val order=compareBy<Message> {
        it.arrival
    }.thenBy {
        it.receiver
    }.thenBy {
        it.sender
    }.thenBy {
        it.serial
    }
    class MessageQueue {
        val queue=PriorityQueue(order);
        var serial=0
        fun send(time:Int,sender:Int,receiver:Int,link:Topology.Link,prefix:Topology.Prefix,content:Decision.Attribute?):Message {
            val message=Message(++serial,sender,receiver,link,prefix,content,time+link.delay);
            queue.add(message);
            return message
        }
        fun nextTime()=queue.peek()?.arrival
        fun take():Message=queue.remove()
        fun ordered()=queue.toList().sortedWith(order)
        fun removeLink(link:Topology.Link):List<Message> {
            val removed=ordered().filter {
                it.link===link
            };
            queue.removeIf {
                it.link===link
            };
            return removed
        }
    }
    class Event(val time:Int,val text:String) {
        val fields=text.split(' ');
        val kind=if(fields[0] in listOf("LINK","POLICY"))fields[0]+"_"+fields[1] else fields[0]
    }
    data class Trace(val source:Int,val address:String,val value:Long)
    data class Params(val defaults:Map<String,Int>,val stepcap:Int,val traces:List<Trace>)
    fun events():List<Event> {
        val events=mutableListOf(Event(0,"INITIAL"));
        for(line in File("input/events.txt").readLines(Charsets.US_ASCII)) {
            val separator=line.indexOf(' ');
            events.add(Event(line.substring(0,separator).toInt(),line.substring(separator+1)))
        }
        return events
    }
    fun params():Params {
        val lines=File("input/params.txt").readLines(Charsets.US_ASCII);
        val f=lines[0].split(' ');
        val defaults=mapOf("customer" to f[1].toInt(),"peer" to f[2].toInt(),"provider" to f[3].toInt());
        val stepcap=lines[1].split(' ')[1].toInt();
        val traces=lines.drop(2).map {
            val t=it.split(' ');
            Trace(t[1].toInt(),t[2],Topology.addressValue(t[2]))
        };
        return Params(defaults,stepcap,traces)
    }
}
