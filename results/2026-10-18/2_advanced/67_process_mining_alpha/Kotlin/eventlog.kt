import java.io.File
object Eventlog {
    data class Row(val line: Int,val caseId: String,val activity: String,val timestamp: String,
        val resource: String)
    data class Event(val line: Int,val caseId: String,val activity: String,val timestamp: String,
        val resource: String,val time: Int)
    class Case(val id: String,source: List<Event>) {
        val events=source.sortedWith(compareBy<Event> {
            it.time
        }.thenBy {
            it.line
        });
        val trace=events.map {
            it.activity
        };
        val duration=events.last().time-events.first().time
    }
    data class Input(val rows: List<Row>,val parameters: Map<String,String>)
    fun read(): Input {
        val rows=File("input","eventlog.csv").readLines().drop(1).mapIndexed {
            i,line->val w=line.split(',');
            Row(i+2,w[0],w[1],w[2],w[3])
        };
        val parameters=File("input","params.txt").readLines().associate {
            val w=it.split(' ');
            w[0] to w[1]
        };
        return Input(rows,parameters)
    }
    fun timestamp(value: String): Int {
        val days=intArrayOf(31,28,31,30,31,30,31,31,30,31,30,31);
        val month=value.substring(5,7).toInt();
        val day=value.substring(8,10).toInt();
        val hour=value.substring(11,13).toInt();
        val minute=value.substring(14,16).toInt();
        if(month !in 1..12||day !in 1..days[month-1]||hour>23||minute>59)return -1;
        return ((days.take(month-1).sum()+day-1)*24+hour)*60+minute
    }
    fun group(events: List<Event>)=events.groupBy {
        it.caseId
    }.toSortedMap().map {
        (id,group)->Case(id,group)
    }
    fun median(input: List<Int>): Report.Fraction {
        val values=input.sorted();
        val n=values.size;
        return if(n%2==1)Report.Fraction(values[n/2],1) else Report.Fraction(values[n/2-1].toLong()+values[n/2],
            2)
    }
}
