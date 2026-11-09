object FmAligner {
    lateinit var references: List<SequenceIo.Reference>;
    lateinit var parameters: Map<String,IntArray>;
    lateinit var text: String;
    lateinit var reverseText: String;
    lateinit var offsets: IntArray;
    lateinit var forward: FmIndex;
    lateinit var reverse: FmIndex;
    val searchCounts=IntArray(4);
    val seedCounts=IntArray(7);
    const val NEG=-1000000
    data class Position(val reference: Int,val offset: Int)
    data class Pair(val readOffset: Int,val offset: Int)
    data class Run(val operation: Char,val count: Int)
    data class Hit(val mismatches: Int,val reference: Int,val position: Int,val strand: Int)
    data class Candidate(val strand: Int,val reference: Int,val center: Int)
    data class Key(val reference: Int,val position: Int,val strand: Int)
    data class Banded(val score: Int,val position: Int,val operations: String)
    data class Scored(val score: Int,val alignment: Alignment)
    class Alignment(val reference: Int,val position: Int,val strand: Int,val operations: String,
        val oriented: String) {
        var nm=0;
        var cigar="";
        var md="";
        val pairs=mutableListOf<Pair>()
    }
    class Result(val read: SequenceIo.Read) {
        val qualities=IntArray(read.quality.length) {
            read.quality[it].code-33
        };
        var length=read.bases.length;
        var trimmed=0;
        var mapq=0;
        var score=0;
        var x0=0;
        var x1=0;
        var core="";
        var reason="SHORT";
        var method="";
        var mapped=false;
        var primary: Alignment?=null;
        var others=listOf<Alignment>();
        var targets=listOf<Int>()
    }
    fun value(key: String)=parameters.getValue(key)[0]
    fun ratio(a: Int,b: Int)=SamWriter.ratio(a,b)
    fun yes(value: Boolean)=if(value)"yes" else "no"
    fun buildText() {
        offsets=IntArray(references.size);
        var offset=0;
        for((r,reference) in references.withIndex()) {
            offsets[r]=offset;
            offset+=reference.bases.length+1
        };
        text=references.joinToString("#") {
            it.bases
        }+"$";
        reverseText=text.dropLast(1).reversed()+"$"
    }
    fun position(p: Int): Position? {
        for(r in references.indices.reversed())if(p>=offsets[r])return if(p<offsets[r]+references[r].bases.length)Position(r,
            p-offsets[r]) else null;
        return null
    }
    fun label(p: Int): String {
        val located=position(p)?:return "*";
        return "${references[located.reference].name}:${located.offset+1}"
    }
    fun locate(row: Int)=position(forward.locate(row).position)!!
    fun runs(operations: String): List<Run> {
        val result=mutableListOf<Run>();
        var i=0;
        while(i<operations.length) {
            var j=i+1;
            while(j<operations.length&&operations[j]==operations[i])j++;
            result.add(Run(operations[i],j-i));
            i=j
        };
        return result
    }
    fun describe(reference: Int,position: Int,strand: Int,operations: String,result: Result): Alignment {
        val a=Alignment(reference,position,strand,operations,if(strand==0)result.core else SequenceIo.reverseComplement(result.core));
        val sequence=references[reference].bases;
        val cigar=StringBuilder();
        val md=StringBuilder();
        var i=0;
        var j=position;
        var matches=0;
        for(run in runs(operations)) {
            val count=run.count;
            cigar.append(count).append(run.operation);
            when(run.operation) {
                'I'-> {
                    i+=count;
                    a.nm+=count
                };
                'D'-> {
                    md.append(matches).append('^').append(sequence.substring(j,j+count));
                    matches=0;
                    j+=count;
                    a.nm+=count
                };
                else->repeat(count) {
                    a.pairs.add(Pair(i,j));
                    if(a.oriented[i]==sequence[j])matches++ else {
                        md.append(matches).append(sequence[j]);
                        matches=0;
                        a.nm++
                    };
                    i++;
                    j++
                }
            }
        };
        md.append(matches);
        if(result.trimmed>0) {
            val soft="${result.trimmed}S";
            if(strand==0)cigar.append(soft) else cigar.insert(0,soft)
        };
        a.cigar=cigar.toString();
        a.md=md.toString();
        return a
    }
    fun cell(values: Array<IntArray>,first: IntArray,i: Int,j: Int): Int {
        if(i !in values.indices)return NEG;
        val k=j-first[i];
        return if(k in values[i].indices)values[i][k] else NEG
    }
    fun subtract(value: Int,penalty: Int)=if(value==NEG)NEG else value-penalty
    fun banded(oriented: String,sequence: String,center: Int): Banded? {
        val l=oriented.length;
        val m=sequence.length;
        val width=value("BAND_WIDTH");
        val scores=parameters.getValue("SCORES");
        val first=IntArray(l+1) {
            maxOf(0,it+center-width)
        };
        val h=Array(l+1) {
            i->IntArray(maxOf(0,minOf(m,i+center+width)-first[i]+1)) {
                if(i==0)0 else NEG
            }
        };
        val e=Array(l+1) {
            IntArray(h[it].size) {
                NEG
            }
        };
        val f=Array(l+1) {
            IntArray(h[it].size) {
                NEG
            }
        };
        for(i in 1..l)for(k in h[i].indices) {
            val j=first[i]+k;
            f[i][k]=maxOf(subtract(cell(h,first,i-1,j),scores[2]+scores[3]),subtract(cell(f,
                first,i-1,j),scores[3]));
            if(j>=1)e[i][k]=maxOf(subtract(cell(h,first,i,j-1),scores[2]+scores[3]),subtract(cell(e,
                first,i,j-1),scores[3]));
            var diagonal=NEG;
            if(j>=1) {
                val previous=cell(h,first,i-1,j-1);
                if(previous!=NEG)diagonal=previous+(if(oriented[i-1]==sequence[j-1])scores[0] else -scores[1])
            };
            h[i][k]=maxOf(diagonal,e[i][k],f[i][k])
        };
        var best=NEG;
        var end=-1;
        for(k in h[l].indices)if(h[l][k]>best) {
            best=h[l][k];
            end=first[l]+k
        };
        if(end<0)return null;
        var i=l;
        var j=end;
        var state='H';
        val backward=StringBuilder();
        while(true) {
            if(state=='H') {
                if(i==0)break;
                val previous=if(j>=1)cell(h,first,i-1,j-1) else NEG;
                if(previous!=NEG&&cell(h,first,i,j)==previous+(if(oriented[i-1]==sequence[j-1])scores[0] else -scores[1])) {
                    backward.append('M');
                    i--;
                    j--;
                    continue
                };
                state=if(cell(f,first,i,j)!=NEG&&cell(h,first,i,j)==cell(f,first,i,j))'I' else 'D'
            } else if(state=='I') {
                backward.append('I');
                val previous=cell(f,first,i-1,j);
                state=if(previous!=NEG&&cell(f,first,i,j)==previous-scores[3])'I' else 'H';
                i--
            } else {
                backward.append('D');
                val previous=cell(e,first,i,j-1);
                state=if(previous!=NEG&&cell(e,first,i,j)==previous-scores[3])'D' else 'H';
                j--
            }
        };
        return Banded(best,j,backward.reverse().toString())
    }
    val alignmentOrder=compareBy<Alignment> {
        it.reference
    }.thenBy {
        it.position
    }.thenBy {
        it.strand
    }
    fun map(read: SequenceIo.Read): Result {
        val result=Result(read);
        while(result.length>0&&result.qualities[result.length-1]<value("TRIM_QUALITY"))result.length--;
        result.trimmed=read.bases.length-result.length;
        result.core=read.bases.take(result.length);
        if(result.length<value("MIN_READ_LENGTH"))return result;
        val oriented=listOf(result.core,SequenceIo.reverseComplement(result.core));
        val exact=oriented.map {
            forward.backward(it)
        };
        val maximum=if(exact.any {
            !it.empty()
        })1 else value("MAX_MISMATCHES");
        val hits=mutableListOf<Hit>();
        for((strand,sequence) in oriented.withIndex()) {
            val search=Search.backtrack(sequence,maximum,forward,reverse);
            searchCounts[0]++;
            searchCounts[1]+=search.nodes;
            searchCounts[2]+=search.leaves.size;
            searchCounts[3]+=search.positions;
            for(leaf in search.leaves)for(row in leaf.lower until leaf.upper) {
                val position=locate(row);
                hits.add(Hit(leaf.mismatches,position.reference,position.offset,strand))
            }
        };
        if(hits.isEmpty())seed(result,oriented) else finish(result,hits);
        return result
    }
    fun finish(result: Result,hits: List<Hit>) {
        val ordered=hits.sortedWith(compareBy<Hit> {
            it.mismatches
        }.thenBy {
            it.reference
        }.thenBy {
            it.position
        }.thenBy {
            it.strand
        });
        val best=ordered.first().mismatches;
        val n1=ordered.count {
            it.mismatches==best
        };
        val n2=ordered.count {
            it.mismatches==best+1
        };
        val alignments=ordered.filter {
            it.mismatches<=best+1
        }.map {
            describe(it.reference,it.position,it.strand,"M".repeat(result.length),result)
        };
        result.mapped=true;
        result.primary=alignments.first();
        result.others=alignments.drop(1);
        result.targets=ordered.filter {
            it.mismatches==best
        }.map {
            it.reference
        }.distinct().sorted();
        result.method=if(best==0)"EXACT" else "MISMATCH";
        val scores=parameters.getValue("SCORES");
        result.score=(result.length-best)*scores[0]-best*scores[1];
        result.x0=n1;
        result.x1=n2;
        result.mapq=if(n1>=2)0 else if(n2==0)60-12*best else maxOf(30-12*best-3*n2,1)
    }
    fun candidates(oriented: List<String>): List<Candidate> {
        val candidates=mutableSetOf<Candidate>();
        val seedLength=value("SEED_LENGTH");
        for((strand,sequence) in oriented.withIndex())for(offset in 0..sequence.length-seedLength step value("SEED_STEP")) {
            seedCounts[1]++;
            val seed=sequence.substring(offset,offset+seedLength);
            if('N' in seed) {
                seedCounts[2]++;
                continue
            };
            val interval=forward.backward(seed);
            if(interval.upper-interval.lower>value("MAX_SEED_HITS"))seedCounts[3]++ else if(interval.empty())seedCounts[4]++ else for(row in interval.lower until interval.upper) {
                val position=locate(row);
                candidates.add(Candidate(strand,position.reference,position.offset-offset))
            }
        };
        seedCounts[5]+=candidates.size;
        return candidates.sortedWith(compareBy<Candidate> {
            it.strand
        }.thenBy {
            it.reference
        }.thenBy {
            it.center
        })
    }
    fun seed(result: Result,oriented: List<String>) {
        result.reason="NOHIT";
        if(result.length<value("SEED_LENGTH"))return;
        seedCounts[0]++;
        val accepted=mutableMapOf<Key,Scored>();
        val threshold=value("MIN_SCORE_PERCENT")*parameters.getValue("SCORES")[0]*result.length;
        for(candidate in candidates(oriented)) {
            val alignment=banded(oriented[candidate.strand],references[candidate.reference].bases,
                candidate.center)?:continue;
            if(100*alignment.score<threshold)continue;
            val key=Key(candidate.reference,alignment.position,candidate.strand);
            val old=accepted[key];
            if(old==null||alignment.score>old.score)accepted[key]=Scored(alignment.score,describe(candidate.reference,
                alignment.position,candidate.strand,alignment.operations,result))
        };
        seedCounts[6]+=accepted.size;
        if(accepted.isEmpty())return;
        val ordered=accepted.values.sortedWith(Comparator {
            a,b->val c=b.score.compareTo(a.score);
            if(c!=0)c else alignmentOrder.compare(a.alignment,b.alignment)
        });
        val best=ordered.first().score;
        val n1=ordered.count {
            it.score==best
        };
        val second=ordered.filter {
            it.score<best
        }.maxOfOrNull {
            it.score
        }
        ?:0;
        result.mapped=true;
        result.primary=ordered.first().alignment;
        result.others=ordered.drop(1).map {
            it.alignment
        };
        result.targets=ordered.filter {
            it.score==best
        }.map {
            it.alignment.reference
        }.distinct().sorted();
        result.method="SEED";
        result.score=best;
        result.x0=n1;
        result.x1=ordered.size-n1;
        result.mapq=if(n1>=2)0 else 60*(best-second)/best
    }
    fun indexStatistics(built: SuffixArray.Built,reversed: SuffixArray.Built): List<String> {
        val size=text.length;
        val lines=mutableListOf("text length $size sequences ${references.size}");
        for((r,reference) in references.withIndex()) {
            val gc=reference.bases.count {
                it=='G'||it=='C'
            };
            lines.add("sequence ${reference.name} length ${reference.bases.length} offset ${offsets[r]} gc ${ratio(gc,reference.bases.length)} masked ${reference.masked}")
        };
        lines.add("symbols "+SuffixArray.SYMBOLS.map {
            "$it ${text.count{c->c==it}}"
        }.joinToString(" "));
        lines.add("");
        lines.add("forward_index");
        lines.add("suffix_array rounds ${built.classes.size-1}");
        for((t,classes) in built.classes.withIndex())lines.add("round $t prefix_length ${1 shl t} classes $classes");
        val check=SuffixArray.check(text,built.suffixes);
        lines.add("sa_check pairs ${size-1} ordered ${check.ordered} lcp_sum ${check.lcpSum} mean_lcp ${ratio(check.lcpSum,size-1)} max_lcp ${check.maximum}");
        lines.add("longest_repeat ${check.maximum} ${label(built.suffixes[check.row-1])} ${label(built.suffixes[check.row])}");
        val length=value("SEED_LENGTH");
        val kmers=mutableMapOf<String,Int>();
        for(reference in references)for(i in 0..reference.bases.length-length) {
            val kmer=reference.bases.substring(i,i+length);
            kmers[kmer]=kmers.getOrDefault(kmer,0)+1
        };
        val occurrences=kmers.values.sum();
        val unique=kmers.values.count {
            it==1
        };
        lines.add("kmers length $length occurrences $occurrences distinct ${kmers.size} unique $unique max_occurrence ${kmers.values.max()} unique_fraction ${ratio(unique,occurrences)}");
        lines.add("bwt runs ${runs(forward.bwt).size} head ${forward.bwt.take(60)}");
        lines.add("c_array "+SuffixArray.SYMBOLS.mapIndexed {
            i,c->"$c ${forward.c[i]}"
        }.joinToString(" "));
        lines.add("occ interval ${forward.interval} checkpoints ${forward.checkpoints.size}");
        lines.add("sa_sample interval ${value("SA_SAMPLE_INTERVAL")} samples ${forward.sampleCount}");
        var correct=0;
        var totalSteps=0;
        var maxSteps=0;
        for(row in 0 until size) {
            val location=forward.locate(row);
            if(location.position==built.suffixes[row])correct++;
            totalSteps+=location.steps;
            maxSteps=maxOf(maxSteps,location.steps)
        };
        lines.add("locate rows $size correct $correct total_steps $totalSteps max_steps $maxSteps mean_steps ${ratio(totalSteps,size)}");
        lines.add("inverse_bwt identical ${yes(forward.inverse()==text)}");
        lines.add("");
        lines.add("reverse_index");
        lines.add("suffix_array rounds ${reversed.classes.size-1}");
        lines.add("sa_check pairs ${size-1} ordered ${SuffixArray.check(reverseText,reversed.suffixes).ordered}");
        lines.add("bwt runs ${runs(reverse.bwt).size} head ${reverse.bwt.take(60)}");
        lines.add("inverse_bwt identical ${yes(reverse.inverse()==reverseText)}");
        lines.add("");
        lines.add("direct_sort");
        var cross=0;
        for(reference in references)if(reference.bases.length<=value("DIRECT_SORT_LIMIT")) {
            val sequence=reference.bases+"$";
            val doubled=SuffixArray.build(sequence);
            lines.add("${reference.name} length ${sequence.length} rounds ${doubled.classes.size-1} identical ${yes(doubled.suffixes.contentEquals(SuffixArray.direct(sequence)))}");
            cross++
        };
        if(cross==0)lines.add("none");
        val occurrenceBytes=24*forward.checkpoints.size;
        val sampleBytes=4*forward.sampleCount;
        val bitmapBytes=(size+7)/8;
        val totalBytes=size+occurrenceBytes+sampleBytes+bitmapBytes;
        lines.add("");
        lines.add("index_size bwt_bytes $size occ_bytes $occurrenceBytes sample_bytes $sampleBytes bitmap_bytes $bitmapBytes total_bytes $totalBytes full_bytes ${5*size} ratio ${ratio(totalBytes,5*size)}");
        return lines
    }
    data class Coverage(val coverage: List<String>,val variants: List<String>)
    fun coverage(results: List<Result>): Coverage {
        val depths=references.map {
            IntArray(it.bases.length)
        };
        val starts=references.map {
            IntArray(it.bases.length)
        };
        val pileups=references.map {
            Array(it.bases.length) {
                Array(4) {
                    IntArray(2)
                }
            }
        };
        val variant=parameters.getValue("VARIANTS");
        val minMapq=value("COVERAGE_MIN_MAPQ");
        for(result in results) {
            if(!result.mapped)continue;
            val a=result.primary!!;
            val r=a.reference;
            if(result.mapq==0)starts[r][a.position]++;
            if(result.mapq<minMapq)continue;
            for(pair in a.pairs) {
                depths[r][pair.offset]++;
                val base=a.oriented[pair.readOffset];
                val cycle=if(a.strand==0)pair.readOffset+1 else result.length-pair.readOffset;
                if(base!='N'&&result.qualities[cycle-1]>=variant[1])pileups[r][pair.offset][SuffixArray.BASES.indexOf(base)][a.strand]++
            }
        };
        val window=value("COVERAGE_WINDOW");
        val coverage=mutableListOf("window $window min_mapq $minMapq");
        val variants=mutableListOf("min_depth ${variant[0]} min_base_quality ${variant[1]} min_alt_percent ${variant[2]} hom_percent ${variant[3]}");
        var callable=0;
        var variantCount=0;
        var heterozygous=0;
        var homozygous=0;
        for((r,reference) in references.withIndex()) {
            val length=reference.bases.length;
            val depth=depths[r];
            val covered=depth.count {
                it>0
            };
            val maximum=depth.max();
            val histogram=IntArray(maximum+1);
            for(d in depth)histogram[d]++;
            coverage.add("reference ${reference.name} length $length covered $covered breadth ${ratio(covered,length)} mean_depth ${ratio(depth.sum(),length)} max_depth $maximum");
            coverage.add("depth_histogram "+histogram.indices.joinToString(" ") {
                "$it:${histogram[it]}"
            });
            for(first in 0 until length step window) {
                val last=minOf(first+window,length);
                val size=last-first;
                val values=depth.sliceArray(first until last);
                val gc=reference.bases.substring(first,last).count {
                    it=='G'||it=='C'
                };
                val total=values.sum();
                val mapq0=starts[r].sliceArray(first until last).sum();
                coverage.add("${reference.name} ${first+1} $last gc ${ratio(gc,size)} sum $total mean ${ratio(total,size)} max ${values.max()} zero ${values.count{it==0}} mapq0 $mapq0 |${"#".repeat(10*total/size)}")
            };
            for(j in 0 until length) {
                val counts=IntArray(4) {
                    pileups[r][j][it].sum()
                };
                val depth=counts.sum();
                if(depth<variant[0])continue;
                callable++;
                val referenceBase=reference.bases[j];
                val alternative=(0..3).filter {
                    SuffixArray.BASES[it]!=referenceBase
                }.maxWith(compareBy<Int> {
                    counts[it]
                }.thenBy {
                    -it
                });
                val count=counts[alternative];
                if(count<2||100*count<variant[2]*depth)continue;
                val hom=100*count>=variant[3]*depth;
                if(hom)homozygous++ else heterozygous++;
                variantCount++;
                variants.add("${reference.name} ${j+1} $referenceBase>${SuffixArray.BASES[alternative]} depth $depth alt $count fraction ${ratio(count,depth)} genotype ${if(hom)"1/1" else "0/1"} strands ${pileups[r][j][alternative][0]} ${pileups[r][j][alternative][1]} counts ${counts.joinToString(" ")}")
            }
        };
        variants.add("callable $callable variants $variantCount heterozygous $heterozygous homozygous $homozygous");
        return Coverage(coverage,variants)
    }
    fun errorStatistics(results: List<Result>): List<String> {
        val maxCycle=results.maxOf {
            it.read.bases.length
        };
        val cycles=Array(maxCycle+1) {
            IntArray(2)
        };
        val substitutions=Array(4) {
            IntArray(5)
        };
        val bins=Array(5) {
            IntArray(2)
        };
        val qualityCounts=IntArray(2);
        val qualitySums=IntArray(2);
        val operationCounts=IntArray(4);
        val events=IntArray(2);
        val indelBases=IntArray(2);
        for(result in results) {
            if(!result.mapped)continue;
            val a=result.primary!!;
            for(operation in a.operations)operationCounts["MIDS".indexOf(operation)]++;
            operationCounts[3]+=result.trimmed;
            if(result.x0!=1)continue;
            val sequence=references[a.reference].bases;
            for(pair in a.pairs) {
                val observed=a.oriented[pair.readOffset];
                val reference=sequence[pair.offset];
                val mismatch=if(observed==reference)0 else 1;
                val cycle=if(a.strand==0)pair.readOffset+1 else result.length-pair.readOffset;
                val quality=result.qualities[cycle-1];
                cycles[cycle][0]++;
                cycles[cycle][1]+=mismatch;
                substitutions[SuffixArray.BASES.indexOf(reference)]["ACGTN".indexOf(observed)]++;
                qualityCounts[mismatch]++;
                qualitySums[mismatch]+=quality;
                val bin=minOf(quality/10,4);
                bins[bin][0]++;
                bins[bin][1]+=mismatch
            };
            for(run in runs(a.operations))if(run.operation=='I'||run.operation=='D') {
                val kind=if(run.operation=='I')0 else 1;
                events[kind]++;
                indelBases[kind]+=run.count
            }
        };
        val aligned=qualityCounts.sum();
        val mismatches=qualityCounts[1];
        val lines=mutableListOf("error_profile aligned_bases $aligned mismatches $mismatches rate ${ratio(mismatches,aligned)}",
            "substitutions","ref A C G T N");
        for(r in 0..3)lines.add("${SuffixArray.BASES[r]} "+substitutions[r].joinToString(" "));
        lines.add("mismatch_by_cycle");
        for(cycle in 1..maxCycle)lines.add("cycle $cycle aligned ${cycles[cycle][0]} mismatches ${cycles[cycle][1]} rate ${ratio(cycles[cycle][1],cycles[cycle][0])}");
        lines.add("quality matched ${qualityCounts[0]} mean ${ratio(qualitySums[0],qualityCounts[0])} mismatched ${qualityCounts[1]} mean ${ratio(qualitySums[1],qualityCounts[1])}");
        lines.add("quality_bins");
        for((b,range) in listOf("0-9","10-19","20-29","30-39","40-").withIndex())lines.add("$range aligned ${bins[b][0]} mismatches ${bins[b][1]} rate ${ratio(bins[b][1],bins[b][0])}");
        lines.add("cigar M ${operationCounts[0]} I ${operationCounts[1]} D ${operationCounts[2]} S ${operationCounts[3]}");
        lines.add("indels insertions ${events[0]} ${indelBases[0]} deletions ${events[1]} ${indelBases[1]}");
        return lines
    }
    fun statistics(results: List<Result>): List<String> {
        val total=results.size;
        val mapped=results.filter {
            it.mapped
        };
        val unique=mapped.count {
            it.x0==1
        };
        val shortCount=results.count {
            !it.mapped&&it.reason=="SHORT"
        };
        val nohit=results.count {
            !it.mapped&&it.reason=="NOHIT"
        };
        val trimmed=results.count {
            it.trimmed>0
        };
        val trimmedBases=results.sumOf {
            it.trimmed
        };
        val forward=mapped.count {
            it.primary!!.strand==0
        };
        val lines=mutableListOf("reads total $total trimmed $trimmed trimmed_bases $trimmedBases short $shortCount",
            "mapped ${mapped.size} rate ${ratio(mapped.size,total)} unique $unique multi ${mapped.size-unique} unmapped ${total-mapped.size}",
            "unmapped short $shortCount nohit $nohit","method exact ${mapped.count{it.method=="EXACT"}} mismatch ${mapped.count{it.method=="MISMATCH"}} seed ${mapped.count{it.method=="SEED"}}",
            "strand forward $forward reverse ${mapped.size-forward}");
        for((r,reference) in references.withIndex()) {
            val selected=mapped.filter {
                it.primary!!.reference==r
            };
            val one=selected.count {
                it.x0==1
            };
            val plus=selected.count {
                it.primary!!.strand==0
            };
            lines.add("reference ${reference.name} mapped ${selected.size} unique $one forward $plus reverse ${selected.size-plus}")
        };
        lines.add("length_bins");
        val minimum=results.minOf {
            it.length
        }
        /10*10;
        val maximum=results.maxOf {
            it.length
        }
        /10*10;
        for(lower in minimum..maximum step 10) {
            val selected=results.filter {
                it.length in lower..lower+9
            };
            val placed=selected.count {
                it.mapped
            };
            val one=selected.count {
                it.mapped&&it.x0==1
            };
            lines.add("$lower-${lower+9} reads ${selected.size} mapped $placed unique $one")
        };
        val withN=results.filter {
            'N' in it.read.bases
        };
        val nBases=withN.sumOf {
            it.read.bases.count {
                base->base=='N'
            }
        };
        lines.add("n_reads ${withN.size} n_bases $nBases mapped ${withN.count{it.mapped}}");
        val targets=mapped.filter {
            it.x0>=2
        }.map {
            result->result.targets.joinToString("+") {
                references[it].name
            }
        }.groupingBy {
            it
        }.eachCount().toSortedMap();
        lines.add("multi_targets");
        if(targets.isEmpty())lines.add("none") else for((names,count) in targets)lines.add("$names $count");
        val mapqs=mapped.groupingBy {
            it.mapq
        }.eachCount();
        val nms=mapped.groupingBy {
            it.primary!!.nm
        }.eachCount();
        lines.add("mapq_histogram");
        for(value in mapqs.keys.sortedDescending())lines.add("$value ${mapqs.getValue(value)}");
        lines.add("nm_histogram");
        for(value in nms.keys.sorted())lines.add("$value ${nms.getValue(value)}");
        lines.addAll(errorStatistics(results));
        lines.add("search dfs_calls ${searchCounts[0]} dfs_nodes ${searchCounts[1]} dfs_leaves ${searchCounts[2]} dfs_positions ${searchCounts[3]}");
        val keys=listOf("reads","seeds","with_n","repetitive","without_hit","candidates","passing");
        lines.add("seeds "+keys.mapIndexed {
            i,key->"$key ${seedCounts[i]}"
        }.joinToString(" "));
        return lines
    }
    @JvmStatic fun main(args: Array<String>) {
        val input=SequenceIo.read();
        references=input.references;
        parameters=input.parameters;
        buildText();
        val built=SuffixArray.build(text);
        val reversed=SuffixArray.build(reverseText);
        forward=FmIndex(text,built.suffixes,value("OCC_INTERVAL"),value("SA_SAMPLE_INTERVAL"));
        reverse=FmIndex(reverseText,reversed.suffixes,value("OCC_INTERVAL"));
        val index=indexStatistics(built,reversed);
        val results=input.reads.map {
            map(it)
        };
        val sam=SamWriter.header(references);
        for(result in results)sam.add(SamWriter.record(result,references,value("MAX_ALT_HITS")));
        val coverageReport=coverage(results);
        SamWriter.write("alignments.sam",sam);
        SamWriter.write("coverage.txt",coverageReport.coverage);
        SamWriter.write("variants.txt",coverageReport.variants);
        SamWriter.write("index_stats.txt",index);
        SamWriter.write("summary.txt",statistics(results))
    }
}
