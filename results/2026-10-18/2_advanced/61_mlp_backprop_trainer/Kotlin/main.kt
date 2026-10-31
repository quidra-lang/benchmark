import java.io.File
import kotlin.math.*

object Mlp {
    lateinit var data: Dataset.Data;
    lateinit var settings: Dataset.Settings;
    lateinit var train: List<Dataset.Image>;
    lateinit var validation: List<Dataset.Image>;
    var classes=0
    fun real(x: Double,digits: Int)=Evaluation.real(x,digits)
    fun ints(values: IntArray)=values.joinToString(" ")
    fun reals(values: DoubleArray,digits: Int)=values.joinToString(" ") {
        real(it,digits)
    }
    fun order(size: Int)=IntArray(size) {
        it
    }
    class Summary(size: Int) {
        var loss=0.0;
        var correct=0;
        val passes=mutableListOf<Network.Pass>();
        val correctness=BooleanArray(size)
    }
    fun evaluate(net: Network,theta: DoubleArray,images: List<Dataset.Image>): Summary {
        val result=Summary(images.size)
        for(i in images.indices) {
            val pass=net.forward(theta,images[i]);
            result.passes.add(pass);
            result.loss+=pass.loss;
            result.correctness[i]=Evaluation.prediction(pass.scores)==images[i].label;
            if(result.correctness[i])result.correct++
        }
        result.loss/=images.size;
        return result
    }
    fun meanGradient(net: Network,theta: DoubleArray,images: List<Dataset.Image>): DoubleArray {
        val sum=DoubleArray(theta.size);
        for(image in images) {
            val gradient=net.backward(theta,net.forward(theta,image)).gradient;
            for(p in sum.indices)sum[p]+=gradient[p]
        }
        for(p in sum.indices)sum[p]/=images.size;
        return sum
    }
    fun gradientChecks(): List<String> {
        val lines=mutableListOf<String>()
        for(net in data.networks) {
            val order=order(train.size);
            Dataset.Generator(settings.seed).shuffle(order);
            val batch=order.take(minOf(settings.batch,order.size)).map {
                train[it]
            };
            val ids=batch.map {
                it.id
            }
            val theta=net.initial.copyOf();
            val gradient=meanGradient(net,theta,batch);
            val counts=Array(net.layers) {
                IntArray(2)
            };
            var checked=0;
            var passed=true
            for(p in theta.indices step settings.stride) {
                val original=theta[p];
                theta[p]=original+0.00001;
                val plus=evaluate(net,theta,batch).loss;
                theta[p]=original-0.00001;
                val minus=evaluate(net,theta,batch).loss;
                theta[p]=original
                val numeric=(plus-minus)/(2*0.00001);
                val error=abs(gradient[p]-numeric)/maxOf(1.0,abs(gradient[p])+abs(numeric));
                if(!(error<0.000001))passed=false;
                checked++
                for(l in 0 until net.layers)if(p>=net.starts[l]&&p<net.biases[l]+net.units[l])counts[l][if(net.weight[p])0 else 1]++
            }
            if(lines.isNotEmpty())lines.add("");
            lines.add("network ${net.name}");
            lines.add("parameters ${net.parameters}");
            lines.add("batch "+ids.joinToString(" "))
            for(l in 0 until net.layers)lines.add("layer ${l+1} weights ${counts[l][0]} biases ${counts[l][1]}")
            lines.add("checked $checked");
            lines.add("result ${if(passed)"PASS" else "FAIL"}")
        }
        return lines
    }
    data class Epoch(val number: Int,val rate: Double,val magnitude: Double,val train: Summary,val validation: Summary,val improved: Boolean)
    data class Noise(val rate: Int,val images: List<Dataset.Image>,val flipped: Int)
    class Result(val run: Dataset.Run,val index: Int,val network: Network) {
        var bestEpoch=0;
        var bestCorrect=0;
        var updates=0;
        lateinit var theta: DoubleArray;
        var bestLoss=0.0;
        var stop="";
        val epochs=mutableListOf<Epoch>();
        lateinit var test: Summary;
        lateinit var predictions: IntArray;
        lateinit var confusion: Array<IntArray>
    }
    fun fit(run: Dataset.Run,index: Int): Result {
        val net=data.networks.first {
            it.name==run.network
        };
        val result=Result(run,index,net);
        val theta=net.initial.copyOf();
        val optimizer=Optimizers.State(run,theta.size);
        val generator=Dataset.Generator(settings.seed);
        val order=order(train.size);
        var wait=0
        for(e in 1..settings.epochs) {
            val eta=Optimizers.rate(run,settings,e);
            generator.shuffle(order);
            var magnitude=0.0;
            var batches=0
            for(first in order.indices step settings.batch) {
                val batch=(first until minOf(order.size,first+settings.batch)).map {
                    train[order[it]]
                };
                val gradient=meanGradient(net,theta,batch);
                var squares=0.0
                for(p in theta.indices) {
                    if(net.weight[p])gradient[p]+=run.lambda*theta[p];
                    squares+=gradient[p]*gradient[p]
                }
                magnitude+=sqrt(squares);
                batches++;
                optimizer.update(theta,gradient,eta);
                result.updates++
            }
            val training=evaluate(net,theta,train);
            val valid=evaluate(net,theta,validation);
            val improved=e==1||valid.loss<result.bestLoss
            if(improved) {
                result.bestLoss=valid.loss;
                result.bestEpoch=e;
                result.bestCorrect=valid.correct;
                result.theta=theta.copyOf();
                wait=0
            } else wait++
            result.epochs.add(Epoch(e,eta,magnitude/batches,training,valid,improved))
            if(wait>=settings.patience) {
                result.stop="early";
                break
            };
            if(e==settings.epochs)result.stop="max_epochs"
        }
        result.test=evaluate(net,result.theta,data.test);
        result.predictions=IntArray(data.test.size) {
            Evaluation.prediction(result.test.passes[it].scores)
        };
        result.confusion=Evaluation.confusion(data.test,result.test.passes,classes)
        return result
    }
    fun noise(): List<Noise> {
        val result=mutableListOf<Noise>()
        for(rate in settings.noise) {
            val generator=Dataset.Generator(settings.seed);
            val images=mutableListOf<Dataset.Image>();
            var flipped=0
            for(image in data.test) {
                val pixels=image.pixels.toCharArray();
                for(p in pixels.indices)if(generator.draw()%100<rate) {
                    pixels[p]=if(pixels[p]=='0')'1' else '0';
                    flipped++
                };
                images.add(Dataset.image(image.id,image.label,pixels.concatToString()))
            }
            result.add(Noise(rate,images,flipped))
        }
        return result
    }
    fun dataSummary(): MutableList<String> {
        val pixels=data.width*data.height;
        val training=IntArray(classes);
        val valid=IntArray(classes);
        val testing=IntArray(classes);
        val ink=IntArray(classes);
        val black=Array(classes) {
            IntArray(pixels)
        };
        val levels=Array(classes) {
            IntArray(pixels)
        }
        for(image in train) {
            val k=image.label;
            training[k]++;
            for(p in 0 until pixels)if(image.pixels[p]=='1') {
                ink[k]++;
                black[k][p]++
            }
        }
        for(image in validation)valid[image.label]++;
        for(image in data.test)testing[image.label]++
        val lines=mutableListOf("data","train ${train.size} validation ${validation.size} test ${data.test.size} pixels $pixels")
        for(k in 0 until classes) {
            lines.add("class $k train ${training[k]} validation ${valid[k]} test ${testing[k]} ink ${Evaluation.ratio(ink[k],training[k])}");
            for(p in 0 until pixels)levels[k][p]=if(training[k]==0)0 else minOf(9,10*black[k][p]/training[k])
        }
        lines.add("mean_images "+ints(order(classes)));
        lines.addAll(Evaluation.maps(levels,data.width,data.height));
        return lines
    }
    fun evaluateRun(result: Result,noise: List<Noise>): List<String> {
        val net=result.network;
        val total=data.test.size;
        var top2=0;
        var correctConfidence=0.0;
        var wrongConfidence=0.0
        for(i in 0 until total) {
            val pass=result.test.passes[i];
            val predicted=result.predictions[i];
            val label=data.test[i].label
            if(predicted==label||Evaluation.second(pass.scores,predicted)==label)top2++;
            if(predicted==label)correctConfidence+=pass.scores[predicted] else wrongConfidence+=pass.scores[predicted]
        }
        var events=0;
        var rows=0;
        var never=0
        for(i in train.indices) {
            var count=0;
            var learned=false
            for(e in result.epochs.indices) {
                val correct=result.epochs[e].train.correctness[i];
                if(correct)learned=true;
                if(e>0&&result.epochs[e-1].train.correctness[i]&&!correct)count++
            }
            events+=count;
            if(count>0)rows++;
            if(!learned)never++
        }
        val norms=DoubleArray(net.layers);
        val changes=DoubleArray(net.layers)
        for(l in 0 until net.layers) {
            var norm=0.0;
            var change=0.0;
            for(p in net.starts[l] until net.biases[l]) {
                norm+=result.theta[p]*result.theta[p];
                val delta=result.theta[p]-net.initial[p];
                change+=delta*delta
            };
            norms[l]=sqrt(norm);
            changes[l]=sqrt(change)
        }
        val correct=result.test.correct
        val lines=mutableListOf("run ${result.run.name} network ${net.name} optimizer ${result.run.optimizer}",
            "epochs ${result.epochs.size} best_epoch ${result.bestEpoch} stop ${result.stop} updates ${result.updates}",
            "best_val_loss ${real(result.bestLoss,6)} best_val_acc ${Evaluation.ratio(result.bestCorrect,validation.size)} correct ${result.bestCorrect}/${validation.size}",
            "test_loss ${real(result.test.loss,6)} test_acc ${Evaluation.ratio(correct,total)} correct $correct/$total",
            "top2_acc ${Evaluation.ratio(top2,total)} correct $top2/$total","confidence correct ${if(correct==0)"-" else real(correctConfidence/correct,4)} wrong ${if(correct==total)"-" else real(wrongConfidence/(total-correct),4)}",
            "forgetting events $events rows $rows never_learned $never","weight_norms ${reals(norms,4)}",
            "weight_changes ${reals(changes,4)}","curve")
        var maximum=0.0;
        for(epoch in result.epochs) {
            maximum=maxOf(maximum,epoch.train.loss);
            maximum=maxOf(maximum,epoch.validation.loss)
        }
        for(epoch in result.epochs) {
            val ct=floor(39*epoch.train.loss/maximum+0.5).toInt();
            val cv=floor(39*epoch.validation.loss/maximum+0.5).toInt();
            val curve=CharArray(40) {
                ' '
            };
            curve[ct]='t';
            curve[cv]=if(ct==cv)'*' else 'v';
            lines.add(epoch.number.toString().padStart(2)+" |"+curve.concatToString()+"|"+(if(epoch.number==result.bestEpoch)" best" else ""))
        }
        lines.add("confusion");
        lines.addAll(Evaluation.confusionLines(result.confusion));
        lines.add("calibration")
        val bins=IntArray(settings.bins);
        val hits=IntArray(settings.bins);
        val confidence=DoubleArray(settings.bins)
        for(i in 0 until total) {
            val c=result.test.passes[i].scores[result.predictions[i]];
            val bin=minOf(settings.bins-1,floor(c*settings.bins).toInt());
            bins[bin]++;
            confidence[bin]+=c;
            if(result.predictions[i]==data.test[i].label)hits[bin]++
        }
        var ece=0.0
        for(b in 0 until settings.bins) {
            var mean="-";
            if(bins[b]>0) {
                val average=confidence[b]/bins[b];
                mean=real(average,4);
                ece+=(bins[b].toDouble()/total)*abs(hits[b].toDouble()/bins[b]-average)
            }
            lines.add("bin ${b+1} ${real(b.toDouble()/settings.bins,2)} ${real((b+1.0)/settings.bins,2)} count ${bins[b]} accuracy ${Evaluation.ratio(hits[b],bins[b])} confidence $mean")
        }
        lines.add("ece ${real(ece,4)}");
        val classCount=IntArray(classes);
        for(image in data.test)classCount[image.label]++
        for(l in 0 until net.layers-1) {
            val units=net.units[l];
            val means=Array(classes) {
                DoubleArray(units)
            };
            val zeros=IntArray(units);
            val preferred=IntArray(units)
            for(i in 0 until total)for(j in 0 until units) {
                val value=result.test.passes[i].a[l+1][j];
                means[data.test[i].label][j]+=value;
                if(value==0.0)zeros[j]++
            }
            lines.add("hidden ${l+1} ${net.activations[l]} units $units")
            for(k in 0 until classes) {
                if(classCount[k]>0)for(j in 0 until units)means[k][j]/=classCount[k];
                lines.add("class $k mean ${if(classCount[k]==0)"-" else reals(means[k],4)}")
            }
            for(j in 0 until units) {
                var chosen=-1;
                for(k in 0 until classes)if(classCount[k]>0&&(chosen<0||means[k][j]>means[chosen][j]))chosen=k;
                preferred[j]=chosen
            }
            lines.add("preferred "+ints(preferred));
            if(net.activations[l]=="RELU")lines.add("zero_counts "+ints(zeros))
        }
        val weights=(0 until net.parameters).filter {
            net.weight[it]
        }.sortedWith(compareBy<Int> {
            abs(result.theta[it])
        }.thenBy {
            it
        });
        lines.add("pruning")
        for(q in settings.prune) {
            val removed=q*net.weights/100;
            val theta=result.theta.copyOf();
            for(i in 0 until removed)theta[weights[i]]=0.0;
            val pruned=evaluate(net,theta,data.test);
            lines.add("prune $q removed $removed correct ${pruned.correct} test_acc ${Evaluation.ratio(pruned.correct,total)} test_loss ${real(pruned.loss,6)}")
        }
        lines.add("noise");
        for(noisy in noise) {
            val evaluated=evaluate(net,result.theta,noisy.images);
            lines.add("noise ${noisy.rate} correct ${evaluated.correct} test_acc ${Evaluation.ratio(evaluated.correct,total)}")
        }
        var misclassified="misclassified ${total-correct}";
        for(i in 0 until total)if(result.predictions[i]!=data.test[i].label)misclassified+=" ${data.test[i].id}";
        lines.add(misclassified)
        return lines
    }

