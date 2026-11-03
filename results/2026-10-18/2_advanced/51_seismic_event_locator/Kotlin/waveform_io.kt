import java.io.File

object WaveformIo {
    class Station(val code: String,val order: Int,val x: Int,val y: Int,val elevation: Int) {
        var start=0;
        var samples=LongArray(0);
        var mean=0L;
        var peak=0L;
        var noise=0.0;
        var clipped=0;
        var triggers=0;
        var shortTriggers=0;
        val picks=mutableListOf<Picker.Pick>();
        var correction=0.0;
        var magnitudeCorrection=0.0
    }
    class Params(val values: Map<String,DoubleArray>) {
        fun get(key: String)=values.getValue(key)[0];
        fun integer(key: String)=get(key).toInt();
        fun row(key: String)=values.getValue(key)
    }
    data class Data(val stations: List<Station>,val params: Params)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun read(): Data {
        val stations=lines("stations.csv").drop(1).mapIndexed {
            i,line->val w=line.split(',');
            Station(w[0],i,w[1].toInt(),w[2].toInt(),w[3].toInt())
        };
        val waveform=lines("waveforms.txt");
        var cursor=0;
        for(s in stations) {
            val header=waveform[cursor++].split(' ');
            s.start=header[2].toInt();
            s.samples=LongArray(header[3].toInt());
            var index=0;
            while(index<s.samples.size)for(word in waveform[cursor++].split(' '))s.samples[index++]=word.toLong()
        };
        val values=lines("params.txt").associate {
            val w=it.split(' ');
            w[0] to w.drop(1).map(String::toDouble).toDoubleArray()
        };
        return Data(stations,Params(values))
    }
}
