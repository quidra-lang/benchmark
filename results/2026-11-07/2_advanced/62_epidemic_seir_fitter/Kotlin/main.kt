import kotlin.math.*

object Epidemic {
    lateinit var data: DataIO.Data;
    lateinit var settings: DataIO.Settings
    var days=0;
    var groups=0;
    var population=0;
    var caseTotal=0;
    var deathTotal=0;
    lateinit var populations: IntArray;
    lateinit var ageInflows: IntArray
    lateinit var fatalities: DoubleArray;
    lateinit var initial: DoubleArray;
    lateinit var sirInitial: DoubleArray;
    lateinit var ageInitial: DoubleArray;
    lateinit var multipliers: DoubleArray
    var fatality=0.0;
    var sigma=0.0;
    var gamma0=0.0;
    var beta=0.0;
    var rho=0.0;
    var gamma=0.0;
    var r0=0.0;
    var betaGrid=0.0;
    var rhoGrid=0.0;
    var betaGolden=0.0;
    var sseGrid=0.0;
    var sseGolden=0.0;
    var sseNelder=0.0;
    var deltaBeta=0.0;
    var deltaRho=0.0;
    var seBeta=0.0
    lateinit var fitted: List<DoubleArray>;
    lateinit var ageFitted: List<DoubleArray>;
    lateinit var incidence: DoubleArray;
    lateinit var reported: DoubleArray;
    lateinit var residuals: DoubleArray;
    lateinit var modelDeaths: DoubleArray;
    lateinit var average7: DoubleArray;
    lateinit var rt: DoubleArray;
    lateinit var generation: DoubleArray;
    lateinit var contacts: Array<DoubleArray>
    val fit=mutableListOf<String>();
    val reproduction=mutableListOf<String>();
    val trajectories=mutableListOf<String>();
    val scenarios=mutableListOf<String>()
    data class Key(val beta: Double,val gamma: Double)
    data class Eigen(val value: Double,val vector: DoubleArray)
    val cache=mutableMapOf<Key,DoubleArray>()
    fun f(value: Double,digits: Int=4)=Report.f(value,digits)
    fun sum(values: DoubleArray): Double {
        var total=0.0;
        for(value in values)total+=value;
        return total
    }
    fun sum(values: IntArray): Int {
        var total=0;
        for(value in values)total+=value;
        return total
    }
    fun peak(values: DoubleArray): Int {
        var selected=0;
        for(i in 1 until values.size)if(values[i]>values[selected])selected=i;
        return selected
    }
    fun constants(size: Int,value: Double)=DoubleArray(size) {
        value
    }
    fun column(states: List<DoubleArray>,column: Int)=DoubleArray(states.size) {
        states[it][column]
    }
    fun scale(values: DoubleArray,factor: Double)=DoubleArray(values.size) {
        factor*values[it]
    }
    fun values(values: DoubleArray,digits: Int)=values.joinToString(" ") {
        f(it,digits)
    }
    fun rmse(error: Double,count: Int=days)=sqrt(error/count)
    fun squared(values: DoubleArray,coefficient: Double,observations: IntArray,first: Int,last: Int): Double {
        var sum=0.0;
        for(i in first until last) {
            val e=coefficient*values[i]-observations[i];
            sum+=e*e
        };
        return sum
    }
    fun sequence(interventions: List<DataIO.Intervention>,count: Int): DoubleArray {
        val result=DoubleArray(count);
        var k=0;
        for(d in 1..count) {
            while(k+1<interventions.size&&interventions[k+1].day<=d)k++;
            result[d-1]=interventions[k].multiplier
        };
        return result
    }
    fun states(b: Double,g: Double,mu: DoubleArray=multipliers,state: DoubleArray=initial,sigmaValue: Double=sigma)=Integrator.simulate(Models.seird(population,
        sigmaValue,fatality,b,g),state,mu,intArrayOf(5))
    fun ageStates(w: Array<DoubleArray>,mu: DoubleArray,state: DoubleArray)=Integrator.simulate(Models.age(populations,
        fatalities,sigma,beta,gamma,w),state,mu,ageInflows)
    fun incidence(b: Double,g: Double)=cache.getOrPut(Key(b,g)) {
        column(states(b,g),5)
    }
    fun error(b: Double,g: Double,p: Double)=squared(incidence(b,g),p,data.cases,0,days)
    fun ageIncidence(states: List<DoubleArray>): DoubleArray {
        val result=DoubleArray(states.size);
        for(d in result.indices)for(g in 0 until groups)result[d]+=states[d][6*g+5];
        return result
    }
    fun sirIncidence(b: Double)=column(Integrator.simulate(Models.sir(population,b,gamma),sirInitial,multipliers,intArrayOf(3)),3)
    fun prepare() {
        data=DataIO.read();
        settings=data.settings;
        days=data.cases.size;
        groups=data.groups.size;
        populations=IntArray(groups);
        fatalities=DoubleArray(groups);
        ageInflows=IntArray(groups)
        for(g in 0 until groups) {
            val group=data.groups[g];
            populations[g]=group.population;
            fatalities[g]=group.fatality;
            population+=populations[g];
            fatality+=populations[g]*fatalities[g];
            ageInflows[g]=6*g+5
        }
        fatality/=population;
        caseTotal=sum(data.cases);
        deathTotal=sum(data.deaths);
        sigma=settings.real("sigma",0);
        gamma0=settings.real("gamma",0)
        val e=settings.real("initial",0);
        val i=settings.real("initial",1);
        initial=doubleArrayOf(population-e-i,e,i,0.0,0.0,0.0);
        sirInitial=doubleArrayOf(population-e-i,e+i,0.0,0.0);
        ageInitial=DoubleArray(groups*6)
        for(g in 0 until groups) {
            val eg=e*populations[g]/population;
            val ig=i*populations[g]/population;
            ageInitial[6*g]=populations[g]-eg-ig;
            ageInitial[6*g+1]=eg;
            ageInitial[6*g+2]=ig
        }
        multipliers=sequence(data.interventions,days)
    }
    fun goldenLines(round: Int,name: String,search: Fitting.Golden) {
        for((i,r) in search.records.withIndex())fit.add("golden $round $name $i a ${f(r.a,6)} b ${f(r.b,6)} c ${f(r.c,6)} d ${f(r.d,6)} rmse ${f(rmse(r.fc))} ${f(rmse(r.fd))}")
        fit.add("golden_result $round $name ${f(search.point,6)} sse ${f(search.value,1)}")
    }
    fun fitModel() {
        val bmin=settings.real("beta_grid",0);
        val bmax=settings.real("beta_grid",1);
        val pmin=settings.real("rho_grid",0);
        val pmax=settings.real("rho_grid",1)
        val nb=settings.integer("beta_grid",2);
        val np=settings.integer("rho_grid",2);
        deltaBeta=(bmax-bmin)/(nb-1);
        deltaRho=(pmax-pmin)/(np-1)
        val betas=DoubleArray(nb) {
            bmin+(bmax-bmin)*it/(nb-1)
        };
        val rhos=DoubleArray(np) {
            pmin+(pmax-pmin)*it/(np-1)
        }
        fit.add("data days $days cases $caseTotal deaths $deathTotal population $population fatality ${f(fatality,6)}");
        fit.add("grid gamma ${f(gamma0)} rho ${values(rhos,4)}");
        sseGrid=Double.MAX_VALUE
        for(i in 0 until nb) {
            val errors=DoubleArray(np);
            for(j in 0 until np) {
                errors[j]=error(betas[i],gamma0,rhos[j]);
                if(errors[j]<sseGrid) {
                    sseGrid=errors[j];
                    betaGrid=betas[i];
                    rhoGrid=rhos[j]
                }
            }
            fit.add("grid beta ${f(betas[i])} rmse "+errors.joinToString(" ") {
                f(rmse(it),2)
            })
        }
        fit.add("grid_best beta ${f(betaGrid)} rho ${f(rhoGrid)} sse ${f(sseGrid,1)} rmse ${f(rmse(sseGrid))}")
        var b=betaGrid;
        var p=rhoGrid;
        val ng=settings.integer("golden",0)
        for(round in 1..settings.integer("golden",1)) {
            val fixedP=p;
            val bs=Fitting.golden( {
                x->error(x,gamma0,fixedP)
            },b-deltaBeta,b+deltaBeta,ng);
            goldenLines(round,"beta",bs);
            b=bs.point
            val fixedB=b;
            val ps=Fitting.golden( {
                x->error(fixedB,gamma0,x)
            },p-deltaRho,p+deltaRho,ng);
            goldenLines(round,"rho",ps);
            p=ps.point;
            sseGolden=ps.value
        }
        betaGolden=b;
        rho=p
        val simplex=Fitting.nelder( {
            x,y->error(x,y,rho)
        },b,gamma0,settings.real("simplex",0),settings.real("simplex",1),settings.real("nelder_mead",
            0),settings.real("nelder_mead",1),settings.real("nelder_mead",2),settings.real("nelder_mead",
            3),settings.integer("nelder_mead",4))
        for(v in simplex.initial)fit.add("simplex ${v.serial} beta ${f(v.beta,6)} gamma ${f(v.gamma,6)} rmse ${f(rmse(v.value))}")
        for((i,op) in simplex.operations.withIndex()) {
            val v=op.best;
            fit.add("nelder_mead ${i+1} ${op.name} beta ${f(v.beta,6)} gamma ${f(v.gamma,6)} rmse ${f(rmse(v.value))}")
        }
        for((i,v) in simplex.vertices.withIndex())fit.add("final_simplex ${i+1} beta ${f(v.beta,6)} gamma ${f(v.gamma,6)} rmse ${f(rmse(v.value))}")
        val best=simplex.vertices[0];
        beta=best.beta;
        gamma=best.gamma;
        sseNelder=best.value;
        r0=beta/gamma;
        val mean=caseTotal.toDouble()/days;
        var sst=0.0;
        for(c in data.cases) {
            val e=c-mean;
            sst+=e*e
        }
        fit.add("fitted beta ${f(beta,6)} gamma ${f(gamma,6)} rho ${f(rho,6)} sigma ${f(sigma,6)} r0 ${f(r0)}")
        fit.add("sse grid ${f(sseGrid,1)} golden ${f(sseGolden,1)} nelder_mead ${f(sseNelder,1)} rmse ${f(rmse(sseNelder))} r2 ${f(1-sseNelder/sst)}")
        val names=arrayOf("grid","golden","nelder_mead");
        val bs=doubleArrayOf(betaGrid,betaGolden,beta);
        val gs=doubleArrayOf(gamma0,gamma0,gamma);
        val ps=doubleArrayOf(rhoGrid,rho,rho);
        val ss=doubleArrayOf(sseGrid,sseGolden,sseNelder)
        for(k in 0..2)fit.add("stage ${names[k]} beta ${f(bs[k],6)} gamma ${f(gs[k],6)} rho ${f(ps[k],6)} r0 ${f(bs[k]/gs[k])} rmse ${f(rmse(ss[k]))}")
    }
    fun fittedCourse() {
        fitted=states(beta,gamma);
        incidence=column(fitted,5);
        reported=scale(incidence,rho);
        residuals=DoubleArray(days);
        modelDeaths=DoubleArray(days);
        average7=DoubleArray(days);
        rt=DoubleArray(days)
        trajectories.add("day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported");
        var observed=0;
        var cumulative=0.0
        for(d in 0 until days) {
            val y=fitted[d];
            residuals[d]=data.cases[d]-reported[d];
            modelDeaths[d]=y[4]-(if(d==0)0.0 else fitted[d-1][4]);
            var count=0
            for(j in maxOf(0,d-6)..d)count+=data.cases[j];
            average7[d]=count.toDouble()/minOf(d+1,7);
            rt[d]=r0*multipliers[d]*(if(d==0)initial[0] else fitted[d-1][0])/population
            observed+=data.cases[d];
            cumulative+=reported[d];
            var row=(d+1).toString();
            for(c in 0..5)row+=",${f(y[c],1)}";
            row+=",${f(reported[d],1)},${data.cases[d]},${f(average7[d],2)},$observed,${f(cumulative,1)}";
            trajectories.add(row)
        }
    }

