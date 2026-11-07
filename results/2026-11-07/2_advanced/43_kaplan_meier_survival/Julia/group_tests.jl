const WEIGHTS = ("logrank","gehan_wilcoxon","tarone_ware")
function empty_totals(groups)
    n = length(groups)
    (groups=groups,events=zeros(Int,n),observed=zeros(n),expected=zeros(n),covariance=zeros(n,n))
end
function weighted_totals(subjects,groups,weight,population)
    result = empty_totals(groups)
    collections = [[s for s in subjects if s.group==group] for group in groups]
    times = sort(unique(s.time for s in subjects if s.event==1))
    for time in times
        risk = [count(s->s.time>=time,rows) for rows in collections]
        deaths = [count(s->s.time==time && s.event==1,rows) for rows in collections]
        n,d = sum(risk),sum(deaths)
        value = weight=="logrank" ? 1.0 : weight=="gehan_wilcoxon" ? n/population : sqrt(n/population)
        for h in eachindex(groups)
            result.events[h] += deaths[h]
            result.observed[h] += value*deaths[h]
            result.expected[h] += value*(d*risk[h]/n)
            n<2 && continue
            factor = value*value*(d*(n-d)/((n-1)*n*n))
            for l in eachindex(groups)
                multiple = h==l ? risk[h]*(n-risk[h]) : -(risk[h]*risk[l])
                result.covariance[h,l] += factor*multiple
            end
        end
    end
    result
end
function finish_test(result)
    df = length(result.groups)-1
    difference = result.observed[1:df].-result.expected[1:df]
    solution = solve_system(result.covariance[1:df,1:df],difference)
    statistic = total(difference[i]*solution[i] for i in 1:df)
    (;result...,statistic=statistic,degrees=df,p=chi_square_p(statistic,df))
end
weighted_test(subjects,groups,weight,population) = finish_test(weighted_totals(
    subjects,
    groups,
    weight,
    population
))
function combine_strata(strata,groups)
    result = empty_totals(groups)
    for stratum in strata
        result.events .+= stratum.events
        result.observed .+= stratum.observed
        result.expected .+= stratum.expected
        result.covariance .+= stratum.covariance
    end
    finish_test(result)
end
