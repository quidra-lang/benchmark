const WINDOW_ORDER = ("rectangular","hann","hamming","blackman","flattop")
const COEFFICIENTS = Dict(
    "rectangular"=>[1.0],
    "hann"=>[0.5,0.5],
    "hamming"=>[0.54,0.46],
    "blackman"=>[0.42,0.5,0.08],
    "flattop"=>[0.21557895,0.41663158,0.277263158,0.083578947,0.006947368]
)
function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
function window(name,n)
    coefficients = COEFFICIENTS[name]
    [ordered_sum((-1)^j*coefficients[j+1]*cos(2PI*j*i/n) for j in 0:length(coefficients)-1) for i in 0:n-1]
end
function figures(values,fs)
    n = length(values)
    s1,s2 = ordered_sum(values),ordered_sum(value*value for value in values)
    magnitude = abs(ordered_sum(values[i+1]*rot(PI*i/n) for i in 0:n-1))
    enbw = n*s2/(s1*s1)
    (s1=s1,s2=s2,coherent_gain=s1/n,enbw_bins=enbw,enbw_hz=enbw*fs/n,scalloping_db=-20log10(magnitude/s1))
end
