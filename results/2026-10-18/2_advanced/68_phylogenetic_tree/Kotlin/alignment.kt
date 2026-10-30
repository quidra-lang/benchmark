import java.io.File
import java.util.Locale
object Alignment {
    const val BASES="ACGT";
    const val AMBIGUOUS="RYSWKMBDHV"
    val sets=mapOf('A' to 1,'C' to 2,'G' to 4,'T' to 8,'R' to 5,'Y' to 10,'S' to 6,'W' to 9,
        'K' to 12,'M' to 3,'B' to 14,'D' to 13,'H' to 11,'V' to 7,'N' to 15,'-' to 15)
    data class Record(val line: Int,val name: String,val sequence: String)
    fun read(): List<Record> {
        val records=mutableListOf<Record>();
        var name: String?=null;
        val sequence=StringBuilder();
        var header=0;
        for((i,line) in File("input","alignment.fasta").readLines().withIndex())if(line.startsWith('>')) {
            val previous=name;
            if(previous!=null)records.add(Record(header,previous,sequence.toString().uppercase(Locale.ROOT)));
            name=line.substring(1).substringBefore(' ');
            header=i+1;
            sequence.setLength(0)
        } else sequence.append(line);
        records.add(Record(header,name!!,sequence.toString().uppercase(Locale.ROOT)));
        return records
    }
    class Patterns(sequences: List<String>) {
        val patterns=mutableListOf<String>();
        val encoded=mutableListOf<IntArray>();
        val columns=IntArray(sequences.first().length);
        val weights=mutableListOf<Int>();
        init {
            val numbers=mutableMapOf<String,Int>();
            for(c in columns.indices) {
                val pattern=sequences.map {
                    it[c]
                }.joinToString("");
                val index=numbers.getOrPut(pattern) {
                    val index=patterns.size;
                    patterns.add(pattern);
                    encoded.add(IntArray(pattern.length) {
                        sets.getValue(pattern[it])
                    });
                    weights.add(0);
                    index
                };
                columns[c]=index;
                weights[index]++
            }
        }
    }
    fun classify(sequences: List<String>): IntArray {
        val totals=IntArray(5);
        for(c in sequences.first().indices) {
            val counts=IntArray(4);
            var gap=false;
            for(sequence in sequences) {
                val value=sequence[c];
                val base=BASES.indexOf(value);
                if(base>=0)counts[base]++;
                if(value=='-')gap=true
            };
            val kinds=counts.count {
                it>0
            };
            totals[if(kinds==0)4 else if(kinds==1)0 else 1]++;
            if(counts.count {
                it>=2
            }
            >=2)totals[2]++;
            if(gap)totals[3]++
        };
        return totals
    }
}
