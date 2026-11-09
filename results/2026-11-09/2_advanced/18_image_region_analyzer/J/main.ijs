ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
Symbols =: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
Orientations =: ;:'none horizontal vertical falling rising'
Directions4 =: 4 2$1 0 0 _1 _1 0 0 1
Directions8 =: 8 2$1 0 1 _1 0 _1 _1 _1 _1 0 _1 1 0 1 1 1
CSVHeader =: 'image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
signed_num =: 3 : 0
    if. '-'={.y do. -num }.y else. num y end.
)
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
text_line =: 3 : 0
    parts =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    ' ' join parts
)
numbers =: 3 : ''' '' join number&.><"0 y'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
normalize =: 3 : 0
    if. 1=#,y do. y =. y,1 end.
    'numerator denominator' =. y
    if. denominator<0 do. numerator =. -numerator
        denominator =. -denominator end.
    divisor =. (|numerator)+.denominator
    (numerator div divisor),denominator div divisor
)
parse_rational =: 3 : 0
    parts =. '/' split y
    if. 1=#parts do. (signed_num 0{::parts),1
    else. normalize num&>parts end.
)
compare_rational =: 4 : '*((0{x)*1{y)-(0{y)*1{x'
feature_put =: 4 : 0
    'name value' =. x
    ((<name),<normalize value)put_key y
)
feature =: 4 : 'y get_key 2{::x'
integer_feature =: 4 : '{.x feature y'
mean_text =: 4 : 0
    if. y=0 do. '-' else. (x,y)decimal 2 end.
)
load SourceDirectory,'pgm_reader.ijs'
load SourceDirectory,'threshold.ijs'
load SourceDirectory,'morphology.ijs'
load SourceDirectory,'labeling.ijs'
load SourceDirectory,'report.ijs'
read_parameters =: 3 : 0
    Elements =: Settings =: empty_table ''
    for_box. read_lines 'input/params.txt' do.
        fields =. ' ' split >box
        keyword =. 0{::fields
        if. keyword-:'otsu_top' do. OtsuTop =: num 1{::fields
        elseif. keyword-:'sweep' do. SweepStep =: num 1{::fields
        elseif. keyword-:'isotropy' do. Isotropy =: parse_rational 1{::fields
        elseif. keyword-:'bay_min' do. BayMin =: num 1{::fields
        elseif. keyword-:'element' do.
            ox =. num 4{::fields
            oy =. num 5{::fields
            offsets =. 0 2$0
            for_row. i.(#fields)-6 do.
                text =. (row+6){::fields
                for_column. I.text='#' do. offsets =. offsets,(column-ox),row-oy end.
            end.
            Elements =: ((1{fields),<offsets)put_key Elements
        else.
            setting =. (<num 2{::fields),(3{fields),(4{fields),<5}.fields
            Settings =: ((1{fields),<setting)put_key Settings
        end.
    end.
    i.0
)
parse_conditions =: 3 : 0
    conditions =. 0$a:
    for_start. 3*i.(#y)div 3 do.
        feature =. start{::y
        comparison =. (start+1){::y
        spelling =. (start+2){::y
        value =. spelling
        if. -.feature-:'orientation' do. value =. parse_rational spelling end.
        conditions =. conditions,<(<feature),(<comparison),(<spelling),<value
    end.
    conditions
)
read_rules =: 3 : 0
    Filters =: Classes =: Flags =: ClassNames =: 0$a:
    for_box. read_lines 'input/rules.txt' do.
        fields =. ' ' split >box
        kind =. 0{::fields
        if. kind-:'filter' do. Filters =: Filters,parse_conditions }.fields
        else.
            name =. 1{::fields
            rule =. (<name),<parse_conditions 2}.fields
            if. kind-:'class' do.
                Classes =: Classes,<rule
                if. -.(<name)e.ClassNames do. ClassNames =: ClassNames,<name end.
            else. Flags =: Flags,<rule end.
        end.
    end.
    ClassNames =: ClassNames,<'other'
    i.0
)
group_pixels =: 3 : 0
    'labels count provisional' =. y
    groups =. (count+1)$<0 2$0
    'height width' =. $labels
    for_py. i.height do.
        for_px. i.width do.
            label =. (<py,px){labels
            groups =. (<(label{::groups),px,py) label}groups
        end.
    end.
    groups
)
enclosed_components =: 4 : 0
    'height width' =. $x
    components =. (-.x)label_components y
    groups =. }.group_pixels components
    enclosed =. 0$a:
    for_group. groups do.
        pixels =. >group
        xs =. 0{"1 pixels
        ys =. 1{"1 pixels
        border =. +./(xs=0)+.(ys=0)+.(xs=width-1)+.ys=height-1
        if. -.border do. enclosed =. enclosed,<pixels end.
    end.
    enclosed
)
binarize =: 3 : 0
    if. Polarity-:'bright' do. ImagePixels>y else. ImagePixels<:y end.
)
label_at =: 3 : 0
    'px py' =. y
    if. (px<0)+.(py<0)+.(px>:Width)+.py>:Height do. _1
    else. (<py,px){Labels end.
)
cross =: 4 : 0
    'a b' =. x
    'ax ay' =. a
    'bx by' =. b
    'px py' =. y
    ((bx-ax)*py-ay)-(by-ay)*px-ax
)
squared_distance =: 4 : '+/*:x-y'
half_hull =: 3 : 0
    chain =. 0 2$0
    for_point. y do.
        while. (#chain)>:2 do.
            if. 0<((<_2{chain),<{:chain)cross point do. break. end.
            chain =. }:chain
        end.
        chain =. chain,point
    end.
    chain
)
convex_hull =: 3 : 0
    points =. 0 2$0
    for_point. y do.
        for_offset. 4 2$0 0 1 0 0 1 1 1 do. points =. points,point+offset end.
    end.
    points =. /:~~.points
    (}:half_hull points),}:half_hull |.points
)
contains_center =: 4 : 0
    center =. 1+2*y
    for_index. i.#x do.
        a =. 2*index{x
        b =. 2*((#x)|index+1){x
        if. 0>((<a),<b)cross center do. 0 return. end.
    end.
    1
)
new_region =: 4 : 0
    (<x),(<y),(<empty_table ''),(<0$0),(<(Height,Width)$0),(<0),(<0),(<0),(<0$0),(<0),(<_1),(<'other'),(<0$a:),(<0),(<0),<'none'
)
chain_code =: 3 : 0
    number =. 0{::y
    pixels =. 1{::y
    first =. current =. 0{pixels
    directions =. Directions4
    if. Connectivity=8 do. directions =. Directions8 end.
    count =. #directions
    heading =. count-1
    codes =. 0$0
    second =. first
    while. 1 do.
        if. Connectivity=4 do. start =. 4|heading+3
        elseif. 0=2|heading do. start =. 8|heading+7
        else. start =. 8|heading+6 end.
        chosen =. _1
        for_offset. i.count do.
            direction =. count|start+offset
            if. number=label_at current+direction{directions do. chosen =. direction break. end.
        end.
        if. chosen=_1 do. 0$0 return. end.
        previous =. current
        current =. current+chosen{directions
        codes =. codes,chosen
        heading =. chosen
        if. (#codes)=1 do. second =. current
        elseif. (current-:second)*.previous-:first do. }:codes return. end.
    end.
)
store_many =: 4 : 0
    'names values' =. y
    for_index. i.#names do. x =. ((index{names),<index{values)feature_put x end.
    x
)
measure_region =: 3 : 0
    region =. y
    number =. 0{::region
    pixels =. 1{::region
    area =. #pixels
    xs =. 0{"1 pixels
    ys =. 1{"1 pixels
    'x0 x1' =. (<./xs),>./xs
    'y0 y1' =. (<./ys),>./ys
    values =. 0$0
    surrounding =. (Height,Width)$0
    perimeter =. runs =. 0
    neighboroffsets =. Directions4
    if. Complement=8 do. neighboroffsets =. Directions8 end.
    for_point. pixels do.
        'px py' =. point
        values =. values,(<py,px){ImagePixels
        for_offset. Directions8 do.
            other =. point+offset
            if. 0=label_at other do. surrounding =. 1 (<|.other)}surrounding end.
        end.
        boundary =. 0
        for_offset. neighboroffsets do.
            if. number~:label_at point+offset do. boundary =. 1 break. end.
        end.
        perimeter =. perimeter+boundary
        runs =. runs+number~:label_at point-1 0
    end.
    si =. +/values
    sii =. +/*:values
    border =. (x0=0)+.(y0=0)+.(x1=Width-1)+.y1=Height-1
    features =. (empty_table '')store_many (<;:'area x0 y0 x1 y1 width height border min max perimeter runs'),<area,x0,y0,x1,y1,(1+x1-x0),(1+y1-y0),border,(<./values),(>./values),perimeter,runs
    features =. ('mean';si,area)feature_put features
    features =. ('variance';((area*sii)-si*si),area*area)feature_put features
    nys =. +/,surrounding
    contrast =. 0 1
    if. nys do. sy =. +/(,ImagePixels)#~,surrounding
        contrast =. ((si*nys)-sy*area),area*nys end.
    features =. ('contrast';contrast)feature_put features
    codes =. chain_code region
    straight =. #codes
    if. Connectivity=8 do. straight =. +/0=2|codes end.
    diagonal =. (#codes)-straight
    turns =. +/codes~:_1|.codes
    features =. features store_many (<;:'chain straight diagonal turns'),<(#codes),straight,diagonal,turns
    length =. (5*straight)+7*diagonal
    features =. ('compactness';(length*length),25*area)feature_put features
    owned =. ownedarea =. 0
    for_hole. Holes do.
        hole =. >hole
        if. number=1{::hole do. owned =. owned+1
            ownedarea =. ownedarea+#2{::hole end.
    end.
    features =. features store_many (<;:'holes hole_area euler depth'),<owned,ownedarea,(1-owned),7{::region
    sx =. +/xs
    sy =. +/ys
    m20 =. (area*+/*:xs)-sx*sx
    m02 =. (area*+/*:ys)-sy*sy
    m11 =. (area*+/xs*ys)-sx*sy
    features =. ('cx';sx,area)feature_put features
    features =. ('cy';sy,area)feature_put features
    features =. ('var_x';m20,area*area)feature_put features
    features =. ('var_y';m02,area*area)feature_put features
    features =. ('cov_xy';m11,area*area)feature_put features
    features =. ('hu1';(m20+m02),area*area*area)feature_put features
    anisotropy =. 0 1
    if. 0<m20+m02 do. anisotropy =. ((|m20-m02)+2*|m11),m20+m02 end.
    features =. ('anisotropy';anisotropy)feature_put features
    orientation =. 'none'
    if. 0<anisotropy compare_rational Isotropy do.
        u =. m20-m02
        v =. 2*m11
        if. (|v)>:|u do.
            if. v>0 do. orientation =. 'falling' else. orientation =. 'rising' end.
        elseif. u>0 do. orientation =. 'horizontal'
        else. orientation =. 'vertical' end.
    end.
    features =. ('extent';area,((1+x1-x0)*1+y1-y0))feature_put features
    lr =. tb =. 0
    for_point. pixels do.
        'px py' =. point
        lr =. lr+number=label_at (x0+x1-px),py
        tb =. tb+number=label_at px,y0+y1-py
    end.
    features =. ('mirror_lr';lr,area)feature_put features
    features =. ('mirror_tb';tb,area)feature_put features
    hull =. convex_hull pixels
    doubled =. feret =. 0
    width2 =. 0 1
    for_index. i.#hull do.
        a =. index{hull
        b =. ((#hull)|index+1){hull
        'ax ay' =. a
        'bx by' =. b
        doubled =. doubled+(ax*by)-bx*ay
        reach =. 0
        for_point. hull do.
            reach =. reach>.|((<a),<b)cross point
            feret =. feret>.a squared_distance point
        end.
        trial =. (reach*reach),a squared_distance b
        if. (index=0)+.0>trial compare_rational width2 do. width2 =. trial end.
    end.
    doubled =. |doubled
    features =. ('solidity';(2*area),doubled)feature_put features
    features =. ('feret2';feret)feature_put features
    features =. ('width2';width2)feature_put features
    features =. ('elongation';(feret*1{width2),0{width2)feature_put features
    concavity =. ((1+y1-y0),1+x1-x0)$0
    for_py. y0+i.1+y1-y0 do.
        for_px. x0+i.1+x1-x0 do.
            if. (0=label_at px,py)*.0=(<py,px){HoleOf do.
                if. hull contains_center px,py do. concavity =. 1 (<(py-y0),px-x0)}concavity end.
            end.
        end.
    end.
    bays =. concavity label_components Complement
    sizes =. #&>}.group_pixels bays
    features =. ('bays';+/sizes>:BayMin)feature_put features
    features =. ('bay_area';+/sizes)feature_put features
    regionmask =. (Height,Width)$0
    for_point. pixels do. regionmask =. 1 (<|.point)}regionmask end.
    skeleton =. thin regionmask
    endpoints =. branches =. 0
    for_point. pixels do.
        if. skeleton occupied point do.
            crossing =. skeleton crossing_number point
            endpoints =. endpoints+crossing=1
            branches =. branches+crossing>:3
        end.
    end.
    features =. features store_many (<;:'skeleton endpoints branches'),<(+/,skeleton),endpoints,branches
    region =. (<features)2}region
    region =. (<codes)3}region
    region =. (<skeleton)4}region
    region =. (<doubled)5}region
    (<orientation)15}region
)
condition_holds =: 4 : 0
    'name comparison spelling value' =. y
    if. name-:'orientation' do. order =. -.value-:15{::x
    else. order =. (x feature name)compare_rational value end.
    if. comparison-:'<' do. order<0
    elseif. comparison-:'<=' do. order<:0
    elseif. comparison-:'>' do. order>0
    elseif. comparison-:'>=' do. order>:0
    elseif. comparison-:'=' do. order=0
    else. order~:0 end.
)
rule_matches =: 4 : 0
    for_condition. 1{::y do.
        if. -.x condition_holds >condition do. 0 return. end.
    end.
    1
)
apply_rules =: 3 : 0
    region =. y
    for_index. i.#Filters do.
        if. -.region condition_holds index{::Filters do. (<index)10}region return. end.
    end.
    region =. (<1)9}region
    for_rule. Classes do.
        if. region rule_matches >rule do. region =. (0{>rule)11}region break. end.
    end.
    flags =. 0$a:
    for_rule. Flags do.
        if. region rule_matches >rule do. flags =. flags,0{>rule end.
    end.
    (<flags)12}region
)
process_image =: 3 : 0
    'ImageName Width Height Maxval ImagePixels' =: y
    'Connectivity Threshold Polarity Operations' =: ImageName get_key Settings
    Complement =: 12-Connectivity
    Histogram =: histogram y
    OtsuResult =: otsu Histogram
    'IsodataCutoff IsodataIterations' =: isodata Histogram
    Method =: 'fixed'
    if. Threshold-:'otsu' do. Cutoff =: 0{::OtsuResult
        Method =: 'otsu'
    elseif. Threshold-:'isodata' do. Cutoff =: IsodataCutoff
        Method =: 'isodata'
    else. Cutoff =: num Threshold end.
    Initial =: Final =: binarize Cutoff
    MorphCounts =: 0$0
    for_operation. Operations do.
        operation =. >operation
        if. operation-:'fill' do.
            for_pixels. Final enclosed_components Complement do.
                for_point. >pixels do. Final =: 1 (<|.point)}Final end.
            end.
        else.
            'kind name' =. ':' split operation
            offsets =. name get_key Elements
            if. kind-:'erode' do. Final =: Final erode offsets
            elseif. kind-:'dilate' do. Final =: Final dilate offsets
            elseif. kind-:'open' do. Final =: Final opening offsets
            else. Final =: Final closing offsets end.
        end.
        MorphCounts =: MorphCounts,+/,Final
    end.
    SweepResults =: 0 3$0
    for_threshold. SweepStep*1+i.(Maxval-1)div SweepStep do.
        mask =. binarize threshold
        result =. mask label_components Connectivity
        SweepResults =: SweepResults,threshold,(+/,mask),1{::result
    end.
    result =. Final label_components Connectivity
    'Labels RegionCount ProvisionalCount' =: result
    FourComponents =: 1{::Final label_components 4
    EightComponents =: 1{::Final label_components 8
    BitQuad =: Final bit_quad_euler Connectivity
    groups =. group_pixels result
    CurrentRegions =: 0$a:
    for_region. 1+i.RegionCount do. CurrentRegions =: CurrentRegions,<region new_region region{::groups end.
    Holes =: 0$a:
    HoleOf =: (Height,Width)$0
    for_pixels. Final enclosed_components Complement do.
        pixels =. >pixels
        number =. 1+#Holes
        owner =. label_at (0{pixels)-0 1
        Holes =: Holes,<(<number),(<owner),<pixels
        for_point. pixels do. HoleOf =: number (<|.point)}HoleOf end.
    end.
    for_index. i.RegionCount do.
        region =. index{::CurrentRegions
        'px py' =. 0{1{::region
        if. py>:1 do.
            hole =. (<(py-1),px){HoleOf
            if. hole>0 do.
                parentnumber =. 1{::(hole-1){::Holes
                parent =. (parentnumber-1){::CurrentRegions
                region =. (<parentnumber)6}region
                region =. (<1+7{::parent)7}region
                parent =. (<(8{::parent),index+1)8}parent
                CurrentRegions =: (<parent)(parentnumber-1)}CurrentRegions
            end.
        end.
        CurrentRegions =: (<apply_rules measure_region region)index}CurrentRegions
    end.
    for_index. i.RegionCount do.
        region =. index{::CurrentRegions
        if. -.9{::region do. continue. end.
        for_otherindex. i.RegionCount do.
            other =. otherindex{::CurrentRegions
            if. (index=otherindex)+.-.9{::other do. continue. end.
            dx =. ((region integer_feature 'x0')+region integer_feature 'x1')-((other integer_feature 'x0')+other integer_feature 'x1')
            dy =. ((region integer_feature 'y0')+region integer_feature 'y1')-((other integer_feature 'y0')+other integer_feature 'y1')
            distance =. (dx*dx)+dy*dy
            if. (0=13{::region)+.distance<14{::region do.
                region =. (<otherindex+1)13}region
                region =. (<distance)14}region
            end.
        end.
        CurrentRegions =: (<region)index}CurrentRegions
    end.
    i.0
)
kept_regions =: 3 : 'CurrentRegions#~(9&{::)&>CurrentRegions'
threshold_lines =: 3 : 0
    'counts belowcounts belowsums total count minimum maximum median mode levels binwidth bins' =. Histogram
    lines =. <text_line 'image';ImageName;'size';Width;Height;'maxval';Maxval
    lines =. lines,<text_line 'histogram pixels';count;'min';minimum;'max';maximum;'mean';(total mean_text count);'median';median;'mode';mode;'levels';levels
    lines =. lines,<text_line 'bins';binwidth;numbers bins
    'otsucutoff upper candidates' =. OtsuResult
    lines =. lines,<text_line 'otsu threshold';otsucutoff;'upper';upper;'candidates';#candidates
    for_index. i.OtsuTop<.#candidates do.
        'cutoff below sbelow above sabove numerator denominator' =. index{candidates
        gap =. ((sabove*below)-sbelow*above),below*above
        lines =. lines,<text_line 'rank';(index+1);'t';cutoff;'below';below;'above';above;'mean_below';(sbelow mean_text below);'mean_above';(sabove mean_text above);'gap';gap decimal 2
    end.
    lines =. lines,<text_line 'isodata threshold';IsodataCutoff;'iterations';IsodataIterations
    lines =. lines,<text_line 'threshold';Cutoff;Method;Polarity;'foreground';+/,Initial
    for_index. i.#Operations do. lines =. lines,<text_line 'morph';(index{::Operations);'foreground';index{MorphCounts end.
    for_result. SweepResults do.
        'cutoff foreground regions' =. result
        lines =. lines,<text_line 'sweep';cutoff;'foreground';foreground;'regions';regions
    end.
    lines
)
map_lines =: 3 : 0
    lines =. <text_line 'morphology';ImageName;Width;Height
    for_py. i.Height do.
        text =. ''
        for_px. i.Width do.
            before =. Initial occupied px,py
            after =. Final occupied px,py
            if. after do.
                if. before do. text =. text,'#' else. text =. text,'+' end.
            elseif. before do. text =. text,'-'
            else. text =. text,'.' end.
        end.
        lines =. lines,<text
    end.
    for_skeletononly. 0 1 do.
        heading =. 'labels'
        if. skeletononly do. heading =. 'skeleton' end.
        lines =. lines,<text_line heading;ImageName;Width;Height
        for_py. i.Height do.
            text =. ''
            for_px. i.Width do.
                label =. label_at px,py
                symbol =. '.'
                if. label=0 do.
                    if. 0<(<py,px){HoleOf do. symbol =. ':' end.
                else.
                    region =. (label-1){::CurrentRegions
                    if. skeletononly*.-.(4{::region)occupied px,py do. symbol =. '+'
                    elseif. 9{::region do. symbol =. (62|label){Symbols
                    else. symbol =. '#' end.
                end.
                text =. text,symbol
            end.
            lines =. lines,<text
        end.
    end.
    lines
)
csv_row =: 3 : 0
    region =. y
    flags =. '-'
    if. #12{::region do. flags =. '+' join 12{::region end.
    fields =. (<ImageName),(<number 0{::region),(11{region),<flags
    for_name. ;:'area x0 y0 x1 y1' do. fields =. fields,<number region integer_feature >name end.
    for_name. ;:'cx cy' do. fields =. fields,<(region feature >name)decimal 3 end.
    for_name. ;:'mean variance' do. fields =. fields,<(region feature >name)decimal 2 end.
    for_name. ;:'min max' do. fields =. fields,<number region integer_feature >name end.
    fields =. fields,<(region feature 'contrast')decimal 2
    for_name. ;:'border perimeter chain straight diagonal turns' do. fields =. fields,<number region integer_feature >name end.
    fields =. fields,<(region feature 'compactness')decimal 3
    for_name. ;:'runs holes hole_area euler' do. fields =. fields,<number region integer_feature >name end.
    parent =. '-'
    if. 6{::region do. parent =. number 6{::region end.
    fields =. fields,(<parent),<number 7{::region
    for_name. ;:'var_x var_y cov_xy' do. fields =. fields,<(region feature >name)decimal 3 end.
    fields =. fields,(<(region feature 'hu1')decimal 4),15{region
    for_name. ;:'anisotropy extent mirror_lr mirror_tb' do. fields =. fields,<(region feature >name)decimal 3 end.
    fields =. fields,(<hull_area_text 5{::region),(<(region feature 'solidity')decimal 3),<number region integer_feature 'feret2'
    for_name. ;:'width2 elongation' do. fields =. fields,<(region feature >name)decimal 3 end.
    for_name. ;:'bays bay_area skeleton endpoints branches' do. fields =. fields,<number region integer_feature >name end.
    neighbor =. distance =. '-'
    if. 13{::region do.
        neighbor =. number 13{::region
        distance =. ((14{::region),4)decimal 2
    end.
    codes =. '-'
    if. #3{::region do. codes =. Digits{~3{::region end.
    ',' join fields,(<neighbor),(<distance),<codes
)
tree_text =: 3 : 0
    region =. (y-1){::CurrentRegions
    text =. number y
    children =. 8{::region
    if. #children do.
        parts =. 0$a:
        for_child. children do. parts =. parts,<tree_text child end.
        text =. text,'(',(' ' join parts),')'
    end.
    text
)
orientation_line =: 3 : 0
    text =. 'orientations'
    for_orientation. Orientations do.
        orientation =. >orientation
        count =. 0
        for_region. y do. count =. count+orientation-:15{::>region end.
        text =. text,' ',text_line orientation;count
    end.
    text
)
summary_lines =: 3 : 0
    kept =. kept_regions ''
    holepixels =. 0
    for_hole. Holes do. holepixels =. holepixels+#2{::>hole end.
    lines =. <text_line 'image';ImageName
    lines =. lines,<text_line 'threshold';Cutoff;Method;Polarity;'conn';Connectivity
    lines =. lines,<text_line 'foreground';(+/,Initial);+/,Final
    lines =. lines,<text_line 'regions';RegionCount;'provisional';ProvisionalCount;'kept';(#kept);'dropped';RegionCount-#kept
    lines =. lines,<text_line 'connectivity four';FourComponents;'eight';EightComponents
    lines =. lines,<text_line 'holes';(#Holes);'hole_pixels';holepixels;'euler';(RegionCount-#Holes);'bitquad';BitQuad
    for_hole. Holes do.
        'number owner pixels' =. >hole
        xs =. 0{"1 pixels
        ys =. 1{"1 pixels
        lines =. lines,<text_line 'hole';number;'owner';owner;'area';(#pixels);'box';(<./xs);(<./ys);(>./xs);>./ys
    end.
    depth =. 0
    trees =. 0$a:
    for_region. CurrentRegions do.
        region =. >region
        depth =. depth>.7{::region
        if. 0=6{::region do. trees =. trees,<tree_text 0{::region end.
    end.
    lines =. lines,<text_line 'depth_max';depth
    tree =. 'tree'
    if. #trees do. tree =. tree,' ',' ' join trees end.
    lines =. lines,<tree
    foreground =. (,ImagePixels)#~,Final
    background =. (,ImagePixels)#~-. ,Final
    lines =. lines,<text_line 'intensity foreground';((+/foreground)mean_text #foreground);'background';(+/background)mean_text #background
    area =. 0
    largest =. smallest =. 0$a:
    for_region. kept do.
        region =. >region
        value =. region integer_feature 'area'
        area =. area+value
        if. 0=#largest do. largest =. smallest =. region
        else.
            if. value>largest integer_feature 'area' do. largest =. region end.
            if. value<smallest integer_feature 'area' do. smallest =. region end.
        end.
    end.
    if. #kept do.
        lines =. lines,<text_line 'area total';area;'mean';(area mean_text #kept);'largest';(0{::largest);(largest integer_feature 'area');'smallest';(0{::smallest);smallest integer_feature 'area'
    else. lines =. lines,<'area total 0 mean - largest - smallest -' end.
    text =. 'classes'
    for_name. ClassNames do.
        name =. >name
        count =. 0
        for_region. kept do. count =. count+name-:11{::>region end.
        text =. text,' ',text_line name;count
    end.
    lines =. lines,(<text),<orientation_line kept
    text =. 'flags'
    for_flag. Flags do.
        name =. 0{::>flag
        count =. 0
        for_region. kept do. count =. count+(<name)e.12{::>region end.
        text =. text,' ',text_line name;count
    end.
    lines,<text
)
overall_lines =: 3 : 0
    kept =. 0$a:
    for_entry. AllEntries do.
        region =. 1{::>entry
        if. 9{::region do. kept =. kept,<region end.
    end.
    lines =. (<'overall'),(<text_line 'images';ImageCount),(<text_line 'regions';(#AllEntries);'kept';(#kept);'dropped';(#AllEntries)-#kept),<text_line 'holes';TotalHoles;'euler';(#AllEntries)-TotalHoles
    for_index. i.#Filters do.
        condition =. index{::Filters
        count =. 0
        for_entry. AllEntries do. count =. count+index=10{::1{::>entry end.
        lines =. lines,<text_line 'filter';(index+1);(0{::condition);(1{::condition);(2{::condition);'dropped';count
    end.
    for_name. ClassNames do.
        name =. >name
        count =. area =. 0
        for_region. kept do.
            region =. >region
            if. name-:11{::region do. count =. count+1
                area =. area+region integer_feature 'area' end.
        end.
        lines =. lines,<text_line 'class';name;'count';count;'area';area;'mean';area mean_text count
    end.
    for_flag. Flags do.
        name =. 0{::>flag
        count =. 0
        for_region. kept do. count =. count+(<name)e.12{::>region end.
        lines =. lines,<text_line 'flag';name;'count';count
    end.
    lines =. lines,<orientation_line kept
    largest =. 0$a:
    imagename =. ''
    for_entry. AllEntries do.
        'name region' =. >entry
        if. -.9{::region do. continue. end.
        if. 0=#largest do. largest =. region
            imagename =. name
        elseif. (region integer_feature 'area')>largest integer_feature 'area' do.
            largest =. region
            imagename =. name
        end.
    end.
    if. #largest do. lines,<text_line 'largest';imagename;(0{::largest);largest integer_feature 'area'
    else. lines,<'largest -' end.
)
main =: 3 : 0
    read_parameters ''
    read_rules ''
    images =. read_images 'input/images.txt'
    ImageCount =: #images
    TotalHoles =: 0
    AllEntries =: 0$a:
    thresholds =. maps =. summary =. 0$a:
    rows =. <CSVHeader
    for_image. images do.
        process_image >image
        thresholds =. thresholds,threshold_lines ''
        maps =. maps,map_lines ''
        summary =. summary,summary_lines ''
        for_region. kept_regions '' do. rows =. rows,<csv_row >region end.
        for_region. CurrentRegions do. AllEntries =: AllEntries,<(<ImageName),region end.
        TotalHoles =: TotalHoles+#Holes
    end.
    summary =. summary,overall_lines ''
    1!:5 ::0: <'output'
    'thresholds.txt' write_lines thresholds
    'labels.txt' write_lines maps
    'regions.csv' write_lines rows
    'summary.txt' write_lines summary
    i.0
)
main ''
