#include "mining.h"
#include <stdlib.h>

static int64_t gcd(int64_t a,int64_t b){if(a<0)a=-a;while(b){int64_t r=a%b;a=b;b=r;}return a;}
Fraction fraction(int64_t n,int64_t d){if(d<0){n=-n;d=-d;}int64_t g=gcd(n,d);return (Fraction){n/g,d/g};}
int fraction_compare(Fraction a,Fraction b){int64_t x=a.n*b.d,y=b.n*a.d;return (x>y)-(x<y);}
Fraction fraction_subtract(Fraction a,Fraction b){return fraction(a.n*b.d-b.n*a.d,a.d*b.d);}
Fraction lift_of(int64_t total,int64_t together,int64_t first,int64_t second){return fraction(total*together,first*second);}
bool meets_thresholds(Fraction confidence,Fraction lift,const Params *p){return fraction_compare(confidence,p->confidence)>=0&&fraction_compare(lift,p->lift)>=0;}
Rule rule_metrics(Itemset set,Itemset x,Itemset y,int64_t count,int64_t total,int64_t nx,int64_t ny){Rule r={.set=set,.x=x,.y=y,.count=count,.support=fraction(count,total),.confidence=fraction(count,nx),.lift=lift_of(total,count,nx,ny),.leverage=fraction(total*count-nx*ny,total*total),.infinite=nx==count};if(!r.infinite)r.conviction=fraction((total-ny)*nx,total*(nx-count));return r;}
void append_rule(RuleSet *r,Rule rule){if(r->count==r->capacity){r->capacity=r->capacity?r->capacity*2:64;Rule *grown=realloc(r->values,(size_t)r->capacity*sizeof *grown);if(!grown)exit(1);r->values=grown;}r->values[r->count++]=rule;}
int compare_rules(const void *left,const void *right){const Rule *a=left,*b=right;int c=fraction_compare(a->confidence,b->confidence);if(c)return -c;c=fraction_compare(a->lift,b->lift);if(c)return -c;if(a->count!=b->count)return a->count>b->count?-1:1;c=compare_itemsets(a->x,b->x);return c?c:compare_itemsets(a->y,b->y);}
