import java.io.File
import java.util.ArrayDeque
import java.util.PriorityQueue
private val classes=listOf("cardinal","semi_cardinal","non_cardinal")
private data class Definition(val solver:String,val function:String) {
    val name get()="$solver-$function"
}
private data class Delay(val agent:Int,val start:Int,val duration:Int)
private class Settings(count:Int) {
    var horizon=0;
    var hlBudget=0;
    var llBudget=0;
    var window=0;
    var step=0;
    var frames=0;
    var animate="";
    val orders=mutableListOf((0 until count).toList());
    val runs=mutableListOf<Definition>();
    val delays=mutableListOf<Delay>()
    init {
        for(line in File("input/params.txt").readLines(Charsets.US_ASCII)) {
            val f=line.split(' ');
            when(f[0]) {
                "HORIZON"->horizon=f[1].toInt();
                "HL_BUDGET"->hlBudget=f[1].toInt();
                "LL_BUDGET"->llBudget=f[1].toInt();
                "WINDOW"-> {
                    window=f[1].toInt();
                    step=f[2].toInt()
                };
                "ORDER"->orders.add(f.drop(1).map {
                    it.toInt()
                });
                "RUN"->runs.add(Definition(f[1],f[2]));
                "ANIMATE"-> {
                    animate=f[1];
                    frames=f[2].toInt()
                };
                "DELAY"->delays.add(Delay(f[1].toInt(),f[2].toInt(),f[3].toInt()))
            }
        }
    }
}
private data class AgentInfo(val shortest:Int,val states:Int,val width:Int)
private data class Split(val conflict:Cbs.Conflict,val category:String?)
private data class PathStats(val cost:Int,val extra:Int,val waits:Int,val turns:Int,val arrive:Int,val leave:Int,
    val actions:String)
