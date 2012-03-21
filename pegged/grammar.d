module pegged.grammar;

import std.algorithm : startsWith;
import std.conv;

public import pegged.peg;

void asModule(string moduleName, string grammarString)
{
    import std.stdio;
    auto f = File(moduleName~".d","w");
    
    f.write("/**\nThis module was automatically generated from the following grammar:\n");
    f.write(grammarString);
    f.write("\n*/\n");
    
    f.write("module " ~ moduleName ~ ";\n\n");
    f.write("import pegged.peg;\n\n");
    f.write(grammar(grammarString));
}

string grammar(string g)
{    
    auto grammarAsOutput = Grammar.parse(g);
    string[] names;
    foreach(definition; grammarAsOutput.parseTree.children)
        if (definition.name == "Definition") 
            names ~= definition.capture[0];
    string ruleNames = "    enum ruleNames = [";
    foreach(name; names)
        ruleNames ~= "\"" ~ name ~ "\":true,";
    ruleNames = ruleNames[0..$-1] ~ "];\n";
    return PEGtoCode(grammarAsOutput.parseTree, ruleNames);
}


string PEGtoCode(ParseTree p, string names = "")
{
    string result;
    auto ch = p.children;
    
    switch (p.name)
    {
        case "Grammar":
            foreach(child; ch)
                result ~= PEGtoCode(child, names);
            return result ~ ((ch[0].name == "GrammarName")? "}\n" : "");
        case "GrammarName":
            result = "class " ~ p.capture[0] ~ "\n{\n" 
~ names ~
"    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }
    
";
            return result;
        case "Definition":
            string code = 
"    enum name = `" ~ch[0].capture[0]~ "`;

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        //p.parseTree.name = `"~ch[0].capture[0]~"`;
        //p.parseTree.children = (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree);
        //return p;
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`"~ch[0].capture[0]~"`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());";

version(none) {
                code =
"    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output( p.text, p.pos, p.namedCaptures,
                       ParseTree(\""~ch[0].capture[0]~"\", p.success, p.capture, input.pos, p.pos,[p]));
    }
    
    mixin(stringToInputMixin());";                
}
            string inheritance;
            switch(ch[1].children[0].name) // ch[1] is the arrow symbol
            {
                case "LEFTARROW":
                    inheritance = PEGtoCode(ch[2]);
                    break;
                case "FUSEARROW":
                    inheritance = "Fuse!(" ~ PEGtoCode(ch[2]) ~ ")";
                    break;
                case "DROPARROW":
                    inheritance = "Drop!(" ~ PEGtoCode(ch[2]) ~ ")";
                    break;
                case "ACTIONARROW":
                    inheritance = "Action!(" ~ PEGtoCode(ch[2]) ~ ", " ~ ch[1].capture[1] ~ ")";
                    break;
                case "SPACEARROW":
                    if (ch[2].children[0].name == "Sequence")
                        inheritance = "Space" ~ PEGtoCode(ch[2]);
                    else
                        inheritance = PEGtoCode(ch[2]);
                    break;
                default:
                    inheritance ="ERROR: Bad arrow: " ~ ch[1].name;
                    break;
            }

            return "class " 
                   ~ ch[0].capture[0] // name 
                   ~ (ch[0].capture.length == 2 ? ch[0].capture[1] : "") // parameter list
                   ~ " : " ~ inheritance // inheritance code
                   ~ "\n{\n" 
                   ~ code // inner code
                   ~ "\n}\n\n";
        case "Expression":
            if (ch.length > 1) // OR present
            {
                result = "Or!(";
                foreach(i,child; ch)
                    if (i%2 == 0) result ~= PEGtoCode(child) ~ ",";
                result = result[0..$-1] ~ ")";
            }
            else // one-element Or -> dropping the Or!( )
                result = PEGtoCode(ch[0]);
            return result;
        case "Sequence":
            if (ch.length > 1)
            {
                result = "Seq!(";
                foreach(child; ch) 
                {
                    auto temp = PEGtoCode(child);
                    if (temp.startsWith("Seq!("))
                        temp = temp[5..$-1];
                    result ~= temp ~ ",";
                }
                result = result[0..$-1] ~ ")";
            }
            else
                result = PEGtoCode(ch[0]);
            return result;
version(none) {        case "Element":
            if (ch.length > 1)
            {
                result = "Join!(";
                foreach(i,child; ch) 
                {
                    if (i%2 == 0) // "Suffix JOIN Suffix JOIN ..."
                    {
                        auto temp = PEGtoCode(child);
                        if (temp.startsWith("Join!("))
                            temp = temp[6..$-1];
                        result ~= temp ~ ",";
                    }
                }
                result = result[0..$-1] ~ ")";
            }
            else
                result = PEGtoCode(ch[0]);
            return result;}
        case "Prefix":
            if (ch.length > 1)
                switch (ch[0].name)
                {
                    case "NOT":
                        result = "NegLookAhead!(" ~ PEGtoCode(ch[1]) ~ ")";
                        break;
                    case "LOOKAHEAD":
                        result = "PosLookAhead!(" ~ PEGtoCode(ch[1]) ~ ")";
                        break;
                    case "DROP":
                        result = "Drop!(" ~ PEGtoCode(ch[1]) ~ ")";
                        break;
                    case "FUSE":
                        result = "Fuse!(" ~ PEGtoCode(ch[1]) ~ ")";
                        break;
                    default:
                        break;
                }
            else
                result = PEGtoCode(ch[0]);
            return result;
        case "Suffix":
            if (ch.length > 1)
                switch (ch[1].name)
                {
                    case "OPTION":
                        result = "Option!(" ~ PEGtoCode(ch[0]) ~ ")";
                        break;
                    case "ZEROORMORE":
                        result = "ZeroOrMore!(" ~ PEGtoCode(ch[0]) ~ ")";
                        break;
                    case "ONEORMORE":
                        result = "OneOrMore!(" ~ PEGtoCode(ch[0]) ~ ")";
                        break;
                    case "NamedExpr":
                        if (ch[1].capture.length == 2)
                            result = "Named!(" ~ PEGtoCode(ch[0]) ~ ", \"" ~ ch[1].capture[1] ~ "\")";
                        else
                            result = "PushName!(" ~ PEGtoCode(ch[0]) ~ ")";
                        break;
                    case "WithAction":
                        result = "Action!(" ~ PEGtoCode(ch[0]) ~ ", " ~ ch[1].capture[0] ~ ")";
                        break;
                    default:
                        break;
                }
            else
                result = PEGtoCode(ch[0]);
            return result;
        case "Primary":
            foreach(child; ch) result ~= PEGtoCode(child);
            return result;
        case "Name":
            result = p.capture[0];
            if (ch.length == 1) result ~= PEGtoCode(ch[0]);
            return result;
        case "ArgList":
            result = "!(";
            foreach(child; ch)
                result ~= PEGtoCode(child) ~ ","; // Wow! Allow  A <- List('A'*,',') 
            result = result[0..$-1] ~ ")";
            return result;
        case "GroupExpr":
            if (ch.length == 0) return "ERROR: Empty group ()";
            auto temp = PEGtoCode(ch[0]);
            if (ch.length == 1 || temp.startsWith("Seq!(")) return temp;
            result = "Seq!(" ~ temp ~ ")";
            return result;
        case "Ident":
            return p.capture[0];
        case "Literal":
            if (p.capture[0].length == 0)
                return "ERROR: empty literal";
            return "Lit!(\"" ~ p.capture[0] ~ "\")";
        case "Class":
            if (ch.length == 0)
                return "ERROR: Empty Class of chars []";
            else 
            {
                if (ch.length > 1)
                {
                    result = "Or!(";
                    foreach(child; ch)
                    {
                        auto temp = PEGtoCode(child);
                        if (temp.startsWith("Or!("))
                            temp = temp[4..$-1];
                        result ~= temp ~ ",";
                    }
                    result = result[0..$-1] ~ ")";
                }
                else
                    result = PEGtoCode(ch[0]);
            }
            return result;
        case "CharRange":
            if (ch.length == 2)
                return "Range!('" ~ PEGtoCode(ch[0]) ~ "','" ~ PEGtoCode(ch[1]) ~ "')";
            else
                return "Lit!(\"" ~ PEGtoCode(ch[0]) ~ "\")"; 
        case "Char":
            if (p.capture.length == 2) // escape sequence \-, \[, \] 
                return p.capture[1];
            else
                return p.capture[0];
        case "OR":
            foreach(child; ch) result ~= PEGtoCode(child);
            return result;
        case "ANY":
            return "Any";
        default:
            return "";
    }
}

