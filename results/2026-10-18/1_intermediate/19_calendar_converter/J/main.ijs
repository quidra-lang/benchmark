LF =: 10{a.
MAXDAY =: 3652059
CALENDARS =: ;:'GREGORIAN JULIAN ISO ISLAMIC HEBREW PERSIAN COPTIC ETHIOPIC FRENCH MAYAN JD FIXED'
WEEKDAYS =: ;:'Sunday Monday Tuesday Wednesday Thursday Friday Saturday'
TZ =: ;:'Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau'
HB =: ;:'Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb'
DC =: ;:'Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi'
FS =: ;:'Vertu Genie Travail Opinion Recompenses Revolution'
COMMANDS =: ;:'CONVERT ALL VALID WEEKDAY INFO LEAP MONTHS MONTHCAL NTH NEWYEAR DIFF COUNT ADD SPAN EASTER COMPUTUS PASSOVER HOLIDAYS MOLAD ROUND'
SCHEMAS =: 'adTa';'ad';'ad';'ad';'cd';'by';'cy';'cym';'cymkw';'by';'adad';'addw';'adiu';'cdd';'ye';'ye';'y';'y';'y';'adztmh'
split =: 4 : '<;._1 x,y'
floor_ratio =: 4 : '<.(x:x)%x:y'
number =: 3 : 0
    ,'0' 8!:2 y
)
padded =: 4 : 0
    s =. number y
    ((0>.x-#s)#'0'),s
)
join =: 4 : 0
    s =. ''
    for_i. i.#y do.
        if. i do. s =. s,x end.
        s =. s,i{::y
    end.
    s
)
words =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        part =. >part
        if. 2~:3!:0 part do. part =. number part end.
        parts =. parts,<part
    end.
    ' ' join parts
)
emit =: 3 : '(y,LF) 1!:2 4'
say =: 3 : 'emit words y'
weekday =: 3 : '(7|y){::WEEKDAYS'
in_range =: 3 : '(y>:1)*.y<:MAXDAY'
digits =: 4 : '((#y)e.1+i.x)*.*./y e.''0123456789'''
signed =: 4 : 0
    if. '-'={.y do. y =. }.y end.
    x digits y
)
integer =: 3 : 0
    if. '-'={.y do. -0".}.y else. 0".y end.
)
hebrew_leap =: 3 : '(19|1+7*y)<7'
months_before =: 4 : 0
    if. x=4 do. ((235*y)-234) floor_ratio 19
    else. (12+x e.6 7 8)*(y-1) end.
)
molad =: 3 : 0
    q =. 5604+765433*4 months_before y
    d =. q floor_ratio 25920
    t =. 25920|q
    r =. d
    rules =. 0$a:
    wd =. 7|d-1373427
    if. t>:19440 do.
        r =. d+1
        rules =. <'ZAKEN'
    elseif. (-.hebrew_leap y)*.(wd=2)*.t>:9924 do.
        r =. d+2
        rules =. <'GATARAD'
    elseif. (hebrew_leap y-1)*.(wd=1)*.t>:16789 do.
        r =. d+1
        rules =. <'BETUTAKPAT'
    end.
    if. (7|r-1373427)e.0 3 5 do.
        r =. r+1
        rules =. rules,<'ADU'
    end.
    d;t;(r-1373427);<rules
)
year_start =: 4 : 0
    z =. y-1
    select. x
    case. 0 do.
        s =. (365*z)+(z floor_ratio 4)
        s =. s-z floor_ratio 100
        1+s+z floor_ratio 400
    case. 1 do. (365*z)+(z floor_ratio 4)-1
    case. 2 do.
        s =. 3+0 year_start y
        s-7|s-1
    case. 3 do. 227015+(354*z)+(3+11*y) floor_ratio 30
    case. 4 do. 2{::molad y
    case. 5 do.
        a =. y-474
        b =. 474+2820|a
        226896+(1029983*a floor_ratio 2820)+(365*(b-1))+((682*b)-110) floor_ratio 2816
    case. 6 do. 103605+(365*z)+y floor_ratio 4
    case. 7 do. 2796+(365*z)+y floor_ratio 4
    case. 8 do.
        s =. (365*z)+(z floor_ratio 4)
        s =. s-z floor_ratio 100
        s =. s+z floor_ratio 400
        654415+s-z floor_ratio 4000
    end.
)
year_length =: 4 : '(x year_start y+1)-x year_start y'
leap =: 4 : 0
    select. x
    case. 0 do. (0=4|y)*.(0~:100|y)+.0=400|y
    case. 1 do. 0=4|y
    case. 2 do. 371=x year_length y
    case. 3 do. (30|y)e.2 5 7 10 13 16 18 21 24 26 29
    case. 4 do. hebrew_leap y
    case. 5 do. (2816|682*38+474+2820|y-474)<682
    case. 6;7 do. 3=4|y
    case. 8 do. (0=4|y)*.(-.(400|y)e.100 200 300)*.0~:4000|y
    end.
)
month_lengths =: 4 : 0
    extra =. x leap y
    select. x
    case. 0;1 do. (28+extra) 1}31 28 31 30 31 30 31 31 30 31 30 31
    case. 3 do. (29+extra) 11}12$30 29
    case. 4 do.
        length =. x year_length y
        h =. 29+length e.355 385
        k =. 30-length e.353 383
        if. extra do. 30,h,k,29 30 30 29 30 29 30 29 30 29
        else. 30,h,k,29 30 29 30 29 30 29 30 29 end.
    case. 5 do. (6#31),(5#30),29+extra
    case. 6;7;8 do. (12#30),5+extra
    end.
)
month_names =: 4 : 0
    select. x
    case. 0;1 do. ;:'January February March April May June July August September October November December'
    case. 3 do. ;:'Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah'
    case. 4 do.
        if. hebrew_leap y do. ;:'Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul'
        else. ;:'Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul' end.
    case. 5 do. ;:'Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand'
    case. 6 do. ;:'Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie'
    case. 7 do. ;:'Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume'
    case. 8 do. ;:'Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides'
    end.
)
year_type =: 3 : '(3|y){::;:''REGULAR COMPLETE DEFICIENT'''
year_at =: 4 : 0
    if. y<x year_start 1 do. 0 return. end.
    lo =. 1
    hi =. 100000
    while. 1<hi-lo do.
        mid =. (lo+hi) floor_ratio 2
        if. (x year_start mid)<:y do. lo =. mid else. hi =. mid end.
    end.
    lo
)
from_fixed =: 4 : 0
    year =. x year_at y
    if. year=0 do. 0 0 0 return. end.
    offset =. y-x year_start year
    if. x=2 do. year,(1+offset floor_ratio 7),1+7|offset return. end.
    lengths =. x month_lengths year
    month =. 1++/offset>:+/\lengths
    day =. (1+offset)-+/(month-1){.lengths
    year,month,day
)
to_fixed =: 4 : 0
    'year month day' =. y
    if. x=2 do. (x year_start year)+(7*(month-1))+day-1
    else. (x year_start year)+(+/(month-1){.x month_lengths year)+day-1 end.
)
format =: 4 : 0
    if. -.in_range y do. 'OUT OF RANGE' return. end.
    if. x<9 do.
        'year month day' =. x from_fixed y
        if. year=0 do. 'OUT OF RANGE' return. end.
        if. x=2 do. (4 padded year),'-W',(2 padded month),'-',number day
        else. (4 padded year),'-',(2 padded month),'-',2 padded day end.
    elseif. x=9 do.
        c =. y+1137142
        fields =. (c floor_ratio 144000),(20|c floor_ratio 7200),(20|c floor_ratio 360),(18|c floor_ratio 20),20|c
        count =. '.' join number each <"0 fields
        h =. 365|c+348
        words count;(1+13|c+3);((20|c+19){::TZ);(20|h);(h floor_ratio 20){::HB
    elseif. x=10 do. number y+1721425
    else. number y end.
)
validate_date =: 4 : 0
    if. x<9 do.
        fields =. '-' split y
        if. 3~:#fields do. 'FORMAT';0 return. end.
        'ys ms ds' =. fields
        if. -.5 digits ys do. 'FORMAT';0 return. end.
        if. x=2 do.
            if. ('W'~:{.ms)+.(-.2 digits }.ms)+.-.1 digits ds do. 'FORMAT';0 return. end.
            ms =. }.ms
        else.
            if. (-.2 digits ms)+.-.2 digits ds do. 'FORMAT';0 return. end.
        end.
        year =. 0".ys
        month =. 0".ms
        day =. 0".ds
        if. year=0 do. 'YEAR';0 return. end.
        if. x=2 do.
            if. (month<1)+.month>(x year_length year) floor_ratio 7 do. 'WEEK';0 return. end.
            if. (day<1)+.day>7 do. 'DAY';0 return. end.
        else.
            lengths =. x month_lengths year
            if. (month<1)+.month>#lengths do. 'MONTH';0 return. end.
            if. (day<1)+.day>(month-1){lengths do. 'DAY';0 return. end.
        end.
        f =. x to_fixed year,month,day
    elseif. x=9 do.
        fields =. '.' split y
        if. 5~:#fields do. 'FORMAT';0 return. end.
        if. -. *./>2&digits each fields do. 'FORMAT';0 return. end.
        values =. 0".each fields
        'b k t u n' =. >values
        if. (k>19)+.(t>19)+.(u>17)+.n>19 do. 'FIELD';0 return. end.
        f =. (n+20*(u+18*(t+20*(k+20*b))))-1137142
    else.
        if. -.8 signed y do. 'FORMAT';0 return. end.
        f =. (integer y)-1721425*x=10
    end.
    if. -.in_range f do. 'RANGE';f else. '';f end.
)
valid_arguments =: 4 : 0
    NB. Check every non-date field before inspecting any date.
    schema =. x{::SCHEMAS
    if. (#y)~:#schema do. 0 return. end.
    for_i. i.#schema do.
        token =. i{::y
        select. i{schema
        case. 'a' do. ok =. (<token)e.CALENDARS
        case. 'b' do. ok =. (<token)e.9{.CALENDARS
        case. 'c' do. ok =. (<token)e.0 1 3 4 5 6 7 8{CALENDARS
        case. 'y' do.
            if. -.5 digits token do. 0 return. end.
            ok =. 0<0".token
        case. 'm' do. ok =. 2 digits token
        case. 'i' do. ok =. 7 signed token
        case. 'T' do. ok =. token-:'TO'
        case. 'k' do. ok =. (<token)e.;:'1 2 3 4 5 LAST'
        case. 'w' do. ok =. (<token)e.WEEKDAYS
        case. 'u' do. ok =. (<token)e.;:'DAYS WEEKS MONTHS YEARS'
        case. 'e' do. ok =. (<token)e.;:'GREGORIAN JULIAN'
        case. 'z' do.
            if. -.2 digits token do. 0 return. end.
            ok =. (0".token)e.1+i.13
        case. 't' do. ok =. (<token)e.TZ
        case. 'h' do. ok =. (<token)e.HB
        case. do. ok =. 1
        end.
        if. -.ok do. 0 return. end.
    end.
    if. x=12 do.
        cal =. CALENDARS i.0{y
        unit =. 3{::y
        if. (unit-:'MONTHS')*.-.cal e.0 1 3 4 5 6 7 8 do. 0 return. end.
        if. (unit-:'YEARS')*.cal>:9 do. 0 return. end.
    elseif. x=19 do.
        limit =. 19-15*('Uayeb'-:5{::y)
        if. (0".4{::y)>limit do. 0 return. end.
    end.
    1
)
shift =: 4 : 0
    'f years months' =. y
    'year month day' =. x from_fixed f
    target =. year+years
    if. x=2 do.
        if. (target<1)+.target>99999 do. _1 return. end.
        week =. month<.(x year_length target) floor_ratio 7
        x to_fixed target,week,day return.
    end.
    if. x=4 do.
        name =. (month-1){::x month_names year
        names =. x month_names target
        index =. names i.<name
        if. index=#names do.
            if. name-:'Adar' do. index =. names i.<'AdarII'
            else. index =. names i.<'Adar' end.
        end.
        month =. index+1
    end.
    absolute =. (x months_before target)+(month-1)+months
    if. (absolute<0)+.absolute>:x months_before 100000 do. _1 return. end.
    if. x=4 do.
        lo =. 1
        hi =. 100000
        while. 1<hi-lo do.
            mid =. (lo+hi) floor_ratio 2
            if. (x months_before mid)<:absolute do. lo =. mid else. hi =. mid end.
        end.
        target =. lo
    else. target =. 1+absolute floor_ratio 12+x e.6 7 8 end.
    month =. 1+absolute-x months_before target
    day =. day<.(month-1){x month_lengths target
    x to_fixed target,month,day
)
month_calendar =: 4 : 0
    'year month first last' =. y
    name =. (month-1){::x month_names year
    say name;year;'(',(0 format first),' to ',(0 format last),')'
    emit 'Mo Tu We Th Fr Sa Su'
    offset =. 7|first-1
    count =. 1+last-first
    weeks =. (offset+count+6) floor_ratio 7
    for_week. i.weeks do.
        fields =. 0$a:
        for_column. i.7 do.
            day =. (1+column+7*week)-offset
            field =. '  '
            if. (day>:1)*.day<:count do.
                field =. number day
                field =. ((2-#field)#' '),field
            end.
            fields =. fields,<field
        end.
        line =. ' ' join fields
        while. ' '={:line do. line =. }:line end.
        emit line
    end.
)
newyears =: 4 : 0
    first =. 0 year_start y
    last =. 0 year_start y+1
    year =. 1>.x year_at first
    result =. 0$a:
    while. (x year_start year)<last do.
        f =. x year_start year
        if. f>:first do. result =. result,<(number year),':',0 format f end.
        year =. year+1
    end.
    if. #result do. ' ' join result else. 'NONE' end.
)
span =: 4 : 0
    'f1 f2' =. y
    a =. f1<.f2
    b =. f1>.f2
    years =. (0{x from_fixed b)-0{x from_fixed a
    while. (x shift a,years,0)>b do. years =. years-1 end.
    while. (x shift a,(years+1),0)<:b do. years =. years+1 end.
    NB. Every candidate shifts the original day, preserving its unclamped day.
    months =. 0
    while. (x shift a,years,months+1)<:b do. months =. months+1 end.
    days =. b-x shift a,years,months
    ((f1>f2)#'-'),(number years),'y ',(number months),'m ',(number days),'d'
)
easter =: 4 : 0
    g =. 19|y
    if. x=0 do.
        c =. 1+y floor_ratio 100
        e =. 30|((14+11*g)-((3*c) floor_ratio 4))+(5+8*c) floor_ratio 25
        if. (e=0)+.(e=1)*.g>10 do. e =. e+1 end.
    else. e =. 30|14+11*g end.
    moon =. (x to_fixed y,4 19)-e
    sunday =. (moon+7)-7|moon
    s =. 7|-x year_start y
    letters =. ,s{'ABCDEFG'
    if. x leap y do. letters =. letters,(7|s-1){'ABCDEFG' end.
    e;letters;moon;sunday
)
HOLIDAY_NAMES =: ;:'AshWednesday GoodFriday Easter Ascension Pentecost OrthodoxEaster Christmas OrthodoxChristmas RoshHashanah YomKippur Sukkot Hanukkah Purim Passover Shavuot IslamicNewYear Ashura Mawlid RamadanStart EidAlFitr EidAlAdha Nowruz SizdahBedar Yalda Nayrouz CopticChristmas Enkutatash Meskel Timkat RepublicDay RevolutionDay'
HOLIDAY_CALS =: 0 0 0 0 0 1 0 1 4 4 4 4 4 4 4 3 3 3 3 3 3 5 5 5 6 6 7 7 7 8 8
HOLIDAY_MONTHS =: ;:'- - - - - - December December Tishri Tishri Tishri Kislev Adar Nisan Sivan Muharram Muharram RabiI Ramadan Shawwal DhuAlHijjah Farvardin Farvardin Azar Thout Koiak Meskerem Meskerem Ter Vendemiaire Sansculottides'
HOLIDAY_DAYS =: 0 0 0 0 0 0 25 25 1 10 15 25 14 15 6 1 10 12 1 1 10 1 13 30 1 29 1 17 11 1 6
holidays =: 3 : 0
    first =. 0 year_start y
    last =. 0 year_start y+1
    gregorian =. 3{::0 easter y
    julian =. 3{::1 easter y
    records =. ((gregorian+_46 _2 0 39 49),julian),.i.6
    for_i. 6+i.25 do.
        cal =. i{HOLIDAY_CALS
        year =. 1>.cal year_at first
        while. (cal year_start year)<last do.
            name =. i{::HOLIDAY_MONTHS
            if. (i=12)*.hebrew_leap year do. name =. 'AdarII' end.
            month =. 1+(cal month_names year)i.<name
            day =. i{HOLIDAY_DAYS
            if. day<:(month-1){cal month_lengths year do.
                f =. cal to_fixed year,month,day
                if. (f>:first)*.f<last do. records =. records,f,i end.
            end.
            year =. year+1
        end.
    end.
    for_record. records /: records do.
        'f i' =. record
        cal =. i{HOLIDAY_CALS
        say (0 format f);(weekday f);(i{::HOLIDAY_NAMES);(cal{::CALENDARS);cal format f
    end.
)
execute =: 3 : 0
    tokens =. ' ' split y
    command =. COMMANDS i.{.tokens
    args =. }.tokens
    if. command=#COMMANDS do. emit 'INVALID COMMAND' return. end.
    if. -.command valid_arguments args do. emit 'INVALID COMMAND' return. end.
    schema =. command{::SCHEMAS
    dates =. 0$0
    cal =. 0
    for_i. i.#schema do.
        if. (i{schema)e.'abc' do. cal =. CALENDARS i.i{args end.
        if. 'd'=i{schema do.
            'reason f' =. cal validate_date i{::args
            if. #reason do.
                if. command=2 do. say 'NO';reason
                elseif. reason-:'RANGE' do. emit 'OUT OF RANGE'
                else. emit 'INVALID DATE' end.
                return.
            end.
            dates =. dates,f
        end.
    end.
    if. #dates do. f =. {.dates end.
    if. ({.schema)e.'abc' do. cal =. CALENDARS i.{.args end.
    select. command
    case. 0 do. emit (CALENDARS i.3{args) format f
    case. 1 do.
        for_c. i.12 do.
            result =. c format f
            if. (c e.0 1 3 4 5 6 7 8)*.-.result-:'OUT OF RANGE' do.
                'year month day' =. c from_fixed f
                result =. result,' ',(month-1){::c month_names year
            end.
            say (c{::CALENDARS);result
        end.
    case. 2 do. say 'YES';cal format f
    case. 3 do. emit weekday f
    case. 4 do.
        'year month day' =. cal from_fixed f
        wd =. weekday f
        if. cal=8 do.
            if. month=13 do. wd =. (day-1){::FS else. wd =. (10|day-1){::DC end.
        end.
        ordinal =. 1+f-cal year_start year
        length =. cal year_length year
        say wd;day;((month-1){::cal month_names year);year;'day=',(number ordinal),'/',number length
    case. 5 do.
        year =. 0".1{::args
        length =. cal year_length year
        result =. words ((cal leap year){::;:'NO YES');length
        if. cal=4 do. result =. result,' ',year_type length end.
        emit result
    case. 6 do.
        year =. 0".1{::args
        lengths =. cal month_lengths year
        names =. cal month_names year
        result =. 0$a:
        for_i. i.#lengths do. result =. result,<(i{::names),'=',number i{lengths end.
        emit ' ' join result
    case. 7;8 do.
        year =. 0".1{::args
        month =. 0".2{::args
        lengths =. cal month_lengths year
        if. (month<1)+.month>#lengths do. emit 'INVALID DATE' return. end.
        first =. cal to_fixed year,month,1
        last =. first+((month-1){lengths)-1
        if. command=7 do.
            if. (first<1)+.last>MAXDAY do. emit 'OUT OF RANGE' return. end.
            cal month_calendar year,month,first,last
        else.
            k =. 3{::args
            wd =. WEEKDAYS i.4{args
            if. k-:'LAST' do. day =. last-7|last-wd
            else. day =. first+(7|wd-first)+7*((0".k)-1) end.
            if. day>last do. emit 'NONE' else. emit cal format day end.
        end.
    case. 9 do.
        year =. 0".1{::args
        if. year>9999 do. emit 'OUT OF RANGE' else. emit cal newyears year end.
    case. 10 do. emit number (1{dates)-0{dates
    case. 11 do.
        lo =. <./dates
        hi =. >./dates
        wd =. WEEKDAYS i.3{args
        first =. lo+7|wd-lo
        emit number 0>.1+(hi-first) floor_ratio 7
    case. 12 do.
        n =. integer 2{::args
        select. 3{::args
        case. 'DAYS' do. g =. f+n
        case. 'WEEKS' do. g =. f+7*n
        case. 'MONTHS' do. g =. cal shift f,0,n
        case. 'YEARS' do. g =. cal shift f,n,0
        end.
        emit cal format g
    case. 13 do. emit cal span dates
    case. 14;15 do.
        year =. 0".0{::args
        if. year>9999 do. emit 'OUT OF RANGE' return. end.
        kind =. CALENDARS i.1{args
        'epact letters moon sunday' =. kind easter year
        if. command=14 do. emit 0 format sunday
        else.
            emit 'golden=',(number 1+19|year),' epact=',(number epact),' letters=',letters,' moon=',(kind format moon),' easter=',kind format sunday
        end.
    case. 16;17;18 do.
        year =. 0".0{::args
        if. (command~:18)*.year>9999 do. emit 'OUT OF RANGE' return. end.
        if. command=16 do.
            hy =. year+3760
            month =. 1+(4 month_names hy)i.<'Nisan'
            day =. 4 to_fixed hy,month,15
            say (0 format day);weekday day
        elseif. command=17 do. holidays year
        else.
            'd t start rules' =. molad year
            if. -.in_range start do. emit 'OUT OF RANGE' return. end.
            if. #rules do. rules =. '+' join rules else. rules =. 'NONE' end.
            say (weekday d-1373427);((number t floor_ratio 1080),'h');((number 1080|t),'p');rules;(weekday start);0 format start
        end.
    case. 19 do.
        num =. 0".2{::args
        name =. TZ i.3{args
        day =. 0".4{::args
        month =. HB i.5{args
        counts =. (f+1137142)+i.18980
        matches =. (((13|counts+3)+1)=num)*.((20|counts+19)=name)*.(365|counts+348)=day+20*month
        found =. I.matches
        if. #found do. emit cal format f+{.found else. emit 'NONE' end.
    end.
    i.0
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    for_line. (0".0{::lines){.}.lines do. execute >line end.
    i.0
)
main ''
