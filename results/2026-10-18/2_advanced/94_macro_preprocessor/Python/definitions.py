"""Macro signatures, definition syntax, and identity comparisons."""


BUILTINS = ("__LINE__", "__FILE__", "__COUNTER__")
VARIADIC_NAME = "__VA_ARGS__"
VARIADIC_ERROR = '"__VA_ARGS__" can only appear in the expansion of a variadic macro'


class DefinitionError(Exception):
    pass


class Macro:
    def __init__(self, name, parameters, variadic, replacement, position, main_file):
        self.name, self.parameters, self.variadic = name, parameters, variadic
        self.replacement, self.position, self.main_file = replacement, position, main_file
        self.expanded, self.tested = 0, 0

    def signature(self):
        if self.parameters is None:
            return self.name
        parameters = list(self.parameters)
        if self.variadic:
            parameters[-1] = "..."
        return self.name + "(" + ", ".join(parameters) + ")"

    def identical(self, other):
        return (self.parameters == other.parameters and self.variadic == other.variadic
                and [(token.spelling, token.space) for token in self.replacement]
                == [(token.spelling, token.space) for token in other.replacement])


def check_name(tokens, directive):
    if not tokens:
        return "no macro name given in #" + directive + " directive"
    if tokens[0].kind != "identifier":
        return "macro names must be identifiers"
    name = tokens[0].spelling
    if name == "defined":
        return '"defined" cannot be used as a macro name'
    if name in BUILTINS:
        operation = "redefine" if directive == "define" else "undefine"
        return f'cannot {operation} builtin macro "{name}"'
    return None


def parse(tokens, position, main_file):
    error = check_name(tokens, "define")
    if error is not None:
        raise DefinitionError(error)
    name = tokens[0].spelling
    if name == VARIADIC_NAME:
        raise DefinitionError(VARIADIC_ERROR)
    parameters, variadic, index = None, False, 1
    if len(tokens) > 1 and tokens[1].spelling == "(" and not tokens[1].space:
        parameters, index = [], 2
        if index == len(tokens):
            raise DefinitionError("missing ')' in macro parameter list")
        if tokens[index].spelling == ")":
            index += 1
        else:
            while True:
                if index == len(tokens):
                    raise DefinitionError("missing ')' in macro parameter list")
                token = tokens[index]
                if token.spelling == "...":
                    parameters.append(VARIADIC_NAME)
                    variadic = True
                elif token.kind == "identifier":
                    if token.spelling == VARIADIC_NAME:
                        raise DefinitionError(VARIADIC_ERROR)
                    if token.spelling in parameters:
                        raise DefinitionError(f'duplicate macro parameter "{token.spelling}"')
                    parameters.append(token.spelling)
                else:
                    raise DefinitionError(f'expected parameter name, found "{token.spelling}"')
                index += 1
                if index == len(tokens):
                    raise DefinitionError("missing ')' in macro parameter list")
                following = tokens[index].spelling
                index += 1
                if following == ")":
                    break
                if variadic:
                    raise DefinitionError(f'expected \')\' after "...", found "{following}"')
                if following != ",":
                    raise DefinitionError(f'expected \',\' or \')\', found "{following}"')
        parameters = tuple(parameters)
    replacement = list(tokens[index:])
    if replacement:
        replacement[0] = replacement[0]._replace(space=False)
        if replacement[0].spelling == "##" or replacement[-1].spelling == "##":
            raise DefinitionError("'##' cannot appear at either end of a macro expansion")
    for index, token in enumerate(replacement):
        if token.kind == "identifier" and token.spelling == VARIADIC_NAME and not variadic:
            raise DefinitionError(VARIADIC_ERROR)
        if token.spelling == "#" and parameters is not None:
            if index + 1 == len(replacement) or replacement[index + 1].kind != "identifier" or replacement[index + 1].spelling not in parameters:
                raise DefinitionError("'#' is not followed by a macro parameter")
    return Macro(name, parameters, variadic, tuple(replacement), position, main_file)
