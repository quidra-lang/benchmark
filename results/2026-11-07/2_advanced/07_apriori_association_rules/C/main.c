#include "mining.h"
#include <stdlib.h>
#include <string.h>

typedef struct {int64_t cases,covered,hit1,hit,baseline;} Evaluation;
typedef struct {
 char id[9];int basket_count,first,last;bool days[113],product_days[MAX_ITEMS][113];Mask purchased;
 int first_item[MAX_ITEMS],last_item[MAX_ITEMS];int64_t category_units[12],units,revenue;
} Customer;
typedef struct {
 Dataset data;Apriori frequent,category,training,testing;RuleSet rules,category_rules,train_rules,test_rules;Growth growth;
 Entries closed,maximal,generators;Customer customers[MAX_CUSTOMERS];int customer_count;
 int64_t buyers[MAX_ITEMS],heldout[MAX_ITEMS],hits[MAX_ITEMS],units[MAX_ITEMS],revenue[MAX_ITEMS],total_units,total_revenue;
 int first,last,multi_day,sequence_pairs,frequent_sequences,emerging,hold,fail,unseen;
 Evaluation evaluation[MAX_ITEMS+1],total_evaluation;Lines validation,sequence_lines;
} Analysis;
static Itemset singleton(int i){return (Itemset){.size=1,.ids={i}};}
static Itemset pair(int i,int j){if(i>j){int t=i;i=j;j=t;}return (Itemset){.size=2,.ids={i,j}};}
static int mask_count(Mask mask){int count=0;for(int i=0;i<MAX_ITEMS;i++)count+=mask_has(mask,i);return count;}
static Params read_params(void){
 FILE *file=fopen("input/params.txt","r");if(!file)exit(1);Params p={0};char name[64],value[64];while(fscanf(file,"%63s %63s",name,value)==2){int64_t n=strtoll(value,NULL,10);long long a,b;Fraction f={0};if(strchr(value,'/')){sscanf(value,"%lld/%lld",&a,&b);f=fraction(a,b);}
  if(!strcmp(name,"min_support"))p.minimum=n;else if(!strcmp(name,"min_confidence"))p.confidence=f;else if(!strcmp(name,"min_lift"))p.lift=f;else if(!strcmp(name,"max_size"))p.max_size=(int)n;else if(!strcmp(name,"category_min_support"))p.category_minimum=n;else if(!strcmp(name,"sequence_min_support"))p.sequence_minimum=n;else if(!strcmp(name,"split_day"))p.split=(int)n;else if(!strcmp(name,"train_min_support"))p.train_minimum=n;else if(!strcmp(name,"test_min_support"))p.test_minimum=n;else if(!strcmp(name,"recommend_top"))p.top=(int)n;else if(!strcmp(name,"matrix_size"))p.matrix=(int)n;else if(!strcmp(name,"group_min_lift"))p.group_lift=f;else if(!strcmp(name,"negative_max_lift"))p.negative_lift=f;else if(!strcmp(name,"negative_min_expected"))p.negative_expected=n;else if(!strcmp(name,"trend_threshold"))p.trend=f;
 }fclose(file);return p;
}
static int compare_products(const void *left,const void *right){const Product *a=left,*b=right;return strcmp(a->name,b->name);}
static int compare_names(const void *left,const void *right){return strcmp(left,right);}
static int product_index(const Dataset *d,const char *name){for(int j=0;j<d->product_ids.count;j++){int i=d->product_ids.values[j];if(!strcmp(d->names[i],name))return i;}return -1;}
static void read_data(Dataset *d){
 d->params=read_params();Product raw[80];int product_count=0;char categories[12][17];int category_count=0;Records rows=read_records("items.csv");d->item_rows=rows.count;
 for(int j=0;j<rows.count;j++){
  Record *row=&rows.rows[j];bool duplicate=false;for(int k=0;k<product_count;k++)if(!strcmp(raw[k].name,row->fields[0]))duplicate=true;int64_t price=strtoll(row->fields[2],NULL,10);
  if(duplicate){add_line(&d->errors,"items.csv line %d: duplicate item %s",j+2,row->fields[0]);continue;}if(!price){add_line(&d->errors,"items.csv line %d: bad price 0",j+2);continue;}
  Product *p=&raw[product_count++];strcpy(p->name,row->fields[0]);strcpy(p->category,row->fields[1]);p->price=price;bool seen=false;for(int k=0;k<category_count;k++)if(!strcmp(categories[k],p->category))seen=true;if(!seen)strcpy(categories[category_count++],p->category);
 }
 free(rows.rows);qsort(raw,(size_t)product_count,sizeof *raw,compare_products);qsort(categories,(size_t)category_count,sizeof *categories,compare_names);d->category_count=category_count;d->item_count=category_count+product_count;for(int i=0;i<MAX_ITEMS;i++)d->taxonomy[i]=-1;
 for(int i=0;i<category_count;i++){strcpy(d->names[i],categories[i]);d->category_ids.values[d->category_ids.count++]=i;}
 for(int j=0;j<product_count;j++){int i=category_count+j;d->products[i]=raw[j];strcpy(d->names[i],raw[j].name);d->product_ids.values[d->product_ids.count++]=i;for(int c=0;c<category_count;c++)if(!strcmp(raw[j].category,categories[c]))d->taxonomy[i]=c;}
 rows=read_records("transactions.csv");d->transaction_rows=rows.count;
 for(int j=0;j<rows.count;j++){
  Record *row=&rows.rows[j];char *tid=row->fields[0],*customer=row->fields[1],*name=row->fields[3];int day=atoi(row->fields[2]),index=-1;for(int k=0;k<d->transaction_count;k++)if(!strcmp(d->transactions[k].id,tid)){index=k;break;}
  if(index>=0&&index!=d->transaction_count-1){add_line(&d->errors,"transactions.csv line %d: tid %s not contiguous",j+2,tid);continue;}
  if(index<0){index=d->transaction_count++;Basket *b=&d->transactions[index];strcpy(b->id,tid);strcpy(b->customer,customer);b->day=day;}Basket *b=&d->transactions[index];
  if(strcmp(customer,b->customer)){add_line(&d->errors,"transactions.csv line %d: tid %s customer %s differs from %s",j+2,tid,customer,b->customer);continue;}
  if(day!=b->day){add_line(&d->errors,"transactions.csv line %d: tid %s day %d differs from %d",j+2,tid,day,b->day);continue;}
  int item=product_index(d,name);if(item<0){add_line(&d->errors,"transactions.csv line %d: unknown item %s",j+2,name);continue;}if(b->counts[item])d->duplicates++;b->counts[item]++;mask_add(&b->items,item);d->adopted++;
 }
 free(rows.rows);for(int j=0;j<d->transaction_count;j++){Basket *b=&d->transactions[j];if(!mask_count(b->items)){d->empty++;continue;}b->extended=extended_basket(b,d);d->baskets.values[d->baskets.count++]=b;BasketList *period=b->day<=d->params.split?&d->train:&d->test;period->values[period->count++]=b;}
}
static Apriori run_apriori(const Dataset *d,const BasketList *baskets,IDs universe,int64_t minimum,bool exclude){
 Apriori result={.total=baskets->count};Entries previous={0};
 for(int size=1;size<=d->params.max_size;size++){
  Candidates candidates={0};if(size==1){candidates.joined=candidates.count=universe.count;candidates.values=calloc((size_t)universe.count,sizeof *candidates.values);if(universe.count&&!candidates.values)exit(1);for(int j=0;j<universe.count;j++)candidates.values[j]=singleton(universe.values[j]);}
  else{if(!previous.count)break;candidates=generate_candidates(&previous,size,d,exclude);}Entries frequent=count_candidates(&candidates,baskets,minimum,exclude);result.levels[result.level_count++]=(Level){size,candidates.joined,candidates.excluded,candidates.pruned,candidates.count,frequent};for(int j=0;j<frequent.count;j++)append_entry(&result.entries,frequent.values[j]);previous=frequent;free(candidates.values);
 }
 return result;
}
static int64_t frequent_count(const Apriori *g,Itemset set){return set.size?entry_count(&g->entries,set):g->total;}
static RuleSet make_rules(const Dataset *d,const Apriori *g,bool category){
 RuleSet result={0};for(int j=0;j<g->entries.count;j++){
  Entry e=g->entries.values[j];if(e.set.size<2||(category&&e.set.ids[0]>=d->category_count))continue;unsigned full=(1u<<e.set.size)-1;
  for(unsigned mask=1;mask<full;mask++){result.generated++;Itemset x=select_items(e.set,mask),y=select_items(e.set,full^mask);Rule r=rule_metrics(e.set,x,y,e.count,g->total,frequent_count(g,x),frequent_count(g,y));if(!meets_thresholds(r.confidence,r.lift,&d->params))continue;Fraction best=fraction(0,1);for(unsigned part=0;part<(1u<<x.size)-1;part++){Itemset w=select_items(x,part);Fraction confidence=fraction(frequent_count(g,set_union(w,y)),frequent_count(g,w));if(fraction_compare(confidence,best)>0)best=confidence;}r.improvement=fraction_subtract(r.confidence,best);result.productive+=r.improvement.n>0;append_rule(&result,r);}
 }
 if(result.count>1)qsort(result.values,(size_t)result.count,sizeof *result.values,compare_rules);for(int j=0;j<result.count;j++)result.values[j].rank=j+1;return result;
}
static void classify(Analysis *a){
 for(int j=0;j<a->frequent.entries.count;j++){
  Entry x=a->frequent.entries.values[j];bool closed=true,maximal=true,generator=true;for(int k=0;k<a->frequent.entries.count;k++){Entry y=a->frequent.entries.values[k];if(y.set.size>x.set.size&&subset(x.set,y.set)){maximal=false;if(x.count==y.count)closed=false;}}
  for(int k=0;k<x.set.size;k++)if(frequent_count(&a->frequent,remove_item(x.set,k))<=x.count){generator=false;break;}if(closed)append_entry(&a->closed,x);if(maximal)append_entry(&a->maximal,x);if(generator)append_entry(&a->generators,x);
 }
}
static int compare_customers(const void *left,const void *right){const Customer *a=left,*b=right;return strcmp(a->id,b->id);}
static void build_customers(Analysis *a){
 Dataset *d=&a->data;a->first=113;
 for(int j=0;j<d->baskets.count;j++){
  Basket *b=d->baskets.values[j];int index=-1;for(int k=0;k<a->customer_count;k++)if(!strcmp(a->customers[k].id,b->customer)){index=k;break;}if(index<0){index=a->customer_count++;Customer *c=&a->customers[index];strcpy(c->id,b->customer);c->first=113;for(int i=0;i<MAX_ITEMS;i++)c->first_item[i]=113;}
  Customer *c=&a->customers[index];c->basket_count++;c->days[b->day]=true;if(b->day<c->first)c->first=b->day;if(b->day>c->last)c->last=b->day;if(b->day<a->first)a->first=b->day;if(b->day>a->last)a->last=b->day;
  for(int k=0;k<d->product_ids.count;k++){int i=d->product_ids.values[k];int64_t units=b->counts[i];if(!units)continue;mask_add(&c->purchased,i);c->product_days[i][b->day]=true;if(b->day<c->first_item[i])c->first_item[i]=b->day;if(b->day>c->last_item[i])c->last_item[i]=b->day;c->category_units[d->taxonomy[i]]+=units;int64_t revenue=units*d->products[i].price;c->units+=units;c->revenue+=revenue;a->units[i]+=units;a->revenue[i]+=revenue;a->total_units+=units;a->total_revenue+=revenue;}
 }
 if(a->customer_count>1)qsort(a->customers,(size_t)a->customer_count,sizeof *a->customers,compare_customers);for(int j=0;j<a->customer_count;j++){Customer *c=&a->customers[j];int days=0;for(int day=1;day<=112;day++)days+=c->days[day];a->multi_day+=days>=2;for(int k=0;k<d->product_ids.count;k++){int i=d->product_ids.values[k];a->buyers[i]+=mask_has(c->purchased,i);}}
}
static int compare_ints(const void *left,const void *right){int a=*(const int *)left,b=*(const int *)right;return (a>b)-(a<b);}
static Fraction median(int *values,int count){if(count>1)qsort(values,(size_t)count,sizeof *values,compare_ints);return count%2?fraction(values[count/2],1):fraction(values[count/2-1]+values[count/2],2);}
static int minimum_gap(const Customer *c,int first,int second){int best=113,y=1;for(int x=1;x<=112;x++)if(c->product_days[first][x]){if(y<=x)y=x+1;while(y<=112&&!c->product_days[second][y])y++;if(y<=112&&y-x<best)best=y-x;}return best;}
typedef struct {int first,second,count;Fraction confidence,lift,gap;} Sequence;
typedef struct {int item,customers,count,minimum,maximum;Fraction mean,median;} Repeat;
static int compare_sequences(const void *left,const void *right){const Sequence *a=left,*b=right;if(a->count!=b->count)return a->count>b->count?-1:1;int c=fraction_compare(a->confidence,b->confidence);if(c)return -c;if(a->first!=b->first)return a->first-b->first;return a->second-b->second;}
static int compare_repeats(const void *left,const void *right){const Repeat *a=left,*b=right;int c=fraction_compare(a->mean,b->mean);return c?c:a->item-b->item;}
static void sequences(Analysis *a){
 Dataset *d=&a->data;Sequence *seqs=malloc(3600*sizeof *seqs);if(!seqs)exit(1);int seq_count=0;Repeat repeats[60];int repeat_count=0;
 for(int p=0;p<d->product_ids.count;p++){
  int i=d->product_ids.values[p];for(int q=0;q<d->product_ids.count;q++){int j=d->product_ids.values[q],gaps[MAX_CUSTOMERS],count=0;for(int k=0;k<a->customer_count;k++){Customer *c=&a->customers[k];if(c->first_item[i]<c->last_item[j])gaps[count++]=minimum_gap(c,i,j);}a->sequence_pairs+=count>0;if(count>=d->params.sequence_minimum)seqs[seq_count++]=(Sequence){i,j,count,fraction(count,a->buyers[i]),fraction((int64_t)count*a->customer_count,a->buyers[i]*a->buyers[j]),median(gaps,count)};}
  int intervals[MAX_BASKETS],count=0,customers=0;int64_t total=0;for(int k=0;k<a->customer_count;k++){Customer *c=&a->customers[k];int previous=0,found=0;for(int day=1;day<=112;day++)if(c->product_days[i][day]){if(previous){int gap=day-previous;intervals[count++]=gap;total+=gap;found++;}previous=day;}customers+=found>0;}
  if(count){Fraction middle=median(intervals,count);repeats[repeat_count++]=(Repeat){i,customers,count,intervals[0],intervals[count-1],fraction(total,count),middle};}
 }
 if(seq_count>1)qsort(seqs,(size_t)seq_count,sizeof *seqs,compare_sequences);a->frequent_sequences=seq_count;
 for(int j=0;j<seq_count;j++){Sequence s=seqs[j];add_line(&a->sequence_lines,"SEQ %d %s -> %s customers %d base %lld confidence %s lift %s gap %s",j+1,d->names[s.first],d->names[s.second],s.count,(long long)a->buyers[s.first],fraction_text(s.confidence),fraction_text(s.lift),fraction_text(s.gap));}
 if(repeat_count>1)qsort(repeats,(size_t)repeat_count,sizeof *repeats,compare_repeats);for(int j=0;j<repeat_count;j++){Repeat r=repeats[j];add_line(&a->sequence_lines,"REPEAT %s customers %d intervals %d min %d max %d mean %s median %s",d->names[r.item],r.customers,r.count,r.minimum,r.maximum,fraction_text(r.mean),fraction_text(r.median));}free(seqs);
}
static IDs recommendations(Mask held,const int *candidates,int count,int top){IDs out={0};Mask selected={0};for(int j=0;j<count;j++){int i=candidates[j];if(mask_has(held,i)||mask_has(selected,i))continue;mask_add(&selected,i);out.values[out.count++]=i;if(out.count==top)break;}return out;}
static IDs rule_recommendation(const RuleSet *rules,Mask held,int top){IDs out={0};Mask selected={0};for(int j=0;j<rules->count;j++){Rule r=rules->values[j];if(r.y.size!=1||!contains(held,r.x))continue;int i=r.y.ids[0];if(mask_has(held,i)||mask_has(selected,i))continue;mask_add(&selected,i);out.values[out.count++]=i;if(out.count==top)break;}return out;}
static bool has_id(IDs ids,int id){for(int j=0;j<ids.count;j++)if(ids.values[j]==id)return true;return false;}
static IDs ranked_ids(IDs ids,const int64_t *values){for(int j=1;j<ids.count;j++){int i=ids.values[j],k=j;while(k>0){int previous=ids.values[k-1];if(values[previous]>values[i]||(values[previous]==values[i]&&previous<i))break;ids.values[k]=previous;k--;}ids.values[k]=i;}return ids;}
static IDs popular(const Dataset *d,const BasketList *baskets,IDs ids,bool extended){int64_t counts[MAX_ITEMS]={0};for(int j=0;j<ids.count;j++){int i=ids.values[j];counts[i]=support_count(baskets,singleton(i),extended);}return ranked_ids(ids,counts);}
static void add_evaluation(Evaluation *a,Evaluation b){a->cases+=b.cases;a->covered+=b.covered;a->hit1+=b.hit1;a->hit+=b.hit;a->baseline+=b.baseline;}
static const char *evaluation_text(Evaluation e){static char buffers[4][512];static unsigned next;char *text=buffers[next++%4];snprintf(text,512,"cases %lld covered %lld hit1 %lld hit %lld rate %s baseline %lld rate %s",(long long)e.cases,(long long)e.covered,(long long)e.hit1,(long long)e.hit,fraction_text(fraction(e.hit,e.cases)),(long long)e.baseline,fraction_text(fraction(e.baseline,e.cases)));return text;}
static bool same_rule(Rule a,Rule b){return !compare_itemsets(a.x,b.x)&&!compare_itemsets(a.y,b.y);}
static void validate(Analysis *a){
 Dataset *d=&a->data;Params *p=&d->params;
 for(int j=0;j<a->train_rules.count;j++){
  Rule r=a->train_rules.values[j];int64_t nx=support_count(&d->test,r.x,false),ny=support_count(&d->test,r.y,false),nz=support_count(&d->test,r.set,false);const char *confidence="-",*lift="-",*verdict="UNSEEN";
  if(!nx||!ny)a->unseen++;else{Fraction c=fraction(nz,nx),l=lift_of(d->test.count,nz,nx,ny);confidence=fraction_text(c);lift=fraction_text(l);if(meets_thresholds(c,l,p)){verdict="HOLD";a->hold++;}else{verdict="FAIL";a->fail++;}}
  add_line(&a->validation,"RULE %d %s train %lld confidence %s lift %s test %lld of %lld confidence %s lift %s %s",r.rank,rule_arrow(r,d),(long long)r.count,fraction_text(r.confidence),fraction_text(r.lift),(long long)nz,(long long)nx,confidence,lift,verdict);
 }
 for(int j=0;j<a->test_rules.count;j++){Rule r=a->test_rules.values[j];bool found=false;for(int k=0;k<a->train_rules.count;k++)if(same_rule(r,a->train_rules.values[k])){found=true;break;}if(!found){a->emerging++;add_line(&a->validation,"EMERGING %d %s test %lld confidence %s lift %s",r.rank,rule_arrow(r,d),(long long)r.count,fraction_text(r.confidence),fraction_text(r.lift));}}
 add_line(&a->validation,"VALIDATION train %d test %d itemsets %d rules %d hold %d fail %d unseen %d emerging %d",d->train.count,d->test.count,a->training.entries.count,a->train_rules.count,a->hold,a->fail,a->unseen,a->emerging);IDs popularity=popular(d,&d->train,d->product_ids,false);
 for(int j=0;j<d->test.count;j++){Basket *b=d->test.values[j];int size=mask_count(b->items);if(size<2)continue;for(int k=0;k<d->product_ids.count;k++){int h=d->product_ids.values[k];if(!mask_has(b->items,h))continue;Mask held=b->items;held.words[h/64]&=~(UINT64_C(1)<<(h%64));IDs rec=rule_recommendation(&a->train_rules,held,p->top),baseline=recommendations(held,popularity.values,popularity.count,p->top);Evaluation e={.cases=1,.covered=rec.count>0,.hit1=rec.count&&rec.values[0]==h,.hit=has_id(rec,h),.baseline=has_id(baseline,h)};a->heldout[h]++;a->hits[h]+=e.hit;add_evaluation(&a->evaluation[size],e);add_evaluation(&a->total_evaluation,e);}}
 for(int size=1;size<=MAX_ITEMS;size++)if(a->evaluation[size].cases)add_line(&a->validation,"RECOMMEND size %d %s",size,evaluation_text(a->evaluation[size]));add_line(&a->validation,"RECOMMEND total %s",evaluation_text(a->total_evaluation));
}
static Lines summary_lines(const Analysis *a){
 const Dataset *d=&a->data;Lines lines={0};for(int j=0;j<d->errors.count;j++)add_line(&lines,"ERROR %s",d->errors.values[j]);int64_t sizes[MAX_ITEMS+1]={0},total=0;int largest=0;for(int j=0;j<d->baskets.count;j++){int size=mask_count(d->baskets.values[j]->items);sizes[size]++;total+=size;if(size>largest)largest=size;}
 add_line(&lines,"ITEMS rows %d adopted %d categories %d",d->item_rows,d->product_ids.count,d->category_count);add_line(&lines,"TRANSACTIONS lines %d adopted %d rejected %d duplicates %d transactions %d empty %d",d->transaction_rows,d->adopted,d->transaction_rows-d->adopted,d->duplicates,d->transaction_count,d->empty);add_line(&lines,"BASKETS count %d customers %d first_day %d last_day %d average_size %s largest %d",d->baskets.count,a->customer_count,a->first,a->last,fraction_text(fraction(total,d->baskets.count)),largest);
 for(int size=1;size<=largest;size++)add_line(&lines,"SIZE %d baskets %lld share %s",size,(long long)sizes[size],percentage(sizes[size],d->baskets.count));add_line(&lines,"FREQUENT itemsets %d closed %d maximal %d generators %d levels %d",a->frequent.entries.count,a->closed.count,a->maximal.count,a->generators.count,a->frequent.level_count);
 bool same=a->frequent.entries.count==a->growth.entries.count;for(int j=0;j<a->frequent.entries.count;j++){Entry e=a->frequent.entries.values[j];if(entry_count(&a->growth.entries,e.set)!=e.count)same=false;}Growth g=a->growth;add_line(&lines,"FPGROWTH header %d nodes %d conditional_trees %d conditional_nodes %d itemsets %d %s",g.header,g.nodes,g.trees,g.conditional_nodes,g.entries.count,same?"MATCH":"MISMATCH");
 if(!same){for(int j=0;j<a->frequent.entries.count;j++){Entry e=a->frequent.entries.values[j];if(entry_count(&g.entries,e.set)!=e.count)add_line(&lines,"ONLY_APRIORI %s %lld",itemset_text(e.set,d),(long long)e.count);}for(int j=0;j<g.entries.count;j++){Entry e=g.entries.values[j];if(entry_count(&a->frequent.entries,e.set)!=e.count)add_line(&lines,"ONLY_FPGROWTH %s %lld",itemset_text(e.set,d),(long long)e.count);}}
 add_line(&lines,"RULES generated %d passed %d productive %d",a->rules.generated,a->rules.count,a->rules.productive);for(int j=0;j<a->category.level_count;j++){Level l=a->category.levels[j];add_line(&lines,"CATEGORY_LEVEL %d candidates %d taxonomy %d pruned %d counted %d frequent %d",l.size,l.joined,l.excluded,l.pruned,l.counted,l.frequent.count);}add_line(&lines,"CATEGORY_RULES itemsets %d generated %d passed %d productive %d",a->category.entries.count,a->category_rules.generated,a->category_rules.count,a->category_rules.productive);add_line(&lines,"SEQUENCES customers %d multi_day %d pairs %d frequent %d",a->customer_count,a->multi_day,a->sequence_pairs,a->frequent_sequences);return lines;
}
static Lines itemset_lines(const Analysis *a){Lines lines={0};for(int j=0;j<a->frequent.level_count;j++){Level l=a->frequent.levels[j];add_line(&lines,"LEVEL %d candidates %d pruned %d counted %d frequent %d",l.size,l.joined,l.pruned,l.counted,l.frequent.count);for(int k=0;k<l.frequent.count;k++){Entry e=l.frequent.values[k];add_line(&lines,"%s %lld",itemset_text(e.set,&a->data),(long long)e.count);}}return lines;}
static Lines closed_lines(const Analysis *a){Lines lines={0};Entries entries[3]={a->closed,a->maximal,a->generators};const char *labels[3]={"CLOSED","MAXIMAL","GENERATOR"};for(int j=0;j<3;j++)for(int k=0;k<entries[j].count;k++){Entry e=entries[j].values[k];add_line(&lines,"%s %s %lld",labels[j],itemset_text(e.set,&a->data),(long long)e.count);}return lines;}
static Lines matrix_lines(const Dataset *d,IDs ids,const BasketList *baskets,bool extended,const char *label){
 Lines lines={0};for(int j=0;j<ids.count;j++){int i=ids.values[j];add_line(&lines,"%s %d %s baskets %lld",label,j+1,d->names[i],(long long)support_count(baskets,singleton(i),extended));}char row[1024];strcpy(row,"    ");for(int j=0;j<ids.count;j++)snprintf(row+strlen(row),sizeof row-strlen(row),"%7d",j+1);add_line(&lines,"%s",row);
 for(int j=0;j<ids.count;j++){int i=ids.values[j];snprintf(row,sizeof row,"%4d",j+1);for(int k=0;k<ids.count;k++){int other=ids.values[k];if(i==other)snprintf(row+strlen(row),sizeof row-strlen(row),"%7s","-");else{int64_t cell=100LL*baskets->count*support_count(baskets,pair(i,other),extended)/(support_count(baskets,singleton(i),extended)*support_count(baskets,singleton(other),extended));snprintf(row+strlen(row),sizeof row-strlen(row),"%7lld",(long long)cell);}}add_line(&lines,"%s",row);}return lines;
}
typedef struct {int first,second;int64_t count;Fraction expected,lift;} Substitute;
static int compare_substitutes(const void *left,const void *right){const Substitute *a=left,*b=right;int c=fraction_compare(a->lift,b->lift);if(c)return c;c=fraction_compare(a->expected,b->expected);if(c)return -c;if(a->first!=b->first)return a->first-b->first;return a->second-b->second;}
static Lines relationship_lines(const Analysis *a){
 const Dataset *d=&a->data;Lines lines={0};bool adj[MAX_ITEMS][MAX_ITEMS]={0},visited[MAX_ITEMS]={0};int degrees[MAX_ITEMS]={0};int64_t supports[MAX_ITEMS]={0};for(int j=0;j<d->product_ids.count;j++){int i=d->product_ids.values[j];supports[i]=support_count(&d->baskets,singleton(i),false);}
 for(int j=0;j<a->frequent.entries.count;j++){Entry e=a->frequent.entries.values[j];if(e.set.size!=2)continue;int i=e.set.ids[0],other=e.set.ids[1];Fraction lift=lift_of(d->baskets.count,e.count,supports[i],supports[other]);if(fraction_compare(lift,d->params.group_lift)>=0){adj[i][other]=adj[other][i]=true;degrees[i]++;degrees[other]++;}}
 IDs groups[60];int group_count=0;
 for(int j=0;j<d->product_ids.count;j++){int i=d->product_ids.values[j];if(!degrees[i]||visited[i])continue;IDs group={0},queue={.count=1,.values={i}};visited[i]=true;int first=0;while(first<queue.count){int x=queue.values[first++];group.values[group.count++]=x;for(int k=0;k<d->product_ids.count;k++){int y=d->product_ids.values[k];if(adj[x][y]&&!visited[y]){visited[y]=true;queue.values[queue.count++]=y;}}}if(group.count>1)qsort(group.values,(size_t)group.count,sizeof *group.values,compare_ints);groups[group_count++]=group;}
 for(int j=1;j<group_count;j++){IDs value=groups[j];int k=j;while(k>0&&(groups[k-1].count<value.count||(groups[k-1].count==value.count&&groups[k-1].values[0]>value.values[0]))){groups[k]=groups[k-1];k--;}groups[k]=value;}
 for(int j=0;j<group_count;j++){IDs group=groups[j];int core=group.values[0],edges=0;int64_t revenue=0;for(int k=0;k<group.count;k++){int i=group.values[k];edges+=degrees[i];revenue+=a->revenue[i];if(degrees[i]>degrees[core]||(degrees[i]==degrees[core]&&supports[i]>supports[core]))core=i;}add_line(&lines,"GROUP %d items %d edges %d core %s revenue %s share %s members %s",j+1,group.count,edges/2,d->names[core],money(revenue),percentage(revenue,a->total_revenue),ids_text(group.values,group.count,d));}
 Substitute *substitutes=malloc(1770*sizeof *substitutes);if(!substitutes)exit(1);int count=0;Entries singles=a->frequent.levels[0].frequent;
 for(int j=0;j<singles.count;j++)for(int k=j+1;k<singles.count;k++){int i=singles.values[j].set.ids[0],other=singles.values[k].set.ids[0];int64_t expected=supports[i]*supports[other];if(expected<d->params.negative_expected*d->baskets.count)continue;int64_t together=support_count(&d->baskets,pair(i,other),false);Fraction lift=lift_of(d->baskets.count,together,supports[i],supports[other]);if(fraction_compare(lift,d->params.negative_lift)<=0)substitutes[count++]=(Substitute){i,other,together,fraction(expected,d->baskets.count),lift};}
 if(count>1)qsort(substitutes,(size_t)count,sizeof *substitutes,compare_substitutes);for(int j=0;j<count;j++){Substitute s=substitutes[j];add_line(&lines,"SUBSTITUTE %s %s count %lld expected %s lift %s",d->names[s.first],d->names[s.second],(long long)s.count,fraction_text(s.expected),fraction_text(s.lift));}free(substitutes);
 IDs product_matrix=popular(d,&d->baskets,d->product_ids,false);product_matrix.count=d->params.matrix;Lines matrix=matrix_lines(d,product_matrix,&d->baskets,false,"MATRIX");append_lines(&lines,&matrix);IDs category_matrix=popular(d,&d->baskets,d->category_ids,true);matrix=matrix_lines(d,category_matrix,&d->baskets,true,"CATEGORY_MATRIX");append_lines(&lines,&matrix);return lines;
}
static bool set_has(Itemset set,int item){for(int j=0;j<set.size;j++)if(set.ids[j]==item)return true;return false;}
static Lines items_report(const Analysis *a){
 const Dataset *d=&a->data;Lines lines={0};IDs ranked=ranked_ids(d->product_ids,a->revenue);int64_t category_revenue[MAX_ITEMS]={0},category_units[MAX_ITEMS]={0};int category_items[MAX_ITEMS]={0};
 for(int j=0;j<ranked.count;j++){
  int i=ranked.values[j],sets=0,partner=-1;Product p=d->products[i];int64_t count=support_count(&d->baskets,singleton(i),false),partner_count=0;Fraction partner_lift=fraction(0,1);
  for(int k=0;k<a->frequent.entries.count;k++){Entry e=a->frequent.entries.values[k];if(!set_has(e.set,i))continue;sets++;if(e.set.size==2){int other=e.set.ids[0]==i?e.set.ids[1]:e.set.ids[0];Fraction lift=lift_of(d->baskets.count,e.count,count,support_count(&d->baskets,singleton(other),false));int c=fraction_compare(lift,partner_lift);if(partner<0||c>0||(c==0&&(e.count>partner_count||(e.count==partner_count&&other<partner)))){partner=other;partner_count=e.count;partner_lift=lift;}}}
  char partner_text[256]="none",best[256]="none";if(partner>=0)snprintf(partner_text,sizeof partner_text,"%s %s",d->names[partner],fraction_text(partner_lift));for(int k=0;k<a->rules.count;k++){Rule r=a->rules.values[k];if(set_has(r.set,i)){snprintf(best,sizeof best,"%d %s",r.rank,rule_arrow(r,d));break;}}
  add_line(&lines,"ITEM %d %s %s price %s units %lld revenue %s share %s baskets %lld support %s customers %lld itemsets %d heldout %lld hits %lld partner %s best %s",j+1,p.name,p.category,money(p.price),(long long)a->units[i],money(a->revenue[i]),percentage(a->revenue[i],a->total_revenue),(long long)count,fraction_text(fraction(count,d->baskets.count)),(long long)a->buyers[i],sets,(long long)a->heldout[i],(long long)a->hits[i],partner_text,best);int category=d->taxonomy[i];category_revenue[category]+=a->revenue[i];category_units[category]+=a->units[i];category_items[category]++;
 }
 IDs categories=ranked_ids(d->category_ids,category_revenue);for(int j=0;j<categories.count;j++){int i=categories.values[j];int64_t count=support_count(&d->baskets,singleton(i),true);add_line(&lines,"CATEGORY %s items %d units %lld revenue %s share %s baskets %lld support %s",d->names[i],category_items[i],(long long)category_units[i],money(category_revenue[i]),percentage(category_revenue[i],a->total_revenue),(long long)count,fraction_text(fraction(count,d->baskets.count)));}
 add_line(&lines,"TOTAL items %d units %lld revenue %s baskets %d customers %d",d->product_ids.count,(long long)a->total_units,money(a->total_revenue),d->baskets.count,a->customer_count);Lines relationships=relationship_lines(a);append_lines(&lines,&relationships);return lines;
}
static void table_row(Lines *lines,const char *label,const int64_t *values,int count){char row[1024];snprintf(row,sizeof row,"%-17s",label);for(int j=0;j<count;j++)snprintf(row+strlen(row),sizeof row-strlen(row),"%6lld",(long long)values[j]);add_line(lines,"%s",row);}
typedef struct {int item;int64_t units;Fraction slope,relative;bool has_relative;const char *verdict;} Trend;
static int compare_trends(const void *left,const void *right){const Trend *a=left,*b=right;if(a->has_relative!=b->has_relative)return a->has_relative?-1:1;if(a->has_relative){int c=fraction_compare(a->relative,b->relative);if(c)return -c;}return a->item-b->item;}
static Lines trend_lines(const Analysis *a){
 const Dataset *d=&a->data;int weeks=(a->last-1)/7+1;int64_t week_numbers[16]={0},basket_counts[16]={0},units[16]={0},customers[16]={0},series[MAX_ITEMS][16]={0};bool customer_week[MAX_CUSTOMERS][16]={0};
 for(int w=0;w<weeks;w++)week_numbers[w]=w+1;
 for(int j=0;j<d->baskets.count;j++){Basket *b=d->baskets.values[j];int w=(b->day-1)/7;basket_counts[w]++;for(int k=0;k<a->customer_count;k++)if(!strcmp(b->customer,a->customers[k].id)){customer_week[k][w]=true;break;}for(int k=0;k<d->product_ids.count;k++){int i=d->product_ids.values[k];units[w]+=b->counts[i];series[i][w]+=b->counts[i];series[d->taxonomy[i]][w]+=b->counts[i];}}
 for(int w=0;w<weeks;w++)for(int j=0;j<a->customer_count;j++)customers[w]+=customer_week[j][w];Lines lines={0};table_row(&lines,"WEEK",week_numbers,weeks);table_row(&lines,"BASKETS",basket_counts,weeks);table_row(&lines,"UNITS",units,weeks);table_row(&lines,"CUSTOMERS",customers,weeks);
 int64_t sw=0,sw2=0;for(int w=1;w<=weeks;w++){sw+=w;sw2+=w*w;}int64_t denominator=weeks*sw2-sw*sw;Trend trends[MAX_ITEMS];
 for(int i=0;i<d->item_count;i++){table_row(&lines,d->names[i],series[i],weeks);int64_t total=0,weighted=0;for(int w=0;w<weeks;w++){total+=series[i][w];weighted+=(w+1)*series[i][w];}Fraction slope=fraction(weeks*weighted-sw*total,denominator);Trend t={.item=i,.units=total,.slope=slope,.has_relative=total>0,.verdict="NONE"};if(total){t.relative=fraction(slope.n*weeks,slope.d*total);t.verdict="FLAT";if(fraction_compare(t.relative,d->params.trend)>=0)t.verdict="RISING";else if(fraction_compare(t.relative,fraction(-d->params.trend.n,d->params.trend.d))<=0)t.verdict="FALLING";}trends[i]=t;}
 if(d->item_count>1)qsort(trends,(size_t)d->item_count,sizeof *trends,compare_trends);for(int j=0;j<d->item_count;j++){Trend t=trends[j];add_line(&lines,"TREND %s units %lld slope %s relative %s %s",d->names[t.item],(long long)t.units,fraction_text(t.slope),t.has_relative?fraction_text(t.relative):"-",t.verdict);}return lines;
}
static Lines customer_lines(const Analysis *a){
 const Dataset *d=&a->data;Lines lines={0};const char *segments[4]={"NEW","LOYAL","AT_RISK","REGULAR"};int counts[4]={0};int64_t revenues[4]={0};
 for(int j=0;j<a->customer_count;j++){const Customer *c=&a->customers[j];int favorite=0,days=0;for(int i=1;i<d->category_count;i++)if(c->category_units[i]>c->category_units[favorite])favorite=i;for(int day=1;day<=112;day++)days+=c->days[day];int segment=3;if(c->first>a->last-28)segment=0;else if(c->basket_count>=4&&a->last-c->last<=14)segment=1;else if(a->last-c->last>28)segment=2;counts[segment]++;revenues[segment]+=c->revenue;IDs offer=rule_recommendation(&a->rules,c->purchased,d->params.top);add_line(&lines,"CUSTOMER %s baskets %d days %d first %d last %d items %d units %lld revenue %s average %s favorite %s segment %s offer %s",c->id,c->basket_count,days,c->first,c->last,mask_count(c->purchased),(long long)c->units,money(c->revenue),money(c->revenue/c->basket_count),d->names[favorite],segments[segment],offer.count?ids_text(offer.values,offer.count,d):"none");}
 for(int j=0;j<4;j++)add_line(&lines,"SEGMENT %s customers %d revenue %s share %s",segments[j],counts[j],money(revenues[j]),percentage(revenues[j],a->total_revenue));return lines;
}
int main(void){
 Analysis *a=calloc(1,sizeof *a);if(!a)return 1;read_data(&a->data);Dataset *d=&a->data;Params *p=&d->params;IDs universe={0};for(int i=0;i<d->item_count;i++)universe.values[universe.count++]=i;
 a->frequent=run_apriori(d,&d->baskets,d->product_ids,p->minimum,false);a->category=run_apriori(d,&d->baskets,universe,p->category_minimum,true);a->training=run_apriori(d,&d->train,d->product_ids,p->train_minimum,false);a->testing=run_apriori(d,&d->test,d->product_ids,p->test_minimum,false);a->growth=fp_growth(&d->baskets,p->minimum,p->max_size,d->item_count);classify(a);a->rules=make_rules(d,&a->frequent,false);a->category_rules=make_rules(d,&a->category,true);a->train_rules=make_rules(d,&a->training,false);a->test_rules=make_rules(d,&a->testing,false);build_customers(a);sequences(a);validate(a);
 const char *names[10]={"summary.txt","itemsets.txt","closed_maximal.txt","rules.csv","category_rules.csv","sequences.txt","validation.txt","items_report.txt","trends.txt","customers.txt"};Lines reports[10]={summary_lines(a),itemset_lines(a),closed_lines(a),rules_csv(&a->rules,d),rules_csv(&a->category_rules,d),a->sequence_lines,a->validation,items_report(a),trend_lines(a),customer_lines(a)};for(int j=0;j<10;j++)write_report(names[j],&reports[j]);return 0;
}
