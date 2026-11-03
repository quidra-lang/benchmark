const PI = 3.141592653589793
rot(angle) = complex(cos(angle),-sin(angle))
function pow2(value)
    result = 1
    while result<value
        result *= 2
    end
    result
end
function radix2(data,inverse=false)
    n = length(data)
    values = ComplexF64.(data)
    bits = trailing_zeros(n)
    for i in 1:n-1
        reversed,t = 0,i
        for _ in 1:bits
            reversed = 2reversed+t%2
            t ÷= 2
        end
        if i<reversed
            values[i+1],values[reversed+1] = values[reversed+1],values[i+1]
        end
    end
    twiddle = [rot(2PI*k/n) for k in 0:n÷2-1]
    inverse && (twiddle=conj.(twiddle))
    span = 2
    while span<=n
        stride,half = n÷span,span÷2
        for start in 0:span:n-1,j in 0:half-1
            t = twiddle[j*stride+1]*values[start+j+half+1]
            u = values[start+j+1]
            values[start+j+1] = u+t
            values[start+j+half+1] = u-t
        end
        span *= 2
    end
    inverse ? values./n : values
end
function bluestein(values)
    m = length(values)
    q = pow2(2m-1)
    chirp = [rot(PI*mod(n*n,2m)/m) for n in 0:m-1]
    a,b = zeros(ComplexF64,q),zeros(ComplexF64,q)
    for n in 0:m-1
        a[n+1] = values[n+1]*chirp[n+1]
        b[n+1] = conj(chirp[n+1])
        n>0 && (b[q-n+1]=b[n+1])
    end
    g = radix2(radix2(a).*radix2(b),true)
    chirp.*g[1:m]
end
dft(values) = ispow2(length(values)) ? radix2(values) : bluestein(values)
idft(values) = ispow2(length(values)) ? radix2(values,true) : conj.(bluestein(conj.(values)))./length(values)
function packed_real(values)
    n = length(values)
    half = n÷2
    transformed = radix2([complex(values[2j+1],values[2j+2]) for j in 0:half-1])
    result = ComplexF64[]
    for k in 0:half
        a,b = transformed[mod(k,half)+1],conj(transformed[mod(half-k,half)+1])
        even,odd = (a+b)/2,(a-b)/(2im)
        push!(result,even+rot(2PI*k/n)*odd)
    end
    result
end
function convolution(a,b)
    n = length(a)+length(b)-1
    q = pow2(n)
    af = radix2(vcat(a,zeros(q-length(a))))
    bf = radix2(vcat(b,zeros(q-length(b))))
    real.(radix2(af.*bf,true)[1:n])
end
function chirp_z(values,fs,low,high,points)
    m = length(values)
    step = (high-low)/(points-1)
    q = pow2(m+points-1)
    a,b = zeros(ComplexF64,q),zeros(ComplexF64,q)
    for n in 0:m-1
        a[n+1] = values[n+1]*rot(2PI*low*n/fs)*rot(PI*step*n*n/fs)
    end
    for offset in -(m-1):points-1
        b[mod(offset,q)+1] = conj(rot(PI*step*offset*offset/fs))
    end
    g = radix2(radix2(a).*radix2(b),true)
    [rot(PI*step*j*j/fs)*g[j+1] for j in 0:points-1]
end
