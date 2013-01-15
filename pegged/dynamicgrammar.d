module pegged.dynamicgrammar;

import std.array;
import std.stdio;

import pegged.peg;
import pegged.parser;
import pegged.dynamicpeg;


struct ParameterizedRule
{
    size_t numArgs;
    Dynamic delegate(Dynamic[]) code;

    Dynamic opCall(D...)(D rules)
    {
        Dynamic[] args;
        foreach(i,rule; rules)
        {
            static if (is(typeof(rule) == Dynamic))
                args ~= rule;
            else
                args ~= rule(); // Dynamic delegate()
        }

        if(rules.length == numArgs)
        {
            switch(numArgs)
            {
                case 1:
                    return code([args[0]]);
                case 2:
                    return code([args[0], args[1]]);
                case 3:
                    return code([args[0], args[1], args[2]]);
                case 4:
                    return code([args[0], args[1], args[2], args[3]]);
                case 5:
                    return code([args[0], args[1], args[2], args[3], args[4]]);
                case 6:
                    return code([args[0], args[1], args[2], args[3], args[4], args[5]]);
                default:
                    throw new Exception("Unimplemented parameterized rule.");
            }
        }
        else
            throw new Exception( "ParameterizedRule called with "
                               ~ to!string(rules.length)
                               ~ " args. Waited for "
                               ~ to!string(numArgs) ~ ".");
        return code(args);
    }
}

ParameterizedRule parameterizedRule(size_t n, Dynamic delegate(Dynamic[] d) code)
{
    ParameterizedRule pr;
    pr.numArgs = n;
    pr.code = code;
    return pr;
}

struct DynamicGrammar
{
    Dynamic[string] rules;
    string startingRule;
    ParameterizedRule[string] paramRules;
    string grammarName;

    ParseTree decimateTree(ParseTree p)
    {
        if(p.children.length == 0) return p;

        ParseTree[] filterChildren(ParseTree pt)
        {
            ParseTree[] result;
            foreach(child; pt.children)
            {
                if (  (child.name.startsWith(grammarName) && child.matches.length != 0)
                   || !child.successful && child.children.length == 0)
                {
                    child.children = filterChildren(child);
                    result ~= child;
                }
                else if (child.name.startsWith("keep!(")) // 'keep' node are never discarded.
                                               // They have only one child, the node to keep
                {
                    result ~= child.children[0];
                }
                else // discard this node, but see if its children contain nodes to keep
                {
                    result ~= filterChildren(child);
                }
            }
            return result;
        }
        p.children = filterChildren(p);
        return p;
    }

    ParseTree opCall(ParseTree p)
    {
        ParseTree result = decimateTree(rules[startingRule](p));
        result.children = [result];
        result.name = grammarName;
        return result;
    }

    ParseTree opCall(string input)
    {
        ParseTree result = decimateTree(rules[startingRule](ParseTree(``, false, [], input, 0, 0)));
        result.children = [result];
        result.name = grammarName;
        return result;
    }

    void opIndexAssign(D)(D code, string s)
    {
        rules[s]= named(code, "Test." ~ s);
    }
    Dynamic opIndex(string s)
    {
        return rules[s];
    }
}

// Helper to insert 'Spacing' before and after Primaries
ParseTree spaceArrow(ParseTree input)
{
    ParseTree wrapInSpaces(ParseTree p)
    {
        ParseTree spacer =
        ParseTree("Pegged.Prefix", true, null, null, 0,0, [
            ParseTree("Pegged.Suffix", true, null, null, 0, 0, [
                ParseTree("Pegged.Primary", true, null, null, 0, 0, [
                    ParseTree("Pegged.RhsName", true, null, null, 0,0, [
                        ParseTree("Pegged.Identifier", true, ["Spacing"])
                    ])
                ])
            ])
        ]);
        ParseTree result = ParseTree("Pegged.WrapAround", true, p.matches, p.input, p.begin, p.end, p.children);
        result.children = spacer ~ result.children ~ spacer;
        return result;
    }
    return modify!( p => p.name == "Pegged.Primary",
                    wrapInSpaces)(input);
}


