log10 =: 3 : '(^.y)%2.302585092994046'
median =: 3 : 0
    ordered =. /:~y
    middle =. (#ordered)intdiv 2
    if. 2|#ordered do.
        middle{ordered
    else.
        (((middle-1){ordered)+middle{ordered)%2.0
    end.
)
per_pick_magnitude =: 3 : 0
    'amplitude duration clipped radius local_coefficients duration_coefficients' =. y
    'a_local b_local c_local' =. 0.0+local_coefficients
    'a_duration b_duration c_duration' =. 0.0+duration_coefficients
    md =. (a_duration+b_duration*log10 duration%100.0)+c_duration*radius
    ml =. 0.0
    if. -.clipped do.
        ml =. (((log10 0.0+amplitude)+a_local*log10 radius%100.0)+b_local*(radius-100.0))+c_local
    end.
    (<radius,ml,md),<-.clipped
)
class_number =: 3 : 0
    hundredths =. x:<.0.5+100.0*|y
    if. y<0.0 do.
        hundredths =. -hundredths
    end.
    (hundredths+5)intdiv 10
)
class_text =: 3 : 0
    sign =. (y<0)#'-'
    absolute =. |y
    sign,(":absolute intdiv 10),'.',":10|absolute
)
frequency_statistics =: 3 : 0
    classes =. class_number&>y
    low =. <./classes
    high =. >./classes
    counts =. (1+high-low)$0
    for_value. classes do.
        index =. value-low
        counts =. (1+index{counts)index}counts
    end.
    completeness =. low+counts i.>./counts
    above =. classes#~classes>:completeness
    mc =. completeness%10.0
    mean =. (+/above)%10.0*#above
    b =. 0.4342944819032518%mean-(mc-0.05)
    sigma =. b%%:#above
    a =. (log10 0.0+#above)+b*mc
    (<counts),(<low),(<high),(<completeness),(<#above),(<b),(<sigma),<a
)
