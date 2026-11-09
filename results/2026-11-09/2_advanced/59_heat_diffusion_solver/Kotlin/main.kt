import java.io.File
import kotlin.math.*

object Heat {
    val SOLVERS=arrayOf("jacobi","gauss_seidel","sor","sor_estimated")
    data class Segment(val name: String,val edge: String,val kind: String,val faces: List<Mesh.FaceRef>,val coefficient: Double,val theta: Double)
    class Source(val name: String,val cells: List<Int>,val power: Double,val intervals: List<IntArray>) {
        val weight=power/cells.size
        fun operating(time: Int)=intervals.any {
            it[0]<=time&&time<it[1]
        }
        fun duty(end: Int): Double {
            var duration=0;
            for(interval in intervals)duration+=minOf(interval[1],end)-minOf(interval[0],end);
            return duration.toDouble()/end
        }
    }
    data class Run(val name: String,val method: String,val step: Int) {
        fun dt()=step/1000.0
    }
    data class Probe(val name: String,val cell: Int)
    class Params {
        var initial=0.0;
        var tolerance=0.0;
        var omega=0.0;
        var alarm=0.0;
        var limit=0.0;
        var end=0;
        var probeEvery=0;
        var maximum=0
        var snapshots=IntArray(0);
        var bands=DoubleArray(0);
        var reference="";
        val probes=mutableListOf<Probe>();
        val runs=mutableListOf<Run>()
    }
    fun readParams(mesh: Mesh): Params {
        val p=Params()
        for(line in File("input/params.txt").readLines()) {
            val w=line.split(' ');
            when(w[0]) {
                "initial"->p.initial=w[1].toDouble()
                "end_time"->p.end=w[1].toInt()
                "probe_every"->p.probeEvery=w[1].toInt()
                "max_iterations"->p.maximum=w[1].toInt()
                "tolerance"->p.tolerance=w[1].toDouble()
                "omega"->p.omega=w[1].toDouble()
                "alarm"->p.alarm=w[1].toDouble()
                "limit"->p.limit=w[1].toDouble()
                "reference"->p.reference=w[1]
                "probe"->p.probes.add(Probe(w[1],mesh.cell(w[2].toInt(),w[3].toInt())))
                "run"->p.runs.add(Run(w[1],w[2],w[3].toInt()))
                "snapshots"->p.snapshots=w.drop(1).map {
                    it.toInt()
                }.toIntArray()
                "bands"->p.bands=w.drop(1).map {
                    it.toDouble()
                }.toDoubleArray()
            }
        }
        return p
    }
    class Face(val neighbor: Int,var g: Double,var theta: Double=0.0,var boundary: Boolean=false)
    class Thermal(val mesh: Mesh,val materials: List<Materials.Material>) {
        val segments=mutableListOf<Segment>();
        val sources=mutableListOf<Source>()
        val material=IntArray(mesh.count);
        val materialCells=List(materials.size) {
            mutableListOf<Int>()
        }
        val capacity=DoubleArray(mesh.count);
        val diagonal=DoubleArray(mesh.count);
        val beta=DoubleArray(mesh.count);
        val all=DoubleArray(mesh.count)
        var power=0.0;
        var maximumStep=Double.MAX_VALUE;
        val faces: Array<Array<Face>>
        init {
            for(line in File("input/boundary.txt").readLines()) {
                val w=line.split(' ')
                if(w[0]=="segment") {
                    val kind=w[5];
                    val coefficient=if(kind=="convective")w[6].toDouble() else 0.0;
                    val theta=if(kind=="fixed")w[6].toDouble() else if(kind=="convective")w[7].toDouble() else 0.0
                    segments.add(Segment(w[1],w[2],kind,mesh.segment(w[2],w[3].toInt(),w[4].toInt()),coefficient,theta))
                }
                else {
                    val intervals=(7 until w.size step 2).map {
                        intArrayOf(w[it].toInt(),w[it+1].toInt())
                    };
                    sources.add(Source(w[1],mesh.source(w[2].toInt(),w[3].toInt(),w[4].toInt(),w[5].toInt()),w[6].toDouble(),intervals))
                }
            }
            for(p in 0 until mesh.count) {
                val i=materials.indexOfFirst {
                    it.code==mesh.codes[p]
                };
                material[p]=i;
                materialCells[i].add(p);
                capacity[p]=Materials.capacity(materials[i],mesh.dx,mesh.thickness)
            }
            faces=Array(mesh.count) {
                p->Array(4) {
                    f->val q=mesh.neighbors[p][f];
                    Face(q,if(q>=0)Materials.interior(materials[material[p]].k,materials[material[q]].k,mesh.thickness) else 0.0)
                }
            }
            for(segment in segments)for(ref in segment.faces) {
                val face=faces[ref.point][ref.direction];
                val k=materials[material[ref.point]].k
                if(segment.kind!="insulated") {
                    face.boundary=true;
                    face.theta=segment.theta;
                    face.g=if(segment.kind=="fixed")Materials.fixedFace(k,mesh.thickness) else Materials.convective(k,
                        segment.coefficient,mesh.dx,mesh.thickness)
                }
            }
            for(p in 0 until mesh.count) {
                for(face in faces[p]) {
                    diagonal[p]+=face.g;
                    if(face.boundary)beta[p]+=face.g*face.theta
                };
                maximumStep=minOf(maximumStep,capacity[p]/diagonal[p])
            }
            for(source in sources) {
                power+=source.power;
                for(p in source.cells)all[p]+=source.weight
            }
        }
    }
    data class Terms(val field: DoubleArray,val power: Double)
    fun terms(s: Thermal,time: Int): Terms {
        val field=DoubleArray(s.mesh.count);
        var power=0.0;
        for(source in s.sources)if(source.operating(time)) {
            power+=source.power;
            for(p in source.cells)field[p]+=source.weight
        };
        return Terms(field,power)
    }
    fun hottest(x: DoubleArray): Int {
        var p=0;
        for(i in 1 until x.size)if(x[i]>x[p])p=i;
        return p
    }
    fun sum(x: DoubleArray): Double {
        var result=0.0;
        for(value in x)result+=value;
        return result
    }
    fun error(x: DoubleArray,y: DoubleArray): Double {
        var maximum=0.0;
        for(i in x.indices)maximum=maxOf(maximum,abs(x[i]-y[i]));
        return maximum
    }
    fun stored(s: Thermal,x: DoubleArray,initial: Double,cells: List<Int>?): Double {
        var value=0.0;
        if(cells==null) {
            for(p in x.indices)value+=s.capacity[p]*(x[p]-initial)
        } else for(p in cells)value+=s.capacity[p]*(x[p]-initial);
        return value
    }
    fun segmentFlow(s: Thermal,segment: Segment,x: DoubleArray): Double {
        var total=0.0;
        if(segment.kind!="insulated")for(ref in segment.faces) {
            val f=s.faces[ref.point][ref.direction];
            total+=f.g*(f.theta-x[ref.point])
        };
        return total
    }
    fun status(run: Run,s: Thermal,settings: Params): String {
        val d=run.step;
        if(settings.end%d!=0||settings.probeEvery%d!=0)return "step";
        for(t in settings.snapshots)if(t%d!=0)return "step"
        for(source in s.sources)for(interval in source.intervals)if(interval[0]%d!=0||interval[1]%d!=0)return "step"
        return if(run.method=="ftcs"&&run.dt()>s.maximumStep)"unstable" else "accepted"
    }
    data class Frame(val field: DoubleArray,val stored: Double,val boundary: Double,val generated: Double)
    data class Sample(val time: Int,val values: DoubleArray)
    class Result(val run: Run,val status: String) {
        val snapshots=mutableMapOf<Int,Frame>();
        val samples=mutableListOf<Sample>();
        lateinit var segmentEnergy: DoubleArray;
        lateinit var field: DoubleArray
        var generated=0.0;
        var stored=0.0;
        var boundary=0.0;
        var peak=-Double.MAX_VALUE;
        var steps=0;
        var peakTime=0;
        var peakCell=0;
        var alarmTime=-1;
        var alarmCell=0;
        var above=0;
        var balanced=false
        fun observe(s: Thermal,settings: Params,time: Int,x: DoubleArray) {
            val hs=hottest(x);
            if(x[hs]>peak) {
                peak=x[hs];
                peakTime=time;
                peakCell=hs
            }
            if(x[hs]>=settings.alarm) {
                if(alarmTime<0) {
                    alarmTime=time;
                    alarmCell=hs
                };
                if(time>0)above+=run.step
            }
            if(time%settings.probeEvery==0)samples.add(Sample(time,DoubleArray(settings.probes.size) {
                x[settings.probes[it].cell]
            }))
            for(t in settings.snapshots)if(t==time)snapshots[time]=Frame(x.copyOf(),Heat.stored(s,x,settings.initial,null),sum(segmentEnergy),generated)
        }
    }
    fun simulate(run: Run,s: Thermal,settings: Params): Result {
        val status=status(run,s,settings);
        val result=Result(run,status);
        if(status!="accepted")return result
        result.steps=settings.end/run.step;
        result.segmentEnergy=DoubleArray(s.segments.size);
        var field=DoubleArray(s.mesh.count) {
            settings.initial
        };
        result.observe(s,settings,0,field)
        for(n in 0 until result.steps) {
            val terms=terms(s,n*run.step);
            val step=Transient.advance(run.method,s,field,terms.field,run.dt());
            val next=step.field
            for(j in s.segments.indices) {
                val segment=s.segments[j];
                var flow=0.0
                if(segment.kind!="insulated")for(ref in segment.faces) {
                    val p=ref.point;
                    val face=s.faces[p][ref.direction]
                    val temperature=if(run.method=="ftcs")field[p] else if(segment.edge=="left"||segment.edge=="right")step.intermediate!![p] else if(run.method=="backward_euler")next[p] else (field[p]+next[p])/2
                    flow+=face.g*(face.theta-temperature)
                }
                result.segmentEnergy[j]+=run.dt()*flow
            }
            result.generated+=run.dt()*terms.power;
            field=next;
            result.observe(s,settings,(n+1)*run.step,field)
        }
        result.field=field;
        result.stored=stored(s,field,settings.initial,null);
        result.boundary=sum(result.segmentEnergy)
        result.balanced=abs(result.stored-result.boundary-result.generated)<=0.000001*(abs(result.stored)+abs(result.boundary)+abs(result.generated))
        return result
    }
    fun summary(prefix: String,s: Thermal,field: DoubleArray): String {
        val p=hottest(field);
        var minimum=field[0];
        for(value in field)minimum=minOf(minimum,value);
        return "$prefix max ${Report.real(field[p],2)} at ${s.mesh.coordinates(p)} min ${Report.real(minimum,2)} mean ${Report.real(sum(field)/field.size,2)}"
    }
    fun verdict(condition: Boolean)=if(condition)"ok" else "failed"
    fun rejected(result: Result,maximum: Double?): String {
        var text="run ${result.run.name} ${result.run.method} dt ${Report.time(result.run.step)} rejected ${result.status}";
        if(result.status=="unstable"&&maximum!=null)text+=" max_dt ${Report.real(maximum,4)}";
        return text
    }
    fun iterations(s: Thermal,settings: Params,solution: DoubleArray,rhs: DoubleArray): List<Steady.Iteration> {
        val results=mutableListOf<Steady.Iteration>();
        val jacobi=Steady.iterate(s,settings,"jacobi",1.0);
        results.add(jacobi);
        var k=jacobi.changes.size
        val rho=sqrt(jacobi.changes[k-1]/jacobi.changes[k-3]);
        val omega=2/(1+sqrt(1-rho*rho))
        for(i in 1..3)results.add(Steady.iterate(s,settings,SOLVERS[i],if(i==3)omega else settings.omega))
        val factors=intArrayOf(1000,100,10,1)
        for(result in results) {
            k=result.changes.size;
            result.rate=sqrt(result.changes[k-1]/result.changes[k-3]);
            result.error=error(result.field,solution);
            result.residual=Steady.residual(s,result.field,rhs)
            for(i in 0..3)for(j in 0 until k)if(result.changes[j]<settings.tolerance*factors[i]) {
                result.milestones[i]=(j+1).toString();
                break
            }
        }
        return results
    }