/**
This module was automatically generated from the following grammar:

Grammar     <- GrammarName? Definition+ EOI
GrammarName <- Identifier (Encapsulation)? :":" EOL
Encapsulation <- :OPEN ( "freeform" / "open" / "closed" / "sealed" ) :CLOSE
Definition  <- RuleName Arrow Expression S
RuleName    <- Identifier (ParamList?) S
Expression  <- Sequence (OR Sequence)*
Sequence    <- Prefix+
Prefix      <- (LOOKAHEAD / NOT / DROP / FUSE)? Suffix
Suffix      <- Primary ( OPTION 
                       / ONEORMORE 
                       / ZEROORMORE 
                       / NamedExpr 
                       / WithAction)? S
Primary     <- Name !Arrow
             / GroupExpr
             / Literal 
             / Class 
             / ANY

Name        <- QualifiedIdentifier ArgList? S
GroupExpr   <- :OPEN Expression :CLOSE S
Literal     <~ :Quote (!Quote Char)* :Quote S
             / :DoubleQuote (!DoubleQuote Char)* :DoubleQuote S
Class       <- :'[' (!']' CharRange)* :']' S
CharRange   <- Char :'-' Char / Char
Char        <- BackSlash ('-' / BackSlash / '[' / ']') # Escape sequences
             / !BackSlash .
ParamList   <~ OPEN Identifier (',' Identifier)* CLOSE S
ArgList     <- :OPEN Expression (:',' Expression)* :CLOSE S
NamedExpr   <- NAME Identifier? S
WithAction  <~ :ACTIONOPEN Identifier :ACTIONCLOSE S

Arrow       <- LEFTARROW / FUSEARROW / DROPARROW / ACTIONARROW / SPACEARROW
LEFTARROW   <- "<-" S
FUSEARROW   <- "<~" S
DROPARROW   <- "<:" S
ACTIONARROW <- "<" WithAction S
SPACEARROW  <- "<" S
  
OR          <- '/' S
    
LOOKAHEAD   <- '&' S
NOT         <- '!' S

DROP        <- ':' S
FUSE        <- '~' S
  
#SPACEMUNCH <- '>' S
    
NAME        <- '=' S
ACTIONOPEN  <- '{' S
ACTIONCLOSE <- '}' S
    
OPTION     <- '?' S
ZEROORMORE <- '*' S
ONEORMORE  <- '+' S
    
OPEN       <- '(' S
CLOSE      <- ')' S
    
ANY        <- '.' S
    
S          <: ~(Blank / EOL / Comment)*
Comment    <- "#" (!EOL .)* (EOL/EOI)

*/
class Grammar : Seq!(S, Option!(GrammarName),OneOrMore!(Definition),EOI)
{
    enum name = `Grammar`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Grammar`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class GrammarName : Seq!(Identifier,S, Option!(Encapsulation),S, Drop!(Lit!(":")),S)
{
    enum name = `GrammarName`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`GrammarName`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Encapsulation : Seq!(Drop!(OPEN),Or!(Lit!("freeform"),Lit!("open"),Lit!("closed"),Lit!("sealed")),Drop!(CLOSE))
{
    enum name = `Encapsulation`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Encapsulation`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Definition : Seq!(RuleName,Arrow,Expression,S)
{
    enum name = `Definition`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Definition`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class RuleName : Seq!(Identifier,Option!(ParamList),S)
{
    enum name = `RuleName`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`RuleName`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Expression : Seq!(Sequence,ZeroOrMore!(Seq!(OR,Sequence)))
{
    enum name = `Expression`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Expression`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Sequence : OneOrMore!(Prefix)
{
    enum name = `Sequence`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Sequence`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Prefix : Seq!(Option!(Or!(LOOKAHEAD,NOT,DROP,FUSE)),Suffix)
{
    enum name = `Prefix`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Prefix`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Suffix : Seq!(Primary,Option!(Or!(OPTION,ONEORMORE,ZEROORMORE,NamedExpr,WithAction)),S)
{
    enum name = `Suffix`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Suffix`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Primary : Or!(Seq!(Name,NegLookAhead!(Arrow)),GroupExpr,Literal,Class,ANY)
{
    enum name = `Primary`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Primary`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Name : Seq!(QualifiedIdentifier,Option!(ArgList),S)
{
    enum name = `Name`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Name`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class GroupExpr : Seq!(Drop!(OPEN),Expression,Drop!(CLOSE),S)
{
    enum name = `GroupExpr`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`GroupExpr`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Literal : Fuse!(Or!(Seq!(Drop!(Quote),ZeroOrMore!(Seq!(NegLookAhead!(Quote),Char)),Drop!(Quote),S),Seq!(Drop!(DoubleQuote),ZeroOrMore!(Seq!(NegLookAhead!(DoubleQuote),Char)),Drop!(DoubleQuote),S)))
{
    enum name = `Literal`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Literal`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Class : Seq!(Drop!(Lit!("[")),ZeroOrMore!(Seq!(NegLookAhead!(Lit!("]")),CharRange)),Drop!(Lit!("]")),S)
{
    enum name = `Class`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Class`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class CharRange : Or!(Seq!(Char,Drop!(Lit!("-")),Char),Char)
{
    enum name = `CharRange`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`CharRange`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Char : Or!(Seq!(BackSlash,Or!(Lit!("-"),BackSlash,Lit!("["),Lit!("]"))),Seq!(NegLookAhead!(BackSlash),Any))
{
    enum name = `Char`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Char`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ParamList : Fuse!(Seq!(OPEN,Identifier,ZeroOrMore!(Seq!(Lit!(","),Identifier)),CLOSE,S))
{
    enum name = `ParamList`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ParamList`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ArgList : Seq!(Drop!(OPEN),Expression,ZeroOrMore!(Seq!(Drop!(Lit!(",")),Expression)),Drop!(CLOSE),S)
{
    enum name = `ArgList`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ArgList`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class NamedExpr : Seq!(NAME,Option!(Identifier),S)
{
    enum name = `NamedExpr`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`NamedExpr`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class WithAction : Fuse!(Seq!(Drop!(ACTIONOPEN),Identifier,Drop!(ACTIONCLOSE),S))
{
    enum name = `WithAction`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`WithAction`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Arrow : Or!(LEFTARROW,FUSEARROW,DROPARROW,ACTIONARROW,SPACEARROW)
{
    enum name = `Arrow`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Arrow`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class LEFTARROW : Seq!(Lit!("<-"),S)
{
    enum name = `LEFTARROW`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`LEFTARROW`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class FUSEARROW : Seq!(Lit!("<~"),S)
{
    enum name = `FUSEARROW`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`FUSEARROW`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class DROPARROW : Seq!(Lit!("<:"),S)
{
    enum name = `DROPARROW`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`DROPARROW`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ACTIONARROW : Seq!(Lit!("<"),WithAction,S)
{
    enum name = `ACTIONARROW`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ACTIONARROW`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class SPACEARROW : Seq!(Lit!("<"),S)
{
    enum name = `SPACEARROW`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`SPACEARROW`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class OR : Seq!(Lit!("/"),S)
{
    enum name = `OR`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`OR`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class LOOKAHEAD : Seq!(Lit!("&"),S)
{
    enum name = `LOOKAHEAD`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`LOOKAHEAD`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class NOT : Seq!(Lit!("!"),S)
{
    enum name = `NOT`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`NOT`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class DROP : Seq!(Lit!(":"),S)
{
    enum name = `DROP`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`DROP`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class FUSE : Seq!(Lit!("~"),S)
{
    enum name = `FUSE`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`FUSE`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class NAME : Seq!(Lit!("="),S)
{
    enum name = `NAME`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`NAME`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ACTIONOPEN : Seq!(Lit!("{"),S)
{
    enum name = `ACTIONOPEN`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ACTIONOPEN`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ACTIONCLOSE : Seq!(Lit!("}"),S)
{
    enum name = `ACTIONCLOSE`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ACTIONCLOSE`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class OPTION : Seq!(Lit!("?"),S)
{
    enum name = `OPTION`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`OPTION`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ZEROORMORE : Seq!(Lit!("*"),S)
{
    enum name = `ZEROORMORE`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ZEROORMORE`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ONEORMORE : Seq!(Lit!("+"),S)
{
    enum name = `ONEORMORE`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ONEORMORE`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class OPEN : Seq!(Lit!("("),S)
{
    enum name = `OPEN`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`OPEN`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class CLOSE : Seq!(Lit!(")"),S)
{
    enum name = `CLOSE`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`CLOSE`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class ANY : Seq!(Lit!("."),S)
{
    enum name = `ANY`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`ANY`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class S : Drop!(Fuse!(ZeroOrMore!(Or!(Blank,EOL,Comment))))
{
    enum name = `S`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`S`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

class Comment : Seq!(Lit!("#"),ZeroOrMore!(Seq!(NegLookAhead!(EOL),Any)),Or!(EOL,EOI))
{
    enum name = `Comment`;

