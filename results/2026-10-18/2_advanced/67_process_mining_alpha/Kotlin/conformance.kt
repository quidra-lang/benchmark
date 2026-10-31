import java.io.File
import java.util.TreeSet
object Conformance {
    class Net(places: List<String>,transitions: List<String>,val initial: Int,val finish: Int) {
        val places=places.toList();
        val transitions=transitions.sorted();
        val placeIndex=this.places.withIndex().associate {
            it.value to it.index
        };
        val transitionIndex=this.transitions.withIndex().associate {
            it.value to it.index
        };
        val inputs=List(transitions.size) {
            TreeSet<Int>()
        };
        val outputs=List(transitions.size) {
            TreeSet<Int>()
        };
        fun arc(from: String,to: String) {
            val place=placeIndex[from];
            if(place!=null)inputs[transitionIndex.getValue(to)].add(place) else outputs[transitionIndex.getValue(from)].add(placeIndex.getValue(to))
        };
        fun arcs()=inputs.sumOf {
            it.size
        }+outputs.sumOf {
            it.size
        };
        fun initialMarking()=IntArray(places.size).also {
            it[initial]=1
        };
        fun finalMarking()=IntArray(places.size).also {
            it[finish]=1
        }
    }
    class Totals(places: Int,transitions: Int) {
        var missing=0L;
        var remaining=0L;
        var consumed=0L;
        var produced=0L;
        var skipped=0L;
        val placeMissing=LongArray(places);
        val placeRemaining=LongArray(places);
        val deviating=LongArray(places);
        val waitingCount=LongArray(places);
        val waitingSum=LongArray(places);
        val waitingMax=LongArray(places);
        val routes=Array(places) {
            LongArray(transitions)
        };
        fun fitness()=Report.Fraction((consumed-missing)*produced+(produced-remaining)*consumed,
            2*consumed*produced)
    }
    fun enabled(net: Net,marking: IntArray,transition: Int)=net.inputs[transition].all {
        marking[it]>=1
    }
    fun fire(net: Net,marking: IntArray,transition: Int): IntArray {
        val result=marking.copyOf();
        for(place in net.inputs[transition])result[place]--;
        for(place in net.outputs[transition])result[place]++;
        return result
    }
    fun read(): Net {
        val places=mutableListOf<String>();
        val transitions=mutableListOf<String>();
        val arcs=mutableListOf<Pair<String,String>>();
        var initial="";
        var finish="";
        for(line in File("input","model.txt").readLines()) {
            val w=line.split(' ');
            when(w[0]) {
                "PLACE"->places.add(w[1]);
                "TRANSITION"->transitions.add(w[1]);
                "ARC"->arcs.add(w[1] to w[2]);
                "INITIAL"->initial=w[1];
                "FINAL"->finish=w[1]
            }
        };
        val net=Net(places,transitions,places.indexOf(initial),places.indexOf(finish));
        for((from,to) in arcs)net.arc(from,to);
        return net
    }
}
