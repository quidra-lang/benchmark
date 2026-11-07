function calculate_diagnostics(fit,params)
    n,r = fit.n,fit.rank
    df = n-r
    sigma = sqrt(fit.rss/df)
    rows = NamedTuple[]
    for i in 1:n
        h,residual = fit.leverage[i],fit.eps[i]
        z = residual/(sigma*sqrt(1-h))
        studentized = z*sqrt((df-1)/(df-z*z))
        cooks = z*z*h/(r*(1-h))
        dffits = studentized*sqrt(h/(1-h))
        flags = ""
        h>params["LEVERAGE"][1]*r/n && (flags*="H")
        abs(studentized)>params["STUDENTIZED"][1] && (flags*="O")
        cooks>params["COOK"][1]/n && (flags*="C")
        abs(dffits)>params["DFFITS"][1]*sqrt(r/n) && (flags*="F")
        deleted = sigma*sqrt((df-z*z)/(df-1))
        dfbetas = [fit.g[i,k]*residual/(1-h)/(deleted*sqrt(fit.variance[k])) for k in 1:r]
        push!(
            rows,
            (
                standardized=z,
                studentized=studentized,
                cooks=cooks,
                dffits=dffits,
                flags=isempty(flags) ? "-" : flags,
                dfbetas=dfbetas
            )
        )
    end
    dw = ordered_sum((fit.eps[i]-fit.eps[i-1])*(fit.eps[i]-fit.eps[i-1]) for i in 2:n)/fit.rss
    squared = fit.eps.*fit.eps
    auxiliary = fit_ols(fit.matrix[:,fit.accepted],squared,ones(n),params["RANK_TOL"][1])
    mean = ordered_sum(squared)/n
    tss = ordered_sum((value-mean)*(value-mean) for value in squared)
    bp = n*(1-auxiliary.rss/tss)
    bp_df = auxiliary.rank-1
    mean = ordered_sum(fit.eps)/n
    centered = fit.eps.-mean
    m2 = ordered_sum(v*v for v in centered)/n
    m3 = ordered_sum(v*v*v for v in centered)/n
    m4 = ordered_sum(v*v*v*v for v in centered)/n
    skewness,kurtosis = m3/(m2*sqrt(m2)),m4/(m2*m2)
    jb = n/6*(skewness*skewness+(kurtosis-3)*(kurtosis-3)/4)
    (rows=rows,dw=dw,bp=(bp,bp_df,chi_pvalue(bp,bp_df)),jb=(jb,chi_pvalue(jb,2),skewness,kurtosis))
end