    enum ruleNames = ["Grammar":true,"GrammarName":true,"Encapsulation":true,"Definition":true,"RuleName":true,"Expression":true,"Sequence":true,"Prefix":true,"Suffix":true,"Primary":true,"Name":true,"GroupExpr":true,"Literal":true,"Class":true,"CharRange":true,"Char":true,"ParamList":true,"ArgList":true,"NamedExpr":true,"WithAction":true,"Arrow":true,"LEFTARROW":true,"FUSEARROW":true,"DROPARROW":true,"ACTIONARROW":true,"SPACEARROW":true,"OR":true,"LOOKAHEAD":true,"NOT":true,"DROP":true,"FUSE":true,"NAME":true,"ACTIONOPEN":true,"ACTIONCLOSE":true,"OPTION":true,"ZEROORMORE":true,"ONEORMORE":true,"OPEN":true,"CLOSE":true,"ANY":true,"S":true,"Comment":true];
    static ParseTree[] filterChildren(ParseTree p)
    {
        ParseTree[] filteredChildren;
        foreach(child; p.children)
        {
            if (child.name in ruleNames)
                filteredChildren ~= child;
            else
            {
                if (child.children.length > 0)
                    filteredChildren ~= filterChildren(child);
            }
        }
        return filteredChildren;
    }

    static Output parse(Input input)
    {
        auto p = typeof(super).parse(input);
        return Output(p.text, p.pos, p.namedCaptures,
                      ParseTree(`Comment`, p.success, p.capture, input.pos, p.pos, 
                               (p.name in ruleNames) ? [p.parseTree] : filterChildren(p.parseTree)));
    }
    
    mixin(stringToInputMixin());
}

