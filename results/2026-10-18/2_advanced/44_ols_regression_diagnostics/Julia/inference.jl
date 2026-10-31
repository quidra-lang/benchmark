using Printf
function log_gamma(x)
    coefficients = (
        76.18009172947146,
        -86.50532032941677,
        24.01409824083091,
        -1.231739572450155,
        0.001208650973866179,
        -0.000005395239384953
    )
    t = x+5.5
    adjustment = t-(x+0.5)*log(t)
    series = 1.000000000190015
    for (j,coefficient) in enumerate(coefficients)
        series += coefficient/(x+j)
    end
    -adjustment+log(2.5066282746310005*series/x)
end
replace_small(value) = abs(value)<1e-300 ? 1e-300 : value
function beta_fraction(a,b,x)
    c = 1.0
    d = 1/replace_small(1-(a+b)*x/(a+1))
    h = d
    for m in 1:1000
        q = m*(b-m)*x/((a-1+2m)*(a+2m))
        d = 1/replace_small(1+q*d)
        c = replace_small(1+q/c)
        h *= d*c
        q = -(a+m)*(a+b+m)*x/((a+2m)*(a+1+2m))
        d = 1/replace_small(1+q*d)
        c = replace_small(1+q/c)
        delta = d*c
        h *= delta
        abs(delta-1)<1e-15 && break
    end
    h
end
function incomplete_beta(x,a,b)
    x<=0 && return 0.0
    x>=1 && return 1.0
    factor = exp(log_gamma(a+b)-log_gamma(a)-log_gamma(b)+a*log(x)+b*log(1-x))
    x<(a+1)/(a+b+2) ? factor*beta_fraction(a,b,x)/a : 1-factor*beta_fraction(b,a,1-x)/b
end
function upper_gamma(a,x)
    x<=0 && return 1.0
    factor = exp(-x+a*log(x)-log_gamma(a))
    if x<a+1
        term,e = 1/a,a
        series = term
        for _ in 1:1000
            e += 1
            term *= x/e
            series += term
            abs(term)<abs(series)*1e-15 && break
        end
        return 1-series*factor
    end
    beta = x+1-a
    c,d = 1/1e-300,1/beta
    h = d
    for i in 1:1000
        q = -i*(i-a)
        beta += 2
        d = 1/replace_small(q*d+beta)
        c = replace_small(beta+q/c)
        delta = d*c
        h *= delta
        abs(delta-1)<1e-15 && break
    end
    factor*h
end
t_pvalue(t,df) = incomplete_beta(df/(df+t*t),df/2,0.5)
f_pvalue(f,a,b) = incomplete_beta(b/(b+a*f),b/2,a/2)
chi_pvalue(x,df) = upper_gamma(df/2,x/2)
function t_quantile(confidence,df)
    lo,hi = 0.0,1000.0
    for _ in 1:100
        mid = (lo+hi)/2
        if t_pvalue(mid,df)>1-confidence
            lo = mid
        else
            hi = mid
        end
    end
    (lo+hi)/2
end
significance(p) = isnothing(p) ? "" : p<0.001 ? "***" : p<0.01 ? "**" : p<0.05 ? "*" : p<0.1 ? "." : ""
function four(value)
    isnothing(value) && return "NA"
    text = @sprintf("%.4f",value)
    text=="-0.0000" ? "0.0000" : text
end
probability(value) = isnothing(value) ? "NA" : value<0.0001 ? "<0.0001" : four(value)
