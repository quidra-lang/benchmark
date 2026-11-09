import java.io.File
import java.util.ArrayDeque
import java.util.Locale
import kotlin.math.*
object BayesianInference {
    lateinit var network: NetworkIo.Network;
    lateinit var settings: NetworkIo.Settings;
    lateinit var samples: List<IntArray>;
    lateinit var names: List<String>;
    lateinit var states: List<List<String>>;
    lateinit var parents: List<List<Int>>;
    val children=mutableListOf<List<Int>>();
    val spouses=mutableListOf<List<Int>>();
    val blankets=mutableListOf<List<Int>>();
    val ancestors=mutableListOf<Set<Int>>();
    val descendants=mutableListOf<Set<Int>>();
    val variables=mutableListOf<Int>();
    val topological=mutableListOf<Int>();
    lateinit var sizes: IntArray;
    lateinit var depths: IntArray;
    lateinit var parameterCounts: IntArray;
    val counts=mutableListOf<Array<IntArray>>();
    val learned=mutableListOf<Array<DoubleArray>>();
    val cpts=mutableListOf<Array<DoubleArray>>();
    lateinit var likelihoods: DoubleArray;
    val factors=mutableListOf<Factors.Factor>();
    lateinit var random: Sampling.Minstd;
    val familyScores=mutableMapOf<String,Double>()
    data class Evidence(val variable: Int,val state: Int)
    data class Parts(val query: List<Int>,val evidence: List<Evidence>)
    data class Plans(val minfill: Elimination.Plan,val given: Elimination.Plan)
    data class SumResult(val distribution: Factors.Factor,val probability: Double,val marginals: Array<DoubleArray>)
    data class Posterior(val relevant: List<Int>,val eliminate: List<Int>,val initial: List<Factors.Factor>,
        val plans: Plans,val result: SumResult)
    data class Enumeration(val count: Long,val result: String)
    data class Answer(val lines: List<String>,val elimination: List<String>)
    data class Mpe(val maximum: Double,val assignment: IntArray)
    data class SampleAnswer(val lines: List<String>,val csv: List<String>)
    data class Ball(val variable: Int,val direction: Int)
    data class Information(val cmi: Double,val g2: Double,val degrees: Long)
    fun real(value: Double): String {
        val text=String.format(Locale.ROOT,"%.4f",value);
        return if(text=="-0.0000")"0.0000" else text
    }
    fun yes(value: Boolean)=if(value)"yes" else "no"
    fun sorted(values: Collection<Int>)=values.distinct().sorted()
    fun union(a: Collection<Int>,b: Collection<Int>)=(a+b).distinct().sorted()
    fun difference(a: Collection<Int>,b: Collection<Int>)=a.filter {
        it !in b
    }.distinct().sorted()
    fun closure(initial: Collection<Int>,links: List<List<Int>>): Set<Int> {
        val reached=initial.toMutableSet();
        val pending=ArrayDeque<Int>(initial);
        while(pending.isNotEmpty())for(neighbor in links[pending.pop()])if(reached.add(neighbor))pending.push(neighbor);
        return reached
    }
    fun sequence(variables: Collection<Int>)=if(variables.isEmpty())"-" else variables.joinToString(" ") {
        names[it]
    }
    fun assignmentText(assignment: IntArray,variables: List<Int>)=if(variables.isEmpty())"-" else variables.joinToString(" ") {
        "${names[it]}=${states[it][assignment[it]]}"
    }
    fun evidenceArray(evidence: List<Evidence>)=IntArray(sizes.size) {
        -1
    }.also {
        values->for(e in evidence)values[e.variable]=e.state
    }
    fun evidenceVariables(evidence: List<Evidence>)=evidence.map {
        it.variable
    }.sorted()
    fun parseEvidence(fields: List<String>)=fields.map {
        val w=it.split('=');
        val v=names.indexOf(w[0]);
        Evidence(v,states[v].indexOf(w[1]))
    }
    fun parseParts(fields: List<String>): Parts {
        val separator=fields.indexOf('|'.toString()).let {
            if(it<0)fields.size else it
        };
        val query=fields.take(separator).map {
            names.indexOf(it)
        };
        return Parts(query,if(separator==fields.size)emptyList() else parseEvidence(fields.drop(separator+1)))
    }
    fun prepare(input: NetworkIo.Input) {
        network=input.network;
        settings=input.settings;
        samples=input.samples;
        names=network.names;
        states=network.states;
        parents=network.parents;
        sizes=IntArray(names.size) {
            states[it].size
        };
        depths=IntArray(names.size);
        likelihoods=DoubleArray(names.size);
        parameterCounts=IntArray(names.size);
        variables.addAll(names.indices);
        for(v in variables)children.add(variables.filter {
            v in parents[it]
        });
        val selected=BooleanArray(sizes.size);
        while(topological.size<sizes.size) {
            val v=variables.first {
                !selected[it]&&parents[it].all {
                    p->selected[p]
                }
            };
            selected[v]=true;
            topological.add(v)
        };
        for(v in topological)for(p in parents[v])depths[v]=maxOf(depths[v],depths[p]+1);
        for(v in variables) {
            ancestors.add(closure(parents[v],parents));
            descendants.add(closure(children[v],children));
            val immediate=union(parents[v],children[v]);
            val coParents=children[v].flatMap {
                parents[it]
            }.filter {
                it!=v&&it !in immediate
            }.distinct().sorted();
            spouses.add(coParents);
            blankets.add(union(immediate,coParents));
            val observed=Learning.counts(v,parents[v],samples,sizes);
            counts.add(observed);
            val fitted=Learning.learn(observed,settings.alpha);
            learned.add(fitted);
            val used=if(settings.sources[v]=="GIVEN")network.expert.getValue(v) else fitted;
            cpts.add(used);
            likelihoods[v]=Learning.likelihood(observed,used);
            parameterCounts[v]=Learning.parameters(observed);
            factors.add(Factors.cpt(v,parents[v],used,sizes))
        };
        random=Sampling.Minstd(settings.seed)
    }
    fun makePlans(initial: List<Factors.Factor>,eliminate: List<Int>)=Plans(Elimination.plan(initial,
        eliminate,"MINFILL",settings.order,sizes),Elimination.plan(initial,eliminate,"GIVEN",
        settings.order,sizes))
    fun used(plans: Plans)=if(settings.method=="MINFILL")plans.minfill else plans.given
    fun sumResult(initial: List<Factors.Factor>,plan: Elimination.Plan,query: List<Int>): SumResult {
        val factor=Elimination.execute(initial,plan,sizes).factor;
        val probability=Learning.total(factor.values);
        val values=DoubleArray(factor.values.size) {
            factor.values[it]/probability
        };
        val distribution=Factors.Factor(factor.variables,values,sizes);
        val marginals=Array(sizes.size) {
            DoubleArray(sizes[it])
        };
        for(i in values.indices) {
            val assignment=Factors.assignment(i,factor.variables,sizes);
            for(v in query)marginals[v][assignment[v]]+=values[i]
        };
        return SumResult(distribution,probability,marginals)
    }
    fun posterior(query: List<Int>,evidence: List<Evidence>): Posterior {
        val relevant=sorted(closure(union(query,evidenceVariables(evidence)),parents));
        val eliminate=difference(difference(relevant,query),evidenceVariables(evidence));
        val observed=evidenceArray(evidence);
        val initial=relevant.map {
            factors[it].reduced(observed)
        };
        val plans=makePlans(initial,eliminate);
        return Posterior(relevant,eliminate,initial,plans,sumResult(initial,used(plans),query))
    }
    fun joint(assignment: IntArray,variables: List<Int>): Double {
        var probability=1.0;
        for(v in variables)probability*=cpts[v][Learning.parentRow(parents[v],assignment,sizes)][assignment[v]];
        return probability
    }
    fun addEvidence(assignment: IntArray,evidence: List<Evidence>) {
        for(e in evidence)assignment[e.variable]=e.state
    }
    fun queryEnumeration(result: Posterior,query: List<Int>,evidence: List<Evidence>): Enumeration {
        val free=difference(result.relevant,evidenceVariables(evidence));
        val count=Factors.entries(free,sizes);
        if(count>settings.limit)return Enumeration(count.toLong(),"skipped");
        val ordered=query.sorted();
        val values=DoubleArray(Factors.entries(ordered,sizes));
        for(i in 0 until count) {
            val assignment=Factors.assignment(i,free,sizes);
            addEvidence(assignment,evidence);
            values[Learning.parentRow(ordered,assignment,sizes)]+=joint(assignment,result.relevant)
        };
        val probability=Learning.total(values);
        var agree=abs(ln(probability)-ln(result.result.probability))<=1e-9;
        for(i in values.indices)agree=agree&&(abs(values[i]/probability-result.result.distribution.values[i])<=1e-9);
        return Enumeration(count.toLong(),if(agree)"agree" else "disagree")
    }
    fun eliminationLines(relevant: List<Int>,eliminate: List<Int>,plans: Plans,agreement: Boolean,
        enumeration: Enumeration): List<String> {
        val lines=mutableListOf("relevant ${sequence(relevant)}","pruned ${sequence(difference(variables,relevant))}",
            "eliminate ${sequence(eliminate)}");
        for((method,plan) in listOf("minfill" to plans.minfill,"given" to plans.given)) {
            lines.add("order $method");
            for(step in plan.steps)lines.add("step ${names[step.variable]} fill ${step.fill} scope ${sequence(step.scope)} entries ${step.size}");
            lines.add("cost max ${plan.maximum} total ${plan.total}")
        };
        lines.add("used ${settings.method.lowercase(Locale.ROOT)}");
        lines.add("orders_agree ${yes(agreement)}");
        lines.add("enumeration ${enumeration.count} ${enumeration.result}");
        return lines
    }
    fun marginalLines(prefix: String,query: List<Int>,marginals: Array<DoubleArray>): List<String> {
        val lines=mutableListOf<String>();
        for(v in query)lines.add("$prefix ${names[v]} "+states[v].mapIndexed {
            s,state->"$state ${real(marginals[v][s])}"
        }.joinToString(" "));
        return lines
    }
    fun answerQuery(query: List<Int>,evidence: List<Evidence>): Answer {
        val result=posterior(query,evidence);
        val lines=mutableListOf("log_evidence ${real(ln(result.result.probability))}");
        if(evidence.isNotEmpty()) {
            var conflict=0.0;
            for(e in evidence)conflict+=ln(posterior(emptyList(),listOf(e)).result.probability);
            conflict-=ln(result.result.probability);
            lines.add("conflict ${real(conflict)}")
        };
        val distribution=result.result.distribution;
        if(query.size>=2)for(i in distribution.values.indices)lines.add("joint ${assignmentText(Factors.assignment(i,distribution.variables,sizes),distribution.variables)} ${real(distribution.values[i])}");
        lines.addAll(marginalLines("marginal",query,result.result.marginals));
        for(e in evidence) {
            val reduced=evidence.filter {
                it.variable!=e.variable
            };
            val without=posterior(query,reduced).result.marginals;
            var shift=0.0;
            for(v in query)for(s in 0 until sizes[v])shift=maxOf(shift,abs(result.result.marginals[v][s]-without[v][s]));
            lines.add("drop ${names[e.variable]}=${states[e.variable][e.state]} shift ${real(shift)}")
        };
        val a=sumResult(result.initial,result.plans.minfill,query);
        val b=sumResult(result.initial,result.plans.given,query);
        var agree=abs(ln(a.probability)-ln(b.probability))<=1e-9;
        for(i in a.distribution.values.indices)agree=agree&&(abs(a.distribution.values[i]-b.distribution.values[i])<=1e-9);
        return Answer(lines,eliminationLines(result.relevant,result.eliminate,result.plans,
            agree,queryEnumeration(result,query,evidence)))
    }
    fun maxResult(initial: List<Factors.Factor>,plan: Elimination.Plan,evidence: List<Evidence>): Mpe {
        val outcome=Elimination.execute(initial,plan,sizes,true);
        val assignment=Elimination.traceback(outcome.products,sizes);
        addEvidence(assignment,evidence);
        return Mpe(outcome.factor.values[0],assignment)
    }
    fun mpeEnumeration(eliminate: List<Int>,evidence: List<Evidence>,mpe: Mpe): Enumeration {
        val count=Factors.entries(eliminate,sizes);
        if(count>settings.limit)return Enumeration(count.toLong(),"skipped");
        var best=-1.0;
        var assignment=IntArray(sizes.size);
        for(i in 0 until count) {
            val candidate=Factors.assignment(i,eliminate,sizes);
            addEvidence(candidate,evidence);
            val probability=joint(candidate,variables);
            if(probability>best) {
                best=probability;
                assignment=candidate
            }
        };
        val agree=assignment.contentEquals(mpe.assignment)&&abs(ln(best)-ln(mpe.maximum))<=1e-9;
        return Enumeration(count.toLong(),if(agree)"agree" else "disagree")
    }
    fun answerMpe(evidence: List<Evidence>): Answer {
        val observed=evidenceArray(evidence);
        val initial=factors.map {
            it.reduced(observed)
        };
        val eliminate=difference(variables,evidenceVariables(evidence));
        val plans=makePlans(initial,eliminate);
        val a=maxResult(initial,plans.minfill,evidence);
        val b=maxResult(initial,plans.given,evidence);
        val result=if(settings.method=="MINFILL")a else b;
        val probability=if(evidence.isEmpty())1.0 else posterior(emptyList(),evidence).result.probability;
        val lines=mutableListOf("assignment ${assignmentText(result.assignment,variables)}",
            "log_joint ${real(ln(result.maximum))}","log_evidence ${real(ln(probability))}",
            "posterior ${real(result.maximum/probability)}");
        for(v in eliminate) {
            val remaining=eliminate.filter {
                it!=v
            };
            val plan=Elimination.plan(initial,remaining,settings.method,settings.order,sizes);
            val factor=Elimination.execute(initial,plan,sizes,true).factor;
            var alternative=-1;
            for(s in 0 until sizes[v])if(s!=result.assignment[v]&&(alternative<0||factor.values[s]>factor.values[alternative]))alternative=s;
            val margin=ln(result.maximum)-ln(factor.values[alternative]);
            lines.add("margin ${names[v]} ${states[v][alternative]} ${real(margin)}")
        };
        val agree=a.assignment.contentEquals(b.assignment)&&abs(ln(a.maximum)-ln(b.maximum))<=1e-9;
        return Answer(lines,eliminationLines(variables,eliminate,plans,agree,mpeEnumeration(eliminate,
            evidence,result)))
    }
    fun answerSample(number: Int,query: List<Int>,evidence: List<Evidence>,checkpoints: List<Int>): SampleAnswer {
        val exact=posterior(query,evidence).result.marginals;
        val weights=Array(sizes.size) {
            DoubleArray(sizes[it])
        };
        val lines=marginalLines("exact",query,exact).toMutableList();
        val csv=mutableListOf<String>();
        var weight=0.0;
        var squaredWeight=0.0;
        val observed=evidenceArray(evidence);
        for(i in 1..checkpoints.last()) {
            val sample=Sampling.weighted(topological,parents,cpts,sizes,observed,random);
            val current=sample.weight;
            weight+=current;
            squaredWeight+=current*current;
            for(v in query)weights[v][sample.sample[v]]+=current;
            if(i !in checkpoints)continue;
            var maximumError=0.0;
            for(v in query)for(s in 0 until sizes[v]) {
                val estimate=weights[v][s]/weight;
                val probability=exact[v][s];
                val error=abs(estimate-probability);
                maximumError=maxOf(maximumError,error);
                csv.add("$number,$i,${names[v]},${states[v][s]},${real(estimate)},${real(probability)},${real(error)}")
            };
            val effective=weight*weight/squaredWeight;
            lines.add("after $i weight ${real(weight)} ess ${real(effective)} max_error ${real(maximumError)}")
        };
        return SampleAnswer(lines,csv)
    }
    fun answerPredict(variable: Int): List<String> {
        val size=sizes[variable];
        val confusion=Array(size) {
            IntArray(size)
        };
        var likelihood=0.0;
        for(sample in samples) {
            val assignment=sample.copyOf();
            val values=DoubleArray(size);
            for(s in 0 until size) {
                assignment[variable]=s;
                var probability=cpts[variable][Learning.parentRow(parents[variable],assignment,
                    sizes)][s];
                for(child in children[variable])probability*=cpts[child][Learning.parentRow(parents[child],
                    assignment,sizes)][assignment[child]];
                values[s]=probability
            };
            val total=Learning.total(values);
            for(s in values.indices)values[s]/=total;
            var predicted=0;
            for(s in 1 until size)if(values[s]>values[predicted])predicted=s;
            val actual=sample[variable];
            confusion[actual][predicted]++;
            likelihood+=ln(values[actual])
        };
        var correct=0;
        for(s in 0 until size)correct+=confusion[s][s];
        val count=samples.size;
        val lines=mutableListOf("blanket ${sequence(blankets[variable])}","accuracy $correct/$count ${real(correct.toDouble()/count)}",
            "log_loss ${real(-likelihood/count)}","predicted ${states[variable].joinToString(" ")}");
        for(s in 0 until size)lines.add("actual ${states[variable][s]} ${confusion[s].joinToString(" ")}");
        return lines
    }
    fun addBall(queue: ArrayDeque<Ball>,visited: Array<BooleanArray>,variable: Int,direction: Int) {
        if(!visited[variable][direction]) {
            visited[variable][direction]=true;
            queue.add(Ball(variable,direction))
        }
    }
    fun reachable(x: Collection<Int>,z: Collection<Int>): List<Int> {
        val ancestors=closure(z,parents);
        val visited=Array(sizes.size) {
            BooleanArray(2)
        };
        val pending=ArrayDeque<Ball>();
        for(v in sorted(x))addBall(pending,visited,v,0);
        while(pending.isNotEmpty()) {
            val ball=pending.removeFirst();
            val v=ball.variable;
            if(ball.direction==0&&v !in z) {
                for(p in parents[v])addBall(pending,visited,p,0);
                for(child in children[v])addBall(pending,visited,child,1)
            } else if(ball.direction==1) {
                if(v !in z)for(child in children[v])addBall(pending,visited,child,1);
                if(v in ancestors)for(p in parents[v])addBall(pending,visited,p,0)
            }
        };
        return variables.filter {
            (visited[it][0]||visited[it][1])&&it !in x&&it !in z
        }
    }
    fun frequencies(scope: List<Int>): Map<Int,Int> {
        val counts=sortedMapOf<Int,Int>();
        for(sample in samples) {
            val row=Learning.parentRow(scope,sample,sizes);
            counts[row]=counts.getOrDefault(row,0)+1
        };
        return counts
    }
    fun information(x: List<Int>,y: List<Int>,z: List<Int>): Information {
        val scope=union(union(x,y),z);
        val xz=union(x,z);
        val yz=union(y,z);
        val orderedZ=z.sorted();
        val observed=frequencies(scope);
        val countsXz=frequencies(xz);
        val countsYz=frequencies(yz);
        val countsZ=frequencies(orderedZ);
        var information=0.0;
        for((index,count) in observed) {
            val assignment=Factors.assignment(index,scope,sizes);
            val nxz=countsXz.getValue(Learning.parentRow(xz,assignment,sizes));
            val nyz=countsYz.getValue(Learning.parentRow(yz,assignment,sizes));
            val nz=countsZ.getValue(Learning.parentRow(orderedZ,assignment,sizes));
            val argument=(count*nz).toDouble()/(nxz*nyz).toDouble();
            information+=count.toDouble()/samples.size*ln(argument)
        };
        val degrees=(Factors.entries(x,sizes)-1).toLong()*(Factors.entries(y,sizes)-1)*Factors.entries(z,
            sizes);
        return Information(information,2*samples.size*information,degrees)
    }
    fun answerDsep(groups: List<List<Int>>): List<String> {
        val x=groups[0];
        val y=groups[1];
        val z=if(groups.size==3)groups[2] else emptyList();
        val reached=reachable(x,z);
        val info=information(x,y,z);
        return listOf("result ${if(reached.none{it in y})"separated" else "connected"}","reachable ${sequence(reached)}",
            "data cmi ${real(info.cmi)} g2 ${real(info.g2)} df ${info.degrees}")
    }
    fun answerBlanket(variable: Int): List<String> {
        val blanket=blankets[variable];
        val rest=variables.filter {
            it!=variable&&it !in blanket
        };
        val separated=reachable(listOf(variable),blanket).none {
            it in rest
        };
        return listOf("parents ${sequence(parents[variable])}","children ${sequence(children[variable])}",
            "spouses ${sequence(spouses[variable])}","blanket ${sequence(blanket)}","rest ${sequence(rest)}",
            "rest_separated ${yes(separated)}")
    }
    fun path(start: Int,finish: Int,ignoreFrom: Int=-1,ignoreTo: Int=-1): List<Int>? {
        val previous=IntArray(sizes.size) {
            -2
        };
        previous[start]=-1;
        val pending=ArrayDeque<Int>();
        pending.add(start);
        while(pending.isNotEmpty()) {
            val v=pending.removeFirst();
            for(child in children[v]) {
                if((v==ignoreFrom&&child==ignoreTo)||previous[child]!=-2)continue;
                previous[child]=v;
                if(child==finish) {
                    val result=mutableListOf<Int>();
                    var node=child;
                    while(node>=0) {
                        result.add(node);
                        node=previous[node]
                    };
                    return result.reversed()
                };
                pending.add(child)
            }
        };
        return null
    }
    fun familyScore(variable: Int,parents: Collection<Int>): Double {
        val ordered=parents.sorted();
        val key="$variable:${ordered.joinToString(",")}";
        return familyScores.getOrPut(key) {
            Learning.familyScore(variable,ordered,samples,sizes,settings.alpha)
        }
    }
    fun answerEdge(operation: String,x: Int,y: Int): List<String> {
        val exists=x in parents[y];
        if(operation=="ADD"&&exists)return listOf("result exists");
        if(operation!="ADD"&&!exists)return listOf("result missing");
        val cycle=when(operation) {
            "ADD"->path(y,x)?.let {
                listOf(x)+it
            };
            "REVERSE"->path(x,y,x,y)?.let {
                listOf(y)+it
            };
            else->null
        };
        if(cycle!=null)return listOf("result cycle "+cycle.joinToString(" -> ") {
            names[it]
        });
        val beforeY=familyScore(y,parents[y]);
        val newParents=if(operation=="ADD")union(parents[y],listOf(x)) else difference(parents[y],
            listOf(x));
        val afterY=familyScore(y,newParents);
        var change=afterY-beforeY;
        val lines=mutableListOf("result ok","family ${names[y]} before ${real(beforeY)} after ${real(afterY)}");
        if(operation=="REVERSE") {
            val beforeX=familyScore(x,parents[x]);
            val afterX=familyScore(x,union(parents[x],listOf(y)));
            change=(afterY-beforeY)+(afterX-beforeX);
            lines.add("family ${names[x]} before ${real(beforeX)} after ${real(afterX)}")
        };
        lines.add("delta ${real(change)} ${if(change>0)"improves" else "worsens"}");
        return lines
    }
    fun cptBlocks(): List<List<String>> {
        val blocks=mutableListOf<List<String>>();
        val count=samples.size;
        for(v in variables) {
            val source=settings.sources[v];
            val parents=this.parents[v];
            val cpt=cpts[v];
            val observed=counts[v];
            val lines=mutableListOf("variable ${names[v]} source $source","states ${states[v].joinToString(" ")}",
                "parents ${sequence(parents)}");
            for(row in observed.indices)lines.add("row ${assignmentText(Factors.assignment(row,parents,sizes),parents)} counts ${observed[row].joinToString(" ")} probs ${cpt[row].joinToString(" "){real(it)}}");
            val likelihood=likelihoods[v];
            val bic=likelihood-parameterCounts[v]*ln(count.toDouble())/2;
            lines.add("loglik ${real(likelihood)} parameters ${parameterCounts[v]} bic ${real(bic)}");
            val marginal=posterior(listOf(v),emptyList()).result.marginals[v];
            val data=DoubleArray(sizes[v]) {
                s->var frequency=0;
                for(row in observed)frequency+=row[s];
                frequency.toDouble()/count
            };
            lines.add("marginal model ${marginal.joinToString(" "){real(it)}} data ${data.joinToString(" "){real(it)}}");
            if(source=="LEARNED") {
                val given=network.expert[v];
                var difference="-";
                if(given!=null) {
                    var maximum=0.0;
                    for(r in observed.indices)for(s in 0 until sizes[v])maximum=maxOf(maximum,
                        abs(learned[v][r][s]-given[r][s]));
                    difference=real(maximum)
                };
                lines.add("given_difference $difference")
            };
            blocks.add(lines)
        };
        val likelihood=Learning.total(likelihoods);
        val parameterCount=parameterCounts.sum();
        val bic=likelihood-parameterCount*ln(count.toDouble())/2;
        blocks.add(listOf("network samples $count pseudocount ${real(settings.alpha)} loglik ${real(likelihood)} parameters $parameterCount bic ${real(bic)}"));
        return blocks
    }
    fun structureSummary(): List<String> {
        val plans=makePlans(factors,variables);
        val widthMinfill=plans.minfill.steps.maxOf {
            it.scope.size
        }
        -1;
        val widthGiven=plans.given.steps.maxOf {
            it.scope.size
        }
        -1;
        val graph=Elimination.interaction(factors,sizes.size);
        var moral=0;
        var edges=0;
        val roots=mutableListOf<Int>();
        val leaves=mutableListOf<Int>();
        for(v in variables) {
            edges+=parents[v].size;
            if(parents[v].isEmpty())roots.add(v);
            if(children[v].isEmpty())leaves.add(v);
            for(u in v+1 until sizes.size)if(graph[v][u])moral++
        };
        val lines=mutableListOf("variables ${sizes.size} edges $edges","topological_order ${sequence(topological)}",
            "roots ${sequence(roots)}","leaves ${sequence(leaves)}","moral_edges $moral width minfill $widthMinfill given $widthGiven");
        for(v in variables)lines.add("variable ${names[v]} states ${sizes[v]} parents ${parents[v].size} children ${children[v].size} depth ${depths[v]} ancestors ${ancestors[v].size} descendants ${descendants[v].size} blanket ${blankets[v].size}");
        return lines
    }
    fun writeBlocks(name: String,blocks: List<List<String>>) {
        val text=blocks.joinToString("\n\n") {
            it.joinToString("\n")
        };
        File("output").mkdirs();
        File("output",name).writeText(text+if(text.isEmpty())"" else "\n")
    }
    fun processQueries(queries: List<String>,cptReport: List<List<String>>) {
        val answers=mutableListOf<List<String>>();
        val elimination=mutableListOf<List<String>>();
        val structure=mutableListOf(structureSummary());
        val csv=mutableListOf("query,samples,variable,state,estimate,exact,abs_error");
        for((index,line) in queries.withIndex()) {
            val number=index+1;
            val tokens=line.split(' ');
            val kind=tokens[0];
            val fields=tokens.drop(1);
            val heading="query $number $line";
            when(kind) {
                "QUERY"-> {
                    val parts=parseParts(fields);
                    val answer=answerQuery(parts.query,parts.evidence);
                    answers.add(listOf(heading)+answer.lines);
                    elimination.add(listOf(heading)+answer.elimination)
                };
                "MPE"-> {
                    val answer=answerMpe(parseEvidence(fields));
                    answers.add(listOf(heading)+answer.lines);
                    elimination.add(listOf(heading)+answer.elimination)
                };
                "SAMPLE"-> {
                    val separator=fields.indexOf("COUNTS");
                    val parts=parseParts(fields.take(separator));
                    val checkpoints=fields.drop(separator+1).map {
                        it.toInt()
                    };
                    val answer=answerSample(number,parts.query,parts.evidence,checkpoints);
                    answers.add(listOf(heading)+answer.lines);
                    csv.addAll(answer.csv)
                };
                "PREDICT"->answers.add(listOf(heading)+answerPredict(names.indexOf(fields.first())));
                "DSEP"-> {
                    val groups=mutableListOf(mutableListOf<Int>());
                    for(field in fields)if(field=="|")groups.add(mutableListOf()) else groups.last().add(names.indexOf(field));
                    structure.add(listOf(heading)+answerDsep(groups))
                };
                "BLANKET"->structure.add(listOf(heading)+answerBlanket(names.indexOf(fields.first())));
                "EDGE"->structure.add(listOf(heading)+answerEdge(fields[0],names.indexOf(fields[1]),
                    names.indexOf(fields[2])))
            }
        };
        writeBlocks("cpts.txt",cptReport);
        writeBlocks("structure.txt",structure);
        writeBlocks("answers.txt",answers);
        writeBlocks("elimination.txt",elimination);
        writeBlocks("sampling.csv",listOf(csv))
    }
    @JvmStatic fun main(args: Array<String>) {
        val input=NetworkIo.read();
        prepare(input);
        val cptReport=cptBlocks();
        processQueries(input.queries,cptReport)
    }
}
