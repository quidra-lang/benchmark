import java.io.File

object Scene {
    data class Color(val r: Long,val g: Long,val b: Long) {
        fun component(axis: Int)=if(axis==0)r else if(axis==1)g else b;
        override fun toString()="$r $g $b";
        companion object {
            fun of(values: LongArray)=Color(values[0],values[1],values[2])
        }
    }
    class Material(val name: String,val color: Color,val kd: Long,val ks: Long,val exponent: Int,val kr: Long,val kt: Long,val ior: Long) {
        var checker: Color?=null;
        var checkerSize=0L
    }
    class Obj(val number: Int,val label: Char,val kind: String,val material: Material) {
        var leafDepth=0;
        var center=Vector3(0,0,0);
        var point=Vector3(0,0,0);
        var normal=Vector3(0,0,0);
        var lo=Vector3(0,0,0);
        var hi=Vector3(0,0,0);
        var radius=0L;
        var bounds: Intersect.Bounds?=null
    }
    class Light(val number: Int,val kind: String) {
        var divisions=1;
        var position=Vector3(0,0,0);
        var direction=Vector3(0,0,0);
        var u=Vector3(0,0,0);
        var v=Vector3(0,0,0);
        var outer=0L;
        var inner=0L;
        var intensity=0L;
        fun samples()=if(kind=="area")divisions*divisions else 1
    }
    class Data {
        lateinit var eye: Vector3;
        lateinit var forward: Vector3;
        lateinit var right: Vector3;
        lateinit var up: Vector3;
        var hw=0L;
        var hh=0L;
        var ambient=0L;
        var fogStart=0L;
        var fogEnd=0L;
        lateinit var background: Color;
        var fog: Color?=null;
        val materials=linkedMapOf<String,Material>();
        val objects=mutableListOf<Obj>();
        val lights=mutableListOf<Light>()
    }
    fun value(words: List<String>,index: Int)=words[index].toLong()
    fun vector(words: List<String>,start: Int)=Vector3(value(words,start),value(words,start+1),value(words,start+2))
    fun color(words: List<String>,start: Int)=Color(value(words,start),value(words,start+1),value(words,start+2))
    fun read(): Data {
        val scene=Data();
        for(line in File("input/scene.txt").readLines(Charsets.US_ASCII)) {
            if(line.isEmpty()||line.startsWith("#"))continue;
            val w=line.split(' ');
            when(w[0]) {
                "eye"->scene.eye=vector(w,1);
                "forward"->scene.forward=vector(w,1);
                "right"->scene.right=vector(w,1);
                "up"->scene.up=vector(w,1);
                "view"-> {
                    scene.hw=value(w,1);
                    scene.hh=value(w,2)
                };
                "background"->scene.background=color(w,1);
                "ambient"->scene.ambient=value(w,1);
                "fog"-> {
                    scene.fog=color(w,1);
                    scene.fogStart=value(w,4);
                    scene.fogEnd=value(w,5)
                };
                "material"-> {
                    val material=Material(w[1],color(w,2),value(w,5),value(w,6),value(w,7).toInt(),value(w,8),value(w,9),value(w,10));
                    scene.materials[material.name]=material
                };
                "checker"-> {
                    val material=scene.materials.getValue(w[1]);
                    material.checker=color(w,2);
                    material.checkerSize=value(w,5)
                };
                "sphere","plane","box"-> {
                    val obj=Obj(scene.objects.size+1,w[1][0],w[0],scene.materials.getValue(w[2]));
                    when(obj.kind) {
                        "sphere"-> {
                            obj.center=vector(w,3);
                            obj.radius=value(w,6)
                        };
                        "plane"-> {
                            obj.point=vector(w,3);
                            obj.normal=vector(w,6).normalize()
                        };
                        else-> {
                            obj.lo=vector(w,3);
                            obj.hi=vector(w,6)
                        }
                    };
                    scene.objects+=obj
                };
                else-> {
                    val light=Light(scene.lights.size+1,w[0]);
                    when(light.kind) {
                        "point"-> {
                            light.position=vector(w,1);
                            light.intensity=value(w,4)
                        };
                        "spot"-> {
                            light.position=vector(w,1);
                            light.direction=vector(w,4).normalize();
                            light.outer=value(w,7);
                            light.inner=value(w,8);
                            light.intensity=value(w,9)
                        };
                        "sun"-> {
                            light.direction=vector(w,1).negate().normalize();
                            light.intensity=value(w,4)
                        };
                        "area"-> {
                            light.position=vector(w,1);
                            light.u=vector(w,4);
                            light.v=vector(w,7);
                            light.divisions=value(w,10).toInt();
                            light.intensity=value(w,11)
                        }
                    };
                    scene.lights+=light
                }
            }
        };
        return scene
    }
}