    fun diagnostics() {
        var residualSum=0.0;
        var absolute=0.0;
        var u=0.0;
        var difference=0.0;
        var positive=0;
        var runs=1;
        var maximum=0
        for(d in 0 until days) {
            val e=residuals[d];
            residualSum+=e;
            absolute+=abs(e);
            u+=e*e;
            if(e>0)positive++;
            if(abs(e)>abs(residuals[maximum]))maximum=d
            if(d>0) {
                if((e>0)!=(residuals[d-1]>0))runs++;
                val delta=e-residuals[d-1];
                difference+=delta*delta
            }
        }
        fit.add("residuals sum ${f(residualSum,1)} mae ${f(absolute/days,1)} max ${f(residuals[maximum],1)} day ${maximum+1} positive $positive runs $runs durbin_watson ${f(difference/u)}")
        val autocorrelation=DoubleArray(7);
        for(k in 1..7) {
            var total=0.0;
            for(d in 0 until days-k)total+=residuals[d]*residuals[d+k];
            autocorrelation[k-1]=total/u
        };
        fit.add("autocorrelation ${values(autocorrelation,4)}")
        var outliers=0;
        for(d in 0 until days) {
            val z=residuals[d]/sqrt(reported[d]);
            if(abs(z)>settings.real("outlier",0)) {
                outliers++;
                fit.add("outlier ${d+1} observed ${data.cases[d]} fitted ${f(reported[d],1)} z ${f(z)}")
            }
        };
        fit.add("outliers $outliers")
        val counts=IntArray(7);
        val totals=DoubleArray(7);
        val factors=DoubleArray(7);
        for(d in 0 until days) {
            counts[d%7]+=data.cases[d];
            totals[d%7]+=reported[d]
        }
        for(k in 0..6) {
            factors[k]=counts[k]/totals[k];
            fit.add("weekday ${k+1} observed ${counts[k]} fitted ${f(totals[k],1)} factor ${f(factors[k])}")
        }
        var adjusted=0.0;
        for(d in 0 until days) {
            val e=reported[d]*factors[d%7]-data.cases[d];
            adjusted+=e*e
        };
        fit.add("weekday_adjusted rmse ${f(rmse(adjusted))}")
        val infections=sum(incidence);
        fit.add("burden infections ${f(infections,1)} ascertainment ${f(caseTotal/infections)} deaths_per_infection ${f(deathTotal/infections,6)}")
        var product=0.0;
        var squares=0.0;
        for(d in 0 until days) {
            product+=modelDeaths[d]*data.deaths[d];
            squares+=modelDeaths[d]*modelDeaths[d]
        };
        val kappa=product/squares
        fit.add("deaths observed $deathTotal model ${f(fitted.last()[4],1)} rmse ${f(rmse(squared(modelDeaths,1.0,data.deaths,0,days)))} scale ${f(kappa)} implied_fatality ${f(fatality*kappa,6)} cfr ${f(deathTotal.toDouble()/caseTotal)}")
        var largest=-Double.MAX_VALUE;
        var lag=0
        for(k in 0..settings.integer("death_lag",0)) {
            var a=0;
            var b=0;
            var y=0;
            var dead=0;
            var cases=0;
            for(d in 0 until days-k) {
                a+=data.cases[d]*data.deaths[d+k];
                b+=data.cases[d]*data.cases[d];
                y+=data.deaths[d+k]*data.deaths[d+k];
                dead+=data.deaths[d+k];
                cases+=data.cases[d]
            }
            val correlation=a/sqrt(b.toDouble()*y);
            if(correlation>largest) {
                largest=correlation;
                lag=k
            };
            fit.add("death_lag $k correlation ${f(correlation)} cfr ${f(dead.toDouble()/cases)}")
        };
        fit.add("death_best_lag $lag")
        var previous=0;
        for(first in 0 until days step 7) {
            val end=minOf(days,first+7);
            var cases=0;
            var deaths=0;
            var predicted=0.0;
            var dead=0.0
            for(d in first until end) {
                cases+=data.cases[d];
                deaths+=data.deaths[d];
                predicted+=reported[d];
                dead+=modelDeaths[d]
            }
            fit.add("weekly ${first/7+1} days ${first+1} $end observed $cases fitted ${f(predicted,1)} deaths_observed $deaths deaths_model ${f(dead,1)} growth "+if(first==0)"-" else f(cases.toDouble()/previous));
            previous=cases
        }
    }
    fun profilesAndBacktest() {
        val names=arrayOf("beta","gamma","rho");
        val fittedValues=doubleArrayOf(beta,gamma,rho)
        for(parameter in 0..2) {
            val v=fittedValues[parameter];
            val h=v/100;
            val errors=DoubleArray(11)
            for(k in -5..5) {
                val point=fittedValues.copyOf();
                point[parameter]=v*(1+k/100.0);
                errors[k+5]=error(point[0],point[1],point[2]);
                fit.add("profile ${names[parameter]} $k value ${f(point[parameter],6)} rmse ${f(rmse(errors[k+5]))}")
            }
            val curvature=(errors[6]-2*errors[5]+errors[4])/(h*h);
            val variance=sseNelder/(days-3);
            val standard=sqrt(2*variance/curvature);
            if(parameter==0)seBeta=standard;
            fit.add("profile_se ${names[parameter]} ${f(standard,6)}")
        }
        val nt=days-settings.integer("holdout",0);
        val ng=settings.integer("golden",0);
        val prefix=multipliers.copyOf(nt)
        val bs=Fitting.golden( {
            x->squared(column(states(x,gamma,prefix,initial,sigma),5),rho,data.cases,0,nt)
        },beta-deltaBeta,beta+deltaBeta,ng);
        val bb=bs.point;
        val trained=column(states(bb,gamma,prefix,initial,sigma),5)
        val ps=Fitting.golden( {
            x->squared(trained,x,data.cases,0,nt)
        },rho-deltaRho,rho+deltaRho,ng);
        val pb=ps.point;
        val forecast=scale(incidence(bb,gamma),pb)
        fit.add("backtest train_days $nt beta ${f(bb,6)} rho ${f(pb,6)} train_rmse ${f(rmse(ps.value,nt))} test_rmse ${f(rmse(squared(forecast,1.0,data.cases,nt,days),days-nt))} full_fit_test_rmse ${f(rmse(squared(reported,1.0,data.cases,nt,days),days-nt))}")
        for(d in nt until days)fit.add("backtest_day ${d+1} observed ${data.cases[d]} forecast ${f(forecast[d],1)} error ${f(data.cases[d]-forecast[d],1)}")
        val estimated=data.interventions.toMutableList();
        var after=sseNelder
        for(k in 1 until estimated.size) {
            val given=data.interventions[k];
            val effect=Fitting.golden( {
                x->val changed=estimated.toMutableList();
                changed[k]=DataIO.Intervention(given.day,x);
                squared(column(states(beta,gamma,sequence(changed,days),initial,sigma),5),rho,data.cases,0,days)
            },given.multiplier-settings.real("effect_width",0),given.multiplier+settings.real("effect_width",0),ng)
            estimated[k]=DataIO.Intervention(given.day,effect.point);
            after=effect.value;
            fit.add("effect ${k+1} day ${given.day} given ${f(given.multiplier)} estimated ${f(effect.point,6)} sse ${f(after,1)}")
        }
        fit.add("effect_sse before ${f(sseNelder,1)} after ${f(after,1)} rmse ${f(rmse(after))}")
        val sensitivities=arrayOf("beta","gamma","sigma","rho");
        for(k in 0..3)for(factor in doubleArrayOf(0.9,1.1)) {
            val point=doubleArrayOf(beta,gamma,sigma,rho);
            point[k]=point[k]*factor;
            val course=states(point[0],point[1],multipliers,initial,point[2]);
            val series=column(course,5);
            val peak=peak(series)
            fit.add("sensitivity ${sensitivities[k]} ${f(factor,2)} r0 ${f(point[0]/point[1])} rmse ${f(rmse(squared(series,point[3],data.cases,0,days)))} peak_day ${peak+1} peak ${f(point[3]*series[peak],1)} attack ${f((population-course.last()[0])/population)}")
        }
    }
    fun finalSize(reproductionNumber: Double): Double {
        if(reproductionNumber<=1)return 0.0;
        var lo=1-1/reproductionNumber;
        var hi=1.0;
        repeat(20) {
            val mid=(lo+hi)/2;
            val g=1-mid-exp(-reproductionNumber*mid);
            if(g>0)lo=mid else hi=mid
        };
        return (lo+hi)/2
    }
    fun power(matrix: Array<DoubleArray>): Eigen {
        var vector=constants(matrix.size,1.0/matrix.size);
        var value=0.0;
        repeat(200) {
            val next=DoubleArray(vector.size);
            for(g in next.indices)for(h in next.indices)next[g]+=matrix[g][h]*vector[h];
            value=sum(next);
            for(g in next.indices)next[g]/=value;
            vector=next
        };
        return Eigen(value,vector)
    }
    fun homogeneous() {
        val terminal=states(beta,gamma,constants(730,1.0),initial,sigma).last();
        reproduction.add("r0 ${f(r0)} herd_immunity ${f(1-1/r0)}");
        reproduction.add("final_size equation ${f(finalSize(r0))} simulated ${f((population-terminal[0])/population)}")
        val length=settings.integer("generation",0);
        val inflow=column(Integrator.simulate(Models.generation(sigma,gamma),doubleArrayOf(1.0,0.0,0.0),constants(length,1.0),intArrayOf(2)),2);
        val coverage=sum(inflow);
        var mean=0.0;
        generation=DoubleArray(length)
        for(i in 0 until length) {
            generation[i]=inflow[i]/coverage;
            mean+=(i+0.5)*generation[i]
        };
        reproduction.add("generation mean ${f(mean)} theory ${f(1/sigma+1/gamma)} coverage ${f(coverage)}");
        for(i in 0 until length)reproduction.add("generation_weight ${i+1} ${f(generation[i],6)}")
        val modelPeak=peak(incidence);
        val infectiousPeak=peak(column(fitted,2));
        var observedPeak=0;
        val averagePeak=peak(average7);
        for(i in 1 until days)if(data.cases[i]>data.cases[observedPeak])observedPeak=i
        reproduction.add("peak model day ${modelPeak+1} incidence ${f(incidence[modelPeak],1)} reported ${f(reported[modelPeak],1)} infectious_day ${infectiousPeak+1} infectious ${f(fitted[infectiousPeak][2],1)}")
        reproduction.add("peak observed day ${observedPeak+1} cases ${data.cases[observedPeak]} average7_day ${averagePeak+1} average7 ${f(average7[averagePeak],2)}")
        for(k in data.interventions.indices) {
            val first=data.interventions[k].day-1;
            val end=if(k+1<data.interventions.size)data.interventions[k+1].day-1 else days;
            var count=0;
            var predicted=0.0;
            var errors=0.0;
            var bias=0.0
            for(d in first until end) {
                count+=data.cases[d];
                predicted+=reported[d];
                errors+=residuals[d]*residuals[d];
                bias+=residuals[d]
            }
            reproduction.add("period ${k+1} days ${first+1} $end multiplier ${f(data.interventions[k].multiplier)} rt_start ${f(rt[first])} rt_end ${f(rt[end-1])} observed $count fitted ${f(predicted,1)} rmse ${f(rmse(errors,end-first))} bias ${f(bias/(end-first),1)}")
        }
        for(target in settings.integers("milestones")) {
            var observed=0;
            var predicted=0.0;
            var observedDay="never";
            var fittedDay="never";
            for(d in 0 until days) {
                observed+=data.cases[d];
                predicted+=reported[d];
                if(observedDay=="never"&&observed>=target)observedDay=(d+1).toString();
                if(fittedDay=="never"&&predicted>=target)fittedDay=(d+1).toString()
            };
            reproduction.add("milestone $target observed $observedDay fitted $fittedDay")
        }
        val fittedTotal=sum(reported);
        val noInterventions=scale(column(states(beta,gamma,constants(days,data.interventions[0].multiplier),initial,sigma),5),rho);
        val peak=peak(noInterventions)
        reproduction.add("counterfactual none reported ${f(sum(noInterventions),1)} peak_day ${peak+1} peak ${f(noInterventions[peak],1)} averted ${f(sum(noInterventions)-fittedTotal,1)}")
        for(k in 1 until data.interventions.size) {
            val removed=data.interventions.toMutableList();
            removed.removeAt(k);
            val total=sum(scale(column(states(beta,gamma,sequence(removed,days),initial,sigma),5),rho));
            reproduction.add("counterfactual without ${k+1} reported ${f(total,1)} averted ${f(total-fittedTotal,1)}")
        }
        for(k in 1 until data.interventions.size)for(shift in intArrayOf(-7,7)) {
            val changed=data.interventions.toMutableList();
            val given=changed[k];
            changed[k]=DataIO.Intervention(given.day+shift,given.multiplier);
            val total=sum(scale(column(states(beta,gamma,sequence(changed,days),initial,sigma),5),rho));
            reproduction.add("timing ${k+1} shift $shift reported ${f(total,1)} change ${f(total-fittedTotal,1)}")
        }
        for(d in 1 until days)if((rt[d]<1)!=(rt[d-1]<1))reproduction.add("rt_cross day ${d+1} "+if(rt[d]<1)"down" else "up")
        val pressure=DoubleArray(days);
        for(d in 0 until days)for(s in 1..minOf(length,d))pressure[d]+=generation[s-1]*data.cases[d-s]
        for(d in 0 until days) {
            var empirical="-";
            if(d+1>=length+7) {
                var count=0;
                var total=0.0;
                for(j in d-6..d) {
                    count+=data.cases[j];
                    total+=pressure[j]
                };
                empirical=f(count/total)
            };
            reproduction.add("rt ${d+1} model ${f(rt[d])} empirical $empirical")
        }
    }
    fun ngm(w: Array<DoubleArray>,susceptible: DoubleArray,multiplier: Double)=Array(groups) {
        g->DoubleArray(groups) {
            h->multiplier*r0*w[g][h]*susceptible[6*g]/populations[h]
        }
    }
    fun ages() {
        var average=0.0;
        for(g in 0 until groups) {
            var row=0.0;
            for(h in 0 until groups)row+=data.contacts[g][h];
            average+=populations[g]*row
        };
        average/=population
        contacts=Array(groups) {
            DoubleArray(groups)
        };
        val matrix=Array(groups) {
            DoubleArray(groups)
        };
        for(g in 0 until groups)for(h in 0 until groups) {
            contacts[g][h]=data.contacts[g][h]/average;
            matrix[g][h]=r0*contacts[g][h]*populations[g]/populations[h]
        }
        val eigen=power(matrix);
        for(g in 0 until groups)reproduction.add("ngm ${data.groups[g].name} ${values(matrix[g],4)}");
        reproduction.add("r0_age ${f(eigen.value)} ratio ${f(eigen.value/r0)} kbar ${f(average)} eigenvector ${values(eigen.vector,4)}")
        var z=constants(groups,1.0);
        repeat(100) {
            val next=DoubleArray(groups);
            for(g in 0 until groups) {
                var total=0.0;
                for(h in 0 until groups)total+=r0*contacts[g][h]*z[h];
                next[g]=1-exp(-total)
            };
            z=next
        }
        var terminal=ageStates(contacts,constants(730,1.0),ageInitial).last();
        var equation=0.0;
        var simulated=0.0
        for(g in 0 until groups) {
            val actual=(populations[g]-terminal[6*g])/populations[g];
            equation+=populations[g]*z[g];
            simulated+=populations[g]*actual;
            reproduction.add("final_size_age ${data.groups[g].name} equation ${f(z[g])} simulated ${f(actual)}")
        };
        reproduction.add("final_size_age total equation ${f(equation/population)} simulated ${f(simulated/population)}")
        ageFitted=ageStates(contacts,multipliers,ageInitial);
        for(d in 0 until days step 7) {
            val previous=if(d==0)ageInitial else ageFitted[d-1];
            reproduction.add("age_rt ${d+1} ${f(power(ngm(contacts,previous,multipliers[d])).value)} homogeneous ${f(rt[d])}")
        }
        for(first in 0 until days step 7) {
            val end=minOf(days,first+7);
            val inflow=DoubleArray(groups);
            for(d in first until end)for(g in 0 until groups)inflow[g]+=ageFitted[d][6*g+5];
            reproduction.add("age_weekly ${first/7+1} days ${first+1} $end ${values(inflow,1)}")
        }
        val infections=DoubleArray(groups);
        for(g in 0 until groups)for(d in 0 until days)infections[g]+=ageFitted[d][6*g+5];
        val total=sum(infections);
        terminal=ageFitted.last()
        for(g in 0 until groups) {
            val series=column(ageFitted,6*g+5);
            val peak=peak(series);
            reproduction.add("age ${data.groups[g].name} attack ${f((populations[g]-terminal[6*g])/populations[g])} infections ${f(infections[g],1)} share ${f(infections[g]/total)} deaths ${f(terminal[6*g+4],1)} peak_day ${peak+1} peak ${f(series[peak],1)}")
        }
        for(change in settings.changes) {
            var target=-1;
            for(g in 0 until groups)if(data.groups[g].name==change.group)target=g;
            val changed=Array(groups) {
                DoubleArray(groups)
            };
            val ngm=Array(groups) {
                DoubleArray(groups)
            }
            for(g in 0 until groups)for(h in 0 until groups) {
                changed[g][h]=contacts[g][h]*(if(g==target)change.factor else 1.0)*(if(h==target)change.factor else 1.0);
                ngm[g][h]=r0*changed[g][h]*populations[g]/populations[h]
            }
            val course=ageStates(changed,multipliers,ageInitial);
            val last=course.last();
            var deaths=0.0;
            var attack=0.0;
            for(g in 0 until groups) {
                deaths+=last[6*g+4];
                attack+=populations[g]-last[6*g]
            };
            reproduction.add("contact_change ${change.name} group ${change.group} factor ${f(change.factor)} r0_age ${f(power(ngm).value)} infections ${f(sum(ageIncidence(course)),1)} deaths ${f(deaths,1)} attack ${f(attack/population)}")
        }
    }
    fun modelComparisons() {
        val names=arrayOf("sir","seir","age");
        val series=arrayOf(sirIncidence(beta),incidence,ageIncidence(ageFitted))
        for(k in 0..2) {
            var numerator=0.0;
            var denominator=0.0;
            for(d in 0 until days) {
                numerator+=data.cases[d]*series[k][d];
                denominator+=series[k][d]*series[k][d]
            };
            val optimal=numerator/denominator
            fit.add("model ${names[k]} rmse ${f(rmse(squared(series[k],rho,data.cases,0,days)))} peak_day ${peak(series[k])+1} rho_opt ${f(optimal,6)} rmse_opt ${f(rmse(squared(series[k],optimal,data.cases,0,days)))}")
        }
        val search=Fitting.golden( {
            x->squared(sirIncidence(x),rho,data.cases,0,days)
        },settings.real("beta_grid",0),settings.real("beta_grid",1),settings.integer("golden",0));
        fit.add("model sir_fit beta ${f(search.point,6)} rmse ${f(rmse(search.value))} peak_day ${peak(sirIncidence(search.point))+1}")
    }
    fun projections() {
        scenarios.add("scenario,day,incidence,reported");
        val horizon=settings.integer("horizon",0);
        var reference=0.0;
        var first=true
        for(scenario in settings.scenarios) {
            val m=scenario.multiplier;
            val course=states(beta,gamma,constants(horizon,m),fitted.last(),sigma);
            val projected=scale(column(course,5),rho);
            val peak=peak(projected);
            var above=0;
            var below="never"
            for(j in 0 until horizon) {
                scenarios.add("${scenario.name},${days+j+1},${f(course[j][5],1)},${f(projected[j],1)}");
                if(projected[j]>=settings.real("threshold",0))above++ else if(below=="never")below=(days+j+1).toString()
            }
            val total=sum(projected);
            if(first) {
                reference=total;
                first=false
            }
            reproduction.add("scenario ${scenario.name} multiplier ${f(m)} rt ${f(r0*m*fitted.last()[0]/population)} reported ${f(total,1)} peak_day ${days+peak+1} peak ${f(projected[peak],1)} attack ${f((population-course.last()[0])/population)} final_size ${f(finalSize(r0*m))} averted ${f(reference-total,1)} below $below days_above $above")
            val low=beta-2*seBeta;
            val high=beta+2*seBeta;
            val combined=DoubleArray(days+horizon);
            multipliers.copyInto(combined);
            combined.fill(m,days,combined.size);
            val totals=DoubleArray(2);
            val betas=doubleArrayOf(low,high)
            for(k in 0..1) {
                val band=states(betas[k],gamma,combined,initial,sigma);
                for(d in days until days+horizon)totals[k]+=rho*band[d][5]
            };
            reproduction.add("scenario_band ${scenario.name} beta_low ${f(low,6)} reported_low ${f(totals[0],1)} beta_high ${f(high,6)} reported_high ${f(totals[1],1)}")
            val last=ageStates(contacts,constants(horizon,m),ageFitted.last()).last();
            val attack=DoubleArray(groups);
            var deaths=0.0;
            for(g in 0 until groups) {
                attack[g]=(populations[g]-last[6*g])/populations[g];
                deaths+=last[6*g+4]
            };
            reproduction.add("scenario_age ${scenario.name} attack ${values(attack,4)} deaths ${f(deaths,1)}")
        }
    }
    fun run() {
        prepare();
        fitModel();
        fittedCourse();
        diagnostics();
        profilesAndBacktest();
        homogeneous();
        ages();
        modelComparisons();
        projections();
        DataIO.write("fit.txt",fit);
        DataIO.write("trajectories.csv",trajectories);
        DataIO.write("scenarios.csv",scenarios);
        DataIO.write("reproduction.txt",reproduction);
        DataIO.write("curve_plot.txt",Report.plot(data.cases,reported))
    }
}
fun main()=Epidemic.run()
