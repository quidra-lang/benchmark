import java.io.File
import java.util.Locale
object SamWriter {
    fun ratio(numerator: Int,denominator: Int)=if(denominator==0)"-" else String.format(Locale.ROOT,
        "%.4f",numerator.toDouble()/denominator)
    fun header(references: List<SequenceIo.Reference>): MutableList<String> {
        val lines=mutableListOf("@HD\tVN:1.6\tSO:unsorted");
        for(reference in references)lines.add("@SQ\tSN:${reference.name}\tLN:${reference.bases.length}");
        lines.add("@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0");
        return lines
    }
    fun record(result: FmAligner.Result,references: List<SequenceIo.Reference>,maximum: Int): String {
        val read=result.read;
        if(!result.mapped)return listOf(read.name,"4","*","0","0","*","*","0","0",read.bases,
            read.quality,"YM:Z:"+result.reason).joinToString("\t");
        val a=result.primary!!;
        val reverse=a.strand==1;
        val fields=mutableListOf(read.name,if(reverse)"16" else "0",references[a.reference].name,
            (a.position+1).toString(),result.mapq.toString(),a.cigar,"*","0","0",if(reverse)SequenceIo.reverseComplement(read.bases) else read.bases,
            if(reverse)read.quality.reversed() else read.quality,"NM:i:${a.nm}","MD:Z:${a.md}",
            "AS:i:${result.score}","X0:i:${result.x0}","X1:i:${result.x1}","YM:Z:${result.method}");
        if(result.others.size in 1..maximum)fields.add("XA:Z:"+result.others.joinToString("") {
            "${references[it.reference].name},${if(it.strand==0)"+" else "-"}${it.position+1},${it.cigar},${it.nm};"
        });
        return fields.joinToString("\t")
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+if(lines.isEmpty())"" else "\n")
    }
}
