object Formula {
    data class Factor(val name: String,val column: String,val power: Int,val categorical: Boolean)
    fun factor(name: String): Factor {
        if(name.startsWith("C("))return Factor(name,name.substring(2,name.length-1),1,true);
        if(name.startsWith("I(")) {
            val caret=name.indexOf('^');
            return Factor(name,name.substring(2,caret),name.substring(caret+1,caret+2).toInt(),false)
        };
        return Factor(name,name,1,false)
    }
    class Term(words: List<String>) {
        val name=words.joinToString(":");
        val factors=words.map {
            factor(it)
        };
        val names=words.toSet()
    }
    fun contained(a: Term,b: Term)=a.names.size<b.names.size&&b.names.containsAll(a.names)
    class Model {
        var response="";
        var weight: String?=null;
        var original="";
        val terms=mutableListOf<Term>();
        val variables=linkedSetOf<String>();
        val factorColumns=linkedSetOf<String>()
    }
    fun add(model: Model,factors: List<String>) {
        val term=Term(factors);
        if(model.terms.none {
            it.names==term.names
        })model.terms+=term
    }
    fun parse(line: String): Model {
        val model=Model();
        val weighted=line.indexOf(" weights=");
        model.original=if(weighted<0)line else line.substring(0,weighted);
        model.weight=if(weighted<0)null else line.substring(weighted+9);
        val split=model.original.indexOf(" ~ ");
        model.response=model.original.substring(0,split);
        for(expression in model.original.substring(split+3).split(" + ")) {
            if('*' !in expression)add(model,expression.split(':')) else {
                val factors=expression.split('*');
                for(size in 1..factors.size)for(mask in 1 until (1 shl factors.size))if(Integer.bitCount(mask)==size)add(model,factors.indices.filter {
                    mask and (1 shl it)!=0
                }.map {
                    factors[it]
                })
            }
        };
        for(term in model.terms)for(factor in term.factors)model.factorColumns+=factor.column;
        model.variables+=model.factorColumns;
        model.variables+=model.response;
        model.weight?.let {
            model.variables+=it
        };
        return model
    }
    data class Component(val factor: Factor,val name: String,val level: String?) {
        fun value(row: Dataframe.Row): Double {
            if(factor.categorical)return if(row.values[factor.column]==level)1.0 else 0.0;
            val v=row.numeric(factor.column);
            return if(factor.power==1)v else if(factor.power==2)v*v else v*v*v
        }
    }
    class Column(val name: String,val term: Int,val components: List<Component>) {
        fun value(row: Dataframe.Row): Double {
            var product=1.0;
            for(component in components)product*=component.value(row);
            return product
        }
    }
    class Design(val model: Model,frame: Dataframe.Frame) {
        val rows=frame.rows.filter {
            row->model.variables.all {
                row.values[it]!=null
            }
        };
        val levels=linkedMapOf<String,List<String>>();
        val columns=mutableListOf(Column("(Intercept)",-1,emptyList()));
        val y=DoubleArray(rows.size);
        val w=DoubleArray(rows.size)
        init {
            for(term in model.terms)for(factor in term.factors)if(factor.categorical&&factor.column !in levels)levels[factor.column]=rows.map {
                it.values.getValue(factor.column)!!
            }.toSortedSet().toList();
            for(t in model.terms.indices) {
                val term=model.terms[t];
                val choices=mutableListOf<List<Component>>();
                var count=1;
                for(factor in term.factors) {
                    val components=if(factor.categorical)levels.getValue(factor.column).drop(1).map {
                        Component(factor,factor.name+it,it)
                    } else listOf(Component(factor,factor.name,null));
                    choices+=components;
                    count*=components.size
                };
                for(ordinal in 0 until count) {
                    var rest=ordinal;
                    val components=mutableListOf<Component>();
                    for(list in choices) {
                        components+=list[rest%list.size];
                        rest/=list.size
                    };
                    columns+=Column(components.joinToString(":") {
                        it.name
                    },t,components)
                }
            };
            for(i in rows.indices) {
                y[i]=rows[i].numeric(model.response);
                w[i]=model.weight?.let {
                    rows[i].numeric(it)
                }
                ?:1.0
            }
        }
        fun indices(mask: Int)=columns.indices.filter {
            columns[it].term<0||mask and (1 shl columns[it].term)!=0
        }.toIntArray()
        fun matrix(indices: IntArray)=Array(rows.size) {
            i->DoubleArray(indices.size) {
                j->columns[indices[j]].value(rows[i])
            }
        }
        fun predictable(row: Dataframe.Row)=model.factorColumns.all {
            val value=row.values[it];
            value!=null&&(it !in levels||value in levels.getValue(it))
        }
        fun vector(row: Dataframe.Row)=DoubleArray(columns.size) {
            columns[it].value(row)
        }
    }
    fun display(model: Model,mask: Int): String {
        val terms=model.terms.indices.filter {
            mask and (1 shl it)!=0
        }.map {
            model.terms[it].name
        };
        return model.response+" ~ "+if(terms.isEmpty())"1" else terms.joinToString(" + ")
    }
    fun removable(model: Model,mask: Int,term: Int)=mask and (1 shl term)!=0&&model.terms.indices.none {
        mask and (1 shl it)!=0&&contained(model.terms[term],model.terms[it])
    }
    fun hierarchical(model: Model,mask: Int)=model.terms.indices.all {
        t->mask and (1 shl t)==0||model.terms.indices.all {
            a->!contained(model.terms[a],model.terms[t])||mask and (1 shl a)!=0
        }
    }
}
