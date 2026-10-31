object Query {
    data class Literal(val kind: String,val value: SchemaIo.Value)
    data class Item(val operation: String,val name: String?)
    sealed interface Condition
    data class Logical(val operation: String,val first: Condition,val second: Condition?): Condition
    class Comparison(val operation: String,val name: String,val literals: List<Literal>): Condition {
        var index=0;
        var values: List<SchemaIo.Value> = emptyList()
    }
    data class Raw(val items: List<Item>?,val condition: Condition?,val group: String?,val order: String?,
        val descending: Boolean,val limit: Int?)
    fun tokenize(text: String): List<String> {
        val tokens=mutableListOf<String>();
        var position=0;
        while(position<text.length) {
            val c=text[position];
            if(c==' ') {
                position++;
                continue
            };
            val start=position++;
            when {
                c=='\''->position=text.indexOf('\'',position)+1;
                c.isLetter()||c=='_'-> {
                    while(position<text.length&&(text[position].isLetterOrDigit()||text[position]=='_'))position++
                };
                c=='-'||c.isDigit()-> {
                    while(position<text.length&&text[position].isDigit())position++
                };
                position<text.length&&text.substring(start,position+1) in listOf("<=",">=","<>")->position++
            };
            tokens.add(text.substring(start,position))
        };
        return tokens
    }
    class Parser(text: String) {
        val tokens=tokenize(text);
        var position=0;
        fun peek()=tokens.getOrElse(position) {
            ""
        };
        fun take()=tokens[position++];
        fun accept(token: String): Boolean {
            if(peek()!=token)return false;
            position++;
            return true
        }
        fun parse(): Raw {
            take();
            val items=if(accept("*"))null else mutableListOf(item()).also {
                while(accept(","))it.add(item())
            };
            val condition=if(accept("WHERE"))condition() else null;
            var group: String?=null;
            var order: String?=null;
            var descending=false;
            if(accept("GROUP")) {
                take();
                group=take()
            };
            if(accept("ORDER")) {
                take();
                order=take();
                if(accept("DESC"))descending=true else accept("ASC")
            };
            val limit=if(accept("LIMIT"))take().toInt() else null;
            return Raw(items,condition,group,order,descending,limit)
        }
        fun item(): Item {
            val name=take();
            if(name[0] in 'a'..'z')return Item("COLUMN",name);
            take();
            val operation=if(accept("DISTINCT"))"COUNT_DISTINCT" else name;
            val column=if(accept("*"))null else take();
            take();
            return Item(operation,column)
        }
        fun literal(): Literal {
            val token=take();
            return when {
                token.startsWith('\'')->Literal("STRING",SchemaIo.TextValue(token.substring(1,token.length-1)));
                token=="TRUE"||token=="FALSE"->Literal("BOOL",SchemaIo.BoolValue(token=="TRUE"));
                else->Literal("INT",SchemaIo.NumberValue(token.toLong()))
            }
        }
        fun condition(): Condition {
            var tree=conjunction();
            while(accept("OR"))tree=Logical("OR",tree,conjunction());
            return tree
        }
        fun conjunction(): Condition {
            var tree=negation();
            while(accept("AND"))tree=Logical("AND",tree,negation());
            return tree
        }
        fun negation(): Condition {
            if(accept("NOT"))return Logical("NOT",negation(),null);
            if(accept("(")) {
                val tree=condition();
                take();
                return tree
            };
            val column=take();
            var operation=take();
            val literals=mutableListOf<Literal>();
            when(operation) {
                "IS"-> {
                    operation=if(accept("NOT"))"IS_NOT_NULL" else "IS_NULL";
                    take()
                };
                "BETWEEN"-> {
                    literals.add(literal());
                    take();
                    literals.add(literal())
                };
                "IN"-> {
                    take();
                    literals.add(literal());
                    while(accept(","))literals.add(literal());
                    take()
                };
                else->literals.add(literal())
            };
            return Comparison(operation,column,literals)
        }
    }
}