DynamicGrammar grammar(string definition, Dynamic[string] context = null)
{
    //writeln("Entering dyn gram");
    ParseTree defAsParseTree = Pegged(definition);
    //writeln(defAsParseTree);
    if (!defAsParseTree.successful)
    {
        // To work around a strange bug with ParseTree printing at compile time
        throw new Exception("Bad grammar input: " ~ defAsParseTree.toString(""));
    }

    DynamicGrammar gram;
    foreach(k,v; context)
        gram[k] = v;

    ParseTree p = defAsParseTree.children[0];

    string grammarName = p.children[0].matches[0];//generateCode(p.children[0]);
    string shortGrammarName = p.children[0].matches[0];
    gram.grammarName = shortGrammarName;
            //string invokedGrammarName = generateCode(transformName(p.children[0]));
    string firstRuleName = p.children[1].children[0].matches[0];

    /// string getName(ParseTree p)? => called for grammar, rules...

    // Predefined spacing
    gram.rules["Spacing"] = discard(zeroOrMore(or(literal(" "), literal("\t"), literal("\n"), literal("\r"))));

    ParseTree[] definitions = p.children[1 .. $];

    foreach(i,def; definitions)
    {
        gram[def.matches[0]] = ()=>fail;
    }

    Dynamic getDyn(string name)
    {
        if (name in gram.rules)
            return gram.rules[name];
        else
            throw new Exception("Unknown name: " ~ name);
    }

    foreach(i,def; definitions)
    {
        string shortName = def.matches[0];
        writeln("Creating rule ", shortName);

        if (i == 0)
            gram.startingRule = shortName;
        //writeln("Definition #", i, def);
        // children[0]: name
        // children[1]: arrow (arrow type as first child)
        // children[2]: description

        Dynamic code;

        Dynamic ruleFromTree(ParseTree p)
        {
            //writeln("rfT: ", p.name, " ", p.matches);
            Dynamic result;
            switch(p.name)
            {
                case "Pegged.Expression":
                    if (p.children.length > 1) // OR expression
                    {
                        Dynamic[] children;
                        foreach(seq; p.children)
                            children ~= ruleFromTree(seq);
                        return distribute!(or)(children);
                    }
                    else // One child -> just a sequence, no need for a or!( , )
                    {
                        return ruleFromTree(p.children[0]);
                    }
                    break;
                case "Pegged.Sequence":
                    if (p.children.length > 1) // real sequence
                    {
                        Dynamic[] children;
                        foreach(seq; p.children)
                            children ~= ruleFromTree(seq);
                        return distribute!(pegged.dynamicpeg.and)(children);
                    }
                    else // One child -> just a Suffix, no need for a and!( , )
                    {
                        return ruleFromTree(p.children[0]);
                    }
                    break;
                case "Pegged.Prefix":
                    foreach(i,ref child; p.children[0..$-1]) // transforming a list into a linear tree
                        child.children[0] = p.children[i+1];
                    return ruleFromTree(p.children[0]);
                case "Pegged.Suffix":
                    result = ruleFromTree(p.children[0]);
                    foreach(child; p.children[1..$])
                    {
                        switch (child.name)
                        {
                            case "Pegged.OPTION":
                                result = option(result);
                                break;
                            case "Pegged.ZEROORMORE":
                                result =zeroOrMore(result);
                                break;
                            case "Pegged.ONEORMORE":
                                result= oneOrMore(result);
                                break;
                            /+ Action is not implemented
                            case "Pegged.Action":
                                foreach(action; child.matches)
                                    result = "pegged.peg.action!(" ~ result ~ ", " ~ action ~ ")";
                                break;
                            +/
                            default:
                                throw new Exception("Bad suffix: " ~ child.name);
                        }
                    }
                    return result;
                case "Pegged.Primary":
                    return ruleFromTree(p.children[0]);
                case "Pegged.RhsName":
                    return ruleFromTree(p.children[0]);
                /+
                result = "";
                    foreach(i,child; p.children)
                        result ~= generateCode(child);
                    break;
                +/
                /+
                case "Pegged.ArgList":
                    result = "!(";
                    foreach(child; p.children)
                        result ~= generateCode(child) ~ ", "; // Allow  A <- List('A'*,',')
                    result = result[0..$-2] ~ ")";
                    break;
                +/
                case "Pegged.Identifier":
                    writeln("Identifier: ", p.matches[0], " ", getDyn(p.matches[0])(ParseTree()).name);
                    return getDyn(p.matches[0]);
                /+
                case "Pegged.NAMESEP":
                    result = ".";
                    break;
                +/
                case "Pegged.Literal":
                    writeln("Literal: ", p.matches);
                    if(p.matches.length == 3) // standard case
                        return literal(p.matches[1]);
                    else // only two children -> empty literal
                        return eps;
                case "Pegged.CharClass":
                    if (p.children.length > 1)
                    {
                        Dynamic[] children;
                        foreach(seq; p.children)
                            children ~= ruleFromTree(seq);
                        return distribute!(pegged.dynamicpeg.or)(children);
                    }
                    else // One child -> just a sequence, no need for a or!( , )
                    {
                        return ruleFromTree(p.children[0]);
                    }
                    break;
                case "Pegged.CharRange":
                    /// Make the generation at the Char level: directly what is needed, be it `` or "" or whatever
                    if (p.children.length > 1) // a-b range
                    {
                        return charRange(p.matches[0].front, p.matches[1].front);
                    }
                    else // lone char
                    {
                        //result = "pegged.peg.literal!(";
                        string ch = p.matches[0];
                        switch (ch)
                        {
                            case "\\[":
                            case "\\]":
                            case "\\-":
                                return literal(ch[0..1]);
                            case "\\\'":
                                return literal("\'");
                            case "\\`":
                                return literal("`");
                            case "\\":
                            case "\\\\":
                                return literal("\\");
                            case "\"":
                            case "\\\"":
                                return literal("\"");
                            case "\n":
                            case "\r":
                            case "\t":
                                return literal(ch);
                            default:
                                return literal(ch);
                        }
                    }
                case "Pegged.Char":
                    string ch = p.matches[0];
                    switch (ch)
                    {
                        case "\\[":
                        case "\\]":
                        case "\\-":

                        case "\\\'":
                        case "\\\"":
                        case "\\`":
                        case "\\\\":
                            return literal(ch[1..$]);
                        case "\n":
                        case "\r":
                        case "\t":
                            return literal(ch);
                        default:
                            return literal(ch);
                    }
                    break;
                case "Pegged.POS":
                    return posLookahead(ruleFromTree(p.children[0]));
                case "Pegged.NEG":
                    return negLookahead(ruleFromTree(p.children[0]));
                case "Pegged.FUSE":
                    return fuse(ruleFromTree(p.children[0]));
                case "Pegged.DISCARD":
                    return discard(ruleFromTree(p.children[0]));
                case "Pegged.KEEP":
                    return keep(ruleFromTree(p.children[0]));
                case "Pegged.DROP":
                    return drop(ruleFromTree(p.children[0]));
                case "Pegged.PROPAGATE":
                    return propagate(ruleFromTree(p.children[0]));
                case "Pegged.OPTION":
                    return option(ruleFromTree(p.children[0]));
                case "Pegged.ZEROORMORE":
                    return zeroOrMore(ruleFromTree(p.children[0]));
                case "Pegged.ONEORMORE":
                    return zeroOrMore(ruleFromTree(p.children[0]));
                case "Pegged.Action":
                    result = ruleFromTree(p.children[0]);
                    foreach(act; p.matches[1..$])
                        result = action(result, getDyn(act));
                    return result;
                case "Pegged.ANY":
                    return any();
                case "Pegged.WrapAround":
                    return wrapAround( ruleFromTree(p.children[0])
                                    , ruleFromTree(p.children[1])
                                    , ruleFromTree(p.children[2]));
                default:
                    throw new Exception("Bad tree: " ~ p.toString());
            }
        }

        switch(def.children[1].children[0].name)
        {
            case "Pegged.LEFTARROW":
                gram[shortName] = ruleFromTree(def.children[2]);
                break;
            case "Pegged.FUSEARROW":
                gram[shortName] = ()=> fuse(ruleFromTree(def.children[2]));
                break;
            case "Pegged.DISCARDARROW":
                gram[shortName] = ()=> discard(ruleFromTree(def.children[2]));
                break;
            case "Pegged.KEEPARROW":
                gram[shortName] = ()=>keep(ruleFromTree(def.children[2]));
                break;
            case "Pegged.DROPARROW":
                gram[shortName] = ()=>drop(ruleFromTree(def.children[2]));
                break;
            case "Pegged.PROPAGATEARROW":
                gram[shortName] = ()=>propagate(ruleFromTree(def.children[2]));
                break;
            case "Pegged.SPACEARROW":
                ParseTree modified = spaceArrow(def.children[2]);
                gram[shortName] = ()=>ruleFromTree(modified);
                break;
            case "Pegged.ACTIONARROW":
                Dynamic actionResult = ruleFromTree(def.children[2]);
                foreach(act; def.children[1].matches[1..$])
                    actionResult = action(actionResult, getDyn(act));
                gram[shortName] = ()=>actionResult;
                break;
            default:
                throw new Exception("Unknow arrow: " ~ p.children[1].children[0].name);
                break;
        }
    }

    return gram;
}

Dynamic distribute(alias fun)(Dynamic[] args)
{
    writeln("Entering distribute for " ~ fun.stringof);
    switch(args.length)
    {
        case 2:
            return fun(args[0], args[1]);
        case 3:
            return fun(args[0], args[1], args[2]);
        case 4:
            return fun(args[0], args[1], args[2], args[3]);
        case 5:
            return fun(args[0], args[1], args[2], args[3], args[4]);
        case 6:
            return fun(args[0], args[1], args[2], args[3], args[4], args[5]);
        case 7:
            return fun(args[0], args[1], args[2], args[3], args[4], args[5], args[6]);
        case 8:
            return fun(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
        case 9:
            return fun(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8]);
        default:
            throw new Exception("Unimplemented distribute for more than 7 arguments.");
    }
}