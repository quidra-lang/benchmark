import java.io.File
class Layout {
    data class Key(val section: String,val end: String)
    data class Beyond(val kind: String,val name: String?)
    data class Buffer(val name: String,val section: String,val end: String,val row: Int,val column: Int)
    data class Boundary(val name: String,val section: String,val end: String)
    data class Label(val row: Int,val column: Int,val text: String)
    class Section(val name: String,val length: Int,val row: Int,val first: Int,val last: Int) {
        var routeLock: String?=null;
        var occupiedSeconds=0;
        var lockedSeconds=0;
        var failed=false;
        val occupants=mutableListOf<String>();
        val trains=mutableSetOf<String>();
        val overlapLocks=mutableSetOf<String>()
    }
    class Point(f: List<String>) {
        val name=f[1];
        val side=f[2];
        val common=f[3];
        val normal=f[4];
        val reverse=f[5];
        val row=f[6].toInt();
        val column=f[7].toInt();
        var position="N";
        var target="";
        var throwsCount=0;
        var lockedSeconds=0;
        var movingSeconds=0;
        var completion: Int?=null;
        var moving=false;
        var failed=false;
        val locks=mutableSetOf<Interlocking.PointLock>();
        fun detected()=!moving&&!failed
    }
    class Signal(f: List<String>) {
        val name=f[1];
        val section=f[2];
        val direction=f[3];
        val row=f[4].toInt();
        val column=f[5].toInt();
        var aspect="RED";
        var passes=0;
        val seconds=mutableMapOf<String,Int>()
    }
    val sections=linkedMapOf<String,Section>();
    val points=linkedMapOf<String,Point>();
    val signals=linkedMapOf<String,Signal>();
    val buffers=linkedMapOf<String,Buffer>();
    val boundaries=linkedMapOf<String,Boundary>();
    val labels=mutableListOf<Label>();
    val ends=mutableMapOf<Key,Beyond>();
    val signalsAt=mutableMapOf<Key,Signal>()
    init {
        for(line in File("input/layout.txt").readLines(Charsets.US_ASCII)) {
            val f=line.split(' ');
            when(f[0]) {
                "SECTION"->sections[f[1]]=Section(f[1],f[2].toInt(),f[3].toInt(),f[4].toInt(),f[5].toInt());
                "JOINT"-> {
                    ends[Key(f[1],"R")]=Beyond("section",f[2]);
                    ends[Key(f[2],"L")]=Beyond("section",f[1])
                };
                "POINT"-> {
                    val p=Point(f);
                    points[p.name]=p;
                    ends[Key(p.common,p.side)]=Beyond("point",p.name);
                    val other=if(p.side=="R")"L" else "R";
                    ends[Key(p.normal,other)]=Beyond("point",p.name);
                    ends[Key(p.reverse,other)]=Beyond("point",p.name)
                };
                "SIGNAL"-> {
                    val signal=Signal(f);
                    signals[signal.name]=signal;
                    signalsAt[Key(signal.section,signal.direction)]=signal
                };
                "BUFFER"-> {
                    buffers[f[1]]=Buffer(f[1],f[2],f[3],f[4].toInt(),f[5].toInt());
                    ends[Key(f[2],f[3])]=Beyond("buffer",f[1])
                };
                "BOUNDARY"-> {
                    boundaries[f[1]]=Boundary(f[1],f[2],f[3]);
                    ends[Key(f[2],f[3])]=Beyond("boundary",f[1])
                };
                "LABEL"->labels.add(Label(f[1].toInt(),f[2].toInt(),f[3]))
            }
        }
    }
    fun beyond(section: String,direction: String): Beyond {
        val beyond=ends.getValue(Key(section,if(direction=="UP")"R" else "L"));
        if(beyond.kind!="point")return beyond;
        val point=points.getValue(beyond.name!!);
        val branch=if(point.position=="N")point.normal else point.reverse;
        if(point.moving||section!=point.common&&section!=branch)return Beyond("impassable",null);
        return Beyond("section",if(section==point.common)branch else point.common)
    }
}
