LF =: 10{a.
Digits =: '0123456789'
NONE =: _1
isnone =: 3 : '_1-:y'
div =: 4 : '<.(x:x) % x:y'
num =: 3 : '10x #. Digits i.y'
digits =: 3 : '(0<#y)*.*./y e.Digits'
width =: 4 : '((#y)>:0{x)*.((#y)<:1{x)*.digits y'
number =: 3 : 0
    n =. |y
    s =. ''
    while. n>0 do.
        s =. ((10|n){Digits),s
        n =. n div 10
    end.
    if. 0=#s do. s =. '0' end.
    if. y<0 do. '-',s else. s end.
)
pad =: 4 : '((0>.x-#number y)#''0''),number y'
split =: 4 : 0
    r =. 0$a:
    while. 1 do.
        i =. y i.x
        r =. r,<i{.y
        if. i=#y do. r return. end.
        y =. (i+1)}.y
    end.
)
join =: 4 : 0
    s =. ''
    for_i. i.#y do.
        if. i do. s =. s,x end.
        s =. s,i{::y
    end.
    s
)
lines =: 3 : '<;._2 (1!:1 <y)'
Sine =: 0 174 342 500 643 766 866 940 985 1000
isin =: 3 : 0
    a =. 360|y
    if. a<:90 do. (a div 10){Sine
    elseif. a<:180 do. ((180-a) div 10){Sine
    elseif. a<:270 do. -((a-180) div 10){Sine
    else. -((360-a) div 10){Sine end.
)
icos =: 3 : 'isin y+90'
knots =: 4 : 0
    if. x-:'MPS' do. (500+1944*y) div 1000 else. y end.
)
inhg =: 3 : '(500+2953*y) div 1000'
hpa =: 3 : '(50000+33864*y) div 100000'
monthdays =: 3 : 0
    'yr mo' =. y
    if. mo=2 do. 28+((0=4|yr)*.0~:100|yr)+.0=400|yr
    else. 30+mo e.1 3 5 7 8 10 12 end.
)
calendar =: 3 : 0
    'yr mo' =. y
    ny =. yr+mo=12
    nm =. 1+12|mo
    yr,mo,(monthdays y),ny,nm,monthdays ny,nm
)
dayminutes =: 3 : 0
    'd h m' =. y
    m+60*(h+24*(d-1))
)
dayof =: 3 : '1+y div 1440'
hourmark =: 3 : 'y-60|y'
forecasttime =: 3 : 0
    'd h m issue' =. y
    n =. (2+3*(d<issue)){Calendar
    if. (d<1)+.d>n do. NONE return. end.
    (1440*(2{Calendar)*(d<issue))+dayminutes d,h,m
)
stamp =: 3 : 0
    'yr mo n ny nm nn' =. Calendar
    t =. y
    if. t>:1440*n do. yr =. ny
    mo =. nm
    t =. t-1440*n end.
    (4 pad yr),'-',(2 pad mo),'-',(2 pad 1+t div 1440),'T',(2 pad (1440|t) div 60),':',(2 pad 60|t),'Z'
)
miles =: 3 : 0
    'kind qual meters whole numerator denominator joined' =. y
    if. kind-:'MILES' do.
        if. denominator=0 do. whole,1 else. (numerator+whole*denominator),denominator end.
    else. (1000*meters),1609344 end.
)
meter_value =: 3 : 0
    if. 'MILES'-:0{::y do.
        'p q' =. miles y
        (1609344*p) div 1000*q
    else. 2{::y end.
)
fraction =: 3 : 0
    'p q' =. y
    if. q=0 do. 'undefined' return. end.
    g =. (|p)+.q
    (number p div g),'/',number q div g
)
fraction_less =: 4 : '((0{x)*1{y) < (0{y)*1{x'
