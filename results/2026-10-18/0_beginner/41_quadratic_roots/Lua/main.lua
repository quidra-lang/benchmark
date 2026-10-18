local function half_up(x)
    local result = math.floor(math.abs(x)*10000+0.5)/10000
    return x < 0 and -result or result
end
for _, coefficients in ipairs({{1,-3,-10},{-2,5,4},{3,1,-2},{4,-12,9},{1,2,5},{-2,3,-4}}) do
    local a,b,c = table.unpack(coefficients)
    local discriminant = b*b-4*a*c
    io.write(string.format("%d %d %d: ",a,b,c))
    if discriminant > 0 then
        local first,second = (-b+math.sqrt(discriminant))/(2*a),(-b-math.sqrt(discriminant))/(2*a)
        io.write(string.format("x1 = %.4f, x2 = %.4f\n",half_up(math.max(first,second)),half_up(math.min(first,second))))
    elseif discriminant == 0 then io.write(string.format("x = %.4f\n",half_up(-b/(2*a))))
    else
        local real,imaginary = -b/(2*a),math.sqrt(-discriminant)/(2*math.abs(a))
        io.write(string.format("x = %.4f + %.4fi, %.4f - %.4fi\n",half_up(real),half_up(imaginary),half_up(real),half_up(imaginary)))
    end
end
