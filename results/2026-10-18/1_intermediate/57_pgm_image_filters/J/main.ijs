LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    r =. ''
    for_i. i.#y do.
        if. i do. r =. r,x end.
        r =. r,i{::y
    end.
    r
)
words =: 3 : 0
    r =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. num v end.
        r =. r,<,v
    end.
    ' 'join r
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
    emit 'error: ',y
    throw.
)
check =: 3 : 'if. -.y do. fail ''bad value'' end.'
parse =: 3 : '0". ''_'' (I.y=''-'')}y'
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
integer =: 3 : 0
    t =. y
    if. '0'eq t do. 1 return. end.
    if. '-'={.t do. t =. }.t end.
    if. (0=#t)+.(7<#t) do. 0 return. end.
    (digits t)*.'0'~:{.t
)
nameword =: 3 : '(0<#y)*.(8>:#y)*.*./y e.''abcdefghijklmnopqrstuvwxyz'''
summary =: 3 : 0
    'w h m p' =. y
    (num w),'x',(num h),' maxval ',(num m),' checksum ',num +/(>:i.#p)*p
)
Image =: 0$a:
Undo =: 0$a:
Redo =: 0$a:
Names =: 0$a:
Slots =: 0$a:
Output =: 0$a:
Patterns =: ;: 'iiii z z i ii i ii i i z z i iiii ii ii iii ii z z z iiiiiiiiii z z z z z z z iiiii iiiii iiii iii z z i i z iiii z z n n n nii n nii z z z z'
Commands =: ;: 'NEW OUTPUT INVERT BRIGHTNESS CONTRAST THRESHOLD LEVELS POSTERIZE MAXVAL FLIPH FLIPV ROTATE CROP PAD SCALE SHIFT TILE BLUR GAUSS SHARPEN CONVOLVE SOBEL MEDIAN ERODE DILATE OPEN CLOSE GRADIENT LINE RECT CIRCLE FLOOD HISTOGRAM EQUALIZE LABEL DISTANCE STATS REGION DITHER ASCIIART STORE RECALL DROP BLEND DIFF PASTE SLOTS INFO UNDO REDO'
replace =: 3 : 0
    Image =: y
    Undo =: 0$a:
    Redo =: 0$a:
)
loadPGM =: 3 : 0
    ts =. 0$a:
    for_line. y do.
        t =. >line
        t =. (t i.'#'){.t
        ts =. ts,(' 'split t)-.<''
    end.
    if. 0=#ts do. fail 'load: bad magic' end.
    if. -. 'P2'eq 0{::ts do. fail 'load: bad magic' end.
    header =. i.0
    for_i. 1 2 3 do.
        if. i>:#ts do. fail 'load: truncated header' end.
        t =. i{::ts
        if. -.digits t do. fail 'load: bad number' end.
        v =. parse t
        limit =. 64
        reason =. 'bad size'
        if. i=3 do. limit =. 255 [ reason =. 'bad maxval' end.
        if. (v<1)+.v>limit do. fail 'load: ',reason end.
        header =. header,v
    end.
    'w h m' =. header
    ps =. 4}.ts
    count =. #ps
    p =. i.0
    for_i. i.w*h do.
        if. i>:count do. fail 'load: too few pixels (',(num count),' of ',(num w*h),')' end.
        t =. i{::ps
        loc =. (num w|i),',',num <.i%w
        if. -.digits t do. fail 'load: bad pixel at ',loc end.
        v =. parse t
        if. v>m do. fail 'load: pixel out of range at ',loc end.
        p =. p,v
    end.
    if. count>w*h do. fail 'load: too many pixels (',(num count),' of ',(num w*h),')' end.
    replace w;h;m;p
    emit 'loaded ',summary Image
)
NB. Neighbor filters always read one immutable source image.
filter =: 4 : 0
    'w h m p' =. y
    result =. i.0
    for_i. i.#p do.
        xx =. w|i
        yy =. <.i%w
        q =. i.0
        for_dy. _1 0 1 do.
            for_dx. _1 0 1 do.
                a =. (w-1)<.0>.xx+dx
                b =. (h-1)<.0>.yy+dy
                q =. q,(a+w*b){p
            end.
        end.
        select. x
        case. 'BLUR' do. v =. <.(+/q)%9
        case. 'GAUSS' do. v =. <.(+/q*1 2 1 2 4 2 1 2 1)%16
        case. 'SHARPEN' do. v =. (5*4{q)-+/1 3 5 7{q
        case. 'CONVOLVE' do. v =. <.(+/Kernel*q)%Divisor
        case. 'SOBEL' do.
            gx =. (+/q* _1 0 1 _2 0 2 _1 0 1)
            gy =. (+/q* _1 _2 _1 0 0 0 1 2 1)
            v =. (|gx)+|gy
        case. 'MEDIAN' do. v =. 4{/:~q
        case. 'ERODE' do. v =. <./q
        case. 'DILATE' do. v =. >./q
        end.
        result =. result,m<.0>.v
    end.
    w;h;m;result
)
statsLine =: 3 : 0
    sorted =. /:~y
    unique =. ~.sorted
    counts =. +/"1 unique=/y
    mode =. ({.I.counts=>./counts){unique
    words 'min';({.sorted);'max';({:sorted);'mean';(<.(+/y)%#y);'median';((<.(<:#y)%2){sorted);'mode';mode
)
NB. Four- or eight-neighbor connected searches use pixel indices.
component =: 4 : 0
    'w h mask start' =. y
    queue =. ,start
    found =. ,start
    head =. 0
    while. head<#queue do.
        at =. head{queue
        head =. >:head
        xx =. w|at
        yy =. <.at%w
        for_d. x do.
            'dx dy' =. >d
            a =. xx+dx
            b =. yy+dy
            if. (a<0)+.(a>:w)+.(b<0)+.b>:h do. continue. end.
            j =. a+w*b
            if. (j{mask)*.-.j e.found do.
                found =. found,j
                queue =. queue,j
            end.
        end.
    end.
    found
)
Neighbors4 =: (<0 _1),(<_1 0),(<1 0),<0 1
Neighbors8 =: Neighbors4,(<_1 _1),(<1 _1),(<_1 1),<1 1
execute =: 3 : 0
    ts =. ' 'split y
    cmd =. 0{::ts
    args =. }.ts
    ci =. Commands i.<cmd
    if. ci=#Commands do. fail 'unknown command ',cmd end.
    pattern =. ci{::Patterns
    if. 'z'eq pattern do. pattern =. '' end.
    fill =. 0
    if. (<cmd)e.;:'RECT CIRCLE' do.
        if. (#args)=1+#pattern do.
            if. 'FILL'eq _1{::args do. fill =. 1 [ args =. }:args end.
        end.
    end.
    if. (#args)~:#pattern do. fail 'bad arguments' end.
    values =. i.0
    slot =. ''
    for_i. i.#args do.
        word =. i{::args
        if. 'n'=i{pattern do.
            if. -.nameword word do. fail 'bad arguments' end.
            slot =. word
        else.
            if. -.integer word do. fail 'bad arguments' end.
            values =. values,parse word
        end.
    end.
    if. -.(<cmd)e.;:'NEW RECALL DROP SLOTS INFO UNDO REDO' do.
        if. 0=#Image do. fail 'no image' end.
    end.
    si =. Names i.<slot
    if. (<cmd)e.;:'RECALL DROP BLEND DIFF PASTE' do.
        if. si=#Names do. fail 'no slot ',slot end.
    end.
    if. 'NEW'eq cmd do.
        'w h m v' =. values
        check (w>:1)*.(w<:64)*.(h>:1)*.(h<:64)*.(m>:1)*.(m<:255)*.(v>:0)*.v<:m
        replace w;h;m;((w*h)#v)
        emit 'created ',summary Image
        return.
    end.
    if. 'RECALL'eq cmd do.
        replace si{::Slots
        emit 'recalled ',slot,' ',summary Image
        return.
    end.
    if. 'DROP'eq cmd do.
        keep =. (i.#Names)-.si
        Names =: keep{Names
        Slots =: keep{Slots
        emit 'dropped ',slot
        return.
    end.
    if. 'SLOTS'eq cmd do.
        if. 0=#Names do. emit 'no slots' end.
        for_i. /:Names do. emit (i{::Names),' ',summary i{::Slots end.
        return.
    end.
    if. 'INFO'eq cmd do.
        text =. 'none'
        if. #Image do. text =. summary Image end.
        say 'image';text;'undo';(#Undo);'redo';(#Redo);'slots';#Names
        return.
    end.
    if. 'UNDO'eq cmd do.
        if. 0=#Undo do. fail 'nothing to undo' end.
        Redo =: Redo,<Image
        Image =: _1{::Undo
        Undo =: }:Undo
        emit 'undo ',summary Image
        return.
    end.
    if. 'REDO'eq cmd do.
        if. 0=#Redo do. fail 'nothing to redo' end.
        Undo =: Undo,<Image
        Image =: _1{::Redo
        Redo =: }:Redo
        emit 'redo ',summary Image
        return.
    end.
    'w h m p' =. Image
    n =. #p
    result =. p
    nw =. w
    nh =. h
    nm =. m
    painted =. _1
    if. 'STORE'eq cmd do.
        if. si=#Names do. Names =: Names,<slot [ Slots =: Slots,<Image
        else. Slots =: (<Image)si}Slots end.
        emit 'stored ',slot,' ',summary Image
        return.
    end.
    if. 'OUTPUT'eq cmd do.
        emit 'P2'
        say w;h
        emit num m
        for_j. i.h do. emit words <"0 ((j*w)+i.w){p end.
        return.
    end.
    if. 'ASCIIART'eq cmd do.
        shades =. '@#*+=~-:,.'
        for_j. i.h do.
            vals =. ((j*w)+i.w){p
            emit (<.(vals*10)%(m+1)){shades
        end.
        return.
    end.
    if. 'STATS'eq cmd do. emit statsLine p return. end.
    if. (<cmd)e.;:'CROP REGION' do.
        'x y cw ch' =. values
        check (x>:0)*.(y>:0)*.(cw>:1)*.(ch>:1)*.((x+cw)<:w)*.(y+ch)<:h
        cut =. i.0
        for_j. i.ch do. cut =. cut,((x+i.cw)+w*(y+j)){p end.
        if. 'REGION'eq cmd do. emit statsLine cut return. end.
        result =. cut [ nw =. cw [ nh =. ch
    elseif. 'HISTOGRAM'eq cmd do.
        bins =. <.(p*16)%(m+1)
        counts =. +/"1 (i.16)=/bins
        top =. >./counts
        for_b. i.16 do.
            us =. I.b=<.((i.>:m)*16)%(m+1)
            if. 0=#us do. continue. end.
            lo =. num {.us
            hi =. num {:us
            count =. num b{counts
            emit ((3-#lo)#' '),lo,'-',((3-#hi)#' '),hi,' ',((4-#count)#' '),count,' |',((<.(32*b{counts)%top)#'#')
        end.
        return.
    elseif. 'LABEL'eq cmd do.
        t =. {.values
        check (t>:0)*.t<:m
        mask =. p>:t
        done =. i.0
        labels =. 0$a:
        for_start. I.mask do.
            if. start e.done do. continue. end.
            cs =. Neighbors8 component w;h;mask;start
            done =. done,cs
            xs =. w|cs
            ys =. <.cs%w
            perimeter =. 0
            for_at. cs do.
                xx =. w|at
                yy =. <.at%w
                boundary =. 0
                for_d. Neighbors4 do.
                    'dx dy' =. >d
                    a =. xx+dx
                    b =. yy+dy
                    if. (a<0)+.(a>:w)+.(b<0)+.b>:h do. boundary =. 1
                    elseif. -. (a+w*b){mask do. boundary =. 1 end.
                end.
                perimeter =. perimeter+boundary
            end.
            labels =. labels,<words 'label';(>: #labels);'area';(#cs);'perimeter';perimeter;'box';(<./xs);(<./ys);(>./xs);(>./ys);'center';(<.(+/xs)%#cs);<.(+/ys)%#cs
        end.
        say 'labels';#labels
        for_line. labels do. emit >line end.
        return.
    elseif. 'INVERT'eq cmd do. result =. m-p
    elseif. 'BRIGHTNESS'eq cmd do.
        d =. {.values
        check (d>:_255)*.d<:255
        result =. m<.0>.p+d
    elseif. 'CONTRAST'eq cmd do.
        'a b' =. values
        check (a>:0)*.(a<:100)*.(b>:1)*.b<:100
        c =. <.(m+1)%2
        result =. m<.0>.c+<.((p-c)*a)%b
    elseif. 'THRESHOLD'eq cmd do.
        t =. {.values
        check (t>:0)*.t<:m
        result =. m*p>:t
    elseif. 'LEVELS'eq cmd do.
        'lo hi' =. values
        check (lo>:0)*.(lo<hi)*.hi<:m
        result =. m<.0>.<.((p-lo)*m)%(hi-lo)
    elseif. 'POSTERIZE'eq cmd do.
        l =. {.values
        check (l>:2)*.l<:m+1
        result =. <.((<.(p*l)%(m+1))*m)%(l-1)
    elseif. 'MAXVAL'eq cmd do.
        nm =. {.values
        check (nm>:1)*.nm<:255
        result =. <.((2*p*nm)+m)%(2*m)
    elseif. (<cmd)e.;:'FLIPH FLIPV ROTATE PAD SCALE SHIFT TILE' do.
        if. 'ROTATE'eq cmd do.
            angle =. {.values
            check angle e.90 180 270
            if. angle~:180 do. nw =. h [ nh =. w end.
        elseif. 'PAD'eq cmd do.
            'border v' =. values
            check (border>:1)*.(v>:0)*.v<:m
            nw =. w+2*border [ nh =. h+2*border
        elseif. 'SCALE'eq cmd do.
            'a b' =. values
            check (a>:1)*.(a<:16)*.(b>:1)*.b<:16
            nw =. <.(w*a)%b [ nh =. <.(h*a)%b
            if. (nw=0)+.nh=0 do. fail 'too small' end.
        elseif. 'SHIFT'eq cmd do.
            'dx dy v' =. values
            check (*./1000>:|dx,dy)*.(v>:0)*.v<:m
        elseif. 'TILE'eq cmd do.
            'a b' =. values
            check (a>:1)*.b>:1
            nw =. w*a [ nh =. h*b
        end.
        if. (nw>64)+.nh>64 do. fail 'too large' end.
        result =. i.0
        for_at. i.nw*nh do.
            xx =. nw|at [ yy =. <.at%nw
            a =. xx [ b =. yy
            select. cmd
            case. 'FLIPH' do. a =. (w-1)-xx
            case. 'FLIPV' do. b =. (h-1)-yy
            case. 'ROTATE' do.
                if. angle=90 do. a =. yy [ b =. (h-1)-xx
                elseif. angle=180 do. a =. (w-1)-xx [ b =. (h-1)-yy
                else. a =. (w-1)-yy [ b =. xx end.
            case. 'PAD' do. a =. xx-border [ b =. yy-border
            case. 'SCALE' do. a =. <.(((2*xx)+1)*(1{values))%(2*{.values)
                b =. <.(((2*yy)+1)*(1{values))%(2*{.values)
            case. 'SHIFT' do. a =. xx-dx [ b =. yy-dy
            case. 'TILE' do. a =. w|xx [ b =. h|yy
            end.
            if. (a<0)+.(a>:w)+.(b<0)+.b>:h do. value =. v
            else. value =. (a+w*b){p end.
            result =. result,value
        end.
    elseif. (<cmd)e.;:'BLUR GAUSS SHARPEN CONVOLVE SOBEL MEDIAN ERODE DILATE OPEN CLOSE GRADIENT' do.
        if. 'CONVOLVE'eq cmd do.
            Kernel =: 9{.values [ Divisor =: 9{values
            check (*./16>:|Kernel)*.(Divisor>:1)*.Divisor<:256
        end.
        if. 'OPEN'eq cmd do. result =. 3{::'DILATE'filter 'ERODE'filter Image
        elseif. 'CLOSE'eq cmd do. result =. 3{::'ERODE'filter 'DILATE'filter Image
        elseif. 'GRADIENT'eq cmd do. result =. (3{::'DILATE'filter Image)-3{::'ERODE'filter Image
        else. result =. 3{::cmd filter Image end.
    elseif. (<cmd)e.;:'LINE RECT CIRCLE FLOOD' do.
        points =. 0 2$0
        if. 'LINE'eq cmd do.
            'x y x1 y1 v' =. values
            check (*./1000>:|4{.values)*.(v>:0)*.v<:m
            dx =. |x1-x [ dy =. -|y1-y
            sx =. _1+2*x<x1 [ sy =. _1+2*y<y1
            e =. dx+dy
            while. 1 do.
                points =. points,x,y
                if. (x=x1)*.y=y1 do. break. end.
                e2 =. 2*e
                if. e2>:dy do. e =. e+dy [ x =. x+sx end.
                if. e2<:dx do. e =. e+dx [ y =. y+sy end.
            end.
        elseif. 'RECT'eq cmd do.
            'x y rw rh v' =. values
            check (*./1000>:|x,y)*.(rw>:1)*.(rw<:1000)*.(rh>:1)*.(rh<:1000)*.(v>:0)*.v<:m
            for_yy. i.h do. for_xx. i.w do.
                if. (xx>:x)*.(xx<x+rw)*.(yy>:y)*.yy<y+rh do.
                    if. fill+.(xx=x)+.(xx=x+rw-1)+.(yy=y)+.yy=y+rh-1 do. points =. points,xx,yy end.
                end.
            end. end.
        elseif. 'CIRCLE'eq cmd do.
            'cx cy radius v' =. values
            check (*./1000>:|cx,cy)*.(radius>:0)*.(radius<:1000)*.(v>:0)*.v<:m
            a =. radius [ b =. 0 [ e =. 1-radius
            while. a>:b do.
                points =. points,8 2$ (cx+a),(cy+b),(cx+b),(cy+a),(cx-b),(cy+a),(cx-a),(cy+b),(cx-a),(cy-b),(cx-b),(cy-a),(cx+b),(cy-a),(cx+a),(cy-b)
                b =. >:b
                if. e<0 do. e =. e+(2*b)+1
                else.
                    a =. <:a
                    e =. e+(2*(b-a))+1
                end.
            end.
            if. fill do.
                outline =. points
                points =. 0 2$0
                for_yy. ~.1{"1 outline do.
                    xs =. 0{"1 outline#~yy=1{"1 outline
                    for_xx. (<./xs)+i.1+(>./xs)-<./xs do. points =. points,xx,yy end.
                end.
            end.
        else.
            'x y v' =. values
            check (x>:0)*.(x<w)*.(y>:0)*.(y<h)*.(v>:0)*.v<:m
            start =. x+w*y
            cs =. Neighbors4 component w;h;(p=start{p);start
            points =. (w|cs),.<.cs%w
        end.
        inside =. (0<:0{"1 points)*.(w>0{"1 points)*.(0<:1{"1 points)*.h>1{"1 points
        points =. ~.inside#points
        indexes =. (0{"1 points)+w*1{"1 points
        result =. v indexes}p
        painted =. #indexes
    elseif. 'EQUALIZE'eq cmd do.
        counts =. +/"1 (i.>:m)=/p
        cdf =. +/\counts
        cmin =. (<./p){cdf
        if. cmin~:n do. result =. <.((2*((p{cdf)-cmin)*m)+(n-cmin))%(2*(n-cmin)) end.
    elseif. 'DISTANCE'eq cmd do.
        t =. {.values
        check (t>:0)*.t<:m
        result =. n#m
        queue =. I.p<t
        result =. 0 queue}result
        head =. 0
        while. head<#queue do.
            at =. head{queue
            head =. >:head
            xx =. w|at [ yy =. <.at%w
            for_d. Neighbors4 do.
                'dx dy' =. >d
                a =. xx+dx [ b =. yy+dy
                if. (a<0)+.(a>:w)+.(b<0)+.b>:h do. continue. end.
                j =. a+w*b
                value =. >:at{result
                if. value<j{result do. result =. value j}result [ queue =. queue,j end.
            end.
        end.
    elseif. 'DITHER'eq cmd do.
        working =. p
        result =. n#0
        for_at. i.n do.
            xx =. w|at [ yy =. <.at%w
            old =. at{working
            value =. m*m<:2*old
            result =. value at}result
            error =. old-value
            for_d. (<1 0 7),(<_1 1 3),(<0 1 5),<1 1 1 do.
                'dx dy weight' =. >d
                a =. xx+dx [ b =. yy+dy
                if. (a<0)+.(a>:w)+.(b<0)+.b>:h do. continue. end.
                j =. a+w*b
                working =. ((j{working)+<.(error*weight)%16)j}working
            end.
        end.
    elseif. (<cmd)e.;:'BLEND DIFF PASTE' do.
        'sw sh sm sp' =. si{::Slots
        if. 'BLEND'eq cmd do.
            'a b' =. values
            check (a>:0)*.(a<:b)*.(b>:1)*.b<:100
        elseif. 'PASTE'eq cmd do. check *./1000>:|values end.
        if. -.'PASTE'eq cmd do.
            if. (w~:sw)+.h~:sh do. fail 'size mismatch' end.
        end.
        if. m~:sm do. fail 'maxval mismatch' end.
        if. 'BLEND'eq cmd do. result =. <.((p*(b-a))+sp*a)%b
        elseif. 'DIFF'eq cmd do. result =. |p-sp
        else.
            'x y' =. values
            painted =. 0
            for_at. i.#sp do.
                xx =. x+sw|at [ yy =. y+<.at%sw
                if. (xx>:0)*.(xx<w)*.(yy>:0)*.yy<h do.
                    result =. (at{sp)(xx+w*yy)}result
                    painted =. >:painted
                end.
            end.
        end.
    end.
    Undo =: Undo,<Image
    Redo =: 0$a:
    Image =: nw;nh;nm;result
    text =. 'ok ',summary Image
    if. painted>:0 do. text =. text,' painted ',num painted end.
    emit text
)
main =: 3 : 0
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    n =. parse 0{::lines
    index =. 1
    for_i. i.n do.
        line =. index{::lines
        index =. >:index
        ts =. ' 'split line
        if. 'LOAD'eq 0{::ts do.
            count =. parse 1{::ts
            data =. (index+i.count){lines
            index =. index+count
            try. loadPGM data catcht. end.
        else.
            try. execute line catcht. end.
        end.
        1!:2&2 (LF join Output),LF
        Output =: 0$a:
    end.
)
main''
