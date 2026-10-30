import java.io.File
class Rbac {
    data class Permission(val action: String,val type: String): Comparable<Permission> {
        override fun compareTo(other: Permission)=compareValuesBy(this,other,Permission::action,Permission::type)
    }
    data class Grant(val role: String,val action: String,val type: String): Comparable<Grant> {
        override fun compareTo(other: Grant)=compareValuesBy(this,other,Grant::role,Grant::action,Grant::type)
    }
    data class Constraint(val name: String,val cardinality: Int,val roles: Set<String>)
    data class Assignment(val user: String,val role: String,val first: Int,val last: Int)
    data class Diagnostic(val line: Int,val keyword: String,val message: String)
    data class Line(val number: Int,val fields: List<String>)
    val roles=sortedSetOf<String>();
    val inherits=mutableMapOf<String,MutableSet<String>>();
    val permissions=mutableMapOf<String,MutableSet<Permission>>();
    val ssd=mutableListOf<Constraint>();
    val dsd=mutableListOf<Constraint>();
    val assignments=mutableListOf<Assignment>();
    val diagnostics=mutableListOf<Diagnostic>();
    val grants=sortedSetOf<Grant>()
    init {
        val lines=File("input/rbac.txt").readLines().mapIndexed {
            i,line->Line(i+1,line.split(' '))
        };
        for(keyword in listOf("ROLE","INHERITS","PERMIT","SSD","DSD","ASSIGN"))for(line in lines)if(line.fields[0]==keyword) {
            val error=accept(keyword,line.fields.drop(1));
            if(error!=null)diagnostics.add(Diagnostic(line.number,keyword,error))
        };
        diagnostics.sortBy {
            it.line
        }
    }
    fun closure(initial: Collection<String>): java.util.SortedSet<String> {
        val reached=initial.toSortedSet();
        val pending=ArrayDeque(initial);
        while(pending.isNotEmpty())for(junior in inherits.getValue(pending.removeLast()))if(reached.add(junior))pending.add(junior);
        return reached
    }
    fun path(start: String,finish: String,failed: MutableSet<String>): MutableList<String>? {
        if(start==finish)return mutableListOf(start);
        if(start in failed)return null;
        for(junior in inherits.getValue(start).sorted()) {
            val suffix=path(junior,finish,failed);
            if(suffix!=null) {
                suffix.add(0,start);
                return suffix
            }
        };
        failed.add(start);
        return null
    }
    fun assigned(user: String,day: Int)=assignments.filter {
        it.user==user&&it.first<=day&&day<=it.last
    }.map {
        it.role
    }.toSortedSet()
    fun authorized(user: String,day: Int)=closure(assigned(user,day))
    fun accept(keyword: String,f: List<String>): String? {
        var role=f[0];
        when(keyword) {
            "ROLE"-> {
                if(role in roles)return "duplicate role $role";
                roles.add(role);
                inherits[role]=mutableSetOf();
                permissions[role]=mutableSetOf()
            };
            "INHERITS"-> {
                val senior=f[0];
                val junior=f[1];
                for(name in listOf(senior,junior))if(name !in roles)return "unknown role $name";
                if(junior in inherits.getValue(senior))return "duplicate inheritance $senior $junior";
                if(senior in closure(listOf(junior))) {
                    val cycle=path(junior,senior,mutableSetOf())!!;
                    cycle.add(0,senior);
                    return "cycle "+cycle.joinToString(" > ")
                };
                inherits.getValue(senior).add(junior)
            };
            "PERMIT"-> {
                if(role !in roles)return "unknown role $role";
                val permission=Permission(f[1],f[2]);
                if(!permissions.getValue(role).add(permission))return "duplicate permission "+f.joinToString(" ");
                grants.add(Grant(role,f[1],f[2]))
            };
            "SSD","DSD"-> {
                val constraints=if(keyword=="SSD")ssd else dsd;
                if(constraints.any {
                    it.name==f[0]
                })return "duplicate constraint ${f[0]}";
                val names=f[2].split(',');
                for(name in names)if(name !in roles)return "unknown role $name";
                val cardinality=f[1].toInt();
                if(cardinality !in 2..names.size)return "bad cardinality ${f[0]} $cardinality";
                constraints.add(Constraint(f[0],cardinality,names.toSet()))
            };
            else-> {
                val user=f[0];
                role=f[1];
                if(role !in roles)return "unknown role $role";
                val first=f[2].toInt();
                val last=f[3].toInt();
                if(first<1||first>last||last>365)return "bad range $first $last";
                for(constraint in ssd)for(day in first..last) {
                    val assigned=assigned(user,day);
                    assigned.add(role);
                    val intersection=closure(assigned).intersect(constraint.roles).sorted();
                    if(intersection.size>=constraint.cardinality)return "ssd ${constraint.name} day $day roles "+intersection.joinToString(",")
                };
                assignments.add(Assignment(user,role,first,last))
            }
        };
        return null
    }
}
