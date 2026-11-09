import java.io.File
import java.util.Locale
import kotlin.math.*
object TrussSolver {
    lateinit var model: ModelIo.Model;
    lateinit var settings: ModelIo.Settings;
    lateinit var nodes: List<ModelIo.Node>;
    lateinit var members: List<ModelIo.Member>;
    lateinit var order: List<Int>;
    val neighbors=mutableListOf<MutableSet<Int>>();
    lateinit var numbers: IntArray;
    lateinit var free: IntArray;
    lateinit var restrained: IntArray;
    lateinit var ownerNode: IntArray;
    lateinit var ownerAxis: IntArray;
    lateinit var choices: IntArray;
    lateinit var governingCases: IntArray;
    lateinit var deckX: IntArray;
    lateinit var nodeDofs: Array<IntArray>;
    var degrees=0;
    lateinit var prescribed: DoubleArray;
    lateinit var limits: DoubleArray;
    lateinit var governing: DoubleArray;
    lateinit var utilizations: Array<DoubleArray>;
    var weight=0.0;
    lateinit var geometry: List<Assembly.Geometry>;
    lateinit var properties: List<Assembly.Properties>;
    val groups=linkedMapOf<String,MutableList<Int>>();
    val combinationDefinitions=mutableMapOf<String,ModelIo.Combination>();
    val resultOrder=mutableListOf<ResultOrder>();
    val supportDirections=mutableListOf<SupportDirection>();
    val units=mutableMapOf<Int,Postprocess.Result>();
    lateinit var finalSystem: StructuralSystem;
    lateinit var results: Map<String,Postprocess.Result>;
    lateinit var combinations: List<Postprocess.Result>
    data class SupportDirection(val node: Int,val axis: Int,val degree: Int)
    data class ResultOrder(val kind: String,val name: String)
    data class StructuralSystem(val properties: List<Assembly.Properties>,val matrix: Array<DoubleArray>,
        val freeMatrix: Array<DoubleArray>,val lower: Array<DoubleArray>?,val unstable: Int,
        val removed: Int)
    data class Metrics(val bandwidth: Int,val profile: Int)
    data class Change(val group: String,val current: Int,val chosen: Int,val utilization: Double)
    data class Range(val maximum: Double,val highPosition: Int,val minimum: Double,val lowPosition: Int)
    data class Rating(val member: Int,val kind: String,val value: Double)
    data class Point(val column: Int,val row: Int)
    fun real(value: Double,digits: Int=4): String {
        val text=String.format(Locale.ROOT,"%.${digits}f",value);
        return if(text.startsWith('-')&&text.toDouble()==0.0)text.substring(1) else text
    }
    fun f(value: Double)=real(value)
    fun rounded(value: Double)=f(value).toDouble()
    fun yes(value: Boolean)=if(value)"yes" else "no"
    fun total(values: DoubleArray): Double {
        var total=0.0;
        for(value in values)total+=value;
        return total
    }
    fun extreme(values: DoubleArray,minimum: Boolean=false): Int {
        var best=0;
        for(i in 1 until values.size)if(if(minimum)rounded(values[i])<rounded(values[best]) else rounded(values[i])>rounded(values[best]))best=i;
        return best
    }
    fun bestMember(members: List<Int>,values: DoubleArray): Int {
        var best=members.first();
        for(m in members)if(rounded(values[m])>rounded(values[best]))best=m;
        return best
    }
    fun prepare(input: ModelIo.Model) {
        model=input;
        settings=model.settings;
        nodes=model.nodes;
        members=model.members;
        repeat(nodes.size) {
            neighbors.add(mutableSetOf())
        };
        for(member in members) {
            neighbors[member.start].add(member.end);
            neighbors[member.end].add(member.start)
        };
        val degreeOrder=compareBy<Int> {
            neighbors[it].size
        }.thenBy {
            nodes[it].identifier
        };
        val queue=mutableListOf(nodes.indices.minWith(degreeOrder));
        val visited=BooleanArray(nodes.size);
        visited[queue.first()]=true;
        var i=0;
        while(i<queue.size) {
            val following=neighbors[queue[i]].filter {
                !visited[it]
            }.sortedWith(degreeOrder);
            for(node in following) {
                queue.add(node);
                visited[node]=true
            };
            i++
        };
        order=queue.reversed();
        numbers=IntArray(nodes.size);
        nodeDofs=Array(nodes.size) {
            IntArray(2)
        };
        degrees=2*nodes.size;
        ownerNode=IntArray(degrees);
        ownerAxis=IntArray(degrees);
        for((number,node) in order.withIndex()) {
            numbers[node]=number;
            for(axis in 0..1) {
                val d=2*number+axis;
                nodeDofs[node][axis]=d;
                ownerNode[d]=node;
                ownerAxis[d]=axis
            }
        };
        prescribed=DoubleArray(degrees);
        val fixed=mutableListOf<Int>();
        for(support in model.supports)for(axis in 0..1)if(support.fixed[axis]==1) {
            val d=nodeDofs[support.node][axis];
            prescribed[d]=support.prescribed[axis];
            fixed.add(d);
            supportDirections.add(SupportDirection(support.node,axis,d))
        };
        restrained=fixed.sorted().toIntArray();
        free=(0 until degrees).filter {
            it !in fixed
        }.toIntArray();
        geometry=Assembly.geometry(nodes,members,nodeDofs);
        for((m,member) in members.withIndex())groups.getOrPut(member.group) {
            mutableListOf()
        }.add(m);
        for(loadCase in model.cases)resultOrder.add(ResultOrder("case",loadCase.name));
        for(combination in model.combinations) {
            resultOrder.add(ResultOrder("combination",combination.name));
            combinationDefinitions[combination.name]=combination
        };
        deckX=IntArray(settings.deck.size) {
            nodes[settings.deck[it]].x
        }
    }
    fun metrics(numbering: IntArray): Metrics {
        var bandwidth=0;
        var profile=0;
        for(member in members)bandwidth=maxOf(bandwidth,abs(numbering[member.start]-numbering[member.end]));
        for(n in nodes.indices) {
            var minimum=numbering[n];
            for(adjacent in neighbors[n])minimum=minOf(minimum,numbering[adjacent]);
            profile+=numbering[n]-minimum
        };
        return Metrics(bandwidth,profile)
    }
    fun system(choices: IntArray,removed: Int=-1): StructuralSystem {
        val properties=Assembly.properties(model,choices,geometry);
        val matrix=Assembly.assemble(geometry,properties,degrees,removed);
        val freeMatrix=Array(free.size) {
            i->DoubleArray(free.size) {
                j->matrix[free[i]][free[j]]
            }
        };
        val factor=Solver.cholesky(freeMatrix,free);
        return StructuralSystem(properties,matrix,freeMatrix,factor.lower,factor.unstable,removed)
    }
    fun displacement(system: StructuralSystem,force: DoubleArray,settlement: Boolean=false): DoubleArray {
        val displacement=DoubleArray(degrees);
        for(d in restrained)displacement[d]=if(settlement)prescribed[d] else 0.0;
        val right=DoubleArray(free.size);
        for(i in free.indices) {
            var value=force[free[i]];
            for(d in restrained)value-=system.matrix[free[i]][d]*displacement[d];
            right[i]=value
        };
        val solution=Solver.solve(system.lower!!,right);
        for(i in free.indices)displacement[free[i]]=solution[i];
        return displacement
    }
    fun caseResult(system: StructuralSystem,loadCase: ModelIo.LoadCase): Postprocess.Result {
        val loading=Assembly.loads(loadCase,geometry,system.properties,nodeDofs,degrees,system.removed);
        val displacement=TrussSolver.displacement(system,loading.total,loading.settlement);
        val forces=Postprocess.forces(geometry,system.properties,displacement,loading.temperature,
            system.removed);
        val reactions=Postprocess.reactions(system.matrix,displacement,loading.total,restrained);
        return Postprocess.Result(loadCase.name,displacement,forces,reactions,loading.external)
    }
    fun analyze(system: StructuralSystem,only: ModelIo.Combination?=null): Map<String,Postprocess.Result> {
        val combinations=if(only==null)model.combinations else listOf(only);
        val needed=combinations.flatMap {
            it.terms.map {
                term->term.name
            }
        }.toSet();
        val results=linkedMapOf<String,Postprocess.Result>();
        for(loadCase in model.cases)if(only==null||loadCase.name in needed)results[loadCase.name]=caseResult(system,
            loadCase);
        for(combination in combinations)results[combination.name]=Postprocess.superpose(combination,
            results);
        return results
    }
    fun unit(node: Int): Postprocess.Result=units.getOrPut(node) {
        val force=DoubleArray(degrees);
        force[nodeDofs[node][1]]=-1000.0;
        val displacement=TrussSolver.displacement(finalSystem,force);
        val forces=Postprocess.forces(geometry,properties,displacement,DoubleArray(members.size));
        val reactions=Postprocess.reactions(finalSystem.matrix,displacement,force,restrained);
        Postprocess.Result("unit",displacement,forces,reactions,force)
    }
    fun designSections(): List<String> {
        choices=IntArray(members.size) {
            members[it].section
        };
        val history=mutableListOf<String>();
        var converged=false;
        var lastRound=0;
        for(round in 1..10) {
            lastRound=round;
            val currentSystem=system(choices);
            val caseResults=analyze(currentSystem);
            val roundCombinations=model.combinations.map {
                caseResults.getValue(it.name)
            };
            val roundLimits=DoubleArray(members.size) {
                Design.limit(it,roundCombinations,settings)
            };
            val roundUtilizations=Array(members.size) {
                DoubleArray(roundCombinations.size)
            };
            var largestMember=0;
            var largestCase=0;
            var roundWeight=0.0;
            for(m in members.indices) {
                val p=currentSystem.properties[m];
                val g=geometry[m];
                roundWeight+=Assembly.weight(p,g);
                for(c in roundCombinations.indices) {
                    roundUtilizations[m][c]=Design.utilization(roundCombinations[c].forces[m],
                        p,g);
                    if(rounded(roundUtilizations[m][c])>rounded(roundUtilizations[largestMember][largestCase])) {
                        largestMember=m;
                        largestCase=c
                    }
                }
            };
            val changes=mutableListOf<Change>();
            for((name,groupMembers) in groups) {
                val chosen=Design.select(groupMembers,model.sections,currentSystem.properties,
                    geometry,roundCombinations,roundLimits);
                val current=choices[groupMembers.first()];
                if(chosen!=current) {
                    var largest=roundUtilizations[groupMembers.first()][0];
                    for(m in groupMembers)for(utilization in roundUtilizations[m])if(rounded(utilization)>rounded(largest))largest=utilization;
                    changes.add(Change(name,current,chosen,largest))
                }
            };
            history.add("round $round weight ${f(roundWeight/1000)} max_utilization ${f(roundUtilizations[largestMember][largestCase])} at ${members[largestMember].identifier} ${roundCombinations[largestCase].name} changes ${changes.size}");
            for(change in changes)history.add("change ${change.group} ${model.sections[change.current].name} ${model.sections[change.chosen].name} utilization ${f(change.utilization)}");
            converged=changes.isEmpty();
            if(converged||round==10) {
                finalSystem=currentSystem;
                properties=currentSystem.properties;
                results=caseResults;
                combinations=roundCombinations;
                limits=roundLimits;
                utilizations=roundUtilizations;
                weight=roundWeight;
                break
            };
            for(change in changes)for(m in groups.getValue(change.group))choices[m]=change.chosen
        };
        governingCases=IntArray(members.size) {
            extreme(utilizations[it])
        };
        governing=DoubleArray(members.size) {
            utilizations[it][governingCases[it]]
        };
        history.add("result ${if(converged)"converged" else "not_converged"} rounds $lastRound");
        return history
    }
    fun designReport(history: List<String>): List<String> {
        val lines=history.toMutableList();
        for((name,groupMembers) in groups) {
            val member=bestMember(groupMembers,governing);
            val section=model.sections[choices[groupMembers.first()]].name;
            lines.add("group $name section $section members ${groupMembers.size} utilization ${f(governing[member])} at ${members[member].identifier}")
        };
        for((m,member) in members.withIndex()) {
            val slender=Design.slenderness(properties[m],geometry[m]);
            lines.add("member ${member.identifier} group ${member.group} section ${model.sections[choices[m]].name} utilization ${f(governing[m])} governing ${combinations[governingCases[m]].name} slenderness ${f(slender)} limit ${f(limits[m])} ${if(governing[m]<=1&&slender<=limits[m])"ok" else "over"}")
        };
        val ranking=members.indices.sortedWith(compareByDescending<Int> {
            rounded(governing[it])
        }.thenBy {
            it
        });
        for((i,m) in ranking.take(5).withIndex())lines.add("rank ${i+1} member ${members[m].identifier} utilization ${f(governing[m])}");
        for(m in members.indices) {
            val values=DoubleArray(combinations.size) {
                combinations[it].forces[m]/1000
            };
            val high=extreme(values);
            val low=extreme(values,true);
            lines.add("envelope ${members[m].identifier} max ${f(values[high])} ${combinations[high].name} min ${f(values[low])} ${combinations[low].name}")
        };
        for((s,section) in model.sections.withIndex()) {
            var count=0;
            var length=0.0;
            for(m in members.indices)if(choices[m]==s) {
                count++;
                length+=geometry[m].length
            };
            if(count>0)lines.add("section ${section.name} members $count length ${f(length)}")
        };
        lines.add("weight ${f(weight/1000)}");
        return lines
    }
    fun magnitudes(result: Postprocess.Result)=DoubleArray(nodes.size) {
        n->val x=result.displacement[nodeDofs[n][0]];
        val y=result.displacement[nodeDofs[n][1]];
        sqrt(x*x+y*y)
    }
    fun resultSummary(kind: String,result: Postprocess.Result): String {
        val magnitudes=TrussSolver.magnitudes(result);
        val node=extreme(magnitudes);
        var energy=0.0;
        for(m in members.indices) {
            val force=result.forces[m];
            val g=geometry[m];
            val p=properties[m];
            energy+=force*force*g.length/(2*p.young*p.area)
        };
        energy/=1000;
        val reactions=DoubleArray(2);
        val loads=DoubleArray(2);
        for(axis in 0..1) {
            for(n in nodes.indices)reactions[axis]+=result.reactions[nodeDofs[n][axis]];
            reactions[axis]/=1000;
            for(n in nodes.indices)loads[axis]+=result.external[nodeDofs[n][axis]];
            loads[axis]/=1000
        };
        var scale=1.0;
        for(value in result.external)scale=maxOf(scale,abs(value));
        for(value in result.reactions)scale=maxOf(scale,abs(value));
        val equilibrium=if(Postprocess.equilibrium(result,geometry)<=0.000001*scale)"ok" else "failed";
        return "$kind ${result.name} equilibrium $equilibrium max_displacement ${f(magnitudes[node])} at ${nodes[node].identifier} energy ${f(energy)} reactions ${f(reactions[0])} ${f(reactions[1])} loads ${f(loads[0])} ${f(loads[1])}"
    }
    fun analysisReport(): List<String> {
        val before=metrics(IntArray(nodes.size) {
            it
        });
        val after=metrics(numbers);
        val lines=mutableListOf("model nodes ${nodes.size} members ${members.size} supports ${model.supports.size} free_dofs ${free.size} restrained_dofs ${restrained.size} indeterminacy ${members.size+restrained.size-2*nodes.size}",
            "renumbering "+order.joinToString(" ") {
            nodes[it].identifier.toString()
        },"bandwidth before ${before.bandwidth} after ${after.bandwidth}","profile before ${before.profile} after ${after.profile}");
        for((m,member) in members.withIndex()) {
            val g=geometry[m];
            lines.add("member ${member.identifier} nodes ${nodes[member.start].identifier} ${nodes[member.end].identifier} length ${f(g.length)} cos ${real(g.cosine,6)} sin ${real(g.sine,6)}")
        };
        for(entry in resultOrder)lines.add(resultSummary(entry.kind,results.getValue(entry.name)));
        for(support in supportDirections) {
            val values=DoubleArray(combinations.size) {
                combinations[it].reactions[support.degree]/1000
            };
            val high=extreme(values);
            val low=extreme(values,true);
            var line="reaction_envelope ${nodes[support.node].identifier} ${"xy"[support.axis]} max ${f(values[high])} ${combinations[high].name} min ${f(values[low])} ${combinations[low].name}";
            if(support.axis==1)line+=" uplift ${yes(values.any{it<0})}";
            lines.add(line)
        };
        val displacements=combinations.map {
            magnitudes(it)
        };
        for(n in nodes.indices) {
            val values=DoubleArray(combinations.size) {
                displacements[it][n]
            };
            val high=extreme(values);
            lines.add("displacement_envelope ${nodes[n].identifier} max ${f(values[high])} ${combinations[high].name}")
        };
        lines.addAll(deflectionReport());
        lines.addAll(removalReport());
        return lines
    }
    fun deflectionReport(): List<String> {
        val result=results.getValue(settings.deflection);
        val fixed=supportDirections.filter {
            it.axis==1
        }.map {
            it.node
        }.toSet();
        val anchors=settings.deck.indices.filter {
            settings.deck[it] in fixed
        };
        val lines=mutableListOf<String>();
        for(span in 0 until anchors.size-1) {
            val first=anchors[span];
            val last=anchors[span+1];
            val left=settings.deck[first];
            val right=settings.deck[last];
            val xa=deckX[first];
            val xb=deckX[last];
            val va=result.displacement[nodeDofs[left][1]];
            val vb=result.displacement[nodeDofs[right][1]];
            val deflections=DoubleArray(last-first-1) {
                k->val i=first+1+k;
                abs(result.displacement[nodeDofs[settings.deck[i]][1]]-(va+(vb-va)*(deckX[i]-xa)/(xb-xa)))
            };
            val chosen=extreme(deflections);
            val node=settings.deck[first+1+chosen];
            val maximum=deflections[chosen];
            val limit=(xb-xa).toDouble()/settings.deflectionRatio;
            lines.add("deflection ${settings.deflection} span ${nodes[left].identifier} ${nodes[right].identifier} max ${f(maximum)} at ${nodes[node].identifier} limit ${f(limit)} ${if(maximum<=limit)"ok" else "exceeded"}");
            val unitResult=unit(node);
            var virtual=0.0;
            for(m in members.indices) {
                val p=properties[m];
                virtual+=result.forces[m]*(unitResult.forces[m]/1000)*geometry[m].length/(p.young*p.area)
            };
            val stiffness=-result.displacement[nodeDofs[node][1]];
            val verified=if(abs(virtual-stiffness)<=0.000001*maxOf(1.0,abs(stiffness)))"ok" else "failed";
            lines.add("virtual_work ${settings.deflection} node ${nodes[node].identifier} stiffness ${f(stiffness)} virtual ${f(virtual)} $verified")
        };
        return lines
    }
    fun removalReport(): List<String> {
        val combination=combinationDefinitions.getValue(settings.removal);
        val lines=mutableListOf<String>();
        for(removed in members.indices) {
            val system=TrussSolver.system(choices,removed);
            if(system.unstable>=0) {
                val degree=system.unstable;
                lines.add("removal ${members[removed].identifier} unstable at ${nodes[ownerNode[degree]].identifier} ${"xy"[ownerAxis[degree]]}");
                continue
            };
            val result=analyze(system,combination).getValue(combination.name);
            val remaining=members.indices.filter {
                it!=removed
            };
            val values=DoubleArray(remaining.size) {
                val m=remaining[it];
                Design.utilization(result.forces[m],system.properties[m],geometry[m])
            };
            val largest=extreme(values);
            val magnitudes=TrussSolver.magnitudes(result);
            val node=extreme(magnitudes);
            lines.add("removal ${members[removed].identifier} stable max_utilization ${f(values[largest])} at ${members[remaining[largest]].identifier} max_displacement ${f(magnitudes[node])} at ${nodes[node].identifier}")
        };
        return lines
    }
    fun ordinate(ordinates: DoubleArray,position: Int): Double {
        if(position<deckX.first()||position>deckX.last())return 0.0;
        if(position==deckX.last())return ordinates.last();
        var index=0;
        while(deckX[index+1]<=position)index++;
        val first=deckX[index];
        val last=deckX[index+1];
        return ordinates[index]+(ordinates[index+1]-ordinates[index])*(position-first)/(last-first)
    }
    fun vehicleRange(ordinates: DoubleArray,positions: List<Int>): Range {
        val effects=DoubleArray(positions.size);
        for((i,position) in positions.withIndex())for(axle in settings.axles)effects[i]+=axle.load*ordinate(ordinates,
            position-axle.offset);
        val high=extreme(effects);
        val low=extreme(effects,true);
        return Range(effects[high],positions[high],effects[low],positions[low])
    }
    fun influenceReport(): List<String> {
        val memberOrdinates=Array(members.size) {
            DoubleArray(settings.deck.size)
        };
        val reactionOrdinates=Array(degrees) {
            DoubleArray(settings.deck.size)
        };
        for((k,node) in settings.deck.withIndex()) {
            val result=unit(node);
            for(m in members.indices)memberOrdinates[m][k]=result.forces[m]/1000;
            for(support in supportDirections)reactionOrdinates[support.degree][k]=result.reactions[support.degree]/1000
        };
        val lines=mutableListOf<String>();
        for(m in settings.influence) {
            val ordinates=memberOrdinates[m];
            lines.add("influence ${members[m].identifier}");
            for((k,ordinate) in ordinates.withIndex())lines.add("node ${nodes[settings.deck[k]].identifier} ${f(ordinate)}");
            val high=extreme(ordinates);
            val low=extreme(ordinates,true);
            var positive=0.0;
            var negative=0.0;
            for(value in ordinates)if(value>0)positive+=value else if(value<0)negative+=value;
            lines.add("max ${f(ordinates[high])} at ${nodes[settings.deck[high]].identifier} min ${f(ordinates[low])} at ${nodes[settings.deck[low]].identifier} positive ${f(positive)} negative ${f(negative)}");
            val crossings=mutableListOf<Double>();
            for(k in 0 until ordinates.size-1) {
                val a=ordinates[k];
                val b=ordinates[k+1];
                if((a>0&&b<0)||(a<0&&b>0))crossings.add(deckX[k]+(deckX[k+1]-deckX[k])*a/(a-b))
            };
            lines.add("crossings ${crossings.size}"+if(crossings.isEmpty())"" else " "+crossings.joinToString(" ") {
                real(it,1)
            })
        };
        val positions=(deckX.first()..deckX.last()+settings.axles.last().offset step settings.vehicleStep).toList();
        lines.add("vehicle axles ${settings.axles.size} positions ${positions.size}");
        val memberRanges=mutableListOf<Range>();
        for((m,member) in members.withIndex()) {
            val range=vehicleRange(memberOrdinates[m],positions);
            memberRanges.add(range);
            lines.add("vehicle_member ${member.identifier} max ${f(range.maximum)} at ${range.highPosition} min ${f(range.minimum)} at ${range.lowPosition}")
        };
        for(support in supportDirections) {
            val range=vehicleRange(reactionOrdinates[support.degree],positions);
            lines.add("vehicle_reaction ${nodes[support.node].identifier} ${"xy"[support.axis]} max ${f(range.maximum)} at ${range.highPosition} min ${f(range.minimum)} at ${range.lowPosition}")
        };
        val dead=results.getValue(settings.rating);
        val ratings=mutableListOf<Rating>();
        for(m in members.indices) {
            val range=memberRanges[m];
            val p=properties[m];
            val g=geometry[m];
            val deadForce=dead.forces[m]/1000;
            val tensionCapacity=p.area*p.yieldStress/1000;
            val compressionCapacity=minOf(p.area*p.yieldStress,Design.buckling(p,g))/1000;
            var tension="none";
            var compression="none";
            if(rounded(range.maximum)>0) {
                val rating=(tensionCapacity-settings.deadFactor*deadForce)/(settings.vehicleFactor*range.maximum);
                tension=f(rating);
                ratings.add(Rating(m,"tension",rating))
            };
            if(rounded(range.minimum)<0) {
                val rating=(compressionCapacity+settings.deadFactor*deadForce)/(settings.vehicleFactor*(-range.minimum));
                compression=f(rating);
                ratings.add(Rating(m,"compression",rating))
            };
            lines.add("rating ${members[m].identifier} tension $tension compression $compression")
        };
        var minimum=ratings.first();
        for(rating in ratings)if(rounded(rating.value)<rounded(minimum.value))minimum=rating;
        lines.add("rating_min ${f(minimum.value)} at ${members[minimum.member].identifier} ${minimum.kind}");
        return lines
    }
    fun vibrationReport(): List<String> {
        val result=results.getValue(settings.vibration);
        val masses=DoubleArray(nodes.size) {
            -result.external[nodeDofs[it][1]]/9.81
        };
        val freeMasses=DoubleArray(free.size) {
            masses[ownerNode[free[it]]]
        };
        val size=free.size;
        val modes=mutableListOf<DoubleArray>();
        val lines=mutableListOf("vibration ${settings.vibration} mass ${f(total(masses))} iterations ${settings.iterations}");
        for(mode in 1..settings.modeCount) {
            val vector=DoubleArray(size) {
                1.0
            };
            repeat(settings.iterations) {
                for(previous in modes) {
                    var beta=0.0;
                    for(i in 0 until size)beta+=previous[i]*freeMasses[i]*vector[i];
                    for(i in 0 until size)vector[i]=vector[i]-beta*previous[i]
                };
                val right=DoubleArray(size) {
                    freeMasses[it]*vector[it]
                };
                val solution=Solver.solve(finalSystem.lower!!,right);
                var norm=0.0;
                for(i in 0 until size)norm+=freeMasses[i]*solution[i]*solution[i];
                norm=sqrt(norm);
                for(i in 0 until size)vector[i]=solution[i]/norm
            };
            modes.add(vector);
            val stiffnessProduct=DoubleArray(size);
            for(i in 0 until size)for(j in 0 until size)stiffnessProduct[i]+=finalSystem.freeMatrix[i][j]*vector[j];
            var numerator=0.0;
            var denominator=0.0;
            for(i in 0 until size)numerator+=vector[i]*stiffnessProduct[i];
            for(i in 0 until size)denominator+=freeMasses[i]*vector[i]*vector[i];
            val eigenvalue=numerator/denominator;
            val frequency=sqrt(1000*eigenvalue)/(2*Design.PI);
            lines.add("mode $mode frequency ${f(frequency)} period ${f(1/frequency)}");
            var peak=0;
            for(i in 1 until size)if(abs(vector[i])>abs(vector[peak]))peak=i;
            val normalized=DoubleArray(degrees);
            for(i in 0 until size)normalized[free[i]]=vector[i]/vector[peak];
            for(n in nodes.indices)lines.add("node ${nodes[n].identifier} ${f(normalized[nodeDofs[n][0]])} ${f(normalized[nodeDofs[n][1]])}")
        };
        return lines
    }
    class Canvas(val horizontal: Int,val vertical: Int) {
        val x0=TrussSolver.nodes.minOf {
            it.x
        };
        val x1=TrussSolver.nodes.maxOf {
            it.x
        };
        val y0=TrussSolver.nodes.minOf {
            it.y
        };
        val y1=TrussSolver.nodes.maxOf {
            it.y
        };
        val width=floor((x1-x0).toDouble()/horizontal+0.5).toInt()+5;
        val height=floor((y1-y0).toDouble()/vertical+0.5).toInt()+5;
        val grid=Array(height) {
            CharArray(width) {
                ' '
            }
        };
        fun position(x: Double,y: Double)=Point(floor((x-x0)/horizontal+0.5).toInt()+2,floor((y1-y)/vertical+0.5).toInt()+2);
        fun put(point: Point,character: Char) {
            if(point.column in 0 until width&&point.row in 0 until height)grid[point.row][point.column]=character
        };
        fun line(first: Point,last: Point,character: Char) {
            var column=first.column;
            var row=first.row;
            val dc=abs(last.column-column);
            val dr=-abs(last.row-row);
            val sc=if(column<last.column)1 else -1;
            val sr=if(row<last.row)1 else -1;
            var error=dc+dr;
            while(true) {
                put(Point(column,row),character);
                if(column==last.column&&row==last.row)break;
                val twice=2*error;
                if(twice>=dr) {
                    error+=dr;
                    column+=sc
                };
                if(twice<=dc) {
                    error+=dc;
                    row+=sr
                }
            }
        };
        fun framed(): List<String> {
            val border="+"+"-".repeat(width)+"+";
            return listOf(border)+grid.map {
                "|"+it.concatToString()+"|"
            }+listOf(border)
        }
    }
    fun drawingReport(): List<String> {
        val lines=mutableListOf<String>();
        for(drawing in settings.drawings) {
            val result=results.getValue(drawing.name);
            val canvas=Canvas(drawing.horizontal,drawing.vertical);
            val original=nodes.map {
                canvas.position(it.x.toDouble(),it.y.toDouble())
            };
            val deformed=nodes.mapIndexed {
                n,node->canvas.position(node.x+drawing.magnification*result.displacement[nodeDofs[n][0]],
                    node.y+drawing.magnification*result.displacement[nodeDofs[n][1]])
            };
            for(member in members)canvas.line(original[member.start],original[member.end],'.');
            for(point in original)canvas.put(point,'+');
            for(member in members)canvas.line(deformed[member.start],deformed[member.end],'*');
            for(point in deformed)canvas.put(point,'o');
            lines.add("drawing ${drawing.name} magnification ${drawing.magnification} columns ${canvas.width} rows ${canvas.height}");
            lines.addAll(canvas.framed())
        };
        val canvas=Canvas(settings.mapHorizontal,settings.mapVertical);
        val positions=nodes.map {
            canvas.position(it.x.toDouble(),it.y.toDouble())
        };
        for((m,member) in members.withIndex()) {
            val character=if(governing[m]>=1)'#' else ('0'.code+floor(10*governing[m]).toInt()).toChar();
            canvas.line(positions[member.start],positions[member.end],character)
        };
        for(point in positions)canvas.put(point,'o');
        lines.add("utilization_map columns ${canvas.width} rows ${canvas.height}");
        lines.addAll(canvas.framed());
        return lines
    }
    fun csvReports() {
        val displacementLines=mutableListOf("case,node,dx,dy");
        val forceLines=mutableListOf("case,member,force,stress,utilization");
        val reactionLines=mutableListOf("case,node,rx,ry");
        for(entry in resultOrder) {
            val name=entry.name;
            val result=results.getValue(name);
            for((n,node) in nodes.withIndex())displacementLines.add("$name,${node.identifier},${f(result.displacement[nodeDofs[n][0]])},${f(result.displacement[nodeDofs[n][1]])}");
            for((m,member) in members.withIndex()) {
                val force=result.forces[m];
                val p=properties[m];
                forceLines.add("$name,${member.identifier},${f(force/1000)},${f(force/p.area)},${f(Design.utilization(force,p,geometry[m]))}")
            };
            for(support in model.supports)reactionLines.add("$name,${nodes[support.node].identifier},${f(result.reactions[nodeDofs[support.node][0]]/1000)},${f(result.reactions[nodeDofs[support.node][1]]/1000)}")
        };
        write("displacements.csv",displacementLines);
        write("member_forces.csv",forceLines);
        write("reactions.csv",reactionLines)
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
    @JvmStatic fun main(args: Array<String>) {
        prepare(ModelIo.read());
        val history=designSections();
        csvReports();
        write("analysis.txt",analysisReport());
        write("design.txt",designReport(history));
        write("influence.txt",influenceReport());
        write("drawing.txt",drawingReport());
        write("vibration.txt",vibrationReport())
    }
}
