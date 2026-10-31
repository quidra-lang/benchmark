const Z95 = 1.959963984540054
function total(values)
    result = 0.0
    for value in values
        result += value
    end
    result
end
function solve_system(matrix,vector)
    a,b = copy(matrix),copy(vector)
    n = length(b)
    for k in 1:n,i in k+1:n
        factor = a[i,k]/a[k,k]
        for j in k:n
            a[i,j] -= factor*a[k,j]
        end
        b[i] -= factor*b[k]
    end
    result = zeros(n)
    for i in n:-1:1
        value = b[i]
        for j in i+1:n
            value -= a[i,j]*result[j]
        end
        result[i] = value/a[i,i]
    end
    result
end
function inverse_matrix(matrix)
    n = size(matrix,1)
    result = zeros(n,n)
    for column in 1:n
        unit = zeros(n)
        unit[column] = 1.0
        result[:,column] = solve_system(matrix,unit)
    end
    result
end
function log_gamma(a)
    coefficients = (76.18009172947146,-86.50532032941677,24.01409824083091,
                    -1.231739572450155,0.001208650973866179,-0.000005395239384953)
    xi = a+5.5
    xi -= (a+0.5)*log(xi)
    sigma,y = 1.000000000190015,a
    for coefficient in coefficients
        y += 1.0
        sigma += coefficient/y
    end
    -xi+log(2.5066282746310005*sigma/a)
end
function gamma_q(a,x)
    x==0 && return 1.0
    prefactor = exp(-x+a*log(x)-log_gamma(a))
    if x<a+1
        alpha,term = a,1/a
        sigma = term
        for _ in 1:1000
            alpha += 1
            term *= x/alpha
            sigma += term
            abs(term)<abs(sigma)*1e-15 && break
        end
        return 1-sigma*prefactor
    end
    epsilon = 1e-300
    b = x+1-a
    c,d = 1/epsilon,1/b
    h = d
    for i in 1:1000
        an = -i*(i-a)
        b += 2
        d = an*d+b
        abs(d)<epsilon && (d=epsilon)
        c = b+an/c
        abs(c)<epsilon && (c=epsilon)
        d = 1/d
        delta = d*c
        h *= delta
        abs(delta-1)<1e-15 && break
    end
    prefactor*h
end
chi_square_p(statistic,degrees) = gamma_q(degrees/2,statistic/2)
