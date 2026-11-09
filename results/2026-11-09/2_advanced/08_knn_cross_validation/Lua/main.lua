local dataset=require("dataset")
local scaling=require("scaling")
local neighbors=require("neighbors")
local validation=require("validation")
local report=require("report")
local format=string.format
local real,ratio=report.fixed,report.ratio
local function append(a,b) for _,v in ipairs(b) do a[#a+1]=v end end
local function copy(a) local out={};append(out,a);return out end
local function indices(n) local out={};for j=1,n do out[j]=j end;return out end
local function part(lines,rows) if #lines>0 then lines[#lines+1]="" end;append(lines,rows) end
local function grid(s)
 local models={};for _,k in ipairs(s.K_VALUES) do for _,metric in ipairs(s.METRICS) do for _,weighting in ipairs(s.WEIGHTINGS) do for _,method in ipairs(s.SCALINGS) do models[#models+1]={k=k,metric=metric,weighting=weighting,scaling=method} end end end end;return models
end
local function finish_results(results,rows)
 for _,result in ipairs(results) do local errors={};result.correct=0;for j,r in ipairs(rows) do local p=result.predictions[j];if p.label==r.label then result.correct=result.correct+1 end;errors[j]=p.estimate-r.target end;result.rmse=validation.rmse(errors) end;return results
end
local function cross_validate(models,rows,features,folds)
 local results={};for j,m in ipairs(models) do results[j]={model=m,predictions={}} end
 for _,fold in ipairs(validation.stratified(rows,folds)) do
  local train=validation.training(rows,fold);local queries={};for _,i in ipairs(fold) do queries[#queries+1]=rows[i] end;local cache={}
  for j,m in ipairs(models) do local key=m.scaling.."|"..m.metric;local orders=cache[key];if not orders then orders=validation.orders(train,queries,m.scaling,m.metric,features);cache[key]=orders end;for k,i in ipairs(fold) do results[j].predictions[i]=neighbors.predict(orders[k],m.k,m.weighting) end end
 end
 return finish_results(results,rows)
end
local function leave_one_out(models,rows,features)
 local results={};for j,m in ipairs(models) do results[j]={model=m,predictions={}} end
 for i,r in ipairs(rows) do local train=validation.training(rows,{i});local cache={};for j,m in ipairs(models) do local key=m.scaling.."|"..m.metric;local order=cache[key];if not order then order=validation.orders(train,{r},m.scaling,m.metric,features)[1];cache[key]=order end;results[j].predictions[i]=neighbors.predict(order,m.k,m.weighting) end end
 return finish_results(results,rows)
end
local function best(results,selected)
 local classifier,regressor=selected[1],selected[1]
 for j=2,#selected do local i=selected[j];if results[i].correct>results[classifier].correct then classifier=i end;if report.four(results[i].rmse)<report.four(results[regressor].rmse) then regressor=i end end;return classifier,regressor
end
local function label_counts(labels,rows)
 local counts={};for _,r in ipairs(rows) do counts[r.label]=(counts[r.label] or 0)+1 end;local out={};for _,label in ipairs(labels) do out[#out+1]=label;out[#out+1]=counts[label] or 0 end;return table.concat(out," ")
end
local function correct(rows,predictions) local count=0;for j,r in ipairs(rows) do if r.label~="" and r.label==predictions[j].label then count=count+1 end end;return count end
local function errors_for(rows,predictions)
 local errors,targets={},{};for j,r in ipairs(rows) do if r.has_target then errors[#errors+1]=predictions[j].estimate-r.target;targets[#targets+1]=r.target end end;return errors,targets
end
local function id_order(rows) local out=indices(#rows);table.sort(out,function(i,j) return rows[i].id<rows[j].id end);return out end
local function evaluation(labels,rows,predictions)
 local index,matrix={},{};for j,label in ipairs(labels) do index[label]=j;matrix[j]={};for k=1,#labels do matrix[j][k]=0 end end
 for j,r in ipairs(rows) do if r.label~="" then local a,b=index[r.label],index[predictions[j].label];matrix[a][b]=matrix[a][b]+1 end end
 local lines={"true\\predicted "..table.concat(labels," ")};for j,label in ipairs(labels) do lines[#lines+1]=label.." "..table.concat(matrix[j]," ") end;local sums,counts={0.0,0.0,0.0},{0,0,0}
 for j,label in ipairs(labels) do
  local actual,predicted=0,0;for k=1,#labels do actual=actual+matrix[j][k];predicted=predicted+matrix[k][j] end;local tp=matrix[j][j];local numerators,denominators={tp,tp,2*tp},{predicted,actual,predicted+actual}
  for k,den in ipairs(denominators) do if den~=0 then sums[k]=sums[k]+numerators[k]/den;counts[k]=counts[k]+1 end end
  lines[#lines+1]=format("class %s precision %s recall %s f1 %s support %d",label,report.fraction(tp,predicted),report.fraction(tp,actual),report.fraction(2*tp,predicted+actual),actual)
 end
 local averages={"-","-","-"};for k,count in ipairs(counts) do if count>0 then averages[k]=real(sums[k]/count) end end;lines[#lines+1]=format("macro precision %s recall %s f1 %s",averages[1],averages[2],averages[3]);return lines
end
local function bins(boundaries,rows,predictions)
 local lower={0};append(lower,boundaries);local counts,correct_counts,sums={},{},{};for j=1,#lower do counts[j],correct_counts[j],sums[j]=0,0,0.0 end
 for j,r in ipairs(rows) do if r.label~="" then local p=predictions[j];local bin=1;while bin<=#boundaries and p.share>=boundaries[bin] do bin=bin+1 end;counts[bin]=counts[bin]+1;if p.label==r.label then correct_counts[bin]=correct_counts[bin]+1 end;sums[bin]=sums[bin]+p.share end end
 local lines={};for j,lo in ipairs(lower) do if counts[j]==0 then lines[#lines+1]="bin "..real(lo,2).." rows 0" else lines[#lines+1]=format("bin %s rows %d correct %s share %s",real(lo,2),counts[j],ratio(correct_counts[j],counts[j]),real(sums[j]/counts[j])) end end;return lines
end
local A={};A.__index=A
function A:best_per(kind,values)
 local lines={"best per "..kind}
 for _,value in ipairs(values) do local selected={};for j,m in ipairs(self.models) do if m[kind]==value then selected[#selected+1]=j end end;local ci,ri=best(self.results,selected);local c,r=self.results[ci],self.results[ri];lines[#lines+1]=format("%s=%s classifier %s accuracy %s regressor %s rmse %s",kind,tostring(value),validation.notation(c.model),real(c.correct/#self.data.train),validation.notation(r.model),real(r.rmse)) end;return lines
end
function A:nested_lines()
 local d,s=self.data,self.data.settings;local lines={"nested_cross_validation folds "..s.FOLDS};local nested_errors={};local total_correct=0
 for f,fold in ipairs(self.folds) do local train=validation.training(d.train,fold);local inner=cross_validate(self.models,train,self.features,s.FOLDS);local ci,ri=best(inner,indices(#inner));local queries={};for _,i in ipairs(fold) do queries[#queries+1]=d.train[i] end
  local cp=validation.predict(self.models[ci],train,queries,self.features);local rp=validation.predict(self.models[ri],train,queries,self.features);local count=correct(queries,cp);total_correct=total_correct+count;local errors=errors_for(queries,rp);for j,i in ipairs(fold) do nested_errors[i]=errors[j] end
  lines[#lines+1]=format("fold %d classifier %s inner %s outer %s",f,validation.notation(self.models[ci]),real(inner[ci].correct/#train),ratio(count,#fold));lines[#lines+1]=format("fold %d regressor %s inner %s outer %s",f,validation.notation(self.models[ri]),real(inner[ri].rmse),real(validation.rmse(errors)))
 end
 lines[#lines+1]=format("nested accuracy %s rmse %s",ratio(total_correct,#d.train),real(validation.rmse(nested_errors)));return lines
end
function A:feature_lines()
 local m=self.models[self.classifier];local features=copy(self.features);local selected=copy(features);local best_count=self.results[self.classifier].correct;local n=#self.data.train
 local function names(ids) local out={};for _,i in ipairs(ids) do out[#out+1]=self.data.features[i] end;return table.concat(out," ") end
 local lines={"feature_selection "..validation.notation(m),"start features "..names(features).." correct "..ratio(best_count,n)};local step=0
 while #features>=3 do
  local counts={};local choice=1
  for j=1,#features do local candidate={};for k,i in ipairs(features) do if k~=j then candidate[#candidate+1]=i end end;counts[j]=cross_validate({m},self.data.train,candidate,self.data.settings.FOLDS)[1].correct;if counts[j]>counts[choice] then choice=j end end
  local candidates={};for j,i in ipairs(features) do candidates[#candidates+1]=self.data.features[i];candidates[#candidates+1]=counts[j] end;local removed=features[choice];table.remove(features,choice);step=step+1;lines[#lines+1]=format("step %d remove %s correct %s candidates %s",step,self.data.features[removed],ratio(counts[choice],n),table.concat(candidates," "))
  if counts[choice]>=best_count then best_count=counts[choice];selected=copy(features) end
 end
 local test=validation.predict(m,self.data.train,self.data.test,selected);lines[#lines+1]="selected features "..names(selected).." correct "..ratio(best_count,n);lines[#lines+1]="selected test "..ratio(correct(self.data.test,test),self.labelled);return lines
end
function A:metrics_lines()
 local d,s=self.data,self.data.settings;local n=#d.train;local c,r=self.results[self.classifier],self.results[self.regressor]
 local lines={format("data train %d test %d labelled %d targets %d features %d classes %d",n,#d.test,self.labelled,self.targets,#d.features,#d.labels),"classes "..label_counts(d.labels,d.train)}
 for _,method in ipairs(s.SCALINGS) do local scale=scaling.compute(d.train,method);local rows={"scaling "..method};for j,name in ipairs(d.features) do rows[#rows+1]=format("%s center %s scale %s",name,real(scale.centers[j],6),real(scale.scales[j],6)) end;part(lines,rows) end
 local rows={"folds "..s.FOLDS};for f,fold in ipairs(self.folds) do local chosen={};for _,i in ipairs(fold) do chosen[#chosen+1]=d.train[i] end;rows[#rows+1]=format("fold %d size %d %s",f,#chosen,label_counts(d.labels,chosen)) end;part(lines,rows)
 part(lines,{"grid "..#self.models,format("best_classifier %s correct %s rmse %s",validation.notation(c.model),ratio(c.correct,n),real(c.rmse)),format("best_regressor %s rmse %s correct %s",validation.notation(r.model),real(r.rmse),ratio(r.correct,n))})
 local accuracy,regression=indices(#self.models),indices(#self.models)
 table.sort(accuracy,function(i,j) local a,b=self.results[i],self.results[j];return a.correct~=b.correct and a.correct>b.correct or a.correct==b.correct and i<j end)
 table.sort(regression,function(i,j) local a,b=report.four(self.results[i].rmse),report.four(self.results[j].rmse);return a~=b and a<b or a==b and i<j end)
 rows={"top "..s.TOP.." by accuracy"};for rank=1,math.min(s.TOP,#accuracy) do local v=self.results[accuracy[rank]];rows[#rows+1]=format("%d %s correct %s rmse %s",rank,validation.notation(v.model),ratio(v.correct,n),real(v.rmse)) end;part(lines,rows)
 rows={"top "..s.TOP.." by rmse"};for rank=1,math.min(s.TOP,#regression) do local v=self.results[regression[rank]];rows[#rows+1]=format("%d %s rmse %s correct %s",rank,validation.notation(v.model),real(v.rmse),ratio(v.correct,n)) end;part(lines,rows)
 for _,entry in ipairs({{"k",s.K_VALUES},{"metric",s.METRICS},{"weighting",s.WEIGHTINGS},{"scaling",s.SCALINGS}}) do part(lines,self:best_per(entry[1],entry[2])) end
 rows={"classifier folds"};for f,fold in ipairs(self.folds) do local count=0;for _,i in ipairs(fold) do if c.predictions[i].label==d.train[i].label then count=count+1 end end;rows[#rows+1]=format("fold %d correct %s",f,ratio(count,#fold)) end;part(lines,rows)
 rows={"regressor folds"};for f,fold in ipairs(self.folds) do local errors={};for _,i in ipairs(fold) do errors[#errors+1]=r.predictions[i].estimate-d.train[i].target end;rows[#rows+1]=format("fold %d size %d rmse %s",f,#fold,real(validation.rmse(errors))) end;part(lines,rows)
 rows={"cross_validation classes"};append(rows,evaluation(d.labels,d.train,c.predictions));part(lines,rows);rows={"cross_validation reliability"};append(rows,bins(s.BINS,d.train,c.predictions));part(lines,rows)
 rows={"mcnemar"}
 for _,metric in ipairs(s.METRICS) do local selected={};for j,m in ipairs(self.models) do if m.metric==metric then selected[#selected+1]=j end end;local comparison=best(self.results,selected);local b,cc=0,0
  for j,row in ipairs(d.train) do local first,second=c.predictions[j].label==row.label,self.results[comparison].predictions[j].label==row.label;if first and not second then b=b+1 end;if second and not first then cc=cc+1 end end
  local u=math.max(0,math.abs(b-cc)-1);u=u*u;local statistic=b+cc>0 and report.fraction(u,b+cc) or "0/1 0.0000";rows[#rows+1]=format("%s b %d c %d statistic %s significant %s",validation.notation(self.models[comparison]),b,cc,statistic,1000*u>3841*(b+cc) and "yes" or "no")
 end;part(lines,rows)
 local loo_c,loo_r=self.loo[1],self.loo[2];local class_errors={};for j,row in ipairs(d.train) do if loo_c.predictions[j].label~=row.label then class_errors[row.label]=(class_errors[row.label] or 0)+1 end end;local by_class={};for _,label in ipairs(d.labels) do by_class[#by_class+1]=label;by_class[#by_class+1]=class_errors[label] or 0 end
 rows={"leave_one_out classifier "..validation.notation(c.model),"errors "..ratio(n-loo_c.correct,n),"class_errors "..table.concat(by_class," ")}
 for _,j in ipairs(id_order(d.train)) do local row,p=d.train[j],loo_c.predictions[j];if p.label~=row.label then rows[#rows+1]=format("%s true %s predicted %s share %s",row.id,row.label,p.label,real(p.share)) end end;part(lines,rows)
 local residuals=errors_for(d.train,loo_r.predictions);local order=indices(n);table.sort(order,function(i,j) local a,b=report.four(math.abs(residuals[i])),report.four(math.abs(residuals[j]));return a~=b and a>b or a==b and d.train[i].id<d.train[j].id end)
 rows={"leave_one_out regressor "..validation.notation(r.model),"rmse "..real(validation.rmse(residuals)).." mae "..real(validation.mae(residuals)),"largest "..s.TOP.." residuals"};for rank=1,math.min(s.TOP,n) do local j=order[rank];rows[#rows+1]=format("%s target %s estimate %s residual %s",d.train[j].id,real(d.train[j].target),real(loo_r.predictions[j].estimate),real(residuals[j])) end;part(lines,rows)
 rows={format("leave_one_out by k metric=%s weighting=%s scaling=%s",c.model.metric,c.model.weighting,c.model.scaling)};for j,k in ipairs(s.K_VALUES) do local v=self.loo[j+2];rows[#rows+1]=format("k=%d correct %s rmse %s",k,ratio(v.correct,n),real(v.rmse)) end;part(lines,rows);part(lines,self:nested_lines());part(lines,self:feature_lines())
 rows={"test classification "..validation.notation(c.model),format("labelled %d correct %s",self.labelled,ratio(correct(d.test,self.test_class),self.labelled))};append(rows,evaluation(d.labels,d.test,self.test_class));part(lines,rows);rows={"test reliability"};append(rows,bins(s.BINS,d.test,self.test_class));part(lines,rows)
 local uncertain=indices(#d.test);table.sort(uncertain,function(i,j) local a,b=self.test_class[i],self.test_class[j];local first,second=report.four(a.share-a.runner_share),report.four(b.share-b.runner_share);return first~=second and first<second or first==second and i<j end)
 rows={"uncertain "..s.TOP.." test rows"};for rank=1,math.min(s.TOP,#uncertain) do local j=uncertain[rank];local row,p=d.test[j],self.test_class[j];rows[#rows+1]=format("%s predicted %s share %s runner_up %s share %s margin %s true %s",row.id,p.label,real(p.share),p.runner~="" and p.runner or "-",real(p.runner_share),real(p.share-p.runner_share),row.label~="" and row.label or "-") end;part(lines,rows)
 local test_errors,targets=errors_for(d.test,self.test_reg);rows={"test regression "..validation.notation(r.model),format("targets %d rmse %s mae %s r2 %s",self.targets,real(validation.rmse(test_errors)),real(validation.mae(test_errors)),real(validation.r_squared(test_errors,targets)))}
 for _,label in ipairs(d.labels) do local errors={};for j,row in ipairs(d.test) do if row.has_target and row.label==label then errors[#errors+1]=self.test_reg[j].estimate-row.target end end;rows[#rows+1]=format("class %s targets %d rmse %s",label,#errors,#errors>0 and real(validation.rmse(errors)) or "-") end;part(lines,rows)
 rows={"misclassified test rows"};local count=0;for j,row in ipairs(d.test) do local p=self.test_class[j];if row.label~="" and row.label~=p.label then count=count+1;rows[#rows+1]=format("%s true %s predicted %s share %s",row.id,row.label,p.label,real(p.share));for _,neighbor in ipairs(p.neighbors) do rows[#rows+1]=format("  %s %s %s",neighbor.row.id,neighbor.row.label,real(neighbor.distance)) end end end;rows[#rows+1]="count "..count;part(lines,rows);return lines
end
function A:learning_lines()
 local lines={"n,train_size,correct,accuracy,rmse"}
 for _,limit in ipairs(self.data.settings.CURVE) do local counts,train={},{};for _,r in ipairs(self.data.train) do if (counts[r.label] or 0)<limit then train[#train+1]=r;counts[r.label]=(counts[r.label] or 0)+1 end end
  local cp=validation.predict(self.models[self.classifier],train,self.data.test,self.features);local rp=validation.predict(self.models[self.regressor],train,self.data.test,self.features);local count=correct(self.data.test,cp);local errors=errors_for(self.data.test,rp);lines[#lines+1]=format("%d,%d,%d,%s,%s",limit,#train,count,real(count/self.labelled),real(validation.rmse(errors)))
 end;return lines
end
local function classifier_space(d,m,features)
 local s=scaling.compute(d.train,m.scaling);local vectors={};for j,r in ipairs(d.train) do vectors[j]=scaling.transform(s,r,features) end;local rows=copy(d.train);append(rows,d.test);local distances={}
 for _,q in ipairs(rows) do local v=scaling.transform(s,q,features);distances[q.index]={};for j,r in ipairs(d.train) do distances[q.index][r.index]=neighbors.distance(v,vectors[j],m.metric) end end
 return distances
end
local function space_order(space,query,refs)
 local order={};for _,r in ipairs(refs) do order[#order+1]={row=r,distance=space[query.index][r.index]} end;neighbors.sort(order);return order
end
local function except(rows,row) local refs={};for _,r in ipairs(rows) do if r~=row then refs[#refs+1]=r end end;return refs end
local function sorted_rows(rows) local out=copy(rows);table.sort(out,function(a,b) return a.id<b.id end);return out end
local function condense(space,rows)
 rows=sorted_rows(rows);local store={rows[1]};local present={[rows[1]]=true};local scans=0
 while true do scans=scans+1;local added=false;for _,r in ipairs(rows) do if not present[r] and space_order(space,r,store)[1].row.label~=r.label then store[#store+1]=r;present[r]=true;added=true end end;if not added then break end end
 return sorted_rows(store),scans
end
local function prototype_ids(name,rows)
 local lines={"prototypes "..name};rows=sorted_rows(rows);for first=1,#rows,10 do local ids={};for j=first,math.min(first+9,#rows) do ids[#ids+1]=rows[j].id end;lines[#lines+1]=table.concat(ids," ") end;return lines
end
function A:prototype_lines()
 local d,s=self.data,self.data.settings;local m=self.models[self.classifier];local space=classifier_space(d,m,self.features);local lines={"space "..validation.notation(m)};local edited=sorted_rows(d.train);local rows={"editing k="..s.EDIT_K};local pass=0
 while true do pass=pass+1;local removed,predictions={},{};for _,r in ipairs(edited) do local p=neighbors.predict(space_order(space,r,except(edited,r)),s.EDIT_K,m.weighting);if p.label~=r.label then removed[#removed+1]=r;predictions[#predictions+1]=p end end;rows[#rows+1]=format("pass %d removed %d",pass,#removed)
  for j,r in ipairs(removed) do local p=predictions[j];rows[#rows+1]=format("  %s true %s predicted %s share %s",r.id,r.label,p.label,real(p.share)) end;if #removed==0 then break end
  local skip={};for _,r in ipairs(removed) do skip[r]=true end;local next_rows={};for _,r in ipairs(edited) do if not skip[r] then next_rows[#next_rows+1]=r end end;edited=next_rows
 end
 rows[#rows+1]=format("edited size %d removed %d",#edited,#d.train-#edited);part(lines,rows)
 local condensed,original_scans=condense(space,d.train);local edited_condensed,edited_scans=condense(space,edited)
 part(lines,{format("condensing original scans %d size %d",original_scans,#condensed),format("condensing edited scans %d size %d",edited_scans,#edited_condensed)})
 rows={};for j,refs in ipairs({d.train,edited,condensed,edited_condensed}) do local knn,one=0,0;for _,q in ipairs(d.test) do if q.label~="" then local order=space_order(space,q,refs);local p=neighbors.predict(order,m.k,m.weighting);if p.label==q.label then knn=knn+1 end;if order[1].row.label==q.label then one=one+1 end end end;rows[#rows+1]=format("set %s size %d %s knn %s 1nn %s",({"original","edited","condensed","edited_condensed"})[j],#refs,label_counts(d.labels,refs),ratio(knn,self.labelled),ratio(one,self.labelled)) end;part(lines,rows);part(lines,prototype_ids("condensed",condensed));part(lines,prototype_ids("edited_condensed",edited_condensed))
 rows={"borders"};local total_border=0
 for _,label in ipairs(d.labels) do local count,border=0,0;local same,other=0.0,0.0;for _,q in ipairs(sorted_rows(d.train)) do if q.label==label then count=count+1;local order=space_order(space,q,except(d.train,q));if order[1].row.label~=label then border=border+1 end;local found_same,found_other=false,false
  for _,neighbor in ipairs(order) do if not found_same and neighbor.row.label==label then same=same+neighbor.distance;found_same=true end;if not found_other and neighbor.row.label~=label then other=other+neighbor.distance;found_other=true end;if found_same and found_other then break end end
 end end;total_border=total_border+border;rows[#rows+1]=format("class %s size %d border %d same %s other %s",label,count,border,real(same/count),real(other/count)) end
 rows[#rows+1]="border total "..ratio(total_border,#d.train);part(lines,rows)
 local occurrences={};for j=1,#d.train do occurrences[j]=0 end;for _,p in ipairs(self.test_class) do for _,neighbor in ipairs(p.neighbors) do local i=neighbor.row.index;occurrences[i]=occurrences[i]+1 end end
 local order=indices(#d.train);table.sort(order,function(i,j) return occurrences[i]~=occurrences[j] and occurrences[i]>occurrences[j] or occurrences[i]==occurrences[j] and d.train[i].id<d.train[j].id end);rows={format("hubs k=%d queries %d",m.k,#d.test)};local anti=0;for _,count in ipairs(occurrences) do if count==0 then anti=anti+1 end end
 for rank=1,math.min(s.TOP,#order) do local j=order[rank];rows[#rows+1]=format("%s %s %d",d.train[j].id,d.train[j].label,occurrences[j]) end;rows[#rows+1]="anti_hubs "..anti;part(lines,rows);return lines
end
local d=dataset.read();local a=setmetatable({data=d,models=grid(d.settings),features=indices(#d.features),folds=validation.stratified(d.train,d.settings.FOLDS),labelled=0,targets=0},A)
a.results=cross_validate(a.models,d.train,a.features,d.settings.FOLDS);a.classifier,a.regressor=best(a.results,indices(#a.results));a.test_class=validation.predict(a.models[a.classifier],d.train,d.test,a.features);a.test_reg=validation.predict(a.models[a.regressor],d.train,d.test,a.features)
for _,r in ipairs(d.test) do if r.label~="" then a.labelled=a.labelled+1 end;if r.has_target then a.targets=a.targets+1 end end
local loo_models={a.models[a.classifier],a.models[a.regressor]};for _,k in ipairs(d.settings.K_VALUES) do local selected=a.models[a.classifier];loo_models[#loo_models+1]={k=k,metric=selected.metric,weighting=selected.weighting,scaling=selected.scaling} end;a.loo=leave_one_out(loo_models,d.train,a.features)
local grid_lines={"k,metric,weighting,scaling,correct,accuracy,rmse"};for _,r in ipairs(a.results) do local m=r.model;grid_lines[#grid_lines+1]=format("%d,%s,%s,%s,%d,%s,%s",m.k,m.metric,m.weighting,m.scaling,r.correct,real(r.correct/#d.train),real(r.rmse)) end
local predictions={"id,label,vote_share,estimate"};for j,r in ipairs(d.test) do predictions[#predictions+1]=format("%s,%s,%s,%s",r.id,a.test_class[j].label,real(a.test_class[j].share),real(a.test_reg[j].estimate)) end
assert(os.execute("mkdir -p output"))
report.write("cv_grid.csv",grid_lines);report.write("predictions.csv",predictions);report.write("metrics.txt",a:metrics_lines());report.write("learning_curve.csv",a:learning_lines());report.write("prototypes.txt",a:prototype_lines())
