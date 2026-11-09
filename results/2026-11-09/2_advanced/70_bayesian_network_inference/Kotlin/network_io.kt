import java.io.File
object NetworkIo {
    data class Network(val names: List<String>,val states: List<List<String>>,val parents: List<List<Int>>,
        val expert: Map<Int,Array<DoubleArray>>)
    data class Settings(val alpha: Double,val method: String,val order: List<Int>,val limit: Int,
        val seed: Long,val sources: List<String>)
    data class Input(val network: Network,val samples: List<IntArray>,val queries: List<String>,
        val settings: Settings)
    fun read(): Input {
        var lines=File("input","network.txt").readLines().filter {
            it.isNotEmpty()&&!it.startsWith('#')
        };
        val names=mutableListOf<String>();
        val states=mutableListOf<List<String>>();
        val parents=mutableListOf<MutableList<Int>>();
        val expert=mutableMapOf<Int,Array<DoubleArray>>();
        var position=0;
        while(position<lines.size) {
            val w=lines[position++].split(' ');
            when(w[0]) {
                "VARIABLE"-> {
                    names.add(w[1]);
                    states.add(w.drop(2));
                    parents.add(mutableListOf())
                };
                "PARENTS"->parents[names.indexOf(w[1])].addAll(w.drop(2).map {
                    names.indexOf(it)
                });
                else-> {
                    val variable=names.indexOf(w[1]);
                    var rows=1;
                    for(parent in parents[variable])rows*=states[parent].size;
                    expert[variable]=Array(rows) {
                        lines[position++].split(' ').map {
                            it.toDouble()
                        }.toDoubleArray()
                    }
                }
            }
        };
        val network=Network(names,states,parents,expert);
        lines=File("input","params.txt").readLines();
        val alpha=lines[0].split(' ')[1].toDouble();
        val method=lines[1].split(' ')[1];
        val order=lines[2].split(' ').drop(1).map {
            names.indexOf(it)
        };
        val limit=lines[3].split(' ')[1].toInt();
        val seed=lines[4].split(' ')[1].toLong();
        val sources=MutableList(names.size) {
            ""
        };
        for(line in lines.drop(5)) {
            val w=line.split(' ');
            sources[names.indexOf(w[1])]=w[2]
        };
        val settings=Settings(alpha,method,order,limit,seed,sources);
        lines=File("input","samples.csv").readLines();
        val columns=lines.first().split(',').map {
            names.indexOf(it)
        };
        val samples=lines.drop(1).map {
            line->val values=line.split(',');
            IntArray(names.size).also {
                sample->for((i,v) in columns.withIndex())sample[v]=states[v].indexOf(values[i])
            }
        };
        return Input(network,samples,File("input","queries.txt").readLines(),settings)
    }
}
