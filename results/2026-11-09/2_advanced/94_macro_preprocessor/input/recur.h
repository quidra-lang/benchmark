/* recur.h: includes itself until the nesting limit */
level(__COUNTER__);
#include "recur.h"
