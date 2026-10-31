import java.io.File
object PolicyParser {
    data class Clause(val reference: String,val mandatory: Boolean,val operator: String,val literal: Expressions.Expr)
    data class Argument(val name: String,val expression: Expressions.Expr)
    data class Attachment(val effect: String,val identifier: String,val arguments: List<Argument>)
    class Element(val kind: String,val identifier: String,val behavior: String,val parent: Element?) {
        val targets=mutableListOf<List<List<Clause>>>();
        val children=mutableListOf<Element>();
        var condition: Expressions.Expr?=null;
        val obligations=mutableListOf<Attachment>();
        val advice=mutableListOf<Attachment>()
    }
    data class Policies(val root: Element,val elements: List<Element>)
    fun target(text: String)=text.split(" | ").map {
        alternative->alternative.split(" & ").map {
            clause->val fields=clause.split(' ');
            val mandatory=fields[0].endsWith('!');
            Clause(fields[0].removeSuffix("!"),mandatory,fields[1],Expressions.parse(fields[2]))
        }
    }
    fun read(): Policies {
        val elements=mutableListOf<Element>();
        val stack=mutableListOf<Element>();
        for(raw in File("input/policies.txt").readLines()) {
            val line=raw.trimStart(' ');
            if(line.isEmpty()||line.startsWith('#'))continue;
            val separator=line.indexOf(' ');
            val keyword=if(separator<0)line else line.substring(0,separator);
            val rest=if(separator<0)"" else line.substring(separator+1);
            when(keyword) {
                "POLICYSET","POLICY","RULE"-> {
                    val fields=rest.split(' ');
                    val element=Element(keyword.lowercase(),fields[0],fields[1],stack.lastOrNull());
                    stack.lastOrNull()?.children?.add(element);
                    elements.add(element);
                    stack.add(element)
                };
                "END"->stack.removeAt(stack.lastIndex);
                "TARGET"->stack.last().targets.add(target(rest));
                "CONDITION"->stack.last().condition=Expressions.parse(rest);
                else-> {
                    val fields=rest.split(' ',limit=3);
                    val arguments=if(fields.size==3)fields[2].split(';').map {
                        part->val item=part.trim(' ');
                        val equals=item.indexOf('=');
                        Argument(item.substring(0,equals),Expressions.parse(item.substring(equals+1)))
                    } else emptyList();
                    val attachment=Attachment(fields[0],fields[1],arguments);
                    (if(keyword=="OBLIGATION")stack.last().obligations else stack.last().advice).add(attachment)
                }
            }
        };
        return Policies(elements.first(),elements)
    }
}
