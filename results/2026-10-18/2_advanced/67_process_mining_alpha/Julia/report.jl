function fraction(value)
    value = value//1
    a,b = abs(numerator(value)),denominator(value)
    scaled = 10000a÷b
    sign = value<0 ? "-" : ""
    decimal_sign = scaled==0 ? "" : sign
    string(sign,a,"/",b,"=",decimal_sign,scaled÷10000,".",lpad(scaled%10000,4,'0'))
end
function percentage(a,b)
    scaled = 10000a÷b
    string(scaled÷100,".",lpad(scaled%100,2,'0'),"%")
end
name_list(values) = isempty(values) ? "-" : join(values,",")
function write_outputs(outputs)
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
