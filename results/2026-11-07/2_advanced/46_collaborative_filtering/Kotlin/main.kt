import kotlin.math.*

private val METHODS=listOf("GLOBAL","BASELINE","USER_KNN","ITEM_KNN","SLOPE_ONE","SVD","ALS")
private val RANKINGS=listOf("POPULAR","BASELINE","USER_KNN","ITEM_KNN","SLOPE_ONE","SVD","ALS")
private lateinit var data: Ratings.Data
private lateinit var settings: Ratings.Settings
private lateinit var neighborhood: Neighborhood.Model
private lateinit var svd: Factorization.Model
private lateinit var als: Factorization.Model
private lateinit var userBias: DoubleArray
private lateinit var itemBias: DoubleArray
private lateinit var rmse: DoubleArray
private lateinit var mae: DoubleArray
private lateinit var train: DoubleArray
private var users=0
private var items=0
private var tests=0
private var neighbors=0
private var listSize=0
private var topN=0
private lateinit var popularity: List<Int>
private lateinit var evaluated: List<Int>
private val relevant=mutableListOf<MutableSet<Int>>()
private val lists=mutableListOf<MutableList<List<Int>?>>()
private val logs=mutableListOf<Factorization.Log>()
private lateinit var predictions: Array<Array<Prediction>>
private lateinit var clipped: Array<DoubleArray>
private lateinit var errors: Array<DoubleArray>
private lateinit var clipCount: IntArray
private lateinit var fallbackCount: IntArray
private data class Prediction(val value: Double,val fallback: Boolean,val count: Int,val meanSimilarity: Double,val neighbor: Int)
private fun real(value: Double)=Report.real(value)
private fun integers(values: IntArray)=values.joinToString(" ")
private fun item(i: Int)=data.catalog.getValue(data.items[i])
private fun baseline(u: Int,i: Int)=(data.mean+userBias[u])+itemBias[i]
private fun training(method: Int): Double {
    var sum=0.0;
    for(row in data.training) {
        val value=if(method==0)data.mean else baseline(row.user,row.item);
        val error=row.rating-value;
        sum+=error*error
    };
    return sqrt(sum/data.training.size)
}
private fun baseline() {
    userBias=DoubleArray(users);
    itemBias=DoubleArray(items);
    for(sweep in 1..10) {
        for(i in 0 until items) {
            var sum=0.0;
            for(u in data.byItem[i])sum+=data.ratings[u][i]-data.mean-userBias[u];
            itemBias[i]=sum/(settings.decimal("BIAS_REG",0)+data.itemCounts[i])
        };
        for(u in 0 until users) {
            var sum=0.0;
            for(i in data.byUser[u])sum+=data.ratings[u][i]-data.mean-itemBias[i];
            userBias[u]=sum/(settings.decimal("BIAS_REG",1)+data.userCounts[u])
        };
        logs+=Factorization.Log("BASELINE",sweep,training(1))
    }
}
private fun predict(method: Int,u: Int,i: Int,count: Int): Prediction {
    val base=baseline(u,i);
    if(method==0)return Prediction(data.mean,false,0,0.0,-1);
    if(method==1)return Prediction(base,false,0,0.0,-1);
    if(method==5)return Prediction(svd.predict(u,i),false,0,0.0,-1);
    if(method==6)return Prediction(als.predict(u,i),false,0,0.0,-1);
    if(method==4) {
        var numerator=0.0;
        var denominator=0;
        for(j in data.byUser[u]) {
            val common=neighborhood.common[i][j];
            if(common>0) {
                val deviation=neighborhood.differences[i][j].toDouble()/(common+settings.integer("SHRINKAGE"));
                numerator+=(deviation+data.ratings[u][j])*common;
                denominator+=common
            }
        };
        return if(denominator==0)Prediction(base,true,0,0.0,-1) else Prediction(numerator/denominator,false,0,0.0,-1)
    };
    val similarities=if(method==2)neighborhood.users[u] else neighborhood.items[i];
    val candidates=(if(method==2)data.byItem[i] else data.byUser[u]).filter {
        similarities[it]>settings.number("MIN_SIMILARITY")
    };
    if(candidates.isEmpty())return Prediction(base,true,0,0.0,-1);
    val selected=Neighborhood.select(similarities,candidates,count);
    var numerator=0.0;
    var denominator=0.0;
    for(index in selected) {
        val rating=if(method==2)data.ratings[index][i]-data.userMeans[index] else data.ratings[u][index]-data.itemMeans[index];
        numerator+=similarities[index]*rating;
        denominator+=similarities[index]
    };
    val mean=if(method==2)data.userMeans[u] else data.itemMeans[i];
    return Prediction(mean+numerator/denominator,false,selected.size,denominator/selected.size,
        if(method==2)data.users[selected[0]] else data.items[selected[0]])
}
private fun ranked(method: Int,u: Int): List<Int> {
    lists[method][u]?.let {
        return it
    };
    var result=popularity.filter {
        data.ratings[u][it]==0
    };
    if(method>0) {
        val values=DoubleArray(items);
        for(i in result)values[i]=predict(method,u,i,neighbors).value;
        result=result.sortedWith(compareByDescending<Int> {
            values[it]
        }.thenBy {
            it
        })
    };
    lists[method][u]=result;
    return result
}
private fun prepare() {
    popularity=(0 until items).sortedWith(compareByDescending<Int> {
        data.itemCounts[it]
    }.thenByDescending {
        data.itemMeans[it]
    }.thenBy {
        it
    });
    repeat(7) {
        lists+=MutableList<List<Int>?>(users) {
            null
        }
    };
    repeat(users) {
        relevant+=mutableSetOf<Int>()
    };
    for(row in data.test)if(row.rating>=4)relevant[row.user]+=row.item;
    evaluated=(0 until users).filter {
        relevant[it].isNotEmpty()
    };
    predictions=Array(7) {
        Array(tests) {
            Prediction(0.0,false,0,0.0,-1)
        }
    };
    clipped=Array(7) {
        DoubleArray(tests)
    };
    errors=Array(7) {
        DoubleArray(tests)
    };
    clipCount=IntArray(7);
    fallbackCount=IntArray(7);
    rmse=DoubleArray(7);
    mae=DoubleArray(7);
    train=DoubleArray(7);
    for(method in 0 until 7) {
        var square=0.0;
        var absolute=0.0;
        for(t in 0 until tests) {
            val row=data.test[t];
            val prediction=predict(method,row.user,row.item,neighbors);
            predictions[method][t]=prediction;
            clipped[method][t]=Evaluation.clip(prediction.value);
            errors[method][t]=clipped[method][t]-row.rating;
            square+=errors[method][t]*errors[method][t];
            absolute+=abs(errors[method][t]);
            if(prediction.value<1||prediction.value>5)clipCount[method]++;
            if(prediction.fallback)fallbackCount[method]++
        };
        rmse[method]=sqrt(square/tests);
        mae[method]=absolute/tests
    };
    train[0]=training(0);
    train[1]=logs[9].rmse;
    train[5]=svd.log.last().rmse;
    train[6]=als.log.last().rmse
}
private fun predictionReport(): List<String> {
    val output=mutableListOf("user,item,actual,"+METHODS.joinToString(","));
    for(t in 0 until tests) {
        val row=data.test[t];
        var line="${data.users[row.user]},${data.items[row.item]},${row.rating}";
        for(method in 0 until 7)line+=","+real(clipped[method][t]);
        output+=line
    };
    return output
}
private fun section(output: MutableList<String>,lines: List<String>) {
    if(output.isNotEmpty())output+="";
    output+=lines
}
private fun genres(test: Boolean): List<String> {
    val genres=sortedSetOf<String>();
    if(test) {
        for(row in data.test)genres+=item(row.item).genres
    } else for(i in 0 until items)genres+=item(i).genres;
    return genres.toList()
}
private fun counts(label: String,values: IntArray): String {
    val sorted=values.sortedArray();
    return "$label min ${sorted[0]} median ${real((sorted[(sorted.size-1)/2]+sorted[sorted.size/2])/2.0)} max ${sorted.last()}"
}
private fun group(count: Int,boundaries: IntArray)=boundaries.count {
    count>=it
}
private fun metricPairs(indices: List<Int>,absolute: Boolean): String {
    var line="";
    for(method in 0 until 7) {
        val values=indices.map {
            errors[method][it]
        };
        line+=" ${METHODS[method]} ${real(if(absolute)Evaluation.mae(values) else Evaluation.rmse(values))}"
    };
    return line
}
private fun errorGroups(user: Boolean): List<String> {
    val boundaries=settings.list(if(user)"USER_GROUPS" else "ITEM_GROUPS");
    val output=mutableListOf((if(user)"user" else "item")+"_groups bounds "+integers(boundaries));
    for(g in 0..boundaries.size) {
        val indices=(0 until tests).filter {
            t->val row=data.test[t];
            val count=if(user)data.userCounts[row.user] else data.itemCounts[row.item];
            group(count,boundaries)==g
        };
        output+="group ${g+1} from ${if(g==0)1 else boundaries[g-1]} to ${if(g==boundaries.size)"-" else (boundaries[g]-1).toString()} pairs ${indices.size}"+metricPairs(indices,
            false)
    };
    return output
}
private fun ratingEvaluation(): MutableList<String> {
    val output=mutableListOf<String>();
    val histogram=IntArray(5);
    var first=Long.MAX_VALUE;
    var last=0L;
    for(row in data.training) {
        histogram[row.rating-1]++;
        first=minOf(first,row.time);
        last=maxOf(last,row.time)
    };
    section(output,listOf("data users $users items $items catalog ${data.catalog.size} ratings ${data.training.size} test $tests",
        "density ${real(data.training.size.toDouble()/(users*items))} global_mean ${real(data.mean)}",
        "histogram "+integers(histogram),counts("user_ratings",data.userCounts),counts("item_ratings",
        data.itemCounts),"timestamps first $first last $last","cold_items ${data.catalog.size-items}",
        "similarities user_pairs ${neighborhood.userPairs} usable ${neighborhood.userUsable} item_pairs ${neighborhood.itemPairs} usable ${neighborhood.itemUsable} slope_pairs ${neighborhood.slopePairs}"));
    var part=mutableListOf("genre_stats");
    for(genre in genres(false)) {
        var count=0;
        var ratings=0;
        var high=0;
        for(i in 0 until items)if(genre in item(i).genres) {
            count++;
            ratings+=data.itemCounts[i];
            for(u in data.byItem[i])if(data.ratings[u][i]>=4)high++
        };
        part+="genre $genre items $count ratings $ratings high $high"
    };
    section(output,part);
    val buckets=settings.integer("TIME_BUCKETS");
    part=mutableListOf("time_buckets $buckets");
    for(bucket in 0 until buckets) {
        var count=0;
        var sum=0;
        val selected=mutableSetOf<Int>();
        for(row in data.training)if((row.time-first)*buckets/(last-first+1)==bucket.toLong()) {
            count++;
            sum+=row.rating;
            selected+=row.user
        };
        part+="bucket ${bucket+1} ratings $count users ${selected.size} mean ${real(if(count==0)Double.NaN else sum.toDouble()/count)}"
    };
    section(output,part);
    part=mutableListOf("rating_metrics");
    for(method in 0 until 7)part+="${METHODS[method]} rmse ${real(rmse[method])} mae ${real(mae[method])} clipped ${clipCount[method]} fallback ${fallbackCount[method]}";
    section(output,part);
    part=mutableListOf("generalization");
    for(method in intArrayOf(0,1,5,6))part+="${METHODS[method]} train ${real(train[method])} test ${real(rmse[method])} gap ${real(rmse[method]-train[method])}";
    section(output,part);
    part=mutableListOf("neighborhoods k $neighbors");
    for(method in 2..3) {
        var with=0;
        var count=0;
        var similarities=0.0;
        for(prediction in predictions[method])if(!prediction.fallback) {
            with++;
            count+=prediction.count;
            similarities+=prediction.meanSimilarity
        };
        part+="${METHODS[method]} predictions $tests with_neighbors $with mean_neighbors ${real(if(with==0)Double.NaN else count.toDouble()/with)} mean_similarity ${real(if(with==0)Double.NaN else similarities/with)}"
    };
    section(output,part);
    var actualMean=0.0;
    for(row in data.test)actualMean+=row.rating;
    actualMean/=tests;
    var actualVariance=0.0;
    for(row in data.test)actualVariance+=(row.rating-actualMean)*(row.rating-actualMean);
    part=mutableListOf("prediction_stats actual mean ${real(actualMean)} std ${real(sqrt(actualVariance/tests))}");
    for(method in 0 until 7) {
        var mean=0.0;
        for(value in clipped[method])mean+=value;
        mean/=tests;
        var variance=0.0;
        var covariance=0.0;
        var constant=true;
        for(t in 0 until tests) {
            val delta=clipped[method][t]-mean;
            variance+=delta*delta;
            covariance+=delta*(data.test[t].rating-actualMean);
            if(clipped[method][t]!=clipped[method][0])constant=false
        };
        part+="${METHODS[method]} mean ${real(mean)} std ${real(sqrt(variance/tests))} correlation ${real(if(constant||actualVariance==0.0)Double.NaN else covariance/sqrt(variance*actualVariance))}"
    };
    section(output,part);
    part=mutableListOf("error_bins edges 0.5 1.0 1.5 2.0");
    for(method in 0 until 7) {
        val bins=IntArray(5);
        for(error in errors[method])bins[minOf(4,floor(abs(error)*2).toInt())]++;
        part+=METHODS[method]+" "+integers(bins)
    };
    section(output,part);
    part=mutableListOf("comparison");
    for(a in 0 until 7)for(b in a+1 until 7) {
        var wins=0;
        var ties=0;
        var losses=0;
        for(t in 0 until tests) {
            val left=abs(errors[a][t]);
            val right=abs(errors[b][t]);
            if(left<right)wins++ else if(left==right)ties++ else losses++
        };
        part+="${METHODS[a]} ${METHODS[b]} wins $wins ties $ties losses $losses"
    };
    section(output,part);
    section(output,errorGroups(true));
    section(output,errorGroups(false));
    part=mutableListOf("by_rating");
    for(value in 1..5) {
        val indices=(0 until tests).filter {
            data.test[it].rating==value
        };
        part+="rating $value pairs ${indices.size}"+metricPairs(indices,true)
    };
    section(output,part);
    part=mutableListOf("genres");
    for(genre in genres(true)) {
        val indices=(0 until tests).filter {
            genre in item(data.test[it].item).genres
        };
        part+="genre $genre pairs ${indices.size}"+metricPairs(indices,false)
    };
    section(output,part);
    return output
}
private fun log2(value: Double)=ln(value)/ln(2.0)
private fun rankingEvaluation(): List<String> {
    val count=evaluated.size;
    var relevantCount=0;
    for(u in evaluated)relevantCount+=relevant[u].size;
    val output=mutableListOf("ranking users $count relevant $relevantCount");
    for(cutoff in settings.list("CUTOFFS")) {
        output+="cutoff $cutoff";
        for(method in 0 until 7) {
            var hits=0;
            var hitUsers=0;
            var recall=0.0;
            var ndcg=0.0;
            var ap=0.0;
            var rr=0.0;
            for(u in evaluated) {
                val m=Evaluation.ranking(ranked(method,u),relevant[u],cutoff);
                hits+=m.hits;
                if(m.hits>0)hitUsers++;
                recall+=m.recall;
                ndcg+=m.ndcg;
                ap+=m.ap;
                rr+=m.rr
            };
            output+="  ${RANKINGS[method]} precision ${real(hits.toDouble()/(cutoff*count))} recall ${real(recall/count)} ndcg ${real(ndcg/count)} map ${real(ap/count)} mrr ${real(rr/count)} hit_rate ${real(hitUsers.toDouble()/count)}"
        }
    };
    var part=mutableListOf("beyond_accuracy top_n $topN head ${items/5}");
    val head=popularity.take(items/5).toSet();
    for(method in 0 until 7) {
        val coverage=mutableSetOf<Int>();
        var diversity=0;
        var popular=0;
        var tail=0;
        var novelty=0.0;
        var similarity=0.0;
        for(u in evaluated) {
            val list=ranked(method,u).take(topN);
            coverage+=list;
            val genres=mutableSetOf<String>();
            var nov=0.0;
            var ils=0.0;
            for(i in list) {
                genres+=item(i).genres;
                popular+=data.itemCounts[i];
                if(i !in head)tail++;
                nov+=log2(users.toDouble()/data.itemCounts[i])
            };
            diversity+=genres.size;
            novelty+=nov/topN;
            for(a in 0 until topN-1)for(b in a+1 until topN) {
                val sim=neighborhood.items[list[a]][list[b]];
                if(!sim.isNaN())ils+=sim
            };
            similarity+=ils/(topN*(topN-1)/2)
        };
        part+="${RANKINGS[method]} coverage ${real(coverage.size.toDouble()/items)} diversity ${real(diversity.toDouble()/count)} novelty ${real(novelty/count)} popularity ${real(popular.toDouble()/(topN*count))} long_tail ${real(tail.toDouble()/(topN*count))} similarity ${real(similarity/count)}"
    };
    section(output,part);
    val boundaries=settings.list("USER_GROUPS");
    part=mutableListOf("ranking_groups top_n $topN bounds "+integers(boundaries));
    for(g in 0..boundaries.size) {
        val selected=evaluated.filter {
            group(data.userCounts[it],boundaries)==g
        };
        var line="group ${g+1} users ${selected.size}";
        for(method in 0 until 7) {
            var sum=0.0;
            for(u in selected)sum+=Evaluation.ranking(ranked(method,u),relevant[u],topN).ndcg;
            line+=" ${RANKINGS[method]} ${real(if(selected.isEmpty())Double.NaN else sum/selected.size)}"
        };
        part+=line
    };
    section(output,part);
    part=mutableListOf("agreement top_n $topN");
    for(a in 0 until 7)for(b in a+1 until 7) {
        var sum=0.0;
        for(u in evaluated) {
            val common=ranked(a,u).take(topN).toSet().intersect(ranked(b,u).take(topN).toSet());
            sum+=common.size.toDouble()/(2*topN-common.size)
        };
        part+="${RANKINGS[a]} ${RANKINGS[b]} jaccard ${real(sum/count)}"
    };
    section(output,part);
    return output
}
private fun ordered(values: DoubleArray,descending: Boolean)=values.indices.sortedWith(Comparator {
    a,b->val comparison=if(descending)values[b].compareTo(values[a]) else values[a].compareTo(values[b]);
    if(comparison!=0)comparison else a.compareTo(b)
})
private fun gridAndBiases(): List<String> {
    val output=mutableListOf("neighbor_grid");
    val grid=settings.list("NEIGHBOR_GRID");
    val best=intArrayOf(grid[0],grid[0]);
    val bestError=doubleArrayOf(Double.POSITIVE_INFINITY,Double.POSITIVE_INFINITY);
    for(count in grid) {
        var line="k $count";
        for(method in 2..3) {
            val errors=data.test.map {
                Evaluation.clip(predict(method,it.user,it.item,count).value)-it.rating
            };
            val error=Evaluation.rmse(errors);
            line+=" ${METHODS[method]} ${real(error)}";
            if(error<bestError[method-2]) {
                bestError[method-2]=error;
                best[method-2]=count
            }
        };
        output+=line
    };
    output+="best USER_KNN ${best[0]} ITEM_KNN ${best[1]}";
    val part=mutableListOf("biases");
    for(kind in 0 until 4) {
        val isItem=kind<2;
        val descending=kind%2==0;
        val bias=if(isItem)itemBias else userBias;
        val order=ordered(bias,descending);
        for(position in 0 until listSize) {
            val index=order[position];
            val label=(if(isItem)"item" else "user")+(if(descending)"_high" else "_low");
            part+="$label ${if(isItem)data.items[index] else data.users[index]} bias ${real(bias[index])} count ${if(isItem)data.itemCounts[index] else data.userCounts[index]} mean ${real(if(isItem)data.itemMeans[index] else data.userMeans[index])}"+(if(isItem)" "+item(index).title else "")
        }
    };
    section(output,part);
    return output
}
private fun evaluationReport(): List<String> {
    val output=ratingEvaluation();
    section(output,rankingEvaluation());
    section(output,gridAndBiases());
    return output
}
private fun genrePreference(u: Int,liked: Boolean,counts: MutableMap<String,Int>): List<String> {
    for(i in data.byUser[u])if(if(liked)data.ratings[u][i]>=4 else data.ratings[u][i]<=2)for(genre in item(i).genres)counts[genre]=counts.getOrDefault(genre,
        0)+1;
    return counts.keys.sortedWith(compareByDescending<String> {
        counts.getValue(it)
    }.thenBy {
        it
    }).take(3)
}
private fun genreLine(label: String,genres: List<String>,counts: Map<String,Int>): String {
    var line=label;
    for(genre in genres)line+=" $genre ${counts[genre]}";
    return if(genres.isEmpty())line+" -" else line
}
private fun popularLine(position: Int,i: Int)="  $position ${data.items[i]} count ${data.itemCounts[i]} mean ${real(data.itemMeans[i])} ${item(i).title}"
private fun recommendationReport(): List<String> {
    val output=mutableListOf<String>();
    for(id in settings.list("RECOMMEND_USERS")) {
        val part=mutableListOf<String>();
        val u=data.userIndex[id];
        if(u==null) {
            part+="user $id unknown";
            part+="list POPULAR";
            for(position in 0 until topN)part+=popularLine(position+1,popularity[position]);
            section(output,part);
            continue
        };
        part+="user $id ratings ${data.userCounts[u]} mean ${real(data.userMeans[u])} bias ${real(userBias[u])}";
        val likedCounts=mutableMapOf<String,Int>();
        val dislikedCounts=mutableMapOf<String,Int>();
        val liked=genrePreference(u,true,likedCounts);
        val disliked=genrePreference(u,false,dislikedCounts);
        part+=genreLine("liked_genres",liked,likedCounts);
        part+=genreLine("disliked_genres",disliked,dislikedCounts);
        val recent=data.training.filter {
            it.user==u
        }.sortedWith(compareByDescending<Ratings.Rating> {
            it.time
        }.thenBy {
            it.item
        });
        var line="recent";
        for(position in 0 until minOf(3,recent.size)) {
            val row=recent[position];
            line+=" ${data.items[row.item]} ${row.rating}"
        };
        part+=line;
        val candidates=(0 until users).filter {
            neighborhood.users[u][it]>settings.number("MIN_SIMILARITY")
        };
        for(v in Neighborhood.select(neighborhood.users[u],candidates,listSize))part+="neighbor ${data.users[v]} similarity ${real(neighborhood.users[u][v])} common ${neighborhood.userCommon[u][v]}";
        for(t in 0 until tests) {
            val row=data.test[t];
            if(row.user!=u)continue;
            line="heldout ${data.items[row.item]} actual ${row.rating}";
            for(method in 0 until 7)line+=" "+real(clipped[method][t]);
            part+=line
        };
        for(method in 0 until 7) {
            val list=ranked(method,u).take(topN);
            var matches=0;
            for(i in list)if(liked.any {
                it in item(i).genres
            })matches++;
            part+="list ${RANKINGS[method]} genre_match $matches";
            for(position in 0 until topN) {
                val i=list[position];
                if(method==0)part+=popularLine(position+1,i) else {
                    val prediction=predict(method,u,i,neighbors);
                    line="  ${position+1} ${data.items[i]} ${real(prediction.value)}";
                    if(method==2||method==3)line+=" via ${if(prediction.fallback)"-" else prediction.neighbor.toString()}";
                    part+=line+" "+item(i).title
                }
            }
        };
        section(output,part)
    };
    return output
}
private fun similarReport(): List<String> {
    val output=mutableListOf<String>();
    for(id in settings.list("SIMILAR_ITEMS")) {
        val i=data.itemIndex.getValue(id);
        val part=mutableListOf("item $id ratings ${data.itemCounts[i]} mean ${real(data.itemMeans[i])} bias ${real(itemBias[i])} genres ${item(i).genreText} title ${item(i).title}");
        for(kind in 0 until 4) {
            part+=listOf("cosine","factors","co_rated","slope_one")[kind];
            val values=DoubleArray(items);
            val candidates=mutableListOf<Int>();
            for(j in 0 until items)if(j!=i) {
                if(kind==0) {
                    values[j]=neighborhood.items[i][j];
                    if(!values[j].isNaN())candidates+=j
                } else if(kind==1) {
                    values[j]=Factorization.dot(svd.items[i],svd.items[j])/sqrt(Factorization.dot(svd.items[i],
                        svd.items[i])*Factorization.dot(svd.items[j],svd.items[j]));
                    candidates+=j
                } else if(neighborhood.common[i][j]>0) {
                    values[j]=if(kind==2)neighborhood.common[i][j].toDouble() else neighborhood.differences[j][i].toDouble()/(neighborhood.common[j][i]+settings.integer("SHRINKAGE"));
                    candidates+=j
                }
            };
            candidates.sortWith(Comparator {
                a,b->var comparison=values[b].compareTo(values[a]);
                if(comparison==0&&kind==3)comparison=neighborhood.common[i][b].compareTo(neighborhood.common[i][a]);
                if(comparison!=0)comparison else a.compareTo(b)
            });
            for(position in 0 until minOf(listSize,candidates.size)) {
                val j=candidates[position];
                var line="  ${position+1} ${data.items[j]}";
                if(kind<2)line+=" similarity "+real(values[j]);
                if(kind==0||kind==2)line+=" common ${neighborhood.common[i][j]}";
                if(kind==3)line+=" difference ${neighborhood.differences[j][i]} common ${neighborhood.common[j][i]}";
                part+=line+" "+item(j).title
            }
        };
        section(output,part)
    };
    return output
}
private fun trainingReport()=listOf("method,epoch,train_rmse")+logs.map {
    "${it.method},${it.epoch},${real(it.rmse)}"
}
fun main() {
    data=Ratings.read();
    settings=data.settings;
    users=data.users.size;
    items=data.items.size;
    tests=data.test.size;
    neighbors=settings.integer("NEIGHBORS");
    listSize=settings.integer("LIST_SIZE");
    topN=settings.integer("TOP_N");
    baseline();
    neighborhood=Neighborhood.compute(data);
    svd=Factorization.svd(data);
    als=Factorization.als(data,userBias,itemBias);
    logs+=svd.log;
    logs+=als.log;
    prepare();
    Report.write("predictions.csv",predictionReport());
    Report.write("evaluation.txt",evaluationReport());
    Report.write("recommendations.txt",recommendationReport());
    Report.write("similar_items.txt",similarReport());
    Report.write("training_log.csv",trainingReport())
}
