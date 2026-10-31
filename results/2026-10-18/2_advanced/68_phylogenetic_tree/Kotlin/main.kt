import java.io.File
import kotlin.math.*
object Phylogenetics {
    val njMethods=listOf("NJ_P","NJ_JC","NJ_K2P");
    val methods=njMethods+listOf("ME","MP","CONSENSUS")
    lateinit var parameters: Map<String,List<String>>;
    lateinit var records: List<Alignment.Record>;
    val names=mutableListOf<String>();
    val sequences=mutableListOf<String>();
    val rejected=mutableListOf<String>();
    lateinit var patterns: Alignment.Patterns;
    var count=0;
    var length=0;
    var outgroup=0;
    lateinit var mainMethod: String;
    val trees=linkedMapOf<String,TreeBuilding.Tree>();
    val matrices=linkedMapOf<String,Distances.Matrix>();
    val patristic=mutableMapOf<String,Array<DoubleArray>>();
    val siteLogs=mutableMapOf<String,DoubleArray>();
    val njScores=mutableMapOf<String,Int>();
    lateinit var mainMatrix: Array<DoubleArray>;
    val support=mutableMapOf<Int,Int>()
    data class Bounds(val minimum: Int,val maximum: Int,val minima: IntArray)
    data class Addition(val taxon: Int,val mask: Int,val score: Int,val ties: Int)
    data class Stepwise(val tree: TreeBuilding.Tree,val initial: Int,val score: Int,val evaluated: Int,
        val additions: List<Addition>,val taxa: List<Int>)
    data class Move(val mask: Int,val swap: Int,val value: Double)
    data class Hill(val tree: TreeBuilding.Tree,val value: Double,val evaluated: Int,val moves: List<Move>)
    data class SearchRecord(val tree: TreeBuilding.Tree,val score: Int,val bme: Double,val newick: String,
        val splits: Set<Int>)
    class Exhaustive(val taxa: List<Int>) {
        val records=mutableListOf<SearchRecord>();
        var optimal=listOf<SearchRecord>();
        val histogram=sortedMapOf<Int,Int>();
        var bestScore=0;
        var heuristic=0;
        lateinit var strict: TreeBuilding.Tree;
        lateinit var bestBme: SearchRecord;
        var secondBme=0.0
    }
    fun parameter(key: String)=parameters.getValue(key).first()
    fun integer(key: String)=parameter(key).toInt()
    fun realParameter(key: String)=parameter(key).toDouble()
    fun f(value: Double,places: Int)=TreeIo.real(value,places)
    fun symbols(mask: Int)=TreeIo.symbols(mask,count)
    fun yes(value: Boolean)=if(value)"yes" else "no"
    fun square(value: Double)=value*value
    fun taxa()=(0 until count).toList()
    fun sum(values: DoubleArray): Double {
        var total=0.0;
        for(value in values)total+=value;
        return total
    }
    fun rf(a: Set<Int>,b: Set<Int>)=(a-b).size+(b-a).size
    fun symbolOrder(masks: Collection<Int>)=masks.sortedBy {
        symbols(it)
    }
    fun read() {
        parameters=File("input","params.txt").readLines().associate {
            val w=it.split(' ');
            w[0] to w.drop(1)
        };
        records=Alignment.read();
        length=records.first().sequence.length;
        val seen=mutableSetOf<String>();
        for(record in records) {
            var reason: String?=null;
            val sequence=record.sequence;
            if(!seen.add(record.name))reason="duplicate name";
            if(reason==null)for((c,value) in sequence.withIndex())if(value !in Alignment.sets) {
                reason="invalid character $value at column ${c+1}";
                break
            };
            if(reason==null&&sequence.length!=length)reason="length mismatch ${sequence.length}";
            if(reason==null) {
                val missing=sequence.count {
                    it=='-'||it=='N'
                };
                if(100*missing>integer("max_missing_percent")*length)reason="too many missing $missing"
            };
            if(reason==null) {
                names.add(record.name);
                sequences.add(sequence)
            } else rejected.add("REJECT line ${record.line} ${record.name} $reason")
        };
        count=names.size;
        outgroup=names.indexOf(parameter("outgroup"));
        mainMethod="NJ_"+parameter("model");
        patterns=Alignment.Patterns(sequences)
    }
    fun summary(): List<String> {
        val lines=mutableListOf("INPUT records ${records.size} accepted $count rejected ${rejected.size} columns $length");
        lines.addAll(rejected);
        val columns=Array(length) {
            IntArray(4)
        };
        for(sequence in sequences)for(c in 0 until length) {
            val base=Alignment.BASES.indexOf(sequence[c]);
            if(base>=0)columns[c][base]++
        };
        val composition=IntArray(4);
        for((i,sequence) in sequences.withIndex()) {
            var bases=0;
            var ambiguous=0;
            var missing=0;
            var unique=0;
            var gc=0;
            for(c in 0 until length) {
                val value=sequence[c];
                val base=Alignment.BASES.indexOf(value);
                if(base>=0) {
                    bases++;
                    composition[base]++;
                    if(base==1||base==2)gc++;
                    if(columns[c][base]==1&&columns[c].sum()>1)unique++
                } else if(value in Alignment.AMBIGUOUS)ambiguous++ else missing++
            };
            lines.add("TAXON ${names[i]} bases $bases ambiguous $ambiguous missing $missing unique $unique gc ${f(gc.toDouble()/bases,4)}")
        };
        val classes=Alignment.classify(sequences);
        lines.add("COLUMNS constant ${classes[0]} variable ${classes[1]} informative ${classes[2]} gapped ${classes[3]} empty ${classes[4]}");
        lines.add("PATTERNS ${patterns.patterns.size}");
        val total=composition.sum();
        lines.add("COMPOSITION "+(0..3).joinToString(" ") {
            "${Alignment.BASES[it]} ${f(composition[it].toDouble()/total,4)}"
        });
        return lines
    }
    fun matrixLines(matrix: Array<DoubleArray>): List<String> {
        val width=names.maxOf {
            it.length
        };
        return names.mapIndexed {
            i,name->name.padEnd(width)+" "+matrix[i].joinToString(" ") {
                f(it,5)
            }
        }
    }
    fun bounds(): Bounds {
        val minima=IntArray(patterns.patterns.size);
        var maximum=0;
        for((i,pattern) in patterns.encoded.withIndex()) {
            minima[i]=(1..15).filter {
                mask->pattern.all {
                    (mask and it)!=0
                }
            }.minOf {
                Integer.bitCount(it)
            }
            -1;
            val greatest=listOf(1,2,4,8).minOf {
                base->pattern.count {
                    (it and base)==0
                }
            };
            maximum+=greatest*patterns.weights[i]
        };
        val columns=IntArray(length) {
            minima[patterns.columns[it]]
        };
        return Bounds(columns.sum(),maximum,columns)
    }
    fun bme(tree: TreeBuilding.Tree): Double {
        val taxa=tree.taxa();
        var total=0.0;
        for((i,a) in taxa.withIndex()) {
            val steps=TreeBuilding.paths(tree,a,true);
            for(b in taxa.drop(i+1))total+=Math.scalb(mainMatrix[a][b],1-steps[b].toInt())
        };
        return total
    }
    fun stepwise(taxa: List<Int>): Stepwise {
        var tree=TreeBuilding.star(count,taxa.take(3));
        val initial=Parsimony.score(tree,patterns,outgroup);
        var score=initial;
        var evaluated=0;
        val additions=mutableListOf<Addition>();
        for(taxon in taxa.drop(3)) {
            var best=Int.MAX_VALUE;
            var chosen: TreeBuilding.Tree?=null;
            var mask=0;
            var ties=0;
            for(edge in Parsimony.branches(tree,outgroup)) {
                val candidate=Parsimony.insert(tree,edge.first,edge.second,taxon);
                val value=Parsimony.score(candidate,patterns,outgroup);
                evaluated++;
                if(value<best) {
                    best=value;
                    chosen=candidate;
                    mask=edge.mask;
                    ties=1
                } else if(value==best)ties++
            };
            tree=chosen!!;
            score=best;
            additions.add(Addition(taxon,mask,score,ties))
        };
        return Stepwise(tree,initial,score,evaluated,additions,taxa)
    }
    fun hill(initial: TreeBuilding.Tree,objective: (TreeBuilding.Tree)->Double,initialValue: Double): Hill {
        var tree=initial.copy();
        var value=initialValue;
        var evaluated=0;
        val moves=mutableListOf<Move>();
        while(true) {
            var moved=false;
            for(candidate in Parsimony.nni(tree,outgroup)) {
                val result=objective(candidate.tree);
                evaluated++;
                if(result<value) {
                    tree=candidate.tree;
                    value=result;
                    moves.add(Move(candidate.mask,candidate.swap,value));
                    moved=true;
                    break
                }
            };
            if(!moved)break
        };
        return Hill(tree,value,evaluated,moves)
    }
    fun consensus(taxa: List<Int>,clades: Set<Int>): TreeBuilding.Tree {
        val tree=TreeBuilding.Tree(count);
        val root=tree.internal();
        val nodes=clades.sorted().associateWith {
            tree.internal()
        };
        for((mask,node) in nodes) {
            val containers=nodes.keys.filter {
                it!=mask&&(it and mask)==mask
            };
            val parent=containers.minByOrNull {
                Integer.bitCount(it)
            }
            ?.let {
                nodes.getValue(it)
            }
            ?:root;
            tree.connect(parent,node)
        };
        for(taxon in taxa) {
            val containers=nodes.keys.filter {
                (it and (1 shl taxon))!=0
            };
            val parent=containers.minByOrNull {
                Integer.bitCount(it)
            }
            ?.let {
                nodes.getValue(it)
            }
            ?:root;
            tree.connect(parent,taxon)
        };
        return tree
    }
    fun exhaustive(taxa: List<Int>): Exhaustive {
        val result=Exhaustive(taxa);
        var trees=listOf(TreeBuilding.star(count,taxa.take(3)));
        for(taxon in taxa.drop(3))trees=trees.flatMap {
            tree->Parsimony.branches(tree,outgroup).map {
                Parsimony.insert(tree,it.first,it.second,taxon)
            }
        };
        for(tree in trees) {
            val score=Parsimony.score(tree,patterns,outgroup);
            result.histogram[score]=result.histogram.getOrDefault(score,0)+1;
            result.records.add(SearchRecord(tree,score,bme(tree),TreeIo.newick(tree,names,outgroup),
                tree.rooted(outgroup).splits()))
        };
        result.bestScore=result.histogram.firstKey();
        result.optimal=result.records.filter {
            it.score==result.bestScore
        }.sortedBy {
            it.newick
        };
        var common=result.optimal.first().splits;
        for(record in result.optimal)common=common.intersect(record.splits);
        result.strict=consensus(taxa,common);
        result.bestBme=result.records.minWith(compareBy<SearchRecord> {
            it.bme
        }.thenBy {
            it.newick
        });
        result.secondBme=result.records.filter {
            it!==result.bestBme
        }.minOf {
            it.bme
        };
        val initial=stepwise(taxa);
        result.heuristic=hill(initial.tree, {
            Parsimony.score(it,patterns,outgroup).toDouble()
        },initial.score.toDouble()).value.toInt();
        return result
    }
    fun likelihood(tree: TreeBuilding.Tree): DoubleArray {
        val rooted=tree.rooted(outgroup);
        val children=TreeIo.childOrder(rooted,names);
        val transition=Array(tree.nextNode) {
            Array(4) {
                DoubleArray(4)
            }
        };
        for(node in rooted.order)if(node!=rooted.root) {
            val branch=tree.adjacent[node].getValue(rooted.parents[node]);
            val e=exp(-4*branch/3);
            for(a in 0..3)for(b in 0..3)transition[node][a][b]=if(a==b)0.25+0.75*e else 0.25-0.25*e
        };
        val values=DoubleArray(patterns.patterns.size);
        for((p,pattern) in patterns.encoded.withIndex()) {
            val partial=Array(tree.nextNode) {
                DoubleArray(4)
            };
            val upward=Array(tree.nextNode) {
                DoubleArray(4)
            };
            for(node in rooted.order.asReversed()) {
                if(node<tree.size) {
                    for(a in 0..3)partial[node][a]=if((pattern[node] and (1 shl a))!=0)1.0 else 0.0
                } else {
                    partial[node].fill(1.0);
                    for(child in children[node])for(a in 0..3)partial[node][a]*=upward[child][a]
                };
                if(node!=rooted.root)for(a in 0..3)for(b in 0..3)upward[node][a]+=transition[node][a][b]*partial[node][b]
            };
            var probability=0.0;
            for(value in partial[rooted.root])probability+=0.25*value;
            values[p]=ln(probability)
        };
        return DoubleArray(length) {
            values[patterns.columns[it]]
        }
    }
    fun likelihoodLines(): List<String> {
        val lines=mutableListOf("LIKELIHOOD columns $length patterns ${patterns.patterns.size}");
        for(method in njMethods) {
            val total=sum(siteLogs.getValue(method));
            lines.add("TREE $method loglik ${f(total,4)} per_site ${f(total/length,4)}")
        };
        for(i in 0..2)for(j in i+1..2) {
            val a=njMethods[i];
            val b=njMethods[j];
            val deltas=DoubleArray(length) {
                siteLogs.getValue(a)[it]-siteLogs.getValue(b)[it]
            };
            val difference=sum(deltas);
            val mean=difference/length;
            var ss=0.0;
            for(delta in deltas)ss+=square(delta-mean);
            val se=sqrt(length.toDouble()/(length-1)*ss);
            lines.add("KH $a $b difference ${f(difference,4)} se ${f(se,4)} z ${f(difference/se,4)}")
        };
        val columns=(0 until length).sortedWith(compareBy<Int> {
            f(siteLogs.getValue(mainMethod)[it],4).toDouble()
        }.thenBy {
            it
        });
        val changes=Parsimony.patternScores(trees.getValue(mainMethod),patterns,outgroup);
        val low=integer("low_sites");
        lines.add("LOWEST $mainMethod sites $low");
        for(c in columns.take(low)) {
            val p=patterns.columns[c];
            lines.add("SITE ${c+1} loglik ${f(siteLogs.getValue(mainMethod)[c],4)} changes ${changes[p]} pattern ${patterns.patterns[p]}")
        };
        return lines
    }
    fun bootstrap(): List<String> {
        val replicates=integer("replicates");
        var state=parameter("seed").toLong();
        val mainSplits=trees.getValue(mainMethod).rooted(outgroup).splits();
        val lines=mutableListOf("BOOTSTRAP model ${parameter("model")} replicates $replicates seed $state");
        var identical=0;
        for(b in 1..replicates) {
            val weights=IntArray(length);
            repeat(length) {
                state=48271*state%2147483647;
                weights[(state%length).toInt()]++
            };
            val matrix=Distances.matrix(Distances.pairs(sequences,weights),count,parameter("model"),
                realParameter("saturation_distance")).values;
            val splits=TreeBuilding.nj(matrix,taxa()).rooted(outgroup).splits();
            for(mask in splits)support[mask]=support.getOrDefault(mask,0)+1;
            val difference=rf(splits,mainSplits);
            if(difference==0)identical++;
            lines.add("REPLICATE $b distinct ${weights.count{it>0}} rf $difference")
        };
        lines.add("IDENTICAL $identical");
        for(mask in symbolOrder(mainSplits))lines.add("SUPPORT ${symbols(mask)} ${support.getOrDefault(mask,0)}");
        for(mask in support.keys.sortedWith(compareByDescending<Int> {
            support.getValue(it)
        }.thenBy {
            symbols(it)
        }))lines.add("SPLIT ${symbols(mask)} ${support.getValue(mask)}");
        val majority=support.filterValues {
            2*it>replicates
        }.keys;
        val consensusTree=consensus(taxa(),majority);
        trees["CONSENSUS"]=consensusTree;
        lines.add("CONSENSUS ${TreeIo.newick(consensusTree,names,outgroup,support=support)}");
        for(taxon in 0 until count)if(taxon!=outgroup) {
            val tree=TreeBuilding.nj(mainMatrix,taxa().filter {
                it!=taxon
            });
            val reduced=mainSplits.map {
                it and (1 shl taxon).inv()
            }.filter {
                Integer.bitCount(it) in 2..count-3
            }.toSet();
            lines.add("JACKKNIFE ${names[taxon]} rf ${rf(tree.rooted(outgroup).splits(),reduced)}")
        };
        return lines
    }
    fun clock(): List<String> {
        val ingroup=taxa().filter {
            it!=outgroup
        };
        val pairs=mutableListOf<String>();
        var rejected=0;
        for((i,a) in ingroup.withIndex())for(b in ingroup.drop(i+1)) {
            var m1=0;
            var m2=0;
            for(c in 0 until length) {
                val x=sequences[a][c];
                val y=sequences[b][c];
                val o=sequences[outgroup][c];
                if(x in Alignment.BASES&&y in Alignment.BASES&&o in Alignment.BASES&&x!=y) {
                    if(y==o)m1++;
                    if(x==o)m2++
                }
            };
            val difference=m1-m2;
            val total=m1+m2;
            val reject=1000*difference*difference>3841*total;
            if(reject)rejected++;
            pairs.add("RRT ${names[a]} ${names[b]} m1 $m1 m2 $m2 chi2 ${if(total==0)"-" else f(difference.toDouble()*difference/total,4)} ${if(reject)"reject" else "ok"}")
        };
        val lines=mutableListOf("RELATIVE_RATE outgroup ${names[outgroup]} pairs ${pairs.size} rejected $rejected");
        lines.addAll(pairs);
        val tree=trees.getValue(mainMethod);
        val paths=TreeBuilding.paths(tree,tree.rooted(outgroup).root);
        var mean=0.0;
        for(t in ingroup)mean+=paths[t];
        mean/=ingroup.size;
        var ss=0.0;
        for(t in ingroup)ss+=square(paths[t]-mean);
        val sd=sqrt(ss/(ingroup.size-1));
        lines.add("ROOT_TO_TIP $mainMethod mean ${f(mean,5)} sd ${f(sd,5)} cv ${f(sd/mean,4)}");
        for(t in ingroup)lines.add("TIP ${names[t]} ${f(paths[t],5)}");
        return lines
    }
    fun quartets(splits: Set<Int>): IntArray {
        val values=mutableListOf<Int>();
        for(a in 0 until count)for(b in a+1 until count)for(c in b+1 until count)for(d in c+1 until count) {
            val quartet=(1 shl a) or (1 shl b) or (1 shl c) or (1 shl d);
            var topology=0;
            for((i,other) in listOf(b,c,d).withIndex()) {
                val side=(1 shl a) or (1 shl other);
                if(splits.any {
                    val part=it and quartet;
                    part==side||part==(quartet xor side)
                }) {
                    topology=i+1;
                    break
                }
            };
            values.add(topology)
        };
        return values.toIntArray()
    }
    fun comparison(mp: Hill,reconstruction: Parsimony.Reconstruction): List<String> {
        val splits=methods.associateWith {
            trees.getValue(it).rooted(outgroup).splits()
        };
        val lines=mutableListOf<String>();
        val replicates=integer("replicates");
        for(method in methods) {
            val tree=trees.getValue(method);
            val supported=splits.getValue(method).count {
                2*support.getOrDefault(it,0)>replicates
            };
            var score="-";
            var bmeText="-";
            var treeLength="-";
            var negative="-";
            var residual="-";
            var likelihood="-";
            if(method!="CONSENSUS") {
                score=(when(method) {
                    "MP"->mp.value.toInt();
                    "ME"->Parsimony.score(tree,patterns,outgroup);
                    else->njScores.getValue(method)
                }).toString();
                bmeText=f(bme(tree),5)
            };
            if(method in njMethods) {
                var total=0.0;
                for(edge in Parsimony.branches(tree,outgroup))total+=tree.adjacent[edge.first].getValue(edge.second);
                treeLength=f(total,5);
                negative=tree.negative.toString();
                var ss=0.0;
                val matrix=matrices.getValue(method.substring(3)).values;
                val paths=patristic.getValue(method);
                for(i in 0 until count)for(j in i+1 until count)ss+=square(matrix[i][j]-paths[i][j]);
                residual=f(ss,6);
                likelihood=f(sum(siteLogs.getValue(method)),4)
            } else if(method=="MP")treeLength=f(mp.value/length,5);
            lines.add("TREE $method splits ${splits.getValue(method).size} supported $supported parsimony $score bme $bmeText length $treeLength negative $negative sse $residual loglik $likelihood")
        };
        lines.add("RF "+methods.joinToString(" "));
        for(a in methods)lines.add(a+" "+methods.joinToString(" ") {
            rf(splits.getValue(a),splits.getValue(it)).toString()
        });
        val quartetValues=methods.associateWith {
            quartets(splits.getValue(it))
        };
        lines.add("QUARTET "+methods.joinToString(" "));
        for(a in methods)lines.add(a+" "+methods.joinToString(" ") {
            b->quartetValues.getValue(a).indices.count {
                quartetValues.getValue(a)[it]!=quartetValues.getValue(b)[it]
            }.toString()
        });
        val all=splits.values.flatten().toSet();
        val lengths=trees.getValue(mainMethod).rooted(outgroup).branchLengths();
        val changes=Parsimony.branches(trees.getValue("MP"),outgroup).associate {
            it.mask to reconstruction.branchChanges.getValue(Parsimony.Ends.of(it.first,it.second))
        };
        for(mask in symbolOrder(all)) {
            val marks=methods.joinToString("") {
                if(mask in splits.getValue(it))"+" else "-"
            };
            lines.add("CLADE ${symbols(mask)} support ${support.getOrDefault(mask,0)} trees $marks length ${lengths[mask]?.let{f(it,5)}?:"-"} changes ${changes[mask]?.toString()?:"-"}")
        };
        return lines
    }
    fun hypotheses(exhaustive: Exhaustive): List<String> {
        val numbers=names.withIndex().associate {
            it.value to it.index
        };
        val ingroup=((1 shl count)-1) xor (1 shl outgroup);
        var exhaustiveIngroup=0;
        for(t in exhaustive.taxa)if(t!=outgroup)exhaustiveIngroup=exhaustiveIngroup or (1 shl t);
        val splits=methods.associateWith {
            trees.getValue(it).rooted(outgroup).splits()
        };
        val lines=mutableListOf<String>();
        for(line in File("input","clades.txt").readLines()) {
            val w=line.split(' ');
            val hypothesis=w[0];
            val members=w.drop(1);
            val unknown=members.firstOrNull {
                it !in numbers
            };
            if(unknown!=null) {
                lines.add("INVALID $hypothesis unknown taxon $unknown");
                continue
            };
            if(names[outgroup] in members) {
                lines.add("INVALID $hypothesis contains outgroup");
                continue
            };
            var mask=0;
            for(name in members)mask=mask or (1 shl numbers.getValue(name));
            lines.add("CLADE $hypothesis taxa ${Integer.bitCount(mask)} support ${support.getOrDefault(mask,0)}");
            for(method in methods) {
                val common=(splits.getValue(method)+ingroup).filter {
                    (it and mask)==mask
                }.minBy {
                    Integer.bitCount(it)
                };
                val intruders=names.filterIndexed {
                    t,_->(common and mask.inv() and (1 shl t))!=0
                };
                lines.add("TEST $hypothesis $method monophyletic ${yes(common==mask)} mrca ${Integer.bitCount(common)} intruders ${if(intruders.isEmpty())"-" else intruders.joinToString(",")}")
            };
            val subset=mask and exhaustiveIngroup;
            val size=Integer.bitCount(subset);
            if(size<2||size>=Integer.bitCount(exhaustiveIngroup)) {
                lines.add("SUBSET $hypothesis untestable");
                continue
            };
            val included=exhaustive.records.filter {
                subset in it.splits
            };
            val excluded=exhaustive.records.filter {
                subset !in it.splits
            };
            lines.add("SUBSET $hypothesis taxa $size with ${included.minOf{it.score}} without ${excluded.minOf{it.score}} bme_with ${f(included.minOf{it.bme},5)} bme_without ${f(excluded.minOf{it.bme},5)}")
        };
        return lines
    }
    fun distanceLines(pairs: List<Distances.Pair>,start: Double,me: Hill,exhaustive: Exhaustive): List<String> {
        val lines=mutableListOf<String>();
        var n=0;
        var s=0;
        var v=0;
        for(pair in pairs) {
            lines.add("PAIR ${names[pair.first]} ${names[pair.second]} sites ${pair.sites} transitions ${pair.transitions} transversions ${pair.transversions}");
            n+=pair.sites;
            s+=pair.transitions;
            v+=pair.transversions
        };
        lines.add("TOTAL sites $n transitions $s transversions $v");
        for(model in Distances.models) {
            lines.add("");
            lines.add("MODEL $model");
            val matrix=matrices.getValue(model);
            lines.addAll(matrixLines(matrix.values));
            for(pair in matrix.saturated)lines.add("SATURATED ${names[pair.first]} ${names[pair.second]} sites ${pair.sites}")
        };
        lines.add("");
        lines.add("PATRISTIC $mainMethod");
        lines.addAll(matrixLines(patristic.getValue(mainMethod)));
        lines.add("");
        lines.add("ME start $mainMethod length ${f(start,5)}");
        for(move in me.moves)lines.add("NNI edge ${symbols(move.mask)} swap ${move.swap} length ${f(move.value,5)}");
        lines.add("ME moves ${me.moves.size} evaluated ${me.evaluated} length ${f(me.value,5)}");
        lines.add("EXHAUSTIVE taxa ${exhaustive.taxa.size} trees ${exhaustive.records.size} best ${f(exhaustive.bestBme.bme,5)} second ${f(exhaustive.secondBme,5)}");
        lines.add("BEST ${exhaustive.bestBme.newick} parsimony ${exhaustive.bestBme.score}");
        return lines
    }
    fun scoreLine(method: String,score: Int,bounds: Bounds)="TREE $method score $score ci ${f(bounds.minimum.toDouble()/score,4)} ri ${f((bounds.maximum-score).toDouble()/(bounds.maximum-bounds.minimum),4)}"
    fun parsimonyLines(bounds: Bounds,initial: Stepwise,search: Hill,reconstruction: Parsimony.Reconstruction,
        exhaustive: Exhaustive): List<String> {
        val lines=mutableListOf("BOUNDS minimum ${bounds.minimum} maximum ${bounds.maximum}");
        for(method in njMethods)lines.add(scoreLine(method,njScores.getValue(method),bounds));
        lines.add("START ${initial.taxa.take(3).joinToString(" "){names[it]}} score ${initial.initial}");
        for(a in initial.additions)lines.add("ADD ${names[a.taxon]} edge ${symbols(a.mask)} score ${a.score} ties ${a.ties}");
        lines.add("STEPWISE score ${initial.score} evaluated ${initial.evaluated}");
        for(move in search.moves)lines.add("NNI edge ${symbols(move.mask)} swap ${move.swap} score ${move.value.toInt()}");
        val score=search.value.toInt();
        lines.add("SEARCH moves ${search.moves.size} evaluated ${search.evaluated} score $score");
        lines.add(scoreLine("MP",score,bounds));
        lines.add("MP ${TreeIo.newick(search.tree,names,outgroup,lengths=true)}");
        val changes=reconstruction.siteChanges;
        for(k in 0..changes.max())lines.add("CHANGES $k columns ${changes.count{it==k}}");
        val homoplasy=changes.indices.count {
            changes[it]>bounds.minima[it]
        };
        lines.add("HOMOPLASY columns $homoplasy extra ${score-bounds.minimum}");
        val rooted=search.tree.rooted(outgroup);
        val ancestors=reconstruction.ancestors.map {
            (node,sequence)->symbols(if(node==rooted.root)rooted.ingroup else rooted.masks[node]) to sequence
        }.sortedBy {
            it.first
        };
        for((symbol,sequence) in ancestors)lines.add("ANCESTOR $symbol $sequence");
        lines.add("");
        lines.add("EXHAUSTIVE taxa ${exhaustive.taxa.size} trees ${exhaustive.records.size} best ${exhaustive.bestScore} optimal ${exhaustive.optimal.size}");
        for((value,number) in exhaustive.histogram)lines.add("SCORE $value trees $number");
        for(record in exhaustive.optimal)lines.add("OPTIMAL ${record.newick} bme ${f(record.bme,5)}");
        lines.add("STRICT ${TreeIo.newick(exhaustive.strict,names,outgroup)}");
        lines.add("HEURISTIC score ${exhaustive.heuristic} optimal ${yes(exhaustive.heuristic==exhaustive.bestScore)}");
        return lines
    }
    @JvmStatic fun main(args: Array<String>) {
        read();
        val weights=IntArray(length) {
            1
        };
        val pairs=Distances.pairs(sequences,weights);
        for((i,model) in Distances.models.withIndex()) {
            val matrix=Distances.matrix(pairs,count,model,realParameter("saturation_distance"));
            matrices[model]=matrix;
            trees[njMethods[i]]=TreeBuilding.nj(matrix.values,taxa())
        };
        mainMatrix=matrices.getValue(parameter("model")).values;
        val start=bme(trees.getValue(mainMethod));
        val me=hill(trees.getValue(mainMethod),::bme,start);
        val order=listOf(outgroup)+taxa().filter {
            it!=outgroup
        };
        val initial=stepwise(order);
        val mp=hill(initial.tree, {
            Parsimony.score(it,patterns,outgroup).toDouble()
        },initial.score.toDouble());
        val reconstruction=Parsimony.reconstruct(mp.tree,patterns,outgroup);
        for((edge,changes) in reconstruction.branchChanges)mp.tree.connect(edge.first,edge.second,
            changes.toDouble()/length);
        val scoreBounds=bounds();
        for(method in njMethods)njScores[method]=Parsimony.score(trees.getValue(method),patterns,
            outgroup);
        val exhaustiveNames=parameters.getValue("exhaustive_taxa").toSet();
        val exhaustiveTaxa=listOf(outgroup)+taxa().filter {
            it!=outgroup&&names[it] in exhaustiveNames
        };
        val exhaustiveResult=exhaustive(exhaustiveTaxa);
        for(method in njMethods) {
            siteLogs[method]=likelihood(trees.getValue(method));
            patristic[method]=TreeBuilding.patristic(trees.getValue(method))
        };
        trees["ME"]=me.tree;
        trees["MP"]=mp.tree;
        val bootstrapReport=bootstrap();
        val newicks=mutableListOf<String>();
        val diagrams=mutableListOf<String>();
        for(method in methods) {
            val tree=trees.getValue(method);
            val lengths=method in njMethods||method=="MP";
            newicks.add(method+" "+TreeIo.newick(tree,names,outgroup,lengths,if(method=="CONSENSUS")support else null));
            if(diagrams.isNotEmpty())diagrams.add("");
            diagrams.add("TREE $method");
            diagrams.addAll(TreeIo.cladogram(tree,names,outgroup,support))
        };
        TreeIo.write("summary.txt",summary());
        TreeIo.write("distances.txt",distanceLines(pairs,start,me,exhaustiveResult));
        TreeIo.write("trees.nwk",newicks);
        TreeIo.write("cladograms.txt",diagrams);
        TreeIo.write("parsimony.txt",parsimonyLines(scoreBounds,initial,mp,reconstruction,exhaustiveResult));
        TreeIo.write("likelihood.txt",likelihoodLines());
        TreeIo.write("bootstrap.txt",bootstrapReport);
        TreeIo.write("clock.txt",clock());
        TreeIo.write("comparison.txt",comparison(mp,reconstruction));
        TreeIo.write("hypotheses.txt",hypotheses(exhaustiveResult))
    }
}
