object CPU {
    val CLASSES=arrayOf("ALU","MUL","LOAD","STORE","BRANCH","JUMP","NOP")
    val MISS=arrayOf("direction","btb_miss","wrong_target")
    val USE=arrayOf(intArrayOf(1,1,2),intArrayOf(1,1,1),intArrayOf(1,1,0),intArrayOf(0,1,1),intArrayOf(0,1,2),intArrayOf(2,2,0),intArrayOf(0,0,0))
    data class Instruction(val number: Int,val line: Int,val pc: Int,val kind: Int,val rd: Int,
        val rs1: Int,val rs2: Int,val taken: Boolean,val target: Int,val address: Int) {
        fun control()=kind==4||kind==5
        fun next()=if(taken)target else pc+4
    }
    data class Detail(val predicted: Int,val kind: Int)
    class Prediction(val definition: TraceIO.Predictor,val size: Int) {
        val flags=BooleanArray(size);
        val details=arrayOfNulls<Detail>(size);
        val counts=IntArray(14);
        var bits=0
        fun accuracy(kind: Int): String {
            val i=if(kind==0)0 else if(kind==4)2 else 4;
            return Report.percentage(counts[i]-counts[i+1],counts[i])
        }
    }
    data class Combination(val variant: TraceIO.Variant,val predictor: String,val run: Pipeline.Run)
    data class Dependency(val producer: Int,val waiting: Int,val cause: Int)
    data class Span(val first: Int,val last: Int,val symbol: Char,val stage: Int)
    class Row(val number: Int,val pc: Int,val kind: String,val annotation: String) {
        val spans=mutableListOf<Span>()
        fun add(first: Int,last: Int,symbol: Char,stage: Int) {
            if(first<=last)spans.add(Span(first,last,symbol,stage))
        }
    }
    lateinit var config: TraceIO.Config
    val instructions=mutableListOf<Instruction>()
    val statics=sortedMapOf<Int,Instruction>();
    val groups=sortedMapOf<Int,MutableList<Int>>()
    val rejects=mutableListOf<String>();
    val gaps=mutableListOf<String>();
    val predictions=mutableMapOf<String,Prediction>()
    lateinit var sources: List<List<Hazards.Source>>
    val combinations=mutableListOf<Combination>();
    lateinit var primary: Pipeline.Run;
    var inputLines=0
    fun check(line: String,lineNumber: Int): String? {
        val w=line.split(' ')
        if(w.size!=8||w.any {
            it.isEmpty()
        })return "fields"
        val pc=TraceIO.hex(w[0]);
        if(pc<0||pc%4!=0)return "pc"
        val kind=CLASSES.indexOf(w[1]);
        if(kind<0)return "class"
        val regs=IntArray(3)
        for(i in 0..2) {
            regs[i]=TraceIO.register(w[i+2]);
            if(regs[i]<0&&w[i+2]!="-")return "register"
        }
        for(i in 0..2)if(USE[kind][i]==1&&regs[i]<0||USE[kind][i]==0&&regs[i]>=0)return "operands"
        val control=kind==4||kind==5
        if(if(kind==4)w[5]!="T"&&w[5]!="N" else if(kind==5)w[5]!="T" else w[5]!="-")return "taken"
        val target=TraceIO.hex(w[6])
        if(if(control)target<0||target%4!=0||target==pc+4 else w[6]!="-")return "target"
        val address=TraceIO.hex(w[7])
        if(kind==2||kind==3) {
            if(address<0||address%4!=0)return "address"
        } else if(w[7]!="-")return "address"
        val first=statics[pc]
        if(first!=null&&(kind!=first.kind||regs[0]!=first.rd||regs[1]!=first.rs1||regs[2]!=first.rs2||((kind==4||kind==5&&regs[1]<0)&&target!=first.target)))return "conflict"
        val n=instructions.size;
        val t=Instruction(n+1,lineNumber,pc,kind,regs[0],regs[1],regs[2],w[5]=="T",target,address)
        if(n>0&&instructions[n-1].next()!=pc)gaps.add("gap line $lineNumber expected ${Report.hex(instructions[n-1].next())} found ${Report.hex(pc)}")
        instructions.add(t);
        statics.putIfAbsent(pc,t);
        val group=groups.getOrPut(pc) {
            mutableListOf()
        };
        group.add(n)
        return null
    }
    fun predict(definition: TraceIO.Predictor): Prediction {
        val p=Prediction(definition,instructions.size);
        val btb=Predictors.BTB(config.btb);
        val ras=Predictors.RAS(config.ras)
        val direction=Predictors.Direction(definition);
        p.bits=direction.bits()
        for(i in instructions.indices) {
            val t=instructions[i];
            if(!t.control())continue
            var candidate=btb.lookup(t.pc);
            if(candidate>=0)p.counts[6]++
            val isReturn=t.kind==5&&t.rd<0&&t.rs1==31;
            val isCall=t.kind==5&&t.rd==31
            if(isReturn) {
                p.counts[8]++;
                val value=ras.pop();
                if(value>=0) {
                    candidate=value;
                    p.counts[9]++;
                    if(value==t.target)p.counts[10]++
                }
            }
            if(isCall) {
                p.counts[7]++;
                ras.push(t.pc+4)
            }
            val taken=t.kind!=4||direction.prediction(t.pc,t.target)
            val predicted=if(definition.scheme=="PERFECT")t.next() else if(taken&&candidate>=0)candidate else t.pc+4
            val missed=predicted!=t.next();
            var miss=-1
            if(missed) {
                miss=if(t.kind==4&&taken!=t.taken)0 else if(candidate<0)1 else 2;
                p.counts[11+miss]++;
                p.counts[1]++
            }
            p.flags[i]=missed;
            p.details[i]=Detail(predicted,miss);
            p.counts[0]++
            val k=if(t.kind==4)2 else 4;
            p.counts[k]++;
            if(missed)p.counts[k+1]++
            if(t.kind==4)direction.update(t.pc,t.taken);
            if(t.taken)btb.insert(t.pc,t.target)
        }
        return p
    }
    fun simulate() {
        for(variant in config.variants)for(predictor in config.predictors) {
            val run=Pipeline.simulate(instructions,sources,variant,predictions.getValue(predictor.name).flags);
            run.predictor=predictor.name
            combinations.add(Combination(variant,predictor.name,run))
            if(variant.name==config.primaryVariant&&predictor.name==config.primaryPredictor)primary=run
        }
        combinations.sortWith(compareBy<Combination> {
            it.run.total
        }.thenBy {
            it.variant.name
        }.thenBy {
            it.predictor
        })
    }
    fun rows(): List<Row> {
        val rows=mutableListOf<Row>();
        val annotations=Array(instructions.size) {
            StringBuilder()
        }
        for(stall in primary.records)if(stall.waiting>=0)annotations[stall.waiting].append(" ${Pipeline.CAUSES[stall.cause]} ${stall.cycles}")
        val p=predictions.getValue(primary.predictor)
        for(i in instructions.indices) {
            val t=instructions[i];
            val time=primary.times[i];
            var annotation=annotations[i].toString()
            if(p.flags[i])annotation+=" mispredict ${MISS[p.details[i]!!.kind]}"
            val row=Row(i+1,t.pc,CLASSES[t.kind],annotation)
            row.add(time.f,time.f,'F',0);
            row.add(time.f+1,time.d-1,'*',0);
            row.add(time.d,time.d,'D',1);
            row.add(time.d+1,time.x-1,'*',1)
            row.add(time.x,time.m-1,'X',2);
            row.add(time.m,time.m,'M',3);
            row.add(time.w,time.w,'W',4);
            rows.add(row)
            if(!p.flags[i])continue
            val early=Hazards.idResolved(t,primary.variant);
            val cancel=time.x+(if(early)0 else 1)
            val wrong=Row(-1,p.details[i]!!.predicted,"FLUSH","");
            wrong.add(time.d,time.d,'F',0);
            wrong.add(time.d+1,time.x-1,'*',0);
            wrong.add(cancel,cancel,'x',-1)
            if(!early)wrong.add(time.x,time.x,'D',1);
            rows.add(wrong)
            if(!early) {
                val second=Row(-1,p.details[i]!!.predicted+4,"FLUSH","");
                second.add(time.x,time.x,'F',0);
                second.add(cancel,cancel,'x',-1);
                rows.add(second)
            }
        }
        return rows
    }
    fun diagram(rows: List<Row>): List<String> {
        val first=config.first;
        val last=config.last;
        val width=last-first+1;
        var visible=0;
        var stars=0;
        var flushed=0
        val lines=mutableListOf("pipeline variant=${config.primaryVariant} predictor=${config.primaryPredictor} cycles $first-$last",Report.heading(first,last))
        val contents=Array(width) {
            Array(5) {
                "."
            }
        }
        for(row in rows) {
            val cells=CharArray(width) {
                '.'
            };
            var show=false
            for(span in row.spans)for(c in maxOf(first,span.first)..minOf(last,span.last)) {
                cells[c-first]=span.symbol;
                show=true;
                if(span.stage>=0)contents[c-first][span.stage]=if(row.number<0)"w" else row.number.toString()
            }
            if(show) {
                visible++;
                stars+=cells.count {
                    it=='*'
                };
                flushed+=cells.count {
                    it=='x'
                };
                lines.add(Report.row(row.number,row.pc,row.kind,cells.concatToString(),row.annotation))
            }
        }
        val completed=primary.times.count {
            it.w in first..last
        }
        lines.add("rows $visible completed $completed stall_cells $stars flushed $flushed");
        lines.add("");
        lines.add("stages");
        lines.add("cycle IF ID EX MEM WB")
        for(c in first..last)lines.add("$c "+contents[c-first].joinToString(" "))
        return lines
    }
    fun causes(values: IntArray)=Pipeline.CAUSES.indices.joinToString(" ") {
        "${Pipeline.CAUSES[it]} ${values[it]}"
    }
    fun part(lines: MutableList<String>,section: List<String>) {
        if(lines.isNotEmpty())lines.add("");
        lines.addAll(section)
    }
    fun statistics(rows: List<Row>): List<String> {
        val n=instructions.size;
        val c=primary.total;
        val v=primary.variant;
        val lines=mutableListOf<String>()
        var section=mutableListOf("input lines $inputLines accepted $n rejected ${rejects.size} gaps ${gaps.size}");
        section.addAll(rejects);
        section.addAll(gaps);
        part(lines,section)
        val mix=IntArray(7);
        val distance=IntArray(6);
        var branchTaken=0;
        var backward=0;
        var indirect=0;
        var link=0;
        var operands=0
        val addresses=mutableSetOf<Int>()
        for(i in instructions.indices) {
            val t=instructions[i];
            mix[t.kind]++
            if(t.kind==4) {
                if(t.taken)branchTaken++;
                if(t.target<t.pc)backward++
            }
            if(t.kind==5) {
                if(t.rs1>=0)indirect++;
                if(t.rd>=0)link++
            }
            if(t.kind==2||t.kind==3)addresses.add(t.address)
            for(source in sources[i]) {
                operands++;
                if(source.producer>=0)distance[minOf(5,i-source.producer)]++
            }
        }
        val staticBranch=statics.values.count {
            it.kind==4
        };
        val staticJump=statics.values.count {
            it.kind==5
        }
        section=mutableListOf("trace","instructions $n","static_instructions ${statics.size}")
        section.add("mix "+CLASSES.indices.joinToString(" ") {
            "${CLASSES[it]} ${mix[it]}"
        })
        section.add("branches ${mix[4]} taken $branchTaken backward $backward");
        section.add("jumps ${mix[5]} indirect $indirect link $link")
        section.add("static_control branches $staticBranch jumps $staticJump");
        section.add("memory loads ${mix[2]} stores ${mix[3]} distinct_addresses ${addresses.size}")
        var dline="operands $operands with_producer ${distance.sum()} distance";
        for(k in 1..5)dline+=" ${if(k==5)"5+" else k.toString()} ${distance[k]}";
        section.add(dline);
        part(lines,section)
        section=mutableListOf("prediction")
        for(definition in config.predictors) {
            val p=predictions.getValue(definition.name);
            val a=p.counts
            section.add("${definition.name} ${definition.scheme} bits ${p.bits} control ${a[0]} mispredicted ${a[1]} accuracy ${p.accuracy(0)} branches ${p.accuracy(4)} jumps ${p.accuracy(5)} direction ${a[11]} btb_miss ${a[12]} wrong_target ${a[13]}")
        }
        val a=predictions.getValue(config.predictors[0].name).counts
        section.add("btb entries ${config.btb} lookups ${a[0]} hits ${a[6]} misses ${a[0]-a[6]}")
        section.add("ras depth ${config.ras} calls ${a[7]} returns ${a[8]} predicted ${a[9]} correct ${a[10]}");
        part(lines,section)
        val finish=IntArray(n);
        var height=0
        for(i in instructions.indices) {
            var start=0;
            for(source in sources[i])if(source.producer>=0)start=maxOf(start,finish[source.producer]);
            val kind=instructions[i].kind;
            finish[i]=start+(if(kind==2)2 else if(kind==1)v.latency else 1);
            height=maxOf(height,finish[i])
        }
        val s=primary.cycles.sum();
        val refetch=rows.size-n
        section=mutableListOf("timing variant=${v.name} predictor=${primary.predictor}","forwarding ${if(v.forwarding)"on" else "off"} branch_stage ${v.stage} mul_latency ${v.latency}",
            "cycles $c","cpi ${Report.fraction(c,n)} ${Report.decimal(c,n)}","ipc ${Report.decimal(n,c)}",
            "stall_cycles total $s ${causes(primary.cycles)}","stall_events ${causes(primary.events)}",
            "flushed $refetch","cycle_check $n + 4 + $s = ${n+4+s}")
        var stack="cpi_stack base 1.0000 fill ${Report.decimal(4,n)}";
        for(k in 0..3)stack+=" ${Pipeline.CAUSES[k]} ${Report.decimal(primary.cycles[k],n)}";
        section.add(stack)
        var lengths="stall_lengths";
        for(k in 1..5)lengths+=" ${if(k==5)"5+" else k.toString()} ${primary.lengths[k]}";
        section.add(lengths);
        section.add("dataflow height $height ilp ${Report.decimal(n,height)}");
        part(lines,section)
        section=mutableListOf("whatif");
        val changedStage=if(v.stage=="EX")"ID" else "EX"
        val variants=listOf(v,v.copy(latency=1),v.copy(forwarding=!v.forwarding),v.copy(stage=changedStage))
        val names=listOf("perfect_prediction","single_cycle_mul",if(v.forwarding)"forwarding_off" else "forwarding_on","branch_stage_$changedStage")
        for(k in 0..3) {
            val flags=if(k==0)BooleanArray(n) else predictions.getValue(primary.predictor).flags;
            val total=Pipeline.simulate(instructions,sources,variants[k],flags).total;
            section.add("${names[k]} cycles $total saved ${c-total} speedup ${Report.decimal(c,total)}")
        };
        part(lines,section)
        val classStalls=IntArray(7);
        val byPC=mutableMapOf<Int,IntArray>();
        val pairs=mutableMapOf<Dependency,IntArray>()
        for(stall in primary.records) {
            val responsible=instructions[stall.responsible];
            classStalls[responsible.kind]+=stall.cycles
            val counts=byPC.getOrPut(responsible.pc) {
                IntArray(4)
            };
            counts[stall.cause]+=stall.cycles
            if(stall.cause>=2) {
                val key=Dependency(instructions[stall.producer].pc,instructions[stall.waiting].pc,stall.cause);
                val value=pairs.getOrPut(key) {
                    IntArray(2)
                };
                value[0]+=stall.cycles;
                value[1]++
            }
        }
        section=mutableListOf("classes");
        for(k in 0..6)section.add("${CLASSES[k]} count ${mix[k]} stall_cycles ${classStalls[k]} per_instruction ${if(mix[k]==0)"-" else Report.decimal(classStalls[k],mix[k])}");
        part(lines,section)
        val paths=IntArray(3)
        for(i in instructions.indices)for(source in sources[i])paths[Hazards.path(instructions[i],
            if(source.producer<0)null else primary.times[source.producer],primary.times[i],
            v)]++
        part(lines,listOf("forwarding regfile ${paths[0]} ex_mem ${paths[1]} mem_wb ${paths[2]}"))
        val occupancy=Array(5) {
            IntArray(2)
        }
        for(row in rows)for(span in row.spans)if(span.stage>=0)occupancy[span.stage][if(row.number<0)1 else 0]+=span.last-span.first+1
        section=mutableListOf("occupancy cycles $c");
        for(k in 0..4) {
            val correct=occupancy[k][0];
            val wrong=occupancy[k][1];
            section.add("${Pipeline.STAGES[k]} correct $correct wrong $wrong idle ${c-correct-wrong} busy ${Report.percentage(correct+wrong,c)}")
        };
        part(lines,section)
        val pcs=byPC.keys.sortedWith(compareByDescending<Int> {
            byPC.getValue(it).sum()
        }.thenBy {
            it
        })
        section=mutableListOf("hotspots");
        for((k,pc) in pcs.take(config.top).withIndex())section.add("${k+1} ${Report.hex(pc)} ${CLASSES[statics.getValue(pc).kind]} stall_cycles ${byPC.getValue(pc).sum()} ${causes(byPC.getValue(pc))}");
        part(lines,section)
        val keys=pairs.keys.sortedWith(compareByDescending<Dependency> {
            pairs.getValue(it)[0]
        }.thenBy {
            it.producer
        }.thenBy {
            it.waiting
        }.thenBy {
            it.cause
        })
        section=mutableListOf("dependencies total ${keys.size}")
        for((k,key) in keys.take(config.top).withIndex()) {
            val value=pairs.getValue(key);
            section.add("${k+1} ${Report.hex(key.producer)} ${CLASSES[statics.getValue(key.producer).kind]} -> ${Report.hex(key.waiting)} ${CLASSES[statics.getValue(key.waiting).kind]} ${Pipeline.CAUSES[key.cause]} stall_cycles ${value[0]} events ${value[1]}")
        };
        part(lines,section)
        section=mutableListOf("intervals size ${config.interval}")
        for(first in 0 until n step config.interval) {
            val last=minOf(n,first+config.interval)-1;
            val total=primary.times[last].w-(if(first==0)0 else primary.times[first-1].w);
            section.add("${first+1}-${last+1} cycles $total cpi ${Report.decimal(total,last-first+1)}")
        };
        part(lines,section)
        section=mutableListOf("cycles_table "+config.predictors.joinToString(" ") {
            it.name
        })
        for(variant in config.variants) {
            var line=variant.name;
            for(p in config.predictors)line+=" "+combinations.first {
                it.variant.name==variant.name&&it.predictor==p.name
            }.run.total;
            section.add(line)
        }
        part(lines,section);
        return lines
    }
    fun misses(prediction: Prediction,indices: List<Int>)=indices.count {
        prediction.flags[it]
    }
    fun branches(): List<String> {
        val lines=mutableListOf("predictor,pc,class,executions,taken,mispredictions,accuracy")
        for(definition in config.predictors)for((pc,indices) in groups) {
            val t=statics.getValue(pc);
            if(!t.control())continue;
            val taken=indices.count {
                instructions[it].taken
            };
            val miss=misses(predictions.getValue(definition.name),indices)
            lines.add("${definition.name},${Report.hex(pc)},${CLASSES[t.kind]},${indices.size},$taken,$miss,${Report.percentage(indices.size-miss,indices.size)}")
        }
        return lines
    }
    fun comparison(): List<String> {
        val lines=mutableListOf("rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw")
        for((i,pair) in combinations.withIndex()) {
            val p=predictions.getValue(pair.predictor);
            val run=pair.run
            var line="${i+1},${pair.variant.name},${pair.predictor},${run.total},${Report.decimal(run.total,instructions.size)},${Report.decimal(primary.total,run.total)},${p.accuracy(0)},${p.counts[1]}"
            for(value in run.cycles)line+=",$value";
            lines.add(line)
        }
        return lines
    }
    fun profile(): List<String> {
        val lines=mutableListOf<String>();
        var section=mutableListOf("branches")
        for((pc,indices) in groups) {
            val t=statics.getValue(pc);
            if(t.kind!=4)continue
            var transitions=0;
            var longT=0;
            var longN=0;
            var length=0;
            var taken=0;
            var previous=false;
            var first=true
            for(i in indices) {
                val outcome=instructions[i].taken;
                if(!first&&outcome!=previous)transitions++;
                length=if(!first&&outcome==previous)length+1 else 1;
                if(outcome) {
                    taken++;
                    longT=maxOf(longT,length)
                } else longN=maxOf(longN,length);
                previous=outcome;
                first=false
            }
            var best="";
            var minimum=Int.MAX_VALUE
            for(definition in config.predictors)if(definition.scheme!="PERFECT") {
                val count=misses(predictions.getValue(definition.name),indices);
                if(count<minimum) {
                    minimum=count;
                    best=definition.name
                }
            }
            section.add("${Report.hex(pc)} ${if(t.target<pc)"backward" else "forward"} executions ${indices.size} taken $taken transitions $transitions longest_taken $longT longest_not_taken $longN best $best $minimum")
        }
        part(lines,section);
        section=mutableListOf("loops")
        for((pc,indices) in groups) {
            val t=statics.getValue(pc);
            if(t.kind!=4||t.target>=pc)continue
            var trips=0;
            var length=0;
            var longest=0
            for(i in indices) {
                length++;
                if(!instructions[i].taken) {
                    trips++;
                    longest=maxOf(longest,length);
                    length=0
                }
            }
            if(length>0) {
                trips++;
                longest=maxOf(longest,length)
            }
            section.add("${Report.hex(t.target)}-${Report.hex(pc)} body ${(pc-t.target)/4+1} entries $trips iterations ${indices.size} avg_trip ${Report.decimal(indices.size,trips)} max_trip $longest")
        }
        part(lines,section);
        val segments=mutableMapOf<Int,IntArray>();
        var first=0
        for(last in instructions.indices)if(instructions[last].control()||last==instructions.lastIndex) {
            val group=segments.getOrPut(instructions[first].pc) {
                IntArray(3)
            };
            group[0]++;
            group[1]+=last-first+1;
            group[2]+=primary.times[last].w-(if(first==0)0 else primary.times[first-1].w);
            first=last+1
        }
        val starts=segments.keys.sortedWith(compareByDescending<Int> {
            segments.getValue(it)[2]
        }.thenBy {
            it
        })
        section=mutableListOf("segments total ${segments.size}");
        for((k,pc) in starts.take(config.top).withIndex()) {
            val group=segments.getValue(pc);
            section.add("${k+1} ${Report.hex(pc)} instances ${group[0]} instructions ${group[1]} cycles ${group[2]} cpi ${Report.decimal(group[2],group[1])}")
        };
        part(lines,section)
        section=mutableListOf("indirect")
        for((pc,indices) in groups) {
            val t=statics.getValue(pc);
            if(t.kind!=5||t.rs1<0)continue
            val counts=indices.groupingBy {
                instructions[it].target
            }.eachCount()
            val targets=counts.keys.sortedWith(compareByDescending<Int> {
                counts.getValue(it)
            }.thenBy {
                it
            })
            val values=targets.joinToString(" ") {
                "${Report.hex(it)}:${counts.getValue(it)}"
            }
            section.add("${Report.hex(pc)} executions ${indices.size} distinct ${targets.size} targets $values")
        }
        part(lines,section);
        section=mutableListOf("instructions");
        val stalls=mutableMapOf<Int,Int>()
        for(stall in primary.records) {
            val pc=instructions[stall.responsible].pc;
            stalls[pc]=stalls.getOrDefault(pc,0)+stall.cycles
        }
        for((pc,indices) in groups) {
            val t=statics.getValue(pc);
            section.add("${Report.hex(pc)} ${CLASSES[t.kind]} ${Report.register(t.rd)} ${Report.register(t.rs1)} ${Report.register(t.rs2)} executions ${indices.size} stall_cycles ${stalls.getOrDefault(pc,0)}")
        }
        part(lines,section);
        return lines
    }
    fun run() {
        config=TraceIO.read();
        val input=TraceIO.lines("trace.txt");
        inputLines=input.size
        for((i,line) in input.withIndex()) {
            val reason=check(line,i+1);
            if(reason!=null)rejects.add("reject line ${i+1} $reason")
        }
        sources=Hazards.dependencies(instructions);
        for(definition in config.predictors)predictions[definition.name]=predict(definition)
        simulate();
        val rows=rows()
        Report.write("pipeline.txt",diagram(rows));
        Report.write("stats.txt",statistics(rows));
        Report.write("branches.csv",branches());
        Report.write("comparison.csv",comparison());
        Report.write("profile.txt",profile())
    }
}
fun main()=CPU.run()
