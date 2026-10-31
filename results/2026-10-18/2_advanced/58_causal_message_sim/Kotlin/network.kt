import java.io.File

class Network {
    class Generator(seed: Int) {
        var state=seed.toLong();
        var draws=0
        fun draw(): Int {
            state=48271*state%2147483647;
            draws++;
            return state.toInt()
        }
    }
    class Channel(val source: Int,val destination: Int,val fifo: Boolean,val a: Int,val b: Int,size: Int) {
        var sequence=0;
        var lastArrival=0;
        var messages=0;
        var markers=0;
        var buffered=0;
        var maxDelay=0;
        var entries=0;
        var previous=IntArray(size)
        fun delay()=if(a==b)a.toString() else "$a-$b"
        fun dispatch(packet: Causal.Packet,time: Int,generator: Generator) {
            packet.source=source;
            packet.destination=destination;
            packet.sequence=++sequence;
            packet.dispatch=time
            val delay=if(a==b)a else a+generator.draw()%(b-a+1);
            var arrival=time+delay
            if(fifo)arrival=maxOf(arrival,lastArrival);
            lastArrival=maxOf(lastArrival,arrival)
            packet.arrival=arrival;
            maxDelay=maxOf(maxDelay,arrival-time)
            val message=packet.message
            if(message==null)markers++
            else {
                messages++;
                val vector=message.send.vector;
                for(i in previous.indices)if(previous[i]!=vector[i])entries++;
                previous=vector.copyOf()
            }
        }
    }
    val names: List<String>;
    val channels: Array<Array<Channel?>>
    init {
        val lines=File("input/topology.txt").readLines();
        names=lines[0].split(' ').drop(1);
        val n=names.size
        channels=Array(n) {
            arrayOfNulls<Channel>(n)
        }
        for(line in lines.drop(1)) {
            val w=line.split(' ');
            val source=names.indexOf(w[1]);
            val destination=names.indexOf(w[2]);
            val a=w[4].toInt();
            val b=if(w.size==6)w[5].toInt() else a;
            channels[source][destination]=Channel(source,destination,w[3]=="FIFO",a,b,n)
        }
    }
}