    data class Confused(val actual: Int,val predicted: Int,val count: Int)
    fun comparison(results: List<Result>,noise: List<Noise>): List<String> {
        val ranked=results.sortedWith(compareByDescending<Result> {
            it.test.correct
        }.thenBy {
            it.bestLoss
        }.thenBy {
            it.index
        });
        val top=ranked[0];
        val total=data.test.size;
        val lines=mutableListOf("comparison")
        for((i,result) in ranked.withIndex())lines.add("rank ${i+1} ${result.run.name} correct ${result.test.correct} test_acc ${Evaluation.ratio(result.test.correct,total)} best_val_loss ${real(result.bestLoss,6)} test_loss ${real(result.test.loss,6)} best_epoch ${result.bestEpoch} epochs ${result.epochs.size} updates ${result.updates}")
        lines.add("agreement")
        for(a in results) {
            var text=a.run.name;
            for(b in results) {
                val count=(0 until total).count {
                    a.predictions[it]==b.predictions[it]
                };
                text+=" $count"
            };
            lines.add(text)
        }
        lines.add("mcnemar ${top.run.name}")
        for(result in ranked)if(result!==top) {
            var b=0;
            var c=0
            for(i in 0 until total) {
                val first=top.predictions[i]==data.test[i].label;
                val second=result.predictions[i]==data.test[i].label;
                if(first&&!second)b++;
                if(second&&!first)c++
            }
            val difference=maxOf(abs(b-c)-1,0);
            val numerator=difference*difference;
            val denominator=b+c
            lines.add("vs ${result.run.name} b $b c $c chi2 ${if(denominator==0)"0.0000" else Evaluation.ratio(numerator,denominator)} significant ${if(numerator*1000>3841*denominator)"yes" else "no"}")
        }
        val ensemble=IntArray(total);
        var ensembleCorrect=0;
        var fixed=0;
        var broken=0
        for(i in 0 until total) {
            val votes=IntArray(classes);
            for(result in results)votes[result.predictions[i]]++;
            var most=0;
            for(count in votes)most=maxOf(most,count)
            for(result in ranked)if(votes[result.predictions[i]]==most) {
                ensemble[i]=result.predictions[i];
                break
            }
            val correct=ensemble[i]==data.test[i].label;
            val topCorrect=top.predictions[i]==data.test[i].label;
            if(correct)ensembleCorrect++;
            if(correct&&!topCorrect)fixed++;
            if(!correct&&topCorrect)broken++
        }
        lines.add("ensemble correct $ensembleCorrect/$total test_acc ${Evaluation.ratio(ensembleCorrect,total)} fixed $fixed broken $broken")
        val soft=results.filter {
            it.network.activations[it.network.layers-1]=="SOFTMAX"
        }
        if(soft.isEmpty())lines.add("soft_ensemble none")
        else {
            var correct=0;
            for(i in 0 until total) {
                val scores=DoubleArray(classes);
                for(result in soft)for(k in 0 until classes)scores[k]+=result.test.passes[i].scores[k];
                for(k in 0 until classes)scores[k]/=soft.size;
                if(Evaluation.prediction(scores)==data.test[i].label)correct++
            };
            lines.add("soft_ensemble runs ${soft.size} correct $correct/$total test_acc ${Evaluation.ratio(correct,total)}")
        }
        for(noisy in noise)lines.add("noise ${noisy.rate} flipped ${noisy.flipped}")
        val aggregate=Array(classes) {
            IntArray(classes)
        };
        for(result in results)for(y in 0 until classes)for(predicted in 0 until classes)aggregate[y][predicted]+=result.confusion[y][predicted]
        val confused=mutableListOf<Confused>();
        for(y in 0 until classes)for(predicted in 0 until classes)if(y!=predicted&&aggregate[y][predicted]>0)confused.add(Confused(y,
            predicted,aggregate[y][predicted]))
        confused.sortWith(compareByDescending<Confused> {
            it.count
        }.thenBy {
            it.actual
        }.thenBy {
            it.predicted
        });
        lines.add("confused_pairs");
        for(pair in confused.take(5))lines.add("${pair.actual} as ${pair.predicted} count ${pair.count}")
        lines.add("");
        lines.add("saliency ${top.run.name}");
        lines.add("classes "+ints(order(classes)))
        val pixels=data.width*data.height;
        val means=Array(classes) {
            DoubleArray(pixels)
        };
        val counts=IntArray(classes);
        val levels=Array(classes) {
            IntArray(pixels)
        }
        for(i in 0 until total) {
            val label=data.test[i].label;
            counts[label]++;
            val gradient=top.network.backward(top.theta,top.test.passes[i]).input;
            for(p in 0 until pixels)means[label][p]+=abs(gradient[p])
        }
        for(k in 0 until classes) {
            var maximum=0.0;
            if(counts[k]>0)for(p in 0 until pixels) {
                means[k][p]/=counts[k];
                maximum=maxOf(maximum,means[k][p])
            };
            if(maximum>0)for(p in 0 until pixels)levels[k][p]=minOf(9,floor(10*means[k][p]/maximum).toInt())
        }
        lines.addAll(Evaluation.maps(levels,data.width,data.height));
        lines.add("");
        lines.add("hardest_training_examples ${top.run.name}")
        val training=evaluate(top.network,top.theta,train);
        val hardest=train.indices.sortedWith(compareByDescending<Int> {
            training.passes[it].loss
        }.thenBy {
            it
        })
        for(i in hardest.take(5)) {
            val image=train[i];
            val pass=training.passes[i];
            lines.add("${image.id} label ${image.label} predicted ${Evaluation.prediction(pass.scores)} loss ${real(pass.loss,6)}")
        }
        lines.add("");
        lines.add("misclassified_examples ${top.run.name}")
        for(i in 0 until total)if(top.predictions[i]!=data.test[i].label) {
            val image=data.test[i];
            val pass=top.test.passes[i];
            val predictions=results.joinToString(" ") {
                it.predictions[i].toString()
            }
            lines.add("${image.id} label ${image.label} predicted ${top.predictions[i]} confidence ${real(pass.scores[top.predictions[i]],4)} true_score ${real(pass.scores[image.label],4)} runs $predictions ensemble ${ensemble[i]}")
            var nearest=0;
            var minimum=Int.MAX_VALUE
            for(j in data.train.indices) {
                var distance=0;
                val pixelsText=data.train[j].pixels;
                for(p in 0 until pixels)if(image.pixels[p]!=pixelsText[p])distance++;
                if(distance<minimum) {
                    minimum=distance;
                    nearest=j
                }
            }
            val neighbor=data.train[nearest];
            lines.add("nearest ${neighbor.id} label ${neighbor.label} distance $minimum");
            lines.addAll(Evaluation.image(image,data.width,data.height))
        }
        return lines
    }
    fun trainingLog(results: List<Result>): List<String> {
        val lines=mutableListOf("run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved")
        for(result in results)for(e in result.epochs)lines.add("${result.run.name},${e.number},${real(e.rate,6)},${real(e.magnitude,4)},${real(e.train.loss,6)},${Evaluation.ratio(e.train.correct,train.size)},${real(e.validation.loss,6)},${Evaluation.ratio(e.validation.correct,validation.size)},${if(e.improved)1 else 0}")
        return lines
    }
    fun weights(results: List<Result>): List<String> {
        val lines=mutableListOf<String>()
        for(result in results) {
            if(lines.isNotEmpty())lines.add("");
            val net=result.network;
            lines.add("RUN ${result.run.name} NETWORK ${net.name} EPOCH ${result.bestEpoch}")
            for(l in 0 until net.layers) {
                val previous=if(l==0)net.inputs else net.units[l-1];
                val units=net.units[l];
                lines.add("LAYER ${l+1} $units $previous")
                for(j in 0 until units) {
                    var row="W";
                    for(i in 0 until previous)row+=" ${real(result.theta[net.starts[l]+j*previous+i],4)}";
                    lines.add(row)
                }
                var biases="B";
                for(j in 0 until units)biases+=" ${real(result.theta[net.biases[l]+j],4)}";
                lines.add(biases)
            }
        }
        return lines
    }
    fun predictions(results: List<Result>): List<String> {
        val lines=mutableListOf("run,id,label,predicted,confidence")
        for(result in results)for(i in data.test.indices) {
            val image=data.test[i];
            val predicted=result.predictions[i];
            lines.add("${result.run.name},${image.id},${image.label},$predicted,${real(result.test.passes[i].scores[predicted],4)}")
        }
        return lines
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
    fun run() {
        data=Dataset.read();
        settings=data.settings;
        classes=data.networks[0].classes;
        val count=data.train.size;
        val training=count-count/5;
        train=data.train.take(training);
        validation=data.train.drop(training)
        val checks=gradientChecks();
        val results=settings.runs.mapIndexed {
            i,run->fit(run,i)
        };
        val noise=noise()
        val evaluation=dataSummary();
        evaluation.add("");
        for(result in results) {
            evaluation.addAll(evaluateRun(result,noise));
            evaluation.add("")
        };
        evaluation.addAll(comparison(results,noise))
        write("gradient_check.txt",checks);
        write("training_log.csv",trainingLog(results));
        write("final_weights.txt",weights(results));
        write("predictions.csv",predictions(results));
        write("evaluation.txt",evaluation)
    }
}
fun main()=Mlp.run()
