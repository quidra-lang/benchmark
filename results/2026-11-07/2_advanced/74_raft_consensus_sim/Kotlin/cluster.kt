import java.io.File
object Cluster {
    data class Settings(val nodes: Int,val electionMin: Int,val electionMax: Int,val heartbeat: Int,val batch: Int,
        val quorum: Int,val seed: Int,val end: Int,val retry: Int,val attempts: Int,val sample: Int)
    data class Control(val time: Int,val kind: String,val arguments: List<Int>,val groups: List<List<Int>>)
    class Request(val number: Int,val time: Int,val initialDestination: Int,val command: String) {
        var scheduled=time;
        var destination=initialDestination;
        var attempts=0;
        var redirects=0;
        var index=0;
        var term=0;
        var latency=0;
        var status="";
        var result: String?=null;
        var accepted=false;
        var abandoned=false
    }
    data class Input(val settings: Settings,val controls: List<Control>,val requests: List<Request>)
    fun read(): Input {
        val values=File("input/cluster.txt").readLines().associate {
            val fields=it.split(' ');
            fields[0] to fields.drop(1).map(String::toInt)
        };
        val election=values.getValue("ELECTION");
        val settings=Settings(values.getValue("NODES")[0],election[0],election[1],values.getValue("HEARTBEAT")[0],
            values.getValue("BATCH")[0],values.getValue("QUORUM")[0],values.getValue("SEED")[0],values.getValue("END")[0],
            values.getValue("RETRY")[0],values.getValue("ATTEMPTS")[0],values.getValue("SAMPLE")[0]);
        val controls=mutableListOf<Control>();
        val requests=mutableListOf<Request>();
        for(line in File("input/script.txt").readLines()) {
            val w=line.split(' ');
            val time=w[0].toInt();
            val kind=w[1];
            if(kind=="REQUEST")requests.add(Request(requests.size+1,time,w[2].toInt(),w.drop(3).joinToString(" "))) else if(kind=="PARTITION")controls.add(Control(time,
                kind,emptyList(),w.drop(2).map {
                group->group.split(',').map(String::toInt)
            })) else controls.add(Control(time,kind,w.drop(2).map(String::toInt),emptyList()))
        };
        return Input(settings,controls,requests)
    }
}
