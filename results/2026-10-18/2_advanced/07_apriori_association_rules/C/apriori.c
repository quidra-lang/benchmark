#include "mining.h"
#include <stdlib.h>

static void append_candidate(Candidates *r,Itemset set){if(r->count==r->capacity){r->capacity=r->capacity?r->capacity*2:64;Itemset *grown=realloc(r->values,(size_t)r->capacity*sizeof *grown);if(!grown)exit(1);r->values=grown;}r->values[r->count++]=set;}
Candidates generate_candidates(const Entries *previous,int size,const Dataset *d,bool exclude){
 Candidates r={0};for(int j=0;j<previous->count;j++)for(int k=j+1;k<previous->count;k++){
  Itemset a=previous->values[j].set,b=previous->values[k].set;bool same=true;for(int p=0;p<size-2;p++)if(a.ids[p]!=b.ids[p]){same=false;break;}if(!same)break;Itemset set=a;set.ids[set.size++]=b.ids[b.size-1];r.joined++;
  if(exclude&&size==2&&(d->taxonomy[set.ids[0]]==set.ids[1]||d->taxonomy[set.ids[1]]==set.ids[0])){r.excluded++;continue;}
  bool pruned=false;for(int p=0;p<set.size;p++)if(!entry_count(previous,remove_item(set,p))){pruned=true;break;}if(pruned)r.pruned++;else append_candidate(&r,set);
 }
 return r;
}
Entries count_candidates(const Candidates *c,const BasketList *baskets,int64_t minimum,bool extended){Entries result={0};for(int j=0;j<c->count;j++){int64_t count=support_count(baskets,c->values[j],extended);if(count>=minimum)append_entry(&result,(Entry){c->values[j],count});}return result;}
