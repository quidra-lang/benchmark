ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'report.ijs'
load SourceDirectory,'records.ijs'
load SourceDirectory,'cleaning.ijs'
load SourceDirectory,'harmonic_fit.ijs'
load SourceDirectory,'predict.ijs'
analyse_station =: 3 : 0
 s =. y
 code =. s{::Codes
 name =. s{::StationNames
 ot =. s{::Times
 ov =. s{::Heights
 good =. s{::Numeric
 f =. {.good#ot
 last =. {:good#ot
 length =. last-f
 times =. f+i.length+1
 vals =. (#times)$0.0
 reason =. (#times)$1
 for_i. i.#ot do.
  j =. (i{ot)-f
  vals =. (i{ov)j}vals
  reason =. ((i{good){2 0)j}reason
 end.
 'flat runs' =. flat_runs ot;ov;good
 for_i. I.flat do. reason =. 3 ((i{ot)-f)}reason end.
 candidates =. I.reason=0
 'selected status' =. select_constituents length
 preliminary =. fit selected;(candidates{times);candidates{vals
 residuals0 =. (candidates{vals)-preliminary predict"_ 0 candidates{times
 'spikes details tested' =. spike_test (candidates{times);residuals0;candidates{vals
 reason =. 4 (spikes#candidates)}reason
 usable =. I.reason=0
 ut =. usable{times
 uv =. usable{vals
 model =. fit selected;ut;uv
 'z chosen coef amp phase ainv' =. model
 fitted =. model predict"_ 0 ut
 residuals =. uv-fitted
 n =. #ut
 p =. #coef
 ss =. sum *:residuals
 s2 =. ss%(n-p)
 'ex raw' =. model find_extrema ''
 high =. ex#~2{"1 ex
 low =. ex#~-.2{"1 ex
 daily =. 0$a:
 for_day. i.<.P%24 do.
  d =. date 60*(Ts+24*day)
  hh =. ll =. i.0
  for_e. high do. if. d-:date 0{e do. hh =. hh,1{e end. end.
  for_e. low do. if. d-:date 0{e do. ll =. ll,1{e end. end.
  h =. l =. r =. 'none'
  if. #hh do. h =. >./hh end.
  if. #ll do. l =. <./ll end.
  if. (#hh)*.#ll do. r =. h-l end.
  daily =. daily,<d;(#hh);(#ll);h;l;r
 end.
 hh =. ll =. ranges =. i.0
 rangedates =. 0$a:
 for_d. daily do.
  'dt nh nl h l r' =. >d
  if. nh do. hh =. hh,h end.
  if. nl do. ll =. ll,l end.
  if. 2~:3!:0 r do. ranges =. ranges,r
  rangedates =. rangedates,<dt end.
 end.
 mhhw =. mean hh
 mllw =. mean ll
 mhw =. mean 1{"1 high
 mlw =. mean 1{"1 low
 mtl =. (mhw+mlw)%2
 gt =. mhhw-mllw
 cleaning =. <'station=| name=|'render code;name
 cleaning =. cleaning,<'span start=| end=| hours=| record_length=|'render (time f);(time last);(length+1);length
 cleaning =. cleaning,<'counts rows=| numeric=| na=| absent=| flat=| spikes=| usable=|'render (#ot);(+/good);(+/reason=2);(+/reason=1);(+/reason=3);(+/reason=4);n
 for_run. runs do.
  'a b v' =. run
  cleaning =. cleaning,<'flat start=| end=| value=| removed=|'render (time a);(time b);(3 fmt v);b-a
 end.
 cleaning =. cleaning,<'spike_test window=| candidates=| tested=| prefit_rms=|'render (num 0{::pv 'spike');(#candidates);tested;4 fmt %:(sum *:residuals0)%#candidates
 for_row. details do.
  't v r me mad lim' =. row
  cleaning =. cleaning,<'spike time=| value=| residual=| median=| mad=| limit=|'render (time t);(3 fmt v);(4 fmt r);(4 fmt me);(4 fmt mad);4 fmt lim
 end.
 for_gap. gaps reason do.
  'a b c' =. gap
  cleaning =. cleaning,<'gap start=| end=| hours=| cause=|'render (time f+a);(time f+b);(b-a+1);c{::'';'absent';'na';'flat';'spike';'mixed'
 end.
 constants =. 0$a:
 for_i. i.#CNames do.
  prefix =. code,',',(i{::CNames),',',(7 fmt i{Speeds),',',i{::status
  k =. selected i.i
  if. k=#selected do. constants =. constants,<prefix,',,,,,,'
  continue. end.
  ia =. 1+2*k
  ib =. ia+1
  a =. ia{coef
  b =. ib{coef
  aa =. k{amp
  va =. s2*(<ia,ia){ainv
  vb =. s2*(<ib,ib){ainv
  cab =. s2*(<ia,ib){ainv
  av =. (((a*a)*va)+((b*b)*vb))+(((2*a)*b)*cab)
  phasevar =. (((b*b)*va)+((a*a)*vb))-(((2*a)*b)*cab)
  ae =. (%:av)%aa
  pe =. (((%:phasevar)%(aa*aa))*180)%3.141592653589793
  snr =. *:aa%ae
  constants =. constants,<prefix,',',','join (4 fmt aa);(2 fmt k{phase);(4 fmt ae);(2 fmt pe);(1 fmt snr);(snr>:pn 'snr_min'){::'no';'yes'
 end.
 extreme =. <'station=| extremes=| raw=| removed=|'render code;(#ex);raw;raw-#ex
 for_i. i.#ex do.
  'mu h hi' =. i{ex
  dt =. date mu
  group =. i.0
  for_j. i.#ex do.
   if. ((j{2{"1 ex)=hi)*.dt-:date (<j,0){ex do. group =. group,j end.
  end.
  heights =. group{1{"1 ex
  if. hi do. winner =. (heights i.>./heights){group
  label =. (i=winner){::'LHW';'HHW'
  else. winner =. (heights i.<./heights){group
  label =. (i=winner){::'HLW';'LLW' end.
  change =. 'none'
  if. i do. change =. 3 fmt h-(<(i-1),1){ex end.
  extreme =. extreme,<'| | | change=|'render (datetime mu);label;(3 fmt h);change
 end.
 for_d. daily do.
  'dt nh nl h l r' =. >d
  if. nh do. h =. 3 fmt h end.
  if. nl do. l =. 3 fmt l end.
  if. 2~:3!:0 r do. r =. 3 fmt r end.
  extreme =. extreme,<'day date=| high_waters=| low_waters=| hhw=| llw=| range=|'render dt;nh;nl;h;l;r
 end.
 summary =. <'[station |] |'render code;name
 summary =. summary,<'record first=| last=| length=| usable=|'render (time f);(time last);length;n
 summary =. summary,<'fit constituents=| unknowns=| dof=| mean_level=|'render (#selected);p;(n-p);4 fmt z
 consecutive =. I.1=(}.ut)-}:ut
 corr =. (sum (consecutive{residuals)*(1+consecutive){residuals)%sum *:consecutive{residuals
 explained =. 100*(1-ss%sum *:uv-mean uv)
 summary =. summary,<'residual rms=| max_abs=| explained_percent=| lag1_autocorrelation=|'render (4 fmt %:ss%n);(4 fmt >./|residuals);(4 fmt explained);4 fmt corr
 for_j. i.pn 'top_residuals' do.
  i =. j{\:|residuals
  summary =. summary,<'top_residual rank=| time=| observed=| fitted=| residual=|'render (j+1);(time i{ut);(3 fmt i{uv);(4 fmt i{fitted);4 fmt i{residuals
 end.
 mid =. f+<.length%2
 train =. I.ut<:mid
 test =. I.ut>mid
 vtimes =. train{ut
 vsel =. 0{::select_constituents ({:vtimes)-{.vtimes
 vm =. fit vsel;vtimes;train{uv
 vr =. (test{uv)-vm predict"_ 0 test{ut
 vs =. sum *:vr
 skill =. 1-vs%sum *:(test{uv)-mean test{uv
 summary =. summary,<'validation split=| train=| test=| constituents=| rms=| in_sample_rms=| skill=|'render (time mid);(#train);(#test);(#vsel);(4 fmt %:vs%#test);(4 fmt %:(sum *:test{residuals)%#test);4 fmt skill
 idx =. selected i.CNames i.'M2';'S2';'K1';'O1';'M4'
 'am as ak ao a4' =. idx{amp
 'gm gs gk go g4' =. idx{phase
 form =. (ak+ao)%(am+as)
 typ =. (+/form>:0.25 1.5 3){::'semidiurnal';'mixed_semidiurnal';'mixed_diurnal';'diurnal'
 rise =. fall =. i.0
 for_i. i.(#ex)-1 do.
  if. (<i,2){ex do. if. -. (<(i+1),2){ex do. fall =. fall,((<(i+1),0){ex)-(<i,0){ex end.
  else. if. (<(i+1),2){ex do. rise =. rise,((<(i+1),0){ex)-(<i,0){ex end. end.
 end.
 rp =. 360|(2*gm)-g4
 summary =. summary,<'form_number=| type=|'render (4 fmt form);typ
 summary =. summary,<'ranges spring=| neap=| mn=| gt=|'render (3 fmt 2*am+as);(3 fmt 2*am-as);(3 fmt mhw-mlw);3 fmt gt
 summary =. summary,<'asymmetry rise_minutes=| fall_minutes=| m4_m2_ratio=| relative_phase=| dominance=|'render (1 fmt mean rise);(1 fmt mean fall);(4 fmt a4%am);(2 fmt rp);(rp<180){::'ebb';'flood'
 summary =. summary,<'datums mhhw=| mhw=| mtl=| dtl=| mlw=| mllw=|'render (3 fmt mhhw);(3 fmt mhw);(3 fmt mtl);(3 fmt (mhhw+mllw)%2);(3 fmt mlw);3 fmt mllw
 summary =. summary,<'bounds hat=| lat=|'render (3 fmt z+sum amp);3 fmt z-sum amp
 hidx =. {.\:1{"1 high
 lidx =. {./:1{"1 low
 summary =. summary,<'window high_waters=| low_waters=| highest=| highest_time=| lowest=| lowest_time=|'render (#high);(#low);(3 fmt (<hidx,1){high);(datetime (<hidx,0){high);(3 fmt (<lidx,1){low);datetime (<lidx,0){low
 hi =. {.\:ranges
 lo =. {./:ranges
 summary =. summary,<'daily_range widest=| widest_date=| narrowest=| narrowest_date=|'render (3 fmt hi{ranges);(hi{::rangedates);(3 fmt lo{ranges);lo{::rangedates
 hourly =. model predict"_ 0 Ts+i.P+1
 summary =. summary,<'exceedance above_mhhw=| below_mllw=|'render (2 fmt (100*+/hourly>mhhw)%(P+1));2 fmt (100*+/hourly<mllw)%(P+1)
 dw =. ((CNames i.<'S2'){Speeds)-(CNames i.<'M2'){Speeds
 dg =. gs-gm
 qa =. ((Ts*dw)-dg)%180
 qb =. (((Ts+P)*dw)-dg)%180
 q0 =. >.qa<.qb
 q1 =. <.qa>.qb
 for_q. q0+i.1+q1-q0 do. summary =. summary,<'| time=|'render ((2|q){::'spring';'neap');datetime <.0.5+60*(dg+180*q)%dw end.
 events =. 0 4$0
 i =. 0
 th =. num 0{::pv 'surge'
 minhours =. num 1{::pv 'surge'
 while. i<n do.
  sg =. (*i{residuals)*(|i{residuals)>th
  j =. i+1
  if. sg do.
   while. j<n do.
    if. ((j{ut)~:1+(j-1){ut)+.(sg*(j{residuals))<:th do. break. end.
    j =. j+1
   end.
   if. (j-i)>:minhours do.
    peak =. i+{.\:sg*(i+i.j-i){residuals
    events =. events,i,(j-1),peak,sg
   end.
  end.
  i =. j
 end.
 summary =. summary,<'surges count=| threshold=| min_hours=|'render (#events);(3 fmt th);minhours
 for_e. events do.
  'a b peak sg' =. e
  summary =. summary,<'surge type=| start=| end=| hours=| peak=| peak_time=|'render ((sg>0){::'negative';'positive');(time a{ut);(time b{ut);(b-a+1);(4 fmt peak{residuals);time peak{ut
 end.
 wt =. 0 2 1 1 2 0 1 1 0 2 0 1 1 0 1 0 0 1 0 1
 dm =. 0 3$0.0
 filled =. vals
 missing =. I.reason~:0
 filled =. (model predict"_ 0 missing{times)missing}filled
 for_day. (<.f%24)+i.1+(<.last%24)-<.f%24 do.
  tn =. (24*day)+12
  if. ((tn-19)>:f)*.(tn+19)<:last do.
   js =. (tn-f)+_19+i.39
   level =. (sum ((|_19+i.39){wt)*js{filled)%30
   dm =. dm,(day*1440),level,+/(js{reason)~:0
  end.
 end.
 dv =. 1{"1 dm
 dx =. ((0{"1 dm)-(<0,0){dm)%1440
 slope =. (sum (dx-mean dx)*(dv-mean dv))%sum *:dx-mean dx
 hi =. {.\:dv
 lo =. {./:dv
 summary =. summary,<'daily_mean days=| average=| slope_mm_per_day=| max=| max_date=| min=| min_date=|'render (#dm);(4 fmt mean dv);(3 fmt 1000*slope);(4 fmt hi{dv);(date (<hi,0){dm);(4 fmt lo{dv);date (<lo,0){dm
 for_d. dm do. summary =. summary,<'daily_mean date=| level=| filled=|'render (date 0{d);(4 fmt 1{d);2{d end.
 cleaning;constants;extreme;summary;model;ex;ut;residuals;gt;mtl
)
main =: 3 : 0
 read_records ''
 1!:5 :: 0: <'output'
 results =. 0$a:
 clean =. ext =. summaries =. 0$a:
 constants =. <'station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant'
 for_s. i.#Codes do.
  r =. analyse_station s
  results =. results,<r
  clean =. clean,0{::r
  constants =. constants,1{::r
  ext =. ext,2{::r
  summaries =. summaries,3{::r
 end.
 predictions =. <'time,',','join Codes
 for_t. Ts+i.P+1 do.
  row =. <time t
  for_r. results do. row =. row,<3 fmt (4{::>r)predict t end.
  predictions =. predictions,<','join row
 end.
 ref =. Codes i.0{pv 'reference'
 rr =. ref{::results
 summaries =. summaries,<'[comparison] reference=',ref{::Codes
 for_s. (i.#Codes)-.ref do.
  r =. s{::results
  lags =. i.0
  for_hi. 1 0 do.
   a =. (5{::r)#~hi=2{"1 5{::r
   b =. (5{::rr)#~hi=2{"1 5{::rr
   ls =. i.0
   for_e. a do.
    dif =. (0{e)-0{"1 b
    j =. (|dif)i.<./|dif
    ls =. ls,j{dif
   end.
   lags =. lags,mean ls
  end.
  code =. s{::Codes
  summaries =. summaries,<'| tide hw_lag_min=| lw_lag_min=| range_ratio=| mtl_diff=|'render code;(1 fmt 0{lags);(1 fmt 1{lags);(4 fmt (8{::r)%8{::rr);3 fmt (9{::r)-9{::rr
  for_cn. 'M2';'S2';'K1';'O1' do.
   ci =. CNames i.cn
   m =. 4{::r
   mr =. 4{::rr
   k =. (1{::m)i.ci
   kr =. (1{::mr)i.ci
   a =. k{3{::m
   ar =. kr{3{::mr
   pd =. (k{4{::m)-kr{4{::mr
   if. pd>180 do. pd =. pd-360 elseif. pd<:_180 do. pd =. pd+360 end.
   summaries =. summaries,<'| | amplitude_ratio=| phase_diff=| time_lag_min=|'render code;(>cn);(4 fmt a%ar);(2 fmt pd);1 fmt (pd%(ci{Speeds))*60
  end.
 end.
 lc =. pn 'correlation_lag'
 summaries =. summaries,<'[correlation] max_lag=',str lc
 for_a. i.#Codes do.
  for_b. (a+1)+i.(#Codes)-a+1 do.
   ra =. a{::results
   rb =. b{::results
   rows =. 0 3$0.0
   for_lag. (-lc)+i.1+2*lc do.
    ta =. 6{::ra
    tb =. 6{::rb
    ia =. I.(ta+lag)e.tb
    ib =. tb i.(ia{ta)+lag
    xx =. ia{7{::ra
    yy =. ib{7{::rb
    xx =. xx-mean xx
    yy =. yy-mean yy
    rho =. (sum xx*yy)%%:(sum *:xx)*sum *:yy
    rows =. rows,lag,rho,#ia
   end.
   order =. /:((-1{"1 rows),.(|0{"1 rows),.0{"1 rows)
   'lag rho np' =. ({.order){rows
   summaries =. summaries,<'|-| lag0=| best_lag=| best=| pairs=|'render (a{::Codes);(b{::Codes);(4 fmt (<lc,1){rows);lag;(4 fmt rho);np
  end.
 end.
 plotindex =. Codes i.<PlotCode
 r =. plotindex{::results
 summaries =. summaries,<'[plot] station=| start=| hours=| step_cm=|'render PlotCode;(time Ts);(0{PlotValues);3{PlotValues
 summaries =. summaries,plot_lines (4{::r);5{::r
 'cleaning.txt'write_lines clean
 'constituents.csv'write_lines constants
 'predictions.csv'write_lines predictions
 'extremes.txt'write_lines ext
 'summary.txt'write_lines summaries
 i.0 0
)
main ''
