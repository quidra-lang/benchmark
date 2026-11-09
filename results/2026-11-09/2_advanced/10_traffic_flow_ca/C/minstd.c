#include "traffic.h"

i64 draw(Minstd *random) { random->state=48271*random->state%2147483647; return random->state; }
int select_weight(const int *weights,int count,i64 value) {
 int total=0; for(int i=0;i<count;i++) total+=weights[i]; i64 q=value%total;
 for(int i=0;i<count;i++) { if(q<weights[i]) return i; q-=weights[i]; }
 abort();
}
