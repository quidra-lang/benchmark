import java.io.File
import java.util.Locale
object SequenceIo {
    data class Reference(val name: String,val bases: String,val masked: Int)
    data class Read(val name: String,val bases: String,val quality: String)
    data class Input(val references: List<Reference>,val reads: List<Read>,val parameters: Map<String,
        IntArray>)
    fun reverseComplement(sequence: String)=sequence.reversed().map {
        "TGCAN"["ACGTN".indexOf(it)]
    }.joinToString("")
    fun read(): Input {
        val references=mutableListOf<Reference>();
        var name: String?=null;
        val bases=StringBuilder();
        var masked=0;
        for(line in File("input","reference.fasta").readLines())if(line.startsWith('>')) {
            val previous=name;
            if(previous!=null)references.add(Reference(previous,bases.toString(),masked));
            name=line.substring(1).substringBefore(' ');
            bases.setLength(0);
            masked=0
        } else {
            masked+=line.count {
                it in 'a'..'z'
            };
            bases.append(line.uppercase(Locale.ROOT))
        };
        val previous=name;
        if(previous!=null)references.add(Reference(previous,bases.toString(),masked));
        val lines=File("input","reads.fastq").readLines();
        val reads=(lines.indices step 4).map {
            Read(lines[it].substring(1),lines[it+1],lines[it+3])
        };
        val parameters=File("input","params.txt").readLines().associate {
            val w=it.split(' ');
            w[0] to w.drop(1).map {
                v->v.toInt()
            }.toIntArray()
        };
        return Input(references,reads,parameters)
    }
}