private class Metrics {
    var soc=0;
    var makespan=0;
    var cost=0;
    var sumExtra=0;
    var maxExtra=0;
    var waits=0;
    var turns=0;
    var ratio="";
    val agents=mutableListOf<PathStats>();
    val arrivals=mutableListOf<Int>();
    val traffic=mutableMapOf<GridMap.Cell,Int>();
    val cellWaits=mutableMapOf<GridMap.Cell,Int>();
    var hotspots=listOf<GridMap.Cell>()
}
private data class Validation(val start:Int,val goal:Int,val moves:Int,val vertex:Int,val edge:Int,val follows:Int,
    val conflicts:List<Cbs.Conflict>) {
    val verdict get()=if(start+goal+moves+vertex+edge==0)"VALID" else "INVALID"
}
private data class Step(val time:Int,val cell:GridMap.Cell)
private data class Prerequisite(val agent:Int,val step:Int)
private data class Execution(val deadlock:Int?,val blocked:Int,val finish:List<Int>,val soc:Int,val makespan:Int)
private class Run(val definition:Definition,limit:Int) {
    var status="FAIL";
    var reason:String?=null;
    var end="";
    var paths:List<List<GridMap.Cell>>?=null;
    var highLevel=0;
    var generated:Int?=null;
    val budget=LowLevel.Budget(limit);
    val specific=mutableListOf<String>();
    val trace=mutableListOf<String>();
    var metrics:Metrics?=null;
    var validation:Validation?=null;
    var execution:Execution?=null;
    val name get()=definition.name
}
private class Planner {
    val grid=GridMap();
    val agents=GridMap.agents();
    val settings=Settings(agents.size);
    val distances=agents.map {
        grid.distances(it.goal)
    };
    val independent=mutableListOf<List<GridMap.Cell>>();
    val info=mutableListOf<AgentInfo>();
    var independentConflicts=listOf<Cbs.Conflict>();
    val independentClasses=mutableMapOf<Cbs.Conflict,String>();
    val results=mutableListOf<Run>();
    var socLower=0;
    var makespanLower=0;
    var components=0;
    val degrees=IntArray(4);
    val groups=mutableListOf<String>()
    init {
        val budget=LowLevel.Budget(null);
        for((id,agent) in agents.withIndex())independent.add(LowLevel.search(grid,agent,distances[id],
            agent.start,0,LowLevel.Prohibitions(),settings.horizon,budget,false).path!!);
        overview()
    }
    fun mdd(id:Int,length:Int,restrictions:LowLevel.Prohibitions):List<Set<GridMap.Cell>> {
        val layers=mutableListOf(setOf(agents[id].start));
        for(time in 1..length) {
            val next=mutableSetOf<GridMap.Cell>();
            for(source in layers.last())for(destination in grid.destinations(source))if(time+distances[id].getOrDefault(destination,
                length+1)<=length&&restrictions.actionAllowed(source,destination,time))next.add(destination);
            layers.add(next)
        }
        val valid=List(length+1) {
            mutableSetOf<GridMap.Cell>()
        };
        valid.last().add(agents[id].goal);
        for(time in length-1 downTo 0)for(source in layers[time])for(destination in grid.destinations(source))if(destination in valid[time+1]&&restrictions.actionAllowed(source,
            destination,time+1)) {
            valid[time].add(source);
            break
        };
        return valid
    }
    fun conflictClass(conflict:Cbs.Conflict,paths:List<List<GridMap.Cell>>,restrictions:List<LowLevel.Prohibitions>,
        cache:MutableMap<Int,List<Set<GridMap.Cell>>>):String {
        var fixed=0;
        for(id in listOf(conflict.a,conflict.b)) {
            val length=paths[id].size-1;
            val layers=cache.getOrPut(id) {
                mdd(id,length,restrictions[id])
            };
            val time=conflict.time;
            val forced=time>length||layers[time].size==1&&(conflict.kind=="vertex"||layers[time-1].size==1);
            if(forced)fixed++
        }
        return classes[2-fixed]
    }
    fun emptyRestrictions()=List(agents.size) {
        LowLevel.Prohibitions()
    }
    fun overview() {
        for(cell in grid.free)degrees[minOf(3,grid.neighbors(cell).size)]++;
        val remaining=grid.free.toMutableSet();
        while(remaining.isNotEmpty()) {
            components++;
            val queue=ArrayDeque<GridMap.Cell>();
            val seed=remaining.first();
            remaining.remove(seed);
            queue.add(seed);
            while(queue.isNotEmpty())for(next in grid.neighbors(queue.remove()))if(remaining.remove(next))queue.add(next)
        }
        for(id in agents.indices) {
            val shortest=distances[id].getValue(agents[id].start);
            val layers=mdd(id,shortest,LowLevel.Prohibitions());
            info.add(AgentInfo(shortest,layers.sumOf {
                it.size
            },layers.maxOf {
                it.size
            }));
            socLower+=shortest;
            makespanLower=maxOf(makespanLower,shortest)
        }
        independentConflicts=Cbs.conflicts(independent);
        val restrictions=emptyRestrictions();
        val cache=mutableMapOf<Int,List<Set<GridMap.Cell>>>();
        val adjacent=List(agents.size) {
            sortedSetOf<Int>()
        };
        for(conflict in independentConflicts) {
            independentClasses[conflict]=conflictClass(conflict,independent,restrictions,cache);
            adjacent[conflict.a].add(conflict.b);
            adjacent[conflict.b].add(conflict.a)
        }
        val seen=mutableSetOf<Int>();
        for(start in agents.indices) {
            if(start in seen||adjacent[start].isEmpty())continue;
            val component=sortedSetOf<Int>();
            val queue=ArrayDeque<Int>();
            queue.add(start);
            seen.add(start);
            while(queue.isNotEmpty()) {
                val current=queue.remove();
                component.add(current);
                for(next in adjacent[current])if(seen.add(next))queue.add(next)
            }
            groups.add(component.joinToString("") {
                Report.name(it).toString()
            })
        }
    }
    fun solvePp(run:Run) {
        var answer=0;
        for((index,order) in settings.orders.withIndex()) {
            val orderNumber=index+1;
            run.highLevel++;
            val before=run.budget.expansions;
            val result=Prioritized.tryOrder(grid,agents,distances,settings.horizon,order,run.budget);
            for(attempt in result.attempts) {
                val search=attempt.search;
                val prefix="order $orderNumber agent ${Report.name(attempt.agent)}";
                run.trace.add(prefix+(if(search.path==null)" failed" else " cost ${search.path.size-1}")+" expansions ${search.expansions}")
            }
            if(result.aborted) {
                run.reason="ll_budget";
                break
            }
            val names=order.joinToString("") {
                Report.name(it).toString()
            };
            val planned=result.attempts.size-if(result.failed==null)0 else 1;
            val summary="order $orderNumber $names planned $planned expansions ${run.budget.expansions-before}";
            if(result.failed==null) {
                run.specific.add("$summary ok");
                run.paths=result.paths;
                run.status="OK";
                answer=orderNumber;
                break
            }
            run.specific.add("$summary failed ${Report.name(result.failed)}")
        }
        if(run.status=="OK")run.end="end OK order $answer" else {
            run.reason=run.reason?:"orders";
            run.end="end FAIL ${run.reason}"
        }
    }
    fun applyConstraint(base:List<LowLevel.Prohibitions>,addition:Cbs.Constraint):List<LowLevel.Prohibitions> {
        val copied=base.toMutableList();
        val changed=base[addition.agent].copy();
        if(addition.kind=="vertex")changed.states.add(LowLevel.State(addition.v,addition.time)) else changed.moves.add(LowLevel.Move(addition.u,
            addition.v,addition.time));
        copied[addition.agent]=changed;
        return copied
    }
    fun chooseSplit(node:Cbs.Node,run:Run):Split {
        if(run.definition.solver=="CBS")return Split(node.conflicts.first(),null);
        val cache=mutableMapOf<Int,List<Set<GridMap.Cell>>>();
        var best:Cbs.Conflict?=null;
        var category:String?=null;
        var earliest=3;
        for(conflict in node.conflicts) {
            val candidate=conflictClass(conflict,node.paths,node.constraints,cache);
            val rank=classes.indexOf(candidate);
            if(rank<earliest) {
                earliest=rank;
                best=conflict;
                category=candidate
            }
        }
        return Split(best!!,category)
    }
    fun solveCbs(run:Run) {
        val empty=emptyRestrictions();
        val paths=mutableListOf<List<GridMap.Cell>>();
        try {
            for(id in agents.indices)paths.add(LowLevel.search(grid,agents[id],distances[id],agents[id].start,
                0,empty[id],settings.horizon,run.budget,false).path!!)
        }catch(exception:LowLevel.BudgetExceeded) {
            run.reason="ll_budget";
            run.generated=0;
            run.specific.add("search expanded 0 generated 0 pruned 0 open 0");
            if(run.definition.solver=="ICBS")run.specific.add("classes cardinal 0 semi_cardinal 0 non_cardinal 0");
            run.end="end FAIL ll_budget";
            return
        }
        val root=Cbs.Node(paths,empty,0,0,null,run.definition.function);
        val open=PriorityQueue(Cbs.order);
        open.add(root);
        var generated=1;
        var expanded=0;
        var pruned=0;
        val classifications=IntArray(3);
        var reason:String?="exhausted";
        var answer:Cbs.Node?=null;
        while(open.isNotEmpty()) {
            val node=open.remove();
            if(node.conflicts.isEmpty()) {
                answer=node;
                reason=null;
                break
            }
            if(expanded==settings.hlBudget) {
                reason="hl_budget";
                break
            }
            expanded++;
            val split=chooseSplit(node,run);
            val conflict=split.conflict;
            split.category?.let {
                classifications[classes.indexOf(it)]++
            };
            val created=mutableListOf<String>();
            var aborted=false;
            for(branch in Cbs.split(conflict)) {
                val id=branch.agent;
                val restrictions=applyConstraint(node.constraints,branch);
                val search=try {
                    LowLevel.search(grid,agents[id],distances[id],agents[id].start,0,restrictions[id],
                        settings.horizon,run.budget,false)
                }catch(exception:LowLevel.BudgetExceeded) {
                    aborted=true;
                    break
                };
                val childPath=search.path;
                if(childPath==null) {
                    pruned++;
                    created.add("-");
                    continue
                }
                val newPaths=node.paths.toMutableList();
                newPaths[id]=childPath;
                val child=Cbs.Node(newPaths,restrictions,generated,node.depth+1,node.number,run.definition.function);
                open.add(child);
                created.add((generated++).toString())
            }
            if(aborted) {
                reason="ll_budget";
                break
            }
            var text="expand $expanded node ${node.number} parent ${node.parent?:"-"} depth ${node.depth} cost ${node.cost} conflicts ${node.conflicts.size} split ${Report.conflict(conflict)}";
            if(split.category!=null)text+=" class ${split.category}";
            run.trace.add("$text children ${created[0]} ${created[1]}")
        }
        run.highLevel=expanded;
        run.generated=generated;
        run.specific.add("search expanded $expanded generated $generated pruned $pruned open ${open.size}");
        if(run.definition.solver=="ICBS")run.specific.add("classes cardinal ${classifications[0]} semi_cardinal ${classifications[1]} non_cardinal ${classifications[2]}");
        val solution=answer;
        if(solution==null) {
            run.reason=reason;
            run.end="end FAIL $reason";
            return
        }
        run.status="OK";
        run.paths=solution.paths;
        run.specific.add("solution node ${solution.number} depth ${solution.depth}");
        for(c in Cbs.orderedConstraints(solution))run.specific.add("constraint ${Report.name(c.agent)} ${c.kind} ${c.u}"+(if(c.kind=="vertex")"" else " ${c.v}")+" t ${c.time}");
        run.end="end OK node ${solution.number} cost ${solution.cost}"
    }
    fun solveWhca(run:Run) {
        val current=agents.map {
            it.start
        }.toMutableList();
        val executed=agents.map {
            mutableListOf(it.start)
        };
        var time=0;
        var rounds=0;
        var reason:String?=null;
        while(true) {
            if(agents.indices.all {
                current[it]==agents[it].goal
            })break;
            if(time>=settings.horizon) {
                reason="timeout";
                break
            }
            rounds++;
            val restrictions=LowLevel.Prohibitions();
            val order=listOf(false,true).flatMap {
                atGoal->agents.indices.filter {
                    (current[it]==agents[it].goal)==atGoal
                }
            };
            val plans=mutableMapOf<Int,List<GridMap.Cell>>();
            var failed=false;
            for(id in order) {
                val search=try {
                    LowLevel.search(grid,agents[id],distances[id],current[id],time,restrictions,time+settings.window,
                        run.budget,true)
                }catch(exception:LowLevel.BudgetExceeded) {
                    reason="ll_budget";
                    failed=true;
                    break
                };
                val prefix="round $rounds time $time agent ${Report.name(id)}";
                val path=search.path;
                if(path==null) {
                    run.trace.add("$prefix blocked expansions ${search.expansions}");
                    reason="blocked";
                    failed=true;
                    break
                }
                val extended=path.toMutableList();
                while(extended.size<settings.window+1)extended.add(extended.last());
                plans[id]=extended;
                run.trace.add("$prefix moves ${Report.actions(extended)} expansions ${search.expansions}");
                LowLevel.reserve(restrictions,extended,time,false)
            }
            if(failed)break;
            for(id in agents.indices) {
                val plan=plans.getValue(id);
                executed[id].addAll(plan.subList(1,settings.step+1));
                current[id]=plan[settings.step]
            }
            time+=settings.step
        }
        run.highLevel=rounds;
        run.specific.add("window ${settings.window} step ${settings.step} rounds $rounds");
        if(reason!=null) {
            run.reason=reason;
            run.end="end FAIL $reason"
        }else {
            run.status="OK";
            for(id in agents.indices) {
                val path=executed[id];
                val goal=agents[id].goal;
                while(path.size>1&&path.last()==goal&&path[path.size-2]==goal)path.removeAt(path.lastIndex)
            }
            run.paths=executed;
            run.end="end OK rounds $rounds"
        }
    }
    fun validate(paths:List<List<GridMap.Cell>>):Validation {
        var start=0;
        var goal=0;
        var moves=0;
        for(id in agents.indices) {
            val path=paths[id];
            if(path.first()!=agents[id].start)start++;
            if(path.last()!=agents[id].goal)goal++;
            for(t in 1 until path.size)if(path[t] !in grid.destinations(path[t-1]))moves++
        }
        val collisions=Cbs.conflicts(paths);
        val vertex=collisions.count {
            it.kind=="vertex"
        };
        val edge=collisions.size-vertex;
        var follows=0;
        val horizon=Cbs.cost(paths,"MAKESPAN");
        for(time in 1..horizon)for(a in paths.indices) {
            val pastA=Cbs.position(paths[a],time-1);
            val nextA=Cbs.position(paths[a],time);
            if(nextA==pastA)continue;
            for(b in paths.indices)if(a!=b&&nextA==Cbs.position(paths[b],time-1)&&Cbs.position(paths[b],
                time)!=pastA)follows++
        }
        return Validation(start,goal,moves,vertex,edge,follows,collisions)
    }
    fun pathStats(path:List<GridMap.Cell>,id:Int):PathStats {
        var waits=0;
        var turns=0;
        var leave=0;
        var previous:Char?=null;
        val actions=Report.actions(path);
        val goal=agents[id].goal;
        val arrive=path.indexOf(goal);
        for(t in 1 until path.size) {
            val action=actions[t-1];
            if(action=='.')waits++ else {
                if(previous!=null&&previous!=action)turns++;
                previous=action
            }
            if(path[t-1]==goal&&path[t]!=goal)leave++
        }
        val cost=path.size-1;
        return PathStats(cost,cost-info[id].shortest,waits,turns,arrive,leave,actions)
    }
    fun metrics(paths:List<List<GridMap.Cell>>,function:String):Metrics {
        val result=Metrics();
        result.soc=Cbs.cost(paths,"SOC");
        result.makespan=Cbs.cost(paths,"MAKESPAN");
        result.cost=if(function=="SOC")result.soc else result.makespan;
        result.ratio=Report.fraction(result.cost,if(function=="SOC")socLower else makespanLower);
        for(id in agents.indices) {
            val path=paths[id];
            val stats=pathStats(path,id);
            result.agents.add(stats);
            result.sumExtra+=stats.extra;
            result.maxExtra=maxOf(result.maxExtra,stats.extra);
            result.waits+=stats.waits;
            result.turns+=stats.turns;
            for(cell in path.toSet())result.traffic[cell]=result.traffic.getOrDefault(cell,0)+1;
            for(t in 1 until path.size)if(path[t]==path[t-1])result.cellWaits[path[t]]=result.cellWaits.getOrDefault(path[t],
                0)+1
        }
        for(time in 0..result.makespan)result.arrivals.add(paths.count {
            it.size-1<=time
        });
        result.hotspots=result.traffic.keys.sortedWith(compareByDescending<GridMap.Cell> {
            result.traffic.getValue(it)
        }.thenBy {
            it.y
        }.thenBy {
            it.x
        }).take(5);
        return result
    }
    fun delayedExecution(paths:List<List<GridMap.Cell>>):Execution {
        val steps=paths.map {
            path->val entries=mutableListOf(Step(0,path.first()));
            for(time in 1 until path.size)if(path[time]!=path[time-1])entries.add(Step(time,path[time]));
            entries
        };
        val prerequisites=steps.mapIndexed {
            i,entries->entries.map {
                target->val required=mutableListOf<Prerequisite>();
                for(j in paths.indices)if(j!=i)for((k,other) in steps[j].withIndex())if(other.cell==target.cell&&other.time<target.time)required.add(Prerequisite(j,
                    k));
                required
            }
        };
        val progress=IntArray(paths.size);
        val finish=IntArray(paths.size);
        var holds=0;
        var time=0;
        while(true) {
            if(paths.indices.all {
                progress[it]==steps[it].size-1
            })break;
            val advancing=mutableListOf<Int>();
            var stopped=0;
            for(i in paths.indices) {
                if(progress[i]==steps[i].size-1)continue;
                val delayed=settings.delays.any {
                    it.agent==i&&it.start<=time&&time<it.start+it.duration
                };
                if(delayed) {
                    stopped++;
                    continue
                }
                val allowed=prerequisites[i][progress[i]+1].all {
                    progress[it.agent]>it.step
                };
                if(allowed)advancing.add(i) else holds++
            }
            if(advancing.isEmpty()&&stopped==0)return Execution(time,holds,emptyList(),0,0);
            for(i in advancing) {
                progress[i]++;
                if(progress[i]==steps[i].size-1)finish[i]=time+1
            }
            time++
        }
        return Execution(null,holds,finish.toList(),finish.sum(),finish.max())
    }
    fun solve() {
        for(definition in settings.runs) {
            val run=Run(definition,settings.llBudget);
            when(definition.solver) {
                "PP"->solvePp(run);
                "CBS","ICBS"->solveCbs(run);
                else->solveWhca(run)
            }
            if(run.status=="OK") {
                val paths=run.paths!!;
                run.metrics=metrics(paths,definition.function);
                run.validation=validate(paths);
                run.execution=delayedExecution(paths)
            }
            results.add(run)
        }
    }
    fun instanceLines():List<String> {
        val lines=mutableListOf("instance width ${grid.width} height ${grid.height} free ${grid.free.size} agents ${agents.size}",
            "map isolated ${degrees[0]} dead_ends ${degrees[1]} corridors ${degrees[2]} junctions ${degrees[3]} components $components");
        for(id in agents.indices) {
            val agent=agents[id];
            val record=info[id];
            lines.add("agent ${agent.name} start ${agent.start} goal ${agent.goal} distance ${record.shortest} mdd ${record.states} width ${record.width}")
        }
        lines.add("lower_bound soc $socLower makespan $makespanLower");
        val vertex=independentConflicts.count {
            it.kind=="vertex"
        };
        val counts=classes.map {
            category->independentConflicts.count {
                independentClasses[it]==category
            }
        };
        lines.add("independent conflicts ${independentConflicts.size} vertex $vertex edge ${independentConflicts.size-vertex} cardinal ${counts[0]} semi_cardinal ${counts[1]} non_cardinal ${counts[2]}");
        lines.add("groups "+if(groups.isEmpty())"-" else groups.joinToString(" "));
        return lines
    }
    fun successfulLines(run:Run):List<String> {
        val m=run.metrics!!;
        val execution=run.execution!!;
        val lines=mutableListOf("run ${run.name} solver ${run.definition.solver} cost_function ${run.definition.function} result OK cost ${m.cost} soc ${m.soc} makespan ${m.makespan} ratio ${m.ratio}");
        lines.addAll(run.specific);
        for(id in agents.indices) {
            val p=m.agents[id];
            lines.add("agent ${Report.name(id)} cost ${p.cost} extra ${p.extra} waits ${p.waits} turns ${p.turns} arrive ${p.arrive} leave ${p.leave} moves ${p.actions}")
        }
        lines.add("arrivals "+m.arrivals.joinToString(" "));
        lines.add("hotspots "+m.hotspots.joinToString(" ") {
            "$it:${m.traffic.getValue(it)}"
        });
        if(execution.deadlock!=null)lines.add("execution deadlock time ${execution.deadlock}")else lines.add("execution soc ${execution.soc} makespan ${execution.makespan} blocked ${execution.blocked} finish ${execution.finish.joinToString(" ")}");
        return lines
    }
    fun solutionLines():List<String> {
        val lines=instanceLines().toMutableList();
        val succeeded=mutableListOf<Run>();
        for(run in results) {
            lines.add("");
            if(run.status=="OK") {
                lines.addAll(successfulLines(run));
                succeeded.add(run)
            }else {
                lines.add("run ${run.name} solver ${run.definition.solver} cost_function ${run.definition.function} result FAIL reason ${run.reason}");
                lines.addAll(run.specific)
            }
        }
        lines.add("");
        lines.add("summary ok ${succeeded.size} failed ${results.size-succeeded.size}");
        if(succeeded.isNotEmpty()) {
            val bestSoc=succeeded.minOf {
                it.metrics!!.soc
            };
            val bestSpan=succeeded.minOf {
                it.metrics!!.makespan
            };
            lines.add("best_soc $bestSoc "+succeeded.filter {
                it.metrics!!.soc==bestSoc
            }.joinToString(" ") {
                it.name
            });
            lines.add("best_makespan $bestSpan "+succeeded.filter {
                it.metrics!!.makespan==bestSpan
            }.joinToString(" ") {
                it.name
            });
            lines.add("ranking "+succeeded.sortedWith(compareBy<Run> {
                it.metrics!!.soc
            }.thenBy {
                it.metrics!!.makespan
            }).joinToString(" ") {
                it.name
            })
        }
        return lines
    }
    fun statsLines():List<String> {
        val lines=mutableListOf("run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions");
        for(run in results) {
            val fields=mutableListOf(run.name,run.definition.solver,run.definition.function,run.status,run.reason?:"-");
            if(run.status=="OK") {
                val m=run.metrics!!;
                fields.addAll(listOf(m.cost,m.soc,m.makespan,m.sumExtra,m.maxExtra,m.waits,m.turns).map {
                    it.toString()
                });
                val execution=run.execution!!;
                fields.add(if(execution.deadlock==null)execution.soc.toString() else "-");
                fields.add(if(execution.deadlock==null)execution.makespan.toString() else "-")
            }else fields.addAll(List(9) {
                "-"
            });
            fields.add(run.highLevel.toString());
            fields.add(run.generated?.toString()?:"-");
            fields.add(run.budget.searches.toString());
            fields.add(run.budget.expansions.toString());
            lines.add(Report.csv(fields))
        }
        return lines
    }
    fun validationBlock(lines:MutableList<String>,name:String,v:Validation) {
        lines.add("plan $name verdict ${v.verdict} start ${v.start} goal ${v.goal} moves ${v.moves} vertex ${v.vertex} edge ${v.edge} follows ${v.follows}");
        for(conflict in v.conflicts)lines.add("  "+Report.conflict(conflict)+if(name=="INDEPENDENT")" ${independentClasses.getValue(conflict)}" else "")
    }
    fun validationLines():List<String> {
        val lines=mutableListOf<String>();
        validationBlock(lines,"INDEPENDENT",validate(independent));
        for(run in results) {
            val validation=run.validation;
            if(validation==null)lines.add("plan ${run.name} verdict NONE") else validationBlock(lines,run.name,validation)
        }
        return lines
    }
    fun traceLines():List<String> {
        val lines=mutableListOf<String>();
        for(run in results) {
            if(lines.isNotEmpty())lines.add("");
            lines.add("run ${run.name}");
            lines.addAll(run.trace);
            lines.add(run.end)
        }
        return lines
    }
    fun picture(placements:Map<GridMap.Cell,Char>):List<String> {
        val lines=mutableListOf<String>();
        for(y in 0 until grid.height) {
            val row=StringBuilder();
            for(x in 0 until grid.width)row.append(placements[GridMap.Cell(x,y)]?:grid.rows[y][x]);
            lines.add(row.toString())
        }
        return lines
    }
    fun countPicture(counts:Map<GridMap.Cell,Int>)=picture(counts.filterValues {
        it>0
    }.mapValues {
        (_,value)->if(value<=9)('0'.code+value).toChar() else '+'
    })
    fun animationLines():List<String> {
        val selected=results.first {
            it.name==settings.animate
        };
        if(selected.status!="OK")return listOf("run ${selected.name} FAIL");
        val paths=selected.paths!!;
        val metrics=selected.metrics!!;
        val lines=mutableListOf("run ${selected.name} frames ${settings.frames}");
        for(time in 0 until settings.frames) {
            var done=0;
            var moving=0;
            var waiting=0;
            val glyphs=mutableMapOf<GridMap.Cell,Char>();
            for(agent in agents)glyphs[agent.goal]=agent.name.lowercaseChar();
            for(id in agents.indices) {
                val path=paths[id];
                val cell=Cbs.position(path,time);
                glyphs[cell]=Report.name(id);
                if(time>=path.size-1)done++ else if(time>=1&&cell!=Cbs.position(path,time-1))moving++ else waiting++
            }
            lines.add("");
            lines.add("frame $time done $done moving $moving waiting $waiting");
            lines.addAll(picture(glyphs))
        }
        lines.add("");
        lines.add("traffic");
        lines.addAll(countPicture(metrics.traffic));
        lines.add("");
        lines.add("waits");
        lines.addAll(countPicture(metrics.cellWaits));
        return lines
    }
    fun write() {
        Report.write("solutions.txt",solutionLines());
        Report.write("stats.csv",statsLines());
        Report.write("validation.txt",validationLines());
        Report.write("trace.txt",traceLines());
        Report.write("frames.txt",animationLines())
    }
}
fun main() {
    val planner=Planner();
    planner.solve();
    planner.write()
}
