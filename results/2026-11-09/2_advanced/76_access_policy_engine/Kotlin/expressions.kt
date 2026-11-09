object Expressions {
    sealed interface Expr
    data class Literal(val value: Any): Expr
    data class Reference(val name: String): Expr
    data object Current: Expr
    data class Operation(val name: String,val arguments: List<Expr>): Expr
    fun lex(text: String): List<String> {
        val tokens=mutableListOf<String>();
        var i=0;
        while(i<text.length) {
            val c=text[i];
            if(c==' ') {
                i++;
                continue
            };
            val start=i++;
            if(c=='"') {
                while(text[i]!='"')i++;
                i++
            } else if(c in '0'..'9') {
                while(i<text.length&&text[i] in '0'..'9')i++
            } else if(c in 'A'..'Z'||c in 'a'..'z') {
                while(i<text.length) {
                    val n=text[i];
                    if(!(n in 'A'..'Z'||n in 'a'..'z'||n in '0'..'9'||n=='_'||n=='.'))break;
                    i++
                }
            } else if(i<text.length&&text[i]=='='&&c in "=!<>")i++;
            tokens.add(text.substring(start,i))
        };
        return tokens
    }
    class Parser(text: String) {
        val tokens=lex(text);
        var position=0;
        fun peek()=tokens.getOrElse(position) {
            ""
        };
        fun take()=tokens[position++]
        fun disjunction(): Expr {
            var tree=conjunction();
            while(peek()=="or") {
                val op=take();
                tree=Operation(op,listOf(tree,conjunction()))
            };
            return tree
        }
        fun conjunction(): Expr {
            var tree=negation();
            while(peek()=="and") {
                val op=take();
                tree=Operation(op,listOf(tree,negation()))
            };
            return tree
        }
        fun negation(): Expr {
            if(peek()=="not") {
                take();
                return Operation("not",listOf(negation()))
            };
            return comparison()
        }
        fun comparison(): Expr {
            var tree=sum();
            if(peek() in setOf("==","!=","<","<=",">",">=","in")) {
                val op=take();
                tree=Operation(op,listOf(tree,sum()))
            };
            return tree
        }
        fun sum(): Expr {
            var tree=product();
            while(peek()=="+"||peek()=="-") {
                val op=take();
                tree=Operation(op,listOf(tree,product()))
            };
            return tree
        }
        fun product(): Expr {
            var tree=unary();
            while(peek()=="*") {
                val op=take();
                tree=Operation(op,listOf(tree,unary()))
            };
            return tree
        }
        fun unary(): Expr {
            if(peek()=="-") {
                take();
                return Operation("-",listOf(unary()))
            };
            return primary()
        }
        fun primary(): Expr {
            val token=take();
            if(token[0] in '0'..'9')return Literal(token.toInt());
            if(token.startsWith('"'))return Literal(token.substring(1,token.length-1));
            if(token=="true"||token=="false")return Literal(token=="true");
            if(token=="it")return Current;
            if('.' in token)return Reference(token);
            if(token=="(") {
                val tree=disjunction();
                take();
                return tree
            };
            if(token=="[") {
                val values=mutableListOf<String>();
                while(peek()!="]") {
                    val value=take();
                    values.add(value.substring(1,value.length-1));
                    if(peek()!="]")take()
                };
                take();
                return Literal(values.toList())
            };
            take();
            val arguments=mutableListOf<Expr>();
            while(peek()!=")") {
                arguments.add(disjunction());
                if(peek()!=")")take()
            };
            take();
            return Operation(token,arguments)
        }
    }
    fun parse(text: String)=Parser(text).disjunction()
}