    fun steadyLines(s: Thermal,settings: Params,solutions: List<DoubleArray>,iterative: List<Steady.Iteration>): List<String> {
        val solution=solutions[0];
        val base=solutions[1];
        val lines=mutableListOf(summary("steady",s,solution));
        lines.addAll(Report.field(s.mesh,solution))
        for(i in s.materials.indices) {
            val material=s.materials[i];
            val cells=s.materialCells[i];
            var minimum=Double.MAX_VALUE;
            var maximum=-Double.MAX_VALUE;
            var total=0.0
            for(p in cells) {
                minimum=minOf(minimum,solution[p]);
                maximum=maxOf(maximum,solution[p]);
                total+=solution[p]
            }
            lines.add("material ${material.code} ${material.name} cells ${cells.size} min ${Report.real(minimum,2)} max ${Report.real(maximum,2)} mean ${Report.real(total/cells.size,2)}")
        }
        val duties=DoubleArray(s.sources.size)
        for(i in s.sources.indices) {
            val source=s.sources[i];
            duties[i]=source.duty(settings.end);
            var total=0.0;
            var maximum=-Double.MAX_VALUE;
            for(p in source.cells) {
                total+=solution[p];
                maximum=maxOf(maximum,solution[p])
            }
            lines.add("source ${source.name} power ${Report.real(source.power,4)} duty ${Report.real(duties[i],4)} mean ${Report.real(total/source.cells.size,2)} max ${Report.real(maximum,2)}")
        }
        for(source in s.sources)for(i in s.sources.indices) {
            var total=0.0;
            for(p in source.cells)total+=solutions[i+2][p];
            lines.add("influence ${source.name} ${s.sources[i].name} ${Report.real(total/source.cells.size,4)}")
        }
        val combined=base.copyOf();
        val duty=base.copyOf()
        for(p in base.indices)for(i in s.sources.indices) {
            val source=s.sources[i];
            combined[p]+=source.power*solutions[i+2][p];
            duty[p]+=(duties[i]*source.power)*solutions[i+2][p]
        }
        lines.add("superposition ${verdict(error(combined,solution)<=0.000001)}")
        for(i in s.sources.indices)for(segment in s.segments) {
            var total=0.0;
            if(segment.kind!="insulated")for(ref in segment.faces)total+=s.faces[ref.point][ref.direction].g*solutions[i+2][ref.point];
            lines.add("path ${s.sources[i].name} ${segment.name} ${Report.real(total,4)}")
        }
        lines.add(summary("duty_steady",s,duty))
        for(i in s.sources.indices) {
            val source=s.sources[i];
            val response=solutions[i+2];
            var minimum=Double.MAX_VALUE;
            var limiting=0
            for(p in solution.indices) {
                val power=(settings.limit-(solution[p]-source.power*response[p]))/response[p];
                if(power<minimum) {
                    minimum=power;
                    limiting=p
                }
            }
            lines.add("headroom ${source.name} max_power ${Report.real(minimum,4)} at ${s.mesh.coordinates(limiting)}")
        }
        val materials=s.materials.size;
        val count=Array(materials) {
            IntArray(materials)
        };
        val forward=Array(materials) {
            DoubleArray(materials)
        };
        val backward=Array(materials) {
            DoubleArray(materials)
        }
        var gradient=-1.0;
        var first=0;
        var second=0
        for(p in solution.indices)for(direction in intArrayOf(1,3)) {
            val face=s.faces[p][direction];
            val q=face.neighbor;
            if(q<0)continue;
            val value=abs(solution[p]-solution[q])/s.mesh.dx;
            if(value>gradient) {
                gradient=value;
                first=p;
                second=q
            }
            var a=s.material[p];
            var b=s.material[q];
            if(a==b)continue;
            var flow=face.g*(solution[p]-solution[q]);
            if(a>b) {
                val swap=a;
                a=b;
                b=swap;
                flow=-flow
            }
            count[a][b]++;
            if(flow>0)forward[a][b]+=flow else if(flow<0)backward[a][b]+=abs(flow)
        }
        for(i in 0 until materials)for(j in i+1 until materials)if(count[i][j]>0)lines.add("interface ${s.materials[i].code} ${s.materials[j].code} faces ${count[i][j]} forward ${Report.real(forward[i][j],4)} backward ${Report.real(backward[i][j],4)}")
        var totalFlow=0.0;
        var absoluteFlow=0.0
        for(segment in s.segments) {
            val flow=segmentFlow(s,segment,solution);
            totalFlow+=flow;
            absoluteFlow+=abs(flow);
            lines.add("segment ${segment.name} ${segment.edge} ${segment.kind} flow ${Report.real(flow,4)}")
        }
        lines.add("sources ${Report.real(s.power,4)}");
        lines.add("balance ${verdict(abs(totalFlow+s.power)<=0.000001*(absoluteFlow+s.power))}")
        lines.add("max_gradient ${Report.real(gradient,2)} between ${s.mesh.coordinates(first)} and ${s.mesh.coordinates(second)}")
        for(result in iterative) {
            var prefix="solver ${result.method}";
            if(result.method=="sor"||result.method=="sor_estimated")prefix+=" omega ${Report.real(result.omega,4)}"
            lines.add("$prefix iterations ${result.changes.size} converged ${if(result.converged)"yes" else "no"} rate ${Report.real(result.rate,6)} milestones ${result.milestones.joinToString(" ")}")
        }
        return lines
    }
    fun snapshotLines(s: Thermal,settings: Params,results: List<Result>): List<String> {
        val lines=mutableListOf<String>()
        for(result in results) {
            if(result.status!="accepted") {
                lines.add(rejected(result,s.maximumStep));
                continue
            }
            for(time in settings.snapshots) {
                val field=result.snapshots.getValue(time).field;
                val prefix="run ${result.run.name} ${result.run.method} dt ${Report.time(result.run.step)} time ${Report.time(time)}";
                lines.add(summary(prefix,s,field));
                lines.addAll(Report.field(s.mesh,field))
            }
        }
        return lines
    }
    fun probeLines(settings: Params,results: List<Result>): List<String> {
        val lines=mutableListOf("run,time,probe,temperature")
        for(result in results)if(result.status=="accepted")for(sample in result.samples)for(i in settings.probes.indices)lines.add("${result.run.name},${Report.time(sample.time)},${settings.probes[i].name},${Report.real(sample.values[i],3)}")
        return lines
    }
    fun comparison(s: Thermal,settings: Params,results: List<Result>,reference: Result,solutions: List<DoubleArray>,
        rhs: DoubleArray,iterative: List<Steady.Iteration>): List<String> {
        val solution=solutions[0];
        val lines=mutableListOf("ftcs_max_dt ${Report.real(s.maximumStep,4)}")
        for(result in results) {
            if(result.status!="accepted") {
                lines.add(rejected(result,null));
                continue
            }
            val run=result.run;
            val name=run.name;
            val alarm=if(result.alarmTime<0)"never" else "${Report.time(result.alarmTime)} at ${s.mesh.coordinates(result.alarmCell)}"
            lines.add("run $name ${run.method} dt ${Report.time(run.step)} steps ${result.steps} peak ${Report.real(result.peak,2)} time ${Report.time(result.peakTime)} at ${s.mesh.coordinates(result.peakCell)} alarm $alarm above ${Report.time(result.above)}")
            lines.add("energy $name stored ${Report.real(result.stored,2)} boundary ${Report.real(result.boundary,2)} source ${Report.real(result.generated,2)} balance ${verdict(result.balanced)}")
            for(time in settings.snapshots) {
                val frame=result.snapshots.getValue(time);
                lines.add("energy_at $name time ${Report.time(time)} stored ${Report.real(frame.stored,2)} boundary ${Report.real(frame.boundary,2)} source ${Report.real(frame.generated,2)}")
            }
            for(i in s.materials.indices)lines.add("energy_material $name ${s.materials[i].code} ${Report.real(stored(s,result.field,settings.initial,s.materialCells[i]),2)}")
            for(i in s.segments.indices)lines.add("energy_segment $name ${s.segments[i].name} ${Report.real(result.segmentEnergy[i],2)}")
            for(i in settings.probes.indices) {
                var maximum=result.samples[0].values[i];
                var minimum=maximum;
                var maximumTime=result.samples[0].time;
                var minimumTime=maximumTime
                for(sample in result.samples) {
                    val value=sample.values[i];
                    if(value>maximum) {
                        maximum=value;
                        maximumTime=sample.time
                    };
                    if(value<minimum) {
                        minimum=value;
                        minimumTime=sample.time
                    }
                }
                lines.add("probe_summary $name ${settings.probes[i].name} max ${Report.real(maximum,3)} time ${Report.time(maximumTime)} min ${Report.real(minimum,3)} time ${Report.time(minimumTime)}")
            }
            if(result!==reference)for(time in settings.snapshots) {
                val field=result.snapshots.getValue(time).field;
                val other=reference.snapshots.getValue(time).field;
                var squares=0.0
                for(p in field.indices) {
                    val e=abs(field[p]-other[p]);
                    squares+=e*e
                }
                lines.add("compare $name ${reference.run.name} time ${Report.time(time)} max_diff ${Report.real(error(field,other),6)} rms_diff ${Report.real(sqrt(squares/field.size),6)}")
            }
            lines.add("final $name steady_max_diff ${Report.real(error(result.field,solution),6)}")
        }
        lines.add("steady direct max_residual ${Report.real(Steady.residual(s,solution,rhs),6)}")
        for(result in iterative)lines.add("steady ${result.method} iterations ${result.changes.size} max_diff ${Report.real(result.error,6)} max_residual ${Report.real(result.residual,6)}")
        val rho=iterative[0].rate;
        val omega=iterative[3].omega
        lines.add("jacobi_spectral_radius ${Report.real(rho,6)} squared ${Report.real(rho*rho,6)}");
        lines.add("omega_estimated ${Report.real(omega,4)}")
        return lines
    }
    fun map(lines: MutableList<String>,prefix: String,s: Thermal,field: DoubleArray,bands: DoubleArray) {
        val image=Report.isotherm(s.mesh,field,bands);
        lines.add("$prefix counts "+image.counts.joinToString(" "));
        lines.addAll(image.lines)
    }
    fun run() {
        val mesh=Mesh();
        val settings=readParams(mesh);
        val system=Thermal(mesh,Materials.read());
        val vectors=mutableListOf<DoubleArray>();
        val rhs=DoubleArray(mesh.count) {
            system.beta[it]+system.all[it]
        };
        vectors.add(rhs);
        vectors.add(system.beta)
        for(source in system.sources) {
            val vector=DoubleArray(mesh.count);
            for(p in source.cells)vector[p]=1.0/source.cells.size;
            vectors.add(vector)
        }
        val solutions=Steady.direct(system,vectors);
        val iterative=iterations(system,settings,solutions[0],rhs)
        val results=settings.runs.map {
            simulate(it,system,settings)
        };
        val reference=results.first {
            it.run.name==settings.reference
        }
        val maps=mutableListOf<String>();
        map(maps,"isotherms steady",system,solutions[0],settings.bands)
        for(time in settings.snapshots)map(maps,"isotherms ${reference.run.name} time ${Report.time(time)}",
            system,reference.snapshots.getValue(time).field,settings.bands)
        Report.write("snapshots.txt",snapshotLines(system,settings,results));
        Report.write("probes.csv",probeLines(settings,results));
        Report.write("steady_state.txt",steadyLines(system,settings,solutions,iterative));
        Report.write("solver_comparison.txt",comparison(system,settings,results,reference,solutions,rhs,iterative));
        Report.write("isotherms.txt",maps)
    }
}
fun main()=Heat.run()
