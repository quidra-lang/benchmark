import java.io.File
object ModelIo {
    data class Node(val identifier: Int,val x: Int,val y: Int)
    data class Member(val identifier: Int,val start: Int,val end: Int,val section: Int,val material: Int,
        val group: String)
    data class Section(val name: String,val area: Double,val inertia: Double)
    data class Material(val name: String,val young: Double,val yieldStress: Double,val density: Double,
        val expansion: Double)
    data class Support(val node: Int,val fixed: IntArray,val prescribed: DoubleArray)
    data class Load(val kind: String,val index: Int=-1,val first: Double=0.0,val second: Double=0.0)
    data class LoadCase(val name: String,val lines: List<Load>)
    data class Term(val name: String,val factor: Double)
    data class Combination(val name: String,val terms: List<Term>)
    data class Axle(val offset: Int,val load: Double)
    data class Drawing(val name: String,val magnification: Int,val horizontal: Int,val vertical: Int)
    class Settings {
        val deck=mutableListOf<Int>();
        val influence=mutableListOf<Int>();
        val axles=mutableListOf<Axle>();
        val drawings=mutableListOf<Drawing>();
        var vehicleStep=0;
        var deflectionRatio=0;
        var modeCount=0;
        var iterations=0;
        var mapHorizontal=0;
        var mapVertical=0;
        var rating="";
        var deflection="";
        var vibration="";
        var removal="";
        var deadFactor=0.0;
        var vehicleFactor=0.0;
        var compressionLimit=0.0;
        var tensionLimit=0.0
    }
    data class Model(val nodes: List<Node>,val members: List<Member>,val sections: List<Section>,
        val materials: List<Material>,val supports: List<Support>,val cases: List<LoadCase>,
        val combinations: List<Combination>,val settings: Settings)
    fun rows(name: String)=File("input","$name.csv").readLines().drop(1).map {
        it.split(',')
    }
    fun read(): Model {
        val nodes=rows("nodes").map {
            Node(it[0].toInt(),it[1].toInt(),it[2].toInt())
        };
        val nodeIndex=nodes.withIndex().associate {
            it.value.identifier to it.index
        };
        val sections=rows("sections").map {
            Section(it[0],it[1].toDouble(),it[2].toDouble())
        };
        val sectionIndex=sections.withIndex().associate {
            it.value.name to it.index
        };
        val materials=rows("materials").map {
            Material(it[0],it[1].toDouble(),it[2].toDouble(),it[3].toDouble(),it[4].toDouble())
        };
        val materialIndex=materials.withIndex().associate {
            it.value.name to it.index
        };
        val members=rows("members").map {
            Member(it[0].toInt(),nodeIndex.getValue(it[1].toInt()),nodeIndex.getValue(it[2].toInt()),
                sectionIndex.getValue(it[3]),materialIndex.getValue(it[4]),it[5])
        };
        val memberIndex=members.withIndex().associate {
            it.value.identifier to it.index
        };
        val supports=rows("supports").map {
            Support(nodeIndex.getValue(it[0].toInt()),intArrayOf(it[1].toInt(),it[2].toInt()),
                doubleArrayOf(it[3].toDouble(),it[4].toDouble()))
        };
        val cases=mutableListOf<LoadCase>();
        val combinations=mutableListOf<Combination>();
        var name="";
        var loads=mutableListOf<Load>();
        for(line in File("input","loads.txt").readLines()) {
            val w=line.split(' ');
            when(w[0]) {
                "LOADCASE"-> {
                    name=w[1];
                    loads=mutableListOf()
                };
                "END"->cases.add(LoadCase(name,loads));
                "COMBINATION"->combinations.add(Combination(w[1],(2 until w.size step 2).map {
                    Term(w[it],w[it+1].toDouble())
                }));
                "FORCE"->loads.add(Load(w[0],nodeIndex.getValue(w[1].toInt()),w[2].toDouble(),
                    w[3].toDouble()));
                "TEMPERATURE"->loads.add(Load(w[0],memberIndex.getValue(w[1].toInt()),w[2].toDouble()));
                else->loads.add(Load(w[0]))
            }
        };
        val s=Settings();
        for(line in File("input","params.txt").readLines()) {
            val w=line.split(' ');
            when(w[0]) {
                "deck"->s.deck.addAll(w.drop(1).map {
                    nodeIndex.getValue(it.toInt())
                });
                "influence"->s.influence.add(memberIndex.getValue(w[1].toInt()));
                "vehicle"-> {
                    s.vehicleStep=w[1].toInt();
                    s.axles.addAll((2 until w.size step 2).map {
                        Axle(w[it].toInt(),w[it+1].toDouble())
                    })
                };
                "rating"-> {
                    s.rating=w[1];
                    s.deadFactor=w[2].toDouble();
                    s.vehicleFactor=w[3].toDouble()
                };
                "slenderness"-> {
                    s.compressionLimit=w[1].toDouble();
                    s.tensionLimit=w[2].toDouble()
                };
                "deflection"-> {
                    s.deflection=w[1];
                    s.deflectionRatio=w[2].toInt()
                };
                "vibration"-> {
                    s.vibration=w[1];
                    s.modeCount=w[2].toInt();
                    s.iterations=w[3].toInt()
                };
                "removal"->s.removal=w[1];
                "drawing"->s.drawings.add(Drawing(w[1],w[2].toInt(),w[3].toInt(),w[4].toInt()));
                "utilization_map"-> {
                    s.mapHorizontal=w[1].toInt();
                    s.mapVertical=w[2].toInt()
                }
            }
        };
        return Model(nodes,members,sections,materials,supports,cases,combinations,s)
    }
}
