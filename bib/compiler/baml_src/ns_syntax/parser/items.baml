// port: baml_parser/src/items.rs @ d9be6853b
//
// Declarations: the file, items, their members, signatures, parameters,
// generics and attributes. Section order follows the Rust file so the two
// read side by side.

// port: baml_parser/src/items.rs::HASH_STRING_REMOVED @ d9be6853b
const HASH_STRING_REMOVED: string = "Hash string literals like `#\"...\"#` are no longer supported. Use quoted strings or backtick strings instead.";
// port: baml_parser/src/items.rs::TYPE_BUILDER_REMOVED @ d9be6853b
const TYPE_BUILDER_REMOVED: string = "`type_builder` blocks were removed; runtime type construction is `reflect` (BEP-066)";
// port: baml_parser/src/items.rs::HEADER_COMMENT_MISPLACED @ d9be6853b
const HEADER_COMMENT_MISPLACED: string = "a `//#` header is a statement inside a block, or the title directly above a function; it is not allowed here";
// port: baml_parser/src/items.rs::HEADER_COMMENT_REPEATED @ d9be6853b
const HEADER_COMMENT_REPEATED: string = "a function has one `//#` title; this is a second one";

// port: baml_parser/src/items.rs::TOP_LEVEL_KEYWORD @ d9be6853b
// A keyword that always starts a fresh item at module scope; inside a body
// it means a closing brace is missing.
const TOP_LEVEL_KEYWORD: KindSet = KindSet.of(
    [
        TokenKind.Class,
        TokenKind.Enum,
        TokenKind.Interface,
        TokenKind.Function,
        TokenKind.Implements,
        TokenKind.Implement,
        TokenKind.Client,
        TokenKind.Generator,
        TokenKind.Test,
        TokenKind.Testset,
        TokenKind.RetryPolicy,
        TokenKind.TemplateString,
    ],
);

// port: baml_parser/src/items.rs::FUNCTION_NAME @ d9be6853b
// Reserved words of the interface syntax remain valid method and field-link
// names, notably on the reflection types.
const FUNCTION_NAME: KindSet = IDENT.union(
    KindSet.of(
        [
            TokenKind.Implements,
            TokenKind.Implement,
            TokenKind.Extends,
            TokenKind.Requires,
            TokenKind.Interface,
        ],
    ),
);

// port: baml_parser/src/items.rs::BLOCK_ATTR_NAME @ d9be6853b
// `@@name` segments: a name, or `throws` (`@@throws` is an attribute).
const BLOCK_ATTR_NAME: KindSet = IDENT.union(KindSet.of([TokenKind.Throws]));

// port: baml_parser/src/items.rs::at_item_head::{TYPE_OPENER, FUNCTION_OPENER, CONFIG_OPENER} @ d9be6853b
const TYPE_OPENER: KindSet = KindSet.of([TokenKind.LBrace, TokenKind.Less]);
const FUNCTION_OPENER: KindSet = KindSet.of([TokenKind.LParen, TokenKind.Less]);
const CONFIG_OPENER: KindSet = KindSet.of([TokenKind.LBrace, TokenKind.LParen]);

// port: baml_parser/src/items.rs::at_item_head @ d9be6853b
// Whether the cursor is at the head of an item no body can nest (`class
// Name {`, `function name(`, `client<` ...), so a body still open here was
// never closed. Reserved words are also member names (`class Class` is a
// field), hence the whole head shape.
function at_item_head(cur: Cursor) -> bool throws never {
    match (cur.kind(0)) {
        TokenKind.Class | TokenKind.Enum | TokenKind.Interface => {
            cur.nth_in(1, IDENT) && cur.nth_in(2, TYPE_OPENER)
        },
        TokenKind.Function => cur.nth_in(1, FUNCTION_NAME) && cur.nth_in(2, FUNCTION_OPENER),
        TokenKind.Generator | TokenKind.TemplateString => {
            cur.nth_in(1, IDENT) && cur.nth_in(2, CONFIG_OPENER)
        },
        TokenKind.Client => cur.nth_is(1, TokenKind.Less),
        _ => false,
    }
}

// port: baml_parser/src/items.rs::at_item_start::ITEM_START @ d9be6853b
const ITEM_START: KindSet = TOP_LEVEL_KEYWORD.union(
    KindSet.of(
        [
            TokenKind.Type,
            TokenKind.TypeBuilder,
            TokenKind.Dynamic,
            TokenKind.AtAt,
            TokenKind.DocComment,
            TokenKind.DirectiveComment,
        ],
    ),
);

// port: baml_parser/src/items.rs::at_item_start @ d9be6853b
// Whether an item can begin at the cursor: where a stray run of text ends.
function at_item_start(cur: Cursor) -> bool throws never {
    cur.at_in(ITEM_START) || cur.at_in(LET_INTRODUCER)
}

// port: baml_parser/src/items.rs::SIGNATURE_RESUME @ d9be6853b
// Where a function signature could resume after a missing name.
const SIGNATURE_RESUME: KindSet = KindSet.of(
    [TokenKind.LParen, TokenKind.Less, TokenKind.LBrace, TokenKind.Arrow, TokenKind.FatArrow],
);

// port: baml_parser/src/items.rs::INVALID_ALIAS_END @ d9be6853b
// Where a misspelled `type Name = ...` ends: a brace or the next declaration
// keyword.
const INVALID_ALIAS_END: KindSet = KindSet.of(
    [
        TokenKind.LBrace,
        TokenKind.RBrace,
        TokenKind.Class,
        TokenKind.Enum,
        TokenKind.Function,
        TokenKind.Client,
        TokenKind.Generator,
        TokenKind.Test,
    ],
);

// ----- names and strings ------------------------------------------------------------

// port: baml_parser/src/items.rs::reject_reserved_trace_parameter @ d9be6853b
function reject_reserved_trace_parameter(p: Parser) -> void throws never {
    if (p.cur.text_at(0) == "$trace") {
        p.error_here(
            "`$trace` is reserved for invocation tracing and cannot be declared as a parameter",
        );
    }
}

// port: baml_parser/src/items.rs::StringSite @ d9be6853b
// Where a string token is read: what is reported for it, and how.
enum StringSite {
    // An expression: everything is reported, and an unknown escape's message
    // offers a raw string as the fix.
    Expr,
    // A type, a pattern or an attribute argument, where a raw string does not
    // parse: everything is reported, with no raw-string fix.
    Literal,
    // An LLM prompt: a raw string is a fix, but a removed `#"..."#` here keeps
    // the prompt-specific migration diagnostic lowering emits.
    Prompt,
    // The body of a removed construct: only an unclosed literal is reported.
    Removed,
}

// port: baml_parser/src/items.rs::StringSite::reports_removed_hash @ d9be6853b
// Whether a removed `#"..."#` string is reported where it is read.
function reports_removed_hash(site: StringSite) -> bool throws never {
    match (site) {
        StringSite.Expr | StringSite.Literal => true,
        StringSite.Prompt | StringSite.Removed => false,
    }
}

// port: baml_parser/src/items.rs::StringSite::escape_check @ d9be6853b
// Whether escape sequences are checked here, and if so whether an unknown
// escape's message offers `r"..."` as the fix.
function escape_check(site: StringSite) -> RawStringFix? throws never {
    match (site) {
        StringSite.Expr | StringSite.Prompt => RawStringFix.Offered,
        StringSite.Literal => RawStringFix.Unavailable,
        StringSite.Removed => null,
    }
}

// port: baml_parser/src/items.rs::RawStringFix @ d9be6853b
// Whether an unknown escape's message offers a raw string: only where one
// would parse.
enum RawStringFix {
    Offered,
    Unavailable,
}

// port: baml_parser/src/items.rs::string_token_diagnostics @ d9be6853b
// Report what the string token `idx` carries: an unclosed literal, the
// removed `#"..."#` form, or escape sequences that do not decode.
function string_token_diagnostics(p: Parser, idx: int, site: StringSite) -> void throws never {
    let report_removed = reports_removed_hash(site);
    let range = p.cur.token_range(idx);
    match (p.cur.tokens().kinds[idx]) {
        TokenKind.UnclosedString => p.unexpected("Unclosed string literal"),
        TokenKind.UnclosedRawString => p.unexpected("Unclosed raw string literal"),
        TokenKind.UnclosedByteString => p.unexpected("Unclosed byte string literal"),
        TokenKind.UnclosedHashString => {
            let text = p.cur.text_of(idx);
            let hashes = 0;
            while (text.at(hashes) == "#") {
                hashes += 1;
            }
            p.unexpected(`Unclosed raw string (expected "${"#".repeat(hashes)}")`);
            if (report_removed) {
                p.removed(HASH_STRING_REMOVED, range);
            }
        },
        TokenKind.LegacyHashString => {
            if (report_removed) {
                p.removed(HASH_STRING_REMOVED, range);
            }
        },
        TokenKind.String | TokenKind.ByteString => {
            let fix = escape_check(site);
            if (fix != null) {
                report_escape_issues(p, idx, fix);
            }
        },
        TokenKind.RawString => {},
        let other => baml.sys.panic(`not a string token: ${other}`),
    }
}

// port: baml_parser/src/items.rs::report_escape_issues @ d9be6853b
// Report every escape sequence in the body of the closed `"..."` or `b"..."`
// literal at `idx` that does not decode: once, here, however many readers
// decode the literal later. An unclosed literal is not checked: its missing
// closer is its diagnostic.
function report_escape_issues(p: Parser, idx: int, fix: RawStringFix) -> void throws never {
    let text = p.cur.text_of(idx);
    let kind = p.cur.tokens().kinds[idx];
    let opener = match (kind) {
        TokenKind.String => 1,
        TokenKind.ByteString => 2,
        _ => baml.sys.panic(`not an escaped string token: ${kind}`),
    };
    let body = text.slice(opener, text.length() - 1);
    let issues = if (kind == TokenKind.String) {
        root.base.string_literal_escape_issues(body)
    } else {
        root.base.byte_string_literal_escape_issues(body)
    };
    // The opener is ASCII: its character count is its byte count.
    report_escape_issues_from(p, p.cur.token_range(idx).start + opener, issues, fix);
}

// port: baml_parser/src/items.rs::report_escape_issues_from @ d9be6853b
// Report `issues` found in literal text that begins at byte `body_start`.
function report_escape_issues_from(
    p: Parser,
    body_start: int,
    issues: root.base.EscapeIssue[],
    fix: RawStringFix,
) -> void throws never {
    for (let issue in issues) {
        if (fix == RawStringFix.Unavailable) {
            issue.suggest_raw_string = false;
        }
        let start = body_start + issue.start;
        p.out.report(
            InvalidStringEscape {
                issue: issue,
                range: TextRange { start: start, end: start + issue.len },
            },
        );
    }
}

// port: baml_parser/src/items.rs::string_lit @ d9be6853b
// A string literal at the current token, with its diagnostics.
function string_lit(p: Parser, site: StringSite) -> StringLit? throws never {
    let token = p.cur.eat_in(STRING_TOKEN)
        ?? return null;
    string_token_diagnostics(p, token, site);
    StringLit { span: p.span_from(Mark { idx: token }), token: token }
}

// port: baml_parser/src/items.rs::any_string_like @ d9be6853b
// A string literal or a backtick template.
function any_string_like(p: Parser, site: StringSite) -> AnyStringLike? throws never {
    let lit = string_lit(p, site);
    if (lit != null) {
        return lit;
    }
    let open = p.cur.eat(TokenKind.BacktickStart)
        ?? return null;
    parse_backtick_string(p, open)
}

// ----- attributes --------------------------------------------------------------------

// port: baml_parser/src/items.rs::Attribute::parse @ d9be6853b
// `name.segment(args)` after the `@` of a field or variant attribute.
function parse_attribute(p: Parser, at: int) -> Attribute throws never {
    let mark = Mark { idx: at };
    if (p.cur.has_newline_ahead()) {
        // The name must share the `@`'s line.
        let range = p.cur.token_range(at);
        let missing = p.missing_because("attribute is missing a name", range);
        return Attribute { span: p.span_from(mark), at: at, path: missing, args: null };
    }
    let head = p.cur.eat_in(IDENT);
    let path: DottedName | Missing = if (head != null) {
        dotted_name(p, head, IDENT, "attribute name segment after dot")
    } else {
        p.missing("attribute name")
    };
    let args = attr_args(p, path is DottedName);
    Attribute { span: p.span_from(mark), at: at, path: path, args: args }
}

// port: baml_parser/src/items.rs::attr_args @ d9be6853b
// The `(args)` of an attribute whose name is there.
function attr_args(p: Parser, named: bool) -> AttrArgs? throws never {
    if (!named) {
        return null;
    }
    let l = p.cur.eat(TokenKind.LParen)
        ?? return null;
    parse_attr_args(p, l)
}

// port: baml_parser/src/items.rs::trailing_attributes @ d9be6853b
// The `@attr`s trailing a field or enum variant. Attributes attach to
// declarations, never to types: a type parse stops at `@` and leaves them to
// the declaration that owns them.
function trailing_attributes(p: Parser) -> Attribute[] throws never {
    let attrs: Attribute[] = [];
    while let at: int = p.cur.eat(TokenKind.At) {
        attrs.push(parse_attribute(p, at));
    }
    attrs
}

// port: baml_parser/src/items.rs::BlockAttr::parse @ d9be6853b
// `name.segment(args)` after the `@@` of a declaration attribute.
function parse_block_attr(p: Parser, at: int) -> BlockAttr throws never {
    let head = p.cur.eat_in(BLOCK_ATTR_NAME);
    let path: DottedName | Missing = if (head != null) {
        dotted_name(p, head, BLOCK_ATTR_NAME, "attribute name segment after dot")
    } else {
        p.missing("attribute name")
    };
    let args = attr_args(p, path is DottedName);
    BlockAttr { span: p.span_from(Mark { idx: at }), at: at, path: path, args: args }
}

// port: baml_parser/src/items.rs::DocPart @ d9be6853b
// A `///` or `//baml:` line read before a declaration, not yet a node: it
// becomes one once the declaration that owns it is known, or one `Bogus`
// with its neighbours when no declaration follows.
class DocPartDoc {
    token: int,
}

class DocPartDirective {
    token: int,
    kind: DirectiveKind,
}

// A `//#` line: a function's title, an error above anything else.
class DocPartHeader {
    token: int,
}

// A `//baml:` line naming no directive, or a malformed trace hook.
class DocPartInvalid {
    token: int,
    problem: DocProblem,
}

type DocPart = DocPartDoc | DocPartDirective | DocPartHeader | DocPartInvalid;

// port: baml_parser/src/items.rs::DocProblem @ d9be6853b
// Why a doc line is no directive.
enum DocProblem {
    // `//baml:<name>` with a name no directive has.
    UnknownDirective,
    // `baml:$trace` with no `=a.b.c` hook path after it.
    MalformedTraceHook,
}

// port: baml_parser/src/items.rs::DocOwner @ d9be6853b
// What a run of docs belongs to: decides what its directives may be.
//
// A function definition, named once its name has parsed: directives are its
// attributes, with one trace hook at most.
class DocOwnerFunction {
    name: string?,
}

// Any other declaration or member: directives belong to function definitions
// only, so each one here is an error.
class DocOwnerOther {
}

type DocOwner = DocOwnerFunction | DocOwnerOther;

// port: baml_parser/src/items.rs::TRACE_HOOK_MISPLACED @ d9be6853b
const TRACE_HOOK_MISPLACED: string = "Trace hooks can only be attached to function definitions.\nhelp: Place `/// baml:$trace=...` immediately before a function definition.";
// port: baml_parser/src/items.rs::TRACE_PASSTHROUGH_MISPLACED @ d9be6853b
const TRACE_PASSTHROUGH_MISPLACED: string = "The internal trace_passthrough directive must immediately precede a function definition.";
// port: baml_parser/src/items.rs::TRACE_HOOK_MALFORMED @ d9be6853b
const TRACE_HOOK_MALFORMED: string = "Expected `/// baml:$trace=hook_name` with a function reference.\nhelp: Use a function name without call parentheses, for example `/// baml:$trace=trace.empty_span`.";

// port: baml_parser/src/items.rs::DocPart::token @ d9be6853b
function doc_part_token(part: DocPart) -> int throws never {
    match (part) {
        let d: DocPartDoc => d.token,
        let d: DocPartDirective => d.token,
        let d: DocPartHeader => d.token,
        let d: DocPartInvalid => d.token,
    }
}

// port: baml_parser/src/items.rs::leading_docs @ d9be6853b
// What precedes a declaration (`///` doc lines, `//baml:` directives and
// `//#` header lines) in source order, parsed before anything decides what
// they belong to. A header is trivia to the cursor, so the ones between the
// last token read and the next significant one are collected before each
// doc line.
function leading_docs(p: Parser) -> DocPart[] throws never {
    let parts: DocPart[] = [];
    while (true) {
        for (let header in p.cur.headers_ahead()) {
            parts.push(DocPartHeader { token: header });
        }
        let doc = p.cur.eat(TokenKind.DocComment);
        if (doc != null) {
            parts.push(doc_line(p, doc));
            continue;
        }
        let comment = p.cur.eat(TokenKind.DirectiveComment)
            ?? break;
        parts.push(directive(p, comment));
    }
    parts
}

// port: baml_parser/src/items.rs::doc_line @ d9be6853b
// A `///` line after its token: a doc line, unless it is a `baml:$trace`
// hook.
function doc_line(p: Parser, token: int) -> DocPart throws never {
    let value = trace_hook_value(p.cur.text_of(token));
    if (value != null) {
        return trace_hook(token, value);
    }
    DocPartDoc { token: token }
}

// port: baml_parser/src/items.rs::directive @ d9be6853b
// A `//baml:` line after its token: the directive it names, or invalid when
// it names none. `//baml:$trace=...` is the hook too.
function directive(p: Parser, token: int) -> DocPart throws never {
    let text = p.cur.text_of(token);
    let value = trace_hook_value(text);
    if (value != null) {
        return trace_hook(token, value);
    }
    let prefix = "//baml:";
    let name = if (text.starts_with(prefix)) {
        text.slice(prefix.length(), text.length())
    } else {
        ""
    };
    let kind = directive_kind_named(name.trim_end());
    if (kind == null) {
        return DocPartInvalid { token: token, problem: DocProblem.UnknownDirective };
    }
    DocPartDirective { token: token, kind: kind }
}

// port: baml_parser/src/items.rs::trace_hook @ d9be6853b
// `baml:$trace` with `value` after it: the hook when the value is `=a.b.c`.
function trace_hook(token: int, value: string) -> DocPart throws never {
    if (trace_hook_path(value) != null) {
        return DocPartDirective { token: token, kind: DirectiveKind.Trace };
    }
    DocPartInvalid { token: token, problem: DocProblem.MalformedTraceHook }
}

// port: baml_parser/src/items.rs::alloc_docs @ d9be6853b
// The nodes of a declaration's docs, now that it owns them. A directive the
// owner cannot take, a second trace hook, a line that is no directive, or a
// `//#` header above anything but a function (or a second one above a
// function) is a `Bogus` with its error, so a `Directive` or `HeaderLine`
// node is always one its owner accepts.
function alloc_docs(p: Parser, docs: DocPart[], owner: DocOwner) -> AnyDoc[] throws never {
    let is_function = owner is DocOwnerFunction;
    let hook_seen = false;
    let header_seen = false;
    let nodes: AnyDoc[] = [];
    for (let part in docs) {
        // The declaration's keyword has been read by now: each node spans
        // exactly its own line.
        let token = doc_part_token(part);
        let span = Mark { idx: token }.to(token + 1);
        let range = p.cur.token_range(token);
        if (part is DocPartHeader) {
            let accepted = is_function && !header_seen;
            header_seen = true;
            if (accepted) {
                nodes.push(p.out.header_line(HeaderLine { span: span, token: token }));
                continue;
            }
            let message = if (is_function) {
                HEADER_COMMENT_REPEATED
            } else {
                HEADER_COMMENT_MISPLACED
            };
            nodes.push(p.bogus_tokens(span, InvalidSyntax { message: message, range: range }));
            continue;
        }
        let text = p.cur.text_of(token).trim_end();
        let message = doc_rejection(part, owner, text, hook_seen);
        if (message != null) {
            nodes.push(p.bogus_tokens(span, InvalidDirective { message: message, range: range }));
            continue;
        }
        match (part) {
            let d: DocPartDirective => {
                hook_seen = hook_seen || d.kind == DirectiveKind.Trace;
                nodes.push(Directive { span: span, token: token, kind: d.kind });
            },
            _ => {
                nodes.push(DocLine { span: span, token: token });
            },
        }
    }
    nodes
}

// port: baml_parser/src/items.rs::alloc_docs (the message match) @ d9be6853b
// Why `owner` cannot take the doc line `part` (its text trimmed), or null
// when it is accepted. Headers are decided by the caller.
// deviation: Rust computes this inline in `alloc_docs`; split out to keep the
// loop readable.
function doc_rejection(
    part: DocPart,
    owner: DocOwner,
    text: string,
    hook_seen: bool,
) -> string? throws never {
    match (owner) {
        let f: DocOwnerFunction => match (part) {
            let d: DocPartDirective if d.kind == DirectiveKind.Trace && hook_seen => {
                `Function \`${f.name ?? ""}\` declares more than one trace hook.\nhelp: Keep one \`/// baml:$trace=...\` directive.`
            },
            let d: DocPartInvalid => match (d.problem) {
                DocProblem.UnknownDirective => `unknown directive \`${text}\``,
                DocProblem.MalformedTraceHook => match (f.name) {
                    null => `Invalid trace hook directive. ${TRACE_HOOK_MALFORMED}`,
                    let name: string => {
                        `Invalid trace hook directive on function \`${name}\`.\n${TRACE_HOOK_MALFORMED}`
                    },
                },
            },
            _ => null,
        },
        _ => match (part) {
            let d: DocPartDirective => match (d.kind) {
                DirectiveKind.Trace => TRACE_HOOK_MISPLACED,
                DirectiveKind.TracePassthrough => TRACE_PASSTHROUGH_MISPLACED,
                DirectiveKind.MutSelf
                    | DirectiveKind.Vm
                    | DirectiveKind.MutVm
                    | DirectiveKind.MayYield
                    | DirectiveKind.Fallible
                    | DirectiveKind.TaggedString
                    | DirectiveKind.LocalTwin =>
                {
                    `\`${text}\` can only be attached to function definitions.`
                },
            },
            let d: DocPartInvalid => match (d.problem) {
                DocProblem.MalformedTraceHook => TRACE_HOOK_MISPLACED,
                DocProblem.UnknownDirective => `unknown directive \`${text}\``,
            },
            _ => null,
        },
    }
}

// port: baml_parser/src/items.rs::reject_docs @ d9be6853b
// Docs that precede nothing they can document: one `Bogus` over their lines,
// with the error; null when there are none. A run of `//#` headers alone
// gets the header message.
function reject_docs(p: Parser, docs: DocPart[]) -> Bogus? throws never {
    let first = docs.at(0)
        ?? return null;
    let last = docs[docs.length() - 1];
    let tokens = TokenRange { start: doc_part_token(first), end: doc_part_token(last) + 1 };
    let range = p.cur.text_range(tokens);
    let error: ParseError = if (
        docs.every((doc) -> {
            doc is DocPartHeader
        })
    ) {
        InvalidSyntax { message: HEADER_COMMENT_MISPLACED, range: range }
    } else {
        InvalidDirective {
            message: "`///` doc comments and `//baml:` directives must directly precede the declaration they belong to; use `//` for a plain comment",
            range: range,
        }
    };
    p.bogus_tokens(tokens, error)
}

// port: baml_parser/src/items.rs::prefixed_mark @ d9be6853b
// Where a declaration with `docs` begins: at its first doc line, else at
// `token`.
function prefixed_mark(docs: DocPart[], token: int) -> Mark throws never {
    let first = docs.at(0);
    if (first == null) {
        return Mark { idx: token };
    }
    Mark { idx: doc_part_token(first) }
}

// port: baml_parser/src/items.rs::dotted_name @ d9be6853b
// `b.c` after the first name `head` of `a.b.c`, each later segment one of
// `segment`; a dot with no segment after it is reported as `expected`.
function dotted_name(
    p: Parser,
    head: int,
    segment: KindSet,
    expected: string,
) -> DottedName throws never {
    let mark = Mark { idx: head };
    let name = p.name(head);
    let segments = path_segments(p, (p) -> {
        p.expect_name(segment, expected)
    });
    DottedName { span: p.span_from(mark), head: name, segments: segments }
}

// port: baml_parser/src/items.rs::path_segments @ d9be6853b
// `.name` segments after a path head, for as long as a `.` follows. A dot
// with no name after it (`segment` says so with a `Missing`) ends the path.
function path_segments(
    p: Parser,
    segment: (Parser) -> Name | Missing throws never,
) -> PathSegment[] throws never {
    let segments: PathSegment[] = [];
    while let dot: int = p.cur.eat(TokenKind.Dot) {
        let name = segment(p);
        segments.push(PathSegment { dot: dot, name: name });
        if (name is Missing) {
            break;
        }
    }
    segments
}

// port: baml_parser/src/items.rs::AttrArgs::parse @ d9be6853b
function parse_attr_args(p: Parser, l: int) -> AttrArgs throws never {
    let args = p.sep_list(TokenKind.RParen, TokenKind.Comma, attribute_arg);
    let r = p.expect(TokenKind.RParen);
    AttrArgs { span: p.span_from(Mark { idx: l }), l: l, args: args, r: r }
}

// port: baml_parser/src/items.rs::attribute_arg @ d9be6853b
// `"text"`, a backtick template, `{{ jinja }}`, or one bare word.
function attribute_arg(p: Parser) -> AnyAttrArg? throws never {
    let lit = string_lit(p, StringSite.Literal);
    if (lit != null) {
        return lit;
    }
    let open = p.cur.eat(TokenKind.BacktickStart);
    if (open != null) {
        return parse_backtick_string(p, open);
    }
    if (p.cur.at(TokenKind.LBrace) && p.cur.nth_is(1, TokenKind.LBrace)) {
        let l1 = p.cur.eat(TokenKind.LBrace);
        let l2 = p.cur.eat(TokenKind.LBrace);
        if (l1 != null && l2 != null) {
            return parse_jinja_arg(p, l1, l2);
        }
    }
    let name = p.eat_name(IDENT);
    if (name != null) {
        return name;
    }
    p.unexpected("attribute argument");
    null
}

// port: baml_parser/src/items.rs::JinjaArg::parse @ d9be6853b
// `... }}` after the `{{`, kept as its tokens.
function parse_jinja_arg(p: Parser, l1: int, l2: int) -> JinjaArg throws never {
    let mark = Mark { idx: l1 };
    let body = p.cur.mark();
    while (!(p.cur.at_end() || p.cur.at(TokenKind.RBrace) && p.cur.nth_is(1, TokenKind.RBrace))) {
        p.cur.skip();
    }
    let tokens = p.cur.range_from(body);
    let r1 = p.expect(TokenKind.RBrace);
    let r2 = p.expect(TokenKind.RBrace);
    JinjaArg { span: p.span_from(mark), l1: l1, l2: l2, tokens: tokens, r1: r1, r2: r2 }
}

// ----- generics and parameters ---------------------------------------------------------

// port: baml_parser/src/items.rs::GenericParamList::parse @ d9be6853b
// Declaration-site `T, U extends A & B>` after its `<`.
function parse_generic_param_list(p: Parser, l: int) -> GenericParamList throws never {
    let params = p.sep_list(TokenKind.Greater, TokenKind.Comma, generic_param);
    let r = p.expect(TokenKind.Greater);
    GenericParamList { span: p.span_from(Mark { idx: l }), l: l, params: params, r: r }
}

// port: baml_parser/src/items.rs::generic_param @ d9be6853b
function generic_param(p: Parser) -> GenericParam? throws never {
    let name = p.eat_name(IDENT);
    if (name == null) {
        p.unexpected("type parameter name");
        return null;
    }
    let kw = p.cur.eat(TokenKind.Extends);
    let bounds = if (kw != null) {
        parse_generic_param_bounds(p, kw)
    } else {
        null
    };
    let mark = p.mark_of(name.span);
    GenericParam { span: p.span_from(mark), name: name, bounds: bounds }
}

// port: baml_parser/src/items.rs::GenericParamBounds::parse @ d9be6853b
// `A & B` after the `extends` of a generic parameter or a `let type` binding.
function parse_generic_param_bounds(p: Parser, kw: int) -> GenericParamBounds throws never {
    let mark = Mark { idx: kw };
    let first = any_type(p);
    let rest: BoundArm[] = [];
    while let amp: int = p.cur.eat(TokenKind.And) {
        let ty = any_type(p);
        rest.push(BoundArm { and: amp, ty: ty });
        if (ty is Missing) {
            break;
        }
    }
    if (p.cur.at(TokenKind.As)) {
        // Consumed for recovery and rejected; the tokens stay unowned.
        p.error_here(
            "generic bound aliases are not supported; use `.as<Interface<...>>()` at call sites",
        );
        p.cur.skip();
        if (p.cur.at_ident()) {
            p.cur.skip();
        } else {
            p.unexpected("alias name");
        }
    }
    GenericParamBounds { span: p.span_from(mark), kw: kw, first: first, rest: rest }
}

// port: baml_parser/src/items.rs::Annotation @ d9be6853b
// Whether a parameter's type annotation is required (a declaration) or
// optional (a lambda, whose parameter types may be inferred).
enum Annotation {
    Required,
    Optional,
}

// port: baml_parser/src/items.rs::param_list @ d9be6853b
// `a: A, b = default)` after the `(`. Rust's `ParamList::parse` is this with
// `Annotation::Required`.
function param_list(p: Parser, l: int, annotation: Annotation) -> ParamList throws never {
    let params = p.sep_list(TokenKind.RParen, TokenKind.Comma, (p) -> {
        param(p, annotation)
    });
    let r = p.expect(TokenKind.RParen);
    ParamList { span: p.span_from(Mark { idx: l }), l: l, params: params, r: r }
}

// port: baml_parser/src/items.rs::param @ d9be6853b
// `name: T = default`; `self` takes no type. The colon is optional, but
// without it the type must share the name's line.
function param(p: Parser, annotation: Annotation) -> Param? throws never {
    let mark = p.cur.mark();
    reject_reserved_trace_parameter(p);
    let is_self = p.cur.at(TokenKind.SelfValue);
    let eaten = p.eat_name(EXPR_NAME);
    let name: Name | Missing = if (eaten != null) {
        eaten
    } else if (annotation == Annotation.Required && is_at_type_start(p.cur)) {
        // A bare type: the name is missing, the type is kept.
        p.missing("parameter name")
    } else {
        p.unexpected("parameter name");
        return null;
    };
    let ascription: TypeAscription? = null;
    if (!is_self) {
        let ascription_mark = p.cur.mark();
        let colon = p.cur.eat(TokenKind.Colon);
        let newline_before_type = p.cur.has_newline_ahead();
        if (annotation == Annotation.Required) {
            let ty = if (is_at_type_start(p.cur) && (!newline_before_type || colon != null)) {
                any_type(p)
            } else {
                p.missing("type annotation")
            };
            reject_unmatched_greater(p);
            ascription = TypeAscription { span: p.span_from(ascription_mark), colon: colon, ty: ty };
        } else if (colon != null) {
            let ty = any_type(p);
            reject_unmatched_greater(p);
            ascription = TypeAscription { span: p.span_from(ascription_mark), colon: colon, ty: ty };
        }
    }
    // `self` consumes a default too, so lowering can reject it specifically.
    let eq = p.cur.eat(TokenKind.Equals);
    let default_value: DefaultValue? = null;
    if (eq != null) {
        let value = if (at_expression_start(p.cur)) {
            expr(p, Restrictions.empty())
        } else {
            p.missing("expression")
        };
        default_value = DefaultValue { span: p.span_from(Mark { idx: eq }), eq: eq, value: value };
    }
    Param { span: p.span_from(mark), name: name, ascription: ascription, default: default_value }
}

// ----- functions ------------------------------------------------------------------------

// port: baml_parser/src/items.rs::Signature @ d9be6853b
// The head every function-shaped member shares:
// `function name<G>(params) -> R throws E`. Its docs are not here: what they
// may hold depends on whether a body follows, so the caller owns them once
// it knows.
class Signature {
    kw: int,
    name: Name | Missing,
    generics: GenericParamList?,
    params: ParamList | Missing,
    ret: ReturnType | Missing,
    throws_: ThrowsClause?,
    // Whether a `{` body may be an LLM body: not after `-> {` (the brace is
    // the body, and `client` text inside must not masquerade as an LLM field)
    // nor after a missing return type.
    allow_llm_body: bool,

    // port: baml_parser/src/items.rs::Signature::function_docs @ d9be6853b
    // The docs of the definition this signature heads, reported by its name
    // where a trace hook is malformed or repeated.
    function function_docs(self, p: Parser, docs: DocPart[]) -> AnyDoc[] throws never {
        let name = match (self.name) {
            let n: Name => p.cur.text_of(n.token),
            _ => null,
        };
        alloc_docs(p, docs, DocOwnerFunction { name: name })
    }
}

// port: baml_parser/src/items.rs::signature @ d9be6853b
// After `function`.
function signature(p: Parser, kw: int) -> Signature throws never {
    let eaten = p.eat_name(FUNCTION_NAME);
    let name: Name | Missing = if (eaten != null) {
        eaten
    } else {
        let missing = p.missing("function name");
        // Recovery: skip to where the signature could resume.
        p.cur.skip_until(SIGNATURE_RESUME);
        missing
    };

    let less = p.cur.eat(TokenKind.Less);
    let generics = if (less != null) {
        parse_generic_param_list(p, less)
    } else {
        null
    };

    // Old-style `function Name {`: one diagnostic for the whole missing head.
    if (p.cur.at(TokenKind.LBrace)) {
        let range = p.cur.error_range();
        let missing = p.missing_because(
            "old-style function syntax; use `function Name(params...) -> ReturnType { ... }`",
            range,
        );
        return Signature {
            kw: kw,
            name: name,
            generics: generics,
            params: missing,
            ret: missing,
            throws_: null,
            allow_llm_body: false,
        };
    }

    let lparen = p.cur.eat(TokenKind.LParen);
    let params = if (lparen != null) {
        param_list(p, lparen, Annotation.Required)
    } else {
        p.missing("'('")
    };

    // `=>` is accepted in place of `->`; the formatter canonicalizes.
    let allow_llm_body = true;
    let arrow = p.cur.eat_in(ANY_ARROW);
    let ret: ReturnType | Missing = if (arrow != null) {
        if (p.cur.at(TokenKind.LBrace)) {
            allow_llm_body = false;
        }
        let ty = any_type(p);
        reject_unmatched_greater(p);
        ReturnType { span: p.span_from(Mark { idx: arrow }), arrow: arrow, ty: ty }
    } else {
        allow_llm_body = false;
        p.missing("return type (->)")
    };

    let throws_kw = p.cur.eat(TokenKind.Throws);
    let throws_ = if (throws_kw != null) {
        parse_throws_clause(p, throws_kw)
    } else {
        null
    };

    Signature {
        kw: kw,
        name: name,
        generics: generics,
        params: params,
        ret: ret,
        throws_: throws_,
        allow_llm_body: allow_llm_body,
    }
}

// port: baml_parser/src/items.rs::function_def @ d9be6853b
// `... { body }` after `function`: a function, method or default method,
// whose body is required. `mark` is where its docs began.
function function_def(p: Parser, mark: Mark, docs: DocPart[], kw: int) -> FunctionDef throws never {
    let sig = signature(p, kw);
    let doc_nodes = sig.function_docs(p, docs);
    let l = p.cur.eat(TokenKind.LBrace);
    let body = if (l != null) {
        function_body(p, l, sig.allow_llm_body)
    } else {
        p.missing("function body")
    };
    FunctionDef {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: sig.kw,
        name: sig.name,
        generics: sig.generics,
        params: sig.params,
        ret: sig.ret,
        throws_: sig.throws_,
        body: body,
    }
}

// port: baml_parser/src/items.rs::interface_method @ d9be6853b
// A method in an interface: a definition when a body follows the signature,
// otherwise a required signature (`;` optional). Decided by the token after
// the signature, not by a scan ahead of it.
function interface_method(
    p: Parser,
    mark: Mark,
    docs: DocPart[],
    kw: int,
) -> AnyInterfaceMember throws never {
    let sig = signature(p, kw);
    let l = p.cur.eat(TokenKind.LBrace);
    if (l != null) {
        let doc_nodes = sig.function_docs(p, docs);
        let body = function_body(p, l, sig.allow_llm_body);
        return FunctionDef {
            span: p.span_from(mark),
            docs: doc_nodes,
            kw: sig.kw,
            name: sig.name,
            generics: sig.generics,
            params: sig.params,
            ret: sig.ret,
            throws_: sig.throws_,
            body: body,
        };
    }
    // A required method is no definition: nothing reads a directive on it.
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let semi = p.cur.eat(TokenKind.Semicolon);
    MethodSig {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: sig.kw,
        name: sig.name,
        generics: sig.generics,
        params: sig.params,
        ret: sig.ret,
        throws_: sig.throws_,
        semi: semi,
    }
}

// port: baml_parser/src/items.rs::function_body @ d9be6853b
// After the body's `{`: an LLM body when allowed and its first member says
// so, otherwise an expression body.
function function_body(p: Parser, l: int, allow_llm_body: bool) -> AnyFunctionBody throws never {
    if (allow_llm_body && p.cur.looks_like_llm_function_body_from(p.cur.sig_index(l))) {
        parse_llm_body(p, l)
    } else {
        block(p, l)
    }
}

// port: baml_parser/src/items.rs::LlmBody::parse @ d9be6853b
function parse_llm_body(p: Parser, l: int) -> LlmBody throws never {
    let mark = Mark { idx: l };
    let fields: AnyLlmField[] = [];
    let has_client = false;
    let has_prompt = false;
    let has_tools = false;
    while (!p.cur.at(TokenKind.RBrace) && !p.cur.at_end()) {
        // A top-level keyword other than `client` means a `}` is missing.
        if (p.cur.at_in(TOP_LEVEL_KEYWORD) && !p.cur.at(TokenKind.Client)) {
            break;
        }
        if (p.cur.at(TokenKind.Client) && has_client) {
            p.unexpected("Duplicate 'client' field");
        } else if (p.cur.at(TokenKind.Prompt) && has_prompt) {
            p.unexpected("Duplicate 'prompt' field");
        } else if (p.cur.at(TokenKind.Tools) && has_tools) {
            p.unexpected("Duplicate 'tools' field");
        }
        let kind = p.cur.kind(0);
        if (kind == TokenKind.Client) {
            has_client = true;
            fields.push(parse_client_field(p, p.cur.eat(TokenKind.Client) ?? 0));
        } else if (kind == TokenKind.Prompt) {
            has_prompt = true;
            fields.push(parse_prompt_field(p, p.cur.eat(TokenKind.Prompt) ?? 0));
        } else if (kind == TokenKind.Tools) {
            has_tools = true;
            fields.push(parse_tools_field(p, p.cur.eat(TokenKind.Tools) ?? 0));
        } else if (at_removed_type_builder(p.cur)) {
            fields.push(skip_removed_type_builder(p, p.cur.eat(TokenKind.TypeBuilder) ?? 0));
        } else if (p.cur.at(TokenKind.Comma) || p.cur.at(TokenKind.Semicolon)) {
            // Fields are separated by a newline; name the real requirement instead
            // of letting the value scanner swallow the separator and misreport
            // `prompt` as missing.
            let sep = p.cur.text_at(0) ?? "";
            let error = InvalidSyntax {
                message: `unexpected \`${sep}\` between LLM function fields; separate \`client\` and \`prompt\` with a newline`,
                range: p.cur.error_range(),
            };
            let sep_mark = p.cur.mark();
            p.cur.skip();
            fields.push(p.bogus_since(sep_mark, error));
        } else {
            // A name is quoted as written; anything else by its kind, so the
            // message never embeds a whole string literal.
            let found = if (kind == null) {
                "EOF"
            } else if (IDENT.contains(kind)) {
                p.cur.text_at(0) ?? ""
            } else {
                found_name(kind)
            };
            fields.push(
                p.bogus_one(
                    `Only 'client', 'tools' and 'prompt' allowed in LLM function, found '${found}'`,
                ),
            );
        }
    }
    if (!has_client) {
        p.unexpected("LLM function missing 'client' field");
    }
    if (!has_prompt) {
        p.unexpected("LLM function missing 'prompt' field");
    }
    let r = p.expect(TokenKind.RBrace);
    LlmBody { span: p.span_from(mark), l: l, fields: fields, r: r }
}

// port: baml_parser/src/items.rs::ClientField::parse @ d9be6853b
// `client: "provider/model"` or `client: <expr>`. The legacy unquoted
// `openai/gpt-4o` is an expression here (a division) that lowering rejects
// with a migration error.
function parse_client_field(p: Parser, kw: int) -> ClientField throws never {
    let mark = Mark { idx: kw };
    let colon = p.expect(TokenKind.Colon);
    let value = if (p.cur.at(TokenKind.RBrace) || p.cur.has_newline_ahead() || p.cur.at_end()) {
        p.missing("client value")
    } else if (at_expression_start(p.cur)) {
        expr(p, Restrictions.statement())
    } else {
        p.missing("expression")
    };
    ClientField { span: p.span_from(mark), kw: kw, colon: colon, value: value }
}

// port: baml_parser/src/items.rs::ToolsField::parse @ d9be6853b
function parse_tools_field(p: Parser, kw: int) -> ToolsField throws never {
    let mark = Mark { idx: kw };
    let colon = p.expect(TokenKind.Colon);
    let value = if (at_expression_start(p.cur)) {
        expr(p, Restrictions.statement())
    } else {
        p.missing("expression")
    };
    ToolsField { span: p.span_from(mark), kw: kw, colon: colon, value: value }
}

// port: baml_parser/src/items.rs::PromptField::parse @ d9be6853b
// `prompt: "..."` or a backtick template. A removed hash string here keeps
// the prompt-specific migration diagnostic lowering emits instead of also
// reporting the general one.
function parse_prompt_field(p: Parser, kw: int) -> PromptField throws never {
    let mark = Mark { idx: kw };
    let colon = p.expect(TokenKind.Colon);
    let value = any_string_like(p, StringSite.Prompt) ?? p.missing("prompt string");
    PromptField { span: p.span_from(mark), kw: kw, colon: colon, value: value }
}

// ----- enums ------------------------------------------------------------------------------

// port: baml_parser/src/items.rs::enum_def @ d9be6853b
// After `enum`, with the docs already parsed; `mark` is where they began.
function enum_def(p: Parser, mark: Mark, docs: AnyDoc[], kw: int) -> EnumDef throws never {
    let name = p.expect_name(IDENT, "enum name");
    let l = p.expect(TokenKind.LBrace);
    if (l is Missing) {
        return EnumDef { span: p.span_from(mark), docs: docs, kw: kw, name: name, l: l, members: [], r: l };
    }
    let members: AnyEnumMember[] = [];
    while (!p.cur.at(TokenKind.RBrace) && !p.cur.at_end()) {
        // A top-level keyword means the closing brace is missing.
        if (p.cur.at_in(TOP_LEVEL_KEYWORD)) {
            break;
        }
        let at = p.cur.eat(TokenKind.AtAt);
        if (at != null) {
            members.push(parse_block_attr(p, at));
            continue;
        }
        let member_docs = leading_docs(p);
        if (p.cur.at(TokenKind.AtAt)) {
            // The docs documented nothing; the attribute is the next member.
            let rejected = reject_docs(p, member_docs);
            if (rejected != null) {
                members.push(rejected);
            }
            continue;
        }
        let name = if (p.cur.at_in(TOP_LEVEL_KEYWORD)) {
            null
        } else {
            p.cur.eat_in(IDENT)
        };
        if (name != null) {
            members.push(parse_enum_variant(p, member_docs, name));
            continue;
        }
        let rejected = reject_docs(p, member_docs);
        if (rejected != null) {
            members.push(rejected);
        }
        // After trailing docs the body may be over: nothing to skip.
        if (p.cur.at_in(TOP_LEVEL_KEYWORD) || p.cur.at(TokenKind.RBrace) || p.cur.at_end()) {
            break;
        }
        members.push(p.bogus_one("Unexpected token in enum body"));
    }
    let r = p.expect(TokenKind.RBrace);
    EnumDef {
        span: p.span_from(mark),
        docs: docs,
        kw: kw,
        name: name,
        l: l,
        members: members,
        r: r,
    }
}

// port: baml_parser/src/items.rs::EnumVariant::parse @ d9be6853b
// A variant after its name.
function parse_enum_variant(p: Parser, docs: DocPart[], name: int) -> EnumVariant throws never {
    let mark = prefixed_mark(docs, name);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let name_node = p.name(name);
    // `A int | string` is a type annotation (an error), `A\n    B` is the next
    // variant: a following name is a type only when a modifier follows it;
    // literals and `(` can only be types.
    let has_type_annotation = if (p.cur.at_ident()) {
        match (p.cur.kind(1)) {
            TokenKind.Pipe | TokenKind.LBracket | TokenKind.Question | TokenKind.Less => true,
            _ => false,
        }
    } else {
        p.cur.at_in(STRING_TOKEN)
            || match (p.cur.kind(0)) {
                TokenKind.Bigint | TokenKind.Integer | TokenKind.Float | TokenKind.LParen => true,
                _ => false,
            }
    };
    if (has_type_annotation) {
        // Parsed for its extent and its own diagnostics, then discarded.
        let ty_mark = p.cur.mark();
        p.discard((p) -> {
            any_type(p);
        });
        let range = p.cur.text_range(p.cur.range_from(ty_mark));
        p.error("enum variants cannot have type annotations", range);
    }
    let attrs = trailing_attributes(p);
    // Commas are canonical; a semicolon is a slip the formatter repairs.
    let sep = p.cur.eat_in(MEMBER_SEP);
    EnumVariant {
        span: p.span_from(mark),
        docs: doc_nodes,
        name: name_node,
        attrs: attrs,
        sep: sep,
    }
}

// ----- classes -----------------------------------------------------------------------------

// port: baml_parser/src/items.rs::class_def @ d9be6853b
// After `class`, with the docs already parsed; `mark` is where they began.
function class_def(p: Parser, mark: Mark, docs: AnyDoc[], kw: int) -> ClassDef throws never {
    let name = p.expect_name(IDENT, "class name");
    let less = p.cur.eat(TokenKind.Less);
    let generics = if (less != null) {
        parse_generic_param_list(p, less)
    } else {
        null
    };
    let l = p.expect(TokenKind.LBrace);
    if (l is Missing) {
        return ClassDef {
            span: p.span_from(mark),
            docs: docs,
            kw: kw,
            name: name,
            generics: generics,
            l: l,
            members: [],
            r: l,
        };
    }
    let members: AnyClassMember[] = [];
    while (!p.cur.at(TokenKind.RBrace) && !p.cur.at_end()) {
        if (class_body_ends(p.cur)) {
            break;
        }
        // A `@@` attribute is the class's, wherever in the body it stands.
        let at = p.cur.eat(TokenKind.AtAt);
        if (at != null) {
            members.push(parse_block_attr(p, at));
            continue;
        }
        let member_mark = p.cur.mark();
        let member_docs = leading_docs(p);
        if (p.cur.at(TokenKind.AtAt)) {
            // The docs documented nothing; the attribute is the next member.
            let rejected = reject_docs(p, member_docs);
            if (rejected != null) {
                members.push(rejected);
            }
            continue;
        }
        let fn_kw = p.cur.eat(TokenKind.Function);
        if (fn_kw != null) {
            members.push(function_def(p, member_mark, member_docs, fn_kw));
            continue;
        }
        let impl_kw = p.cur.eat_in(IMPLEMENTS_KW);
        if (impl_kw != null) {
            members.push(parse_implements_block(p, member_docs, impl_kw));
            continue;
        }
        let ends = class_body_ends(p.cur);
        let name = if (ends) {
            null
        } else {
            p.cur.eat_in(MEMBER_NAME)
        };
        if (name != null) {
            members.push(parse_field(p, member_docs, name));
            continue;
        }
        // The docs preceded the next item or nothing, not a member.
        let rejected = reject_docs(p, member_docs);
        if (rejected != null) {
            members.push(rejected);
        }
        // After trailing docs the body may be over: nothing to skip.
        if (ends || p.cur.at(TokenKind.RBrace) || p.cur.at_end()) {
            break;
        }
        members.push(p.bogus_one("Unexpected token in class body"));
    }
    let r = p.expect(TokenKind.RBrace);
    ClassDef {
        span: p.span_from(mark),
        docs: docs,
        kw: kw,
        name: name,
        generics: generics,
        l: l,
        members: members,
        r: r,
    }
}

// port: baml_parser/src/items.rs::Field::parse @ d9be6853b
// `name: T @attr,` after its name: the colon is optional, but without it
// the type must share the name's line.
function parse_field(p: Parser, docs: DocPart[], name: int) -> Field throws never {
    let mark = prefixed_mark(docs, name);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let name_node = p.name(name);
    let colon = p.cur.eat(TokenKind.Colon);
    let newline_before_type = p.cur.has_newline_ahead();
    let ty = if (is_at_type_start(p.cur) && (!newline_before_type || colon != null)) {
        any_type(p)
    } else {
        let text = p.cur.text_of(name);
        p.missing_because(`field '${text}' is missing a type annotation`, p.cur.token_range(name))
    };
    reject_unmatched_greater(p);
    let attrs = trailing_attributes(p);
    let sep = p.cur.eat_in(MEMBER_SEP);
    Field {
        span: p.span_from(mark),
        docs: doc_nodes,
        name: name_node,
        colon: colon,
        ty: ty,
        attrs: attrs,
        sep: sep,
    }
}

// ----- interfaces -----------------------------------------------------------------------------

// port: baml_parser/src/items.rs::interface_def @ d9be6853b
// After `interface`, with the docs already parsed; `mark` is where they
// began.
function interface_def(
    p: Parser,
    mark: Mark,
    docs: AnyDoc[],
    kw: int,
) -> InterfaceDef throws never {
    let name = p.expect_name(IDENT, "interface name");
    let less = p.cur.eat(TokenKind.Less);
    let generics = if (less != null) {
        parse_generic_param_list(p, less)
    } else {
        null
    };
    // Interfaces do not extend each other: `requires` says implementors must
    // also implement the listed interfaces.
    let requires_kw = p.cur.eat(TokenKind.Requires);
    let requires_ = if (requires_kw != null) {
        parse_requires_clause(p, requires_kw)
    } else {
        null
    };
    let l = p.expect(TokenKind.LBrace);
    if (l is Missing) {
        return InterfaceDef {
            span: p.span_from(mark),
            docs: docs,
            kw: kw,
            name: name,
            generics: generics,
            requires_: requires_,
            l: l,
            members: [],
            r: l,
        };
    }
    let members: AnyInterfaceMember[] = [];
    while (!p.cur.at(TokenKind.RBrace) && !p.cur.at_end()) {
        if (p.cur.at_in(TOP_LEVEL_KEYWORD) && !p.cur.at(TokenKind.Function)) {
            break;
        }
        let at = p.cur.eat(TokenKind.AtAt);
        if (at != null) {
            members.push(parse_block_attr(p, at));
            continue;
        }
        let member_mark = p.cur.mark();
        let member_docs = leading_docs(p);
        if (p.cur.at(TokenKind.AtAt)) {
            // The docs documented nothing; the attribute is the next member.
            let rejected = reject_docs(p, member_docs);
            if (rejected != null) {
                members.push(rejected);
            }
            continue;
        }
        let fn_kw = p.cur.eat(TokenKind.Function);
        if (fn_kw != null) {
            members.push(interface_method(p, member_mark, member_docs, fn_kw));
            continue;
        }
        let type_kw = p.cur.eat(TokenKind.Type);
        if (type_kw != null) {
            members.push(parse_assoc_type_decl(p, member_docs, type_kw));
            continue;
        }
        let field_name = p.cur.eat_in(IDENT);
        if (field_name != null) {
            members.push(parse_field(p, member_docs, field_name));
            continue;
        }
        let rejected = reject_docs(p, member_docs);
        if (rejected != null) {
            members.push(rejected);
        }
        // After trailing docs the body may be over: nothing to skip.
        if (p.cur.at_in(TOP_LEVEL_KEYWORD) || p.cur.at(TokenKind.RBrace) || p.cur.at_end()) {
            break;
        }
        members.push(p.bogus_one("Unexpected token in interface body"));
    }
    let r = p.expect(TokenKind.RBrace);
    InterfaceDef {
        span: p.span_from(mark),
        docs: docs,
        kw: kw,
        name: name,
        generics: generics,
        requires_: requires_,
        l: l,
        members: members,
        r: r,
    }
}

// port: baml_parser/src/items.rs::RequiresClause::parse @ d9be6853b
// `I1, I2` after an interface's `requires`.
function parse_requires_clause(p: Parser, kw: int) -> RequiresClause throws never {
    let mark = Mark { idx: kw };
    // `is_at_type_start` admits a `<` that `any_type` then rejects (no function
    // type follows): a reported `Missing` either way.
    let first = if (is_at_type_start(p.cur)) {
        any_type(p)
    } else {
        null
    };
    let types: SepItem<AnyType>[] | Missing = match (first) {
        // A trailing comma before the body is allowed.
        let ty: AnyType => p.sep1_list(ty, TokenKind.Comma, requires_item),
        _ => p.missing("interface name"),
    };
    RequiresClause { span: p.span_from(mark), kw: kw, types: types }
}

// port: baml_parser/src/items.rs::RequiresClause::parse (the item closure) @ d9be6853b
// An interface after a `,` of a `requires` list; null at the body's `{`.
// deviation: a named function rather than an inline closure, so its return
// type is declared.
function requires_item(p: Parser) -> AnyType? throws never {
    if (p.cur.at(TokenKind.LBrace)) {
        return null;
    }
    if (!is_at_type_start(p.cur)) {
        p.unexpected("interface name");
        return null;
    }
    match (any_type(p)) {
        let ty: AnyType => ty,
        _ => null,
    }
}

// ----- implementations -------------------------------------------------------------------------

// port: baml_parser/src/items.rs::ImplementsBlock::parse @ d9be6853b
// `I { ... }` after the `implements` inside a class.
function parse_implements_block(
    p: Parser,
    docs: DocPart[],
    kw: int,
) -> ImplementsBlock throws never {
    let mark = prefixed_mark(docs, kw);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let target = if (is_at_type_start(p.cur)) {
        any_type(p)
    } else {
        p.missing("interface name")
    };
    let l = p.expect(TokenKind.LBrace);
    if (l is Missing) {
        return ImplementsBlock {
            span: p.span_from(mark),
            docs: doc_nodes,
            kw: kw,
            target: target,
            l: l,
            members: [],
            r: l,
        };
    }
    let members = impl_members(p);
    let r = p.expect(TokenKind.RBrace);
    ImplementsBlock {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: kw,
        target: target,
        l: l,
        members: members,
        r: r,
    }
}

// port: baml_parser/src/items.rs::ImplementsFor::parse @ d9be6853b
// `<G> I for T { ... }` after a top-level `implements`.
function parse_implements_for(p: Parser, docs: DocPart[], kw: int) -> ImplementsFor throws never {
    let mark = prefixed_mark(docs, kw);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let less = p.cur.eat(TokenKind.Less);
    let generics = if (less != null) {
        parse_generic_param_list(p, less)
    } else {
        null
    };
    let target = if (is_at_type_start(p.cur)) {
        any_type(p)
    } else {
        p.missing("interface name")
    };
    let for_kw = p.expect(TokenKind.For);
    let self_ty = if (is_at_type_start(p.cur)) {
        any_type(p)
    } else {
        p.missing("target type")
    };
    let l = p.expect(TokenKind.LBrace);
    let members: AnyImplMember[] = [];
    let r: int | Missing = l;
    if (!(l is Missing)) {
        members = impl_members(p);
        r = p.expect(TokenKind.RBrace);
    }
    ImplementsFor {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: kw,
        generics: generics,
        target: target,
        for_kw: for_kw,
        self_ty: self_ty,
        l: l,
        members: members,
        r: r,
    }
}

// port: baml_parser/src/items.rs::IMPL_MEMBER_EXPECTED @ d9be6853b
// deviation: Rust repeats this literal; named here.
const IMPL_MEMBER_EXPECTED: string = "field or method definition expected in `implements` block";

// port: baml_parser/src/items.rs::impl_members @ d9be6853b
// The members of an `implements` body, up to its `}`.
function impl_members(p: Parser) -> AnyImplMember[] throws never {
    let members: AnyImplMember[] = [];
    while (!p.cur.at(TokenKind.RBrace) && !p.cur.at_end()) {
        if (p.cur.at_in(TOP_LEVEL_KEYWORD) && !p.cur.at(TokenKind.Function)) {
            break;
        }
        let member_mark = p.cur.mark();
        let before = p.cur.pos;
        // The attempt's `Err`: the error the member's `Bogus` reports.
        let failure: ParseError? = null;
        let member = p.attempt((p) -> {
            match (impl_member(p, member_mark)) {
                let error: ParseError => {
                    failure = error;
                    null
                },
                let parsed: AnyImplMember => parsed,
            }
        });
        if (member != null) {
            members.push(member);
        } else if let error: ParseError = failure {
            members.push(p.bogus_since(member_mark, error));
        }
        // A member that consumed nothing must not be read again here.
        if (p.cur.pos == before && !p.cur.at(TokenKind.RBrace) && !p.cur.at_end()) {
            p.cur.skip();
        }
    }
    members
}

// port: baml_parser/src/items.rs::impl_members (the attempt closure) @ d9be6853b
// One member of an `implements` body, or the error for a `Bogus` over what
// it read when a top-level keyword starts here instead.
// deviation: a named function rather than the closure passed to `attempt`;
// its `Err` is the `ParseError` member of the result.
function impl_member(p: Parser, member_mark: Mark) -> AnyImplMember | ParseError throws never {
    let docs = leading_docs(p);
    // An `implements` body has no attributes of its own: the docs before a
    // `@@` documented nothing, and the `@@` is skipped so the loop moves on.
    if (p.cur.at(TokenKind.AtAt)) {
        return reject_docs(p, docs) ?? p.bogus_one(IMPL_MEMBER_EXPECTED);
    }
    let fn_kw = p.cur.eat(TokenKind.Function);
    if (fn_kw != null) {
        return function_def(p, member_mark, docs, fn_kw);
    }
    let type_kw = p.cur.eat(TokenKind.Type);
    if (type_kw != null) {
        return parse_assoc_type_def(p, docs, type_kw);
    }
    let name = if (p.cur.at_in(TOP_LEVEL_KEYWORD)) {
        null
    } else {
        p.cur.eat_in(MEMBER_NAME)
    };
    if (name != null) {
        // `name as field` links an interface field; otherwise a field.
        let as_kw = p.cur.eat(TokenKind.As);
        if (as_kw != null) {
            return parse_interface_field_link(p, docs, name, as_kw);
        }
        return parse_field(p, docs, name);
    }
    let rejected = reject_docs(p, docs);
    if (rejected != null) {
        return rejected;
    }
    if (p.cur.at_in(TOP_LEVEL_KEYWORD)) {
        return p.unexpected_error(IMPL_MEMBER_EXPECTED);
    }
    p.bogus_one(IMPL_MEMBER_EXPECTED)
}

// port: baml_parser/src/items.rs::InterfaceFieldLink::parse @ d9be6853b
// `class_field,` after `interface_field as`.
function parse_interface_field_link(
    p: Parser,
    docs: DocPart[],
    iface_field: int,
    as_kw: int,
) -> InterfaceFieldLink throws never {
    let mark = prefixed_mark(docs, iface_field);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let iface_name = p.name(iface_field);
    let class_field = p.expect_name(MEMBER_NAME, "class field name");
    let sep = p.cur.eat_in(MEMBER_SEP);
    InterfaceFieldLink {
        span: p.span_from(mark),
        docs: doc_nodes,
        iface_field: iface_name,
        as_kw: as_kw,
        class_field: class_field,
        sep: sep,
    }
}

// port: baml_parser/src/items.rs::AssocTypeDecl::parse @ d9be6853b
// `type Item extends Bound = Default,` in an interface: bound and default
// optional.
function parse_assoc_type_decl(p: Parser, docs: DocPart[], kw: int) -> AssocTypeDecl throws never {
    let mark = prefixed_mark(docs, kw);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let name = p.expect_name(IDENT, "associated type name");
    let extends_kw = p.cur.eat(TokenKind.Extends);
    let bound: AssocBound? = null;
    if (extends_kw != null) {
        let ty = if (is_at_type_start(p.cur)) {
            any_type(p)
        } else {
            p.missing("associated type bound")
        };
        bound = AssocBound { kw: extends_kw, ty: ty };
    }
    let eq = p.cur.eat(TokenKind.Equals);
    let default_ty: AssocDefault? = null;
    if (eq != null) {
        let ty = if (is_at_type_start(p.cur)) {
            any_type(p)
        } else {
            p.missing("associated type binding")
        };
        default_ty = AssocDefault { eq: eq, ty: ty };
    }
    let sep = p.cur.eat_in(MEMBER_SEP);
    AssocTypeDecl {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: kw,
        name: name,
        bound: bound,
        default: default_ty,
        sep: sep,
    }
}

// port: baml_parser/src/items.rs::AssocTypeDef::parse @ d9be6853b
// `type Item = T,` in an implementation: the binding is required, and an
// interface-style `extends` bound is rejected.
function parse_assoc_type_def(p: Parser, docs: DocPart[], kw: int) -> AssocTypeDef throws never {
    let mark = prefixed_mark(docs, kw);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let name = p.expect_name(IDENT, "associated type name");
    if (p.cur.at(TokenKind.Extends)) {
        // Consumed for recovery and rejected: the tokens stay unowned and the
        // bound's nodes are discarded; its diagnostics stay.
        p.error_here("associated type bounds are only allowed on interface declarations");
        p.discard((p) -> {
            p.cur.skip();
            if (is_at_type_start(p.cur)) {
                any_type(p);
            } else {
                p.unexpected("associated type bound");
            }
        });
    }
    let eq: int | Missing = p.cur.eat(TokenKind.Equals) ?? p.missing("associated type binding (`= Type`)");
    let ty: AnyType | Missing = match (eq) {
        let missing: Missing => missing,
        _ => {
            if (is_at_type_start(p.cur)) {
                any_type(p)
            } else {
                p.missing("associated type binding")
            }
        },
    };
    let sep = p.cur.eat_in(MEMBER_SEP);
    AssocTypeDef {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: kw,
        name: name,
        eq: eq,
        ty: ty,
        sep: sep,
    }
}

// ----- type aliases, client values ---------------------------------------------------------------

// port: baml_parser/src/items.rs::TypeAliasDef::parse @ d9be6853b
// `Name = T;` after a top-level `type`.
function parse_type_alias_def(p: Parser, docs: DocPart[], kw: int) -> TypeAliasDef throws never {
    let mark = prefixed_mark(docs, kw);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let name = p.expect_name(IDENT, "type alias name");
    let eq = p.expect(TokenKind.Equals);
    // Runtime type atoms are accepted here too; the declaration checker
    // reports that they have no lexical scope.
    let ty = any_type(p);
    reject_unmatched_greater(p);
    let semi = p.cur.eat(TokenKind.Semicolon);
    TypeAliasDef {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: kw,
        name: name,
        eq: eq,
        ty: ty,
        semi: semi,
    }
}

// port: baml_parser/src/items.rs::ClientValueDef::parse @ d9be6853b
// `<expr>;` after `client Name =`.
function parse_client_value_def(
    p: Parser,
    docs: DocPart[],
    kw: int,
    name: int,
    eq: int,
) -> ClientValueDef throws never {
    let mark = prefixed_mark(docs, kw);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let name_node = p.name(name);
    let value = if (at_expression_start(p.cur)) {
        expr(p, Restrictions.statement())
    } else {
        p.missing("expression")
    };
    let semi = p.cur.eat(TokenKind.Semicolon);
    ClientValueDef {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: kw,
        name: name_node,
        eq: eq,
        value: value,
        semi: semi,
    }
}

// ----- removed items -------------------------------------------------------------------------------

// port: baml_parser/src/items.rs::skip_removed_body @ d9be6853b
// The `{ ... }` of a removed item, skipped without parsing. A body still open
// where an item head starts a line was never closed: the skip stops there
// and the missing `}` is reported, so the item after it is parsed. A
// `type_builder` body nests `class` and `enum` heads by design, so it passes
// no `resync` and is only ever skipped balanced.
function skip_removed_body(p: Parser, resync: (Cursor) -> bool throws never) -> void throws never {
    if (!p.cur.skip_balanced_braces(resync)) {
        p.unexpected("'}'");
    }
}

// port: baml_parser/src/items.rs::removed_client @ d9be6853b
// `<llm> Name { ... }` after `client`: the config-block client of the legacy
// world. `name` is the name when the caller already read it (looking for a
// `client Name =` value).
function removed_client(p: Parser, kw: int, name: Name?) -> RemovedItem throws never {
    let mark = Mark { idx: kw };
    let head_mark = p.cur.mark();
    if (name == null && p.cur.at(TokenKind.Less)) {
        p.cur.skip();
        if (p.cur.at_ident()) {
            p.cur.skip();
        }
        if (p.cur.at(TokenKind.Greater)) {
            p.cur.skip();
        } else {
            p.unexpected("'>'");
        }
    }
    let head = p.cur.range_from(head_mark);
    let item_name = name;
    if (item_name == null) {
        item_name = p.eat_name(IDENT);
        if (item_name == null) {
            p.unexpected("client name");
        }
    }
    let body_mark = p.cur.mark();
    if (p.cur.at(TokenKind.LBrace)) {
        skip_removed_body(p, at_item_head);
    } else {
        p.unexpected("config block");
    }
    let body = p.cur.range_from(body_mark);
    RemovedItem { span: p.span_from(mark), kw: kw, head: head, name: item_name, body: body }
}

// port: baml_parser/src/items.rs::removed_retry_policy @ d9be6853b
// `Name { ... }` after `retry_policy`.
function removed_retry_policy(p: Parser, kw: int) -> RemovedItem throws never {
    let mark = Mark { idx: kw };
    let head = p.cur.range_from(p.cur.mark());
    let name = p.eat_name(IDENT);
    if (name == null) {
        p.unexpected("retry policy name");
    }
    let body_mark = p.cur.mark();
    if (p.cur.at(TokenKind.LBrace)) {
        skip_removed_body(p, at_item_head);
    } else {
        p.unexpected("retry policy body");
    }
    let body = p.cur.range_from(body_mark);
    RemovedItem { span: p.span_from(mark), kw: kw, head: head, name: name, body: body }
}

// port: baml_parser/src/items.rs::removed_generator @ d9be6853b
// `generator name { ... }`: swallowed opaquely so stale config never produces
// interior errors; lowering raises the migration warning.
function removed_generator(p: Parser, kw: int) -> RemovedItem throws never {
    let mark = Mark { idx: kw };
    let head = p.cur.range_from(p.cur.mark());
    let name = p.eat_name(IDENT);
    let body_mark = p.cur.mark();
    if (p.cur.at(TokenKind.LBrace)) {
        skip_removed_body(p, at_item_head);
    }
    let body = p.cur.range_from(body_mark);
    RemovedItem { span: p.span_from(mark), kw: kw, head: head, name: name, body: body }
}

// port: baml_parser/src/items.rs::removed_template_string @ d9be6853b
// `Name(params) "body"` after `template_string`.
function removed_template_string(p: Parser, kw: int) -> RemovedItem throws never {
    let mark = Mark { idx: kw };
    let head = p.cur.range_from(p.cur.mark());
    let name = p.eat_name(IDENT);
    if (name == null) {
        p.unexpected("template string name");
    }
    let body_mark = p.cur.mark();
    if (p.cur.at(TokenKind.LParen)) {
        p.cur.skip();
        p.cur.skip_until(KindSet.of([TokenKind.RParen]));
        if (p.cur.at(TokenKind.RParen)) {
            p.cur.skip();
        } else {
            p.unexpected("')'");
        }
    }
    // The declaration-level removal diagnostic is more actionable than also
    // reporting the general hash-string error for its body.
    let token = p.cur.eat_in(STRING_TOKEN);
    if (token != null) {
        string_token_diagnostics(p, token, StringSite.Removed);
    } else if let open: int = p.cur.eat(TokenKind.BacktickStart) {
        // Read for its extent only: the removal diagnostic covers it.
        p.probe((p) -> {
            parse_backtick_string(p, open);
        });
    } else {
        p.unexpected("template string body");
    }
    let body = p.cur.range_from(body_mark);
    RemovedItem { span: p.span_from(mark), kw: kw, head: head, name: name, body: body }
}

// port: baml_parser/src/items.rs::at_removed_type_builder @ d9be6853b
// `type_builder {` / `type_builder: {` at a position where a declaration or
// config entry may start; a bare `type_builder` elsewhere is a name.
function at_removed_type_builder(cur: Cursor) -> bool throws never {
    cur.at(TokenKind.TypeBuilder)
        && match (cur.kind(1)) {
            TokenKind.LBrace => true,
            TokenKind.Colon => cur.nth_is(2, TokenKind.LBrace),
            _ => false,
        }
}

// port: baml_parser/src/items.rs::type_builder_removed_error @ d9be6853b
function type_builder_removed_error(p: Parser, kw: int) -> ParseError throws never {
    RemovedFeature { message: TYPE_BUILDER_REMOVED, range: p.cur.token_range(kw) }
}

// port: baml_parser/src/items.rs::skip_removed_type_builder @ d9be6853b
// E0098 for the legacy `type_builder` block inside a body, after its
// keyword, and the block consumed.
function skip_removed_type_builder(p: Parser, kw: int) -> Bogus throws never {
    let error = type_builder_removed_error(p, kw);
    p.cur.eat(TokenKind.Colon);
    skip_removed_body(p, (cur) -> {
        false
    });
    p.bogus_since(Mark { idx: kw }, error)
}

// port: baml_parser/src/items.rs::removed_type_builder @ d9be6853b
function removed_type_builder(p: Parser, kw: int) -> RemovedItem throws never {
    p.out.report(type_builder_removed_error(p, kw));
    let mark = Mark { idx: kw };
    let head = p.cur.range_from(p.cur.mark());
    let body_mark = p.cur.mark();
    p.cur.eat(TokenKind.Colon);
    skip_removed_body(p, (cur) -> {
        false
    });
    let body = p.cur.range_from(body_mark);
    RemovedItem { span: p.span_from(mark), kw: kw, head: head, name: null, body: body }
}

// port: baml_parser/src/items.rs::at_removed_dynamic_def @ d9be6853b
// `dynamic class Name { ... }` / `dynamic enum Name { ... }`.
function at_removed_dynamic_def(cur: Cursor) -> bool throws never {
    cur.at(TokenKind.Dynamic) && (cur.nth_is(1, TokenKind.Class) || cur.nth_is(1, TokenKind.Enum))
}

// port: baml_parser/src/items.rs::removed_dynamic_def @ d9be6853b
// `class Name { ... }` after `dynamic`.
function removed_dynamic_def(p: Parser, kw: int) -> RemovedItem throws never {
    let mark = Mark { idx: kw };
    let keyword = p.cur.text_at(0) ?? "";
    p.removed(
        `\`dynamic ${keyword}\` definitions were removed; runtime type construction is \`reflect\` (BEP-066)`,
        p.cur.token_range(kw),
    );
    let head_mark = p.cur.mark();
    // class / enum
    p.cur.skip();
    let head = p.cur.range_from(head_mark);
    let name = p.eat_name(IDENT);
    let body_mark = p.cur.mark();
    skip_removed_body(p, at_item_head);
    let body = p.cur.range_from(body_mark);
    RemovedItem { span: p.span_from(mark), kw: kw, head: head, name: name, body: body }
}

// port: baml_parser/src/items.rs::at_removed_legacy_test @ d9be6853b
// `test Name { functions [...] ... }`: a legacy config-block test.
function at_removed_legacy_test(cur: Cursor) -> bool throws never {
    if (!(cur.at(TokenKind.Test) && cur.nth_is_ident(1) && cur.nth_is(2, TokenKind.LBrace))) {
        return false;
    }
    let next = cur.kind(4);
    match (cur.text_at(3)) {
        "functions" => next == TokenKind.LBracket || next == TokenKind.Colon,
        "args" => next == TokenKind.LBrace || next == TokenKind.Colon,
        _ if cur.nth_is(3, TokenKind.TypeBuilder) => {
            next == TokenKind.LBrace || next == TokenKind.Colon
        },
        _ => false,
    }
}

// port: baml_parser/src/items.rs::removed_legacy_test @ d9be6853b
// `Name { functions ... }` after a legacy `test`.
function removed_legacy_test(p: Parser, kw: int) -> RemovedItem throws never {
    let mark = Mark { idx: kw };
    let start = p.cur.token_range(kw);
    let name_range = p.cur.error_range();
    p.removed(
        "Legacy test declarations were removed. Use an expression-body test with a quoted name, for example: `test \"Name\" { assert.equal(Foo(...), expected) }`.",
        start.cover(name_range),
    );
    let head = p.cur.range_from(p.cur.mark());
    let name = p.eat_name(IDENT);
    let body_mark = p.cur.mark();
    skip_removed_body(p, at_item_head);
    let body = p.cur.range_from(body_mark);
    RemovedItem { span: p.span_from(mark), kw: kw, head: head, name: name, body: body }
}

// ----- recovery -------------------------------------------------------------------------------------

// port: baml_parser/src/items.rs::try_recover_invalid_block @ d9be6853b
// `classs Foo { ... }`: a misspelled keyword before a braced block.
function try_recover_invalid_block(p: Parser) -> Bogus? throws never {
    if (!(p.cur.at_ident() && p.cur.nth_is_ident(1) && p.cur.nth_is(2, TokenKind.LBrace))) {
        return null;
    }
    let keyword = p.cur.text_at(0) ?? "";
    let error = InvalidSyntax {
        message: `unknown keyword \`${keyword}\`; expected \`class\`, \`enum\`, \`function\`, \`client\`, \`generator\`, \`test\`, or \`type\``,
        range: p.cur.error_range(),
    };
    let mark = p.cur.mark();
    p.cur.skip();
    p.cur.skip();
    p.cur.skip_balanced_braces(at_item_head);
    p.bogus_since(mark, error)
}

// port: baml_parser/src/items.rs::try_recover_invalid_type_alias @ d9be6853b
// `typpe Name = ...`: a misspelled `type`.
function try_recover_invalid_type_alias(p: Parser) -> Bogus? throws never {
    if (!(p.cur.at_ident() && p.cur.nth_is_ident(1) && p.cur.nth_is(2, TokenKind.Equals))) {
        return null;
    }
    let keyword = p.cur.text_at(0) ?? "";
    let error = InvalidSyntax {
        message: `unknown keyword \`${keyword}\`; did you mean \`type\`? usage: \`type Name = expression\``,
        range: p.cur.error_range(),
    };
    let mark = p.cur.mark();
    p.cur.skip();
    p.cur.skip();
    p.cur.skip();
    while (!p.cur.at_end() && !p.cur.at_in(INVALID_ALIAS_END)) {
        p.cur.skip();
    }
    p.bogus_since(mark, error)
}

// ----- lookahead -------------------------------------------------------------------------------------

// port: baml_parser/src/items.rs::looks_like_client_declaration_start @ d9be6853b
// A `client<...>` declaration, as opposed to a class field named `client`.
function looks_like_client_declaration_start(cur: Cursor) -> bool throws never {
    cur.at(TokenKind.Client) && cur.nth_is(1, TokenKind.Less)
}

// port: baml_parser/src/items.rs::looks_like_interface_declaration_start @ d9be6853b
// `interface Name ... {` before any `}` or `;`, as opposed to a field named
// `interface`.
function looks_like_interface_declaration_start(cur: Cursor) -> bool throws never {
    if (!(cur.at(TokenKind.Interface) && cur.nth_is_ident(1))) {
        return false;
    }
    let i = cur.pos + 2;
    while let kind: TokenKind = cur.kind_at_sig(i) {
        match (kind) {
            TokenKind.LBrace => {
                return true;
            },
            TokenKind.RBrace | TokenKind.Semicolon => {
                return false;
            },
            _ => {
                i += 1;
            },
        }
    }
    false
}

// ----- tests ---------------------------------------------------------------------------------------------

// port: baml_parser/src/items.rs::TestPosition @ d9be6853b
// Where a `test`/`testset` is written: at the top level, or as a statement in
// a testset's body, where its name may be a computed expression, so only the
// item position reports a bare word as a mistaken unquoted name.
enum TestPosition {
    Item,
    Stmt,
}

// port: baml_parser/src/items.rs::test_def @ d9be6853b
// `"name" with runner { body }` after `test`/`testset`.
function test_def(
    p: Parser,
    docs: DocPart[],
    kw: int,
    position: TestPosition,
) -> TestDef throws never {
    let mark = prefixed_mark(docs, kw);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let what = if (p.cur.tokens().kinds[kw] == TokenKind.Test) {
        "test"
    } else {
        "testset"
    };
    // A bare identifier can never resolve at the top level: report the fix
    // instead of a downstream "unresolved name".
    if (
        position == TestPosition.Item
            && p.cur.at(TokenKind.Word)
            && (p.cur.nth_is(1, TokenKind.LBrace) || p.cur.nth_is(1, TokenKind.With))
    ) {
        let name = p.cur.text_at(0) ?? "";
        p.error_here(`${what} names must be quoted strings: \`${what} "${name}"\``);
    }
    let r = Restrictions.statement().before_body();
    let name = if (at_expression_start(p.cur)) {
        expr(p, r)
    } else {
        p.missing("expression")
    };
    let with_kw = p.cur.eat(TokenKind.With);
    let with_node = if (with_kw != null) {
        with_clause(p, with_kw, r)
    } else {
        null
    };
    let body = body_block(p, `${what} body`);
    TestDef {
        span: p.span_from(mark),
        docs: doc_nodes,
        kw: kw,
        name: name,
        with: with_node,
        body: body,
    }
}

// ----- the file ---------------------------------------------------------------------------------------

// port: baml_parser/src/items.rs::source_file @ d9be6853b
function source_file(p: Parser) -> SourceFile throws never {
    let mark = p.cur.mark();
    let items: AnyItem[] = [];
    while (!p.cur.at_end()) {
        items.push(item(p));
    }
    diagnose_header_comments(p);
    diagnose_unclosed_block_comments(p);
    // The file starts where its first item does (a leading `//#` title
    // included), not at the first significant token.
    let first = items.at(0);
    let file_mark = if (first != null) {
        p.mark_of(node_span(first))
    } else {
        mark
    };
    SourceFile { span: p.span_from(file_mark), items: items }
}

// port: baml_parser/src/items.rs::item @ d9be6853b
// Docs first; the token after them says what they belong to, and docs with
// nothing to document become one `Bogus`.
// deviation: Rust runs this under `p.attempt`, but its closure only ever
// returns `Ok`, so nothing is rolled back; the attempt is dropped.
function item(p: Parser) -> AnyItem throws never {
    let docs = leading_docs(p);
    // A `//#` title is trivia to the cursor: an item that begins with one
    // starts there, not at its first significant token.
    let first = docs.at(0);
    let mark = if (first != null) {
        Mark { idx: doc_part_token(first) }
    } else {
        p.cur.mark()
    };
    if (p.cur.at(TokenKind.AtAt)) {
        // A `@@` attribute has no position at the top level: it is written inside
        // the body of the declaration it is for. The docs before it documented
        // nothing and are their own `Bogus`; the attribute is the next item.
        return reject_docs(p, docs) ?? misplaced_block_attr(p);
    }
    let enum_kw = p.cur.eat(TokenKind.Enum);
    if (enum_kw != null) {
        return enum_def(p, mark, alloc_docs(p, docs, DocOwnerOther {}), enum_kw);
    }
    let class_kw = p.cur.eat(TokenKind.Class);
    if (class_kw != null) {
        return class_def(p, mark, alloc_docs(p, docs, DocOwnerOther {}), class_kw);
    }
    let interface_kw = p.cur.eat(TokenKind.Interface);
    if (interface_kw != null) {
        return interface_def(p, mark, alloc_docs(p, docs, DocOwnerOther {}), interface_kw);
    }
    let fn_kw = p.cur.eat(TokenKind.Function);
    if (fn_kw != null) {
        return function_def(p, mark, docs, fn_kw);
    }
    unattributed_item(p, docs)
}

// port: baml_parser/src/items.rs::misplaced_block_attr @ d9be6853b
// A `@@` attribute outside every body, at its `@@`: read for its extent and
// reported as one `Bogus`.
function misplaced_block_attr(p: Parser) -> Bogus throws never {
    let mark = p.cur.mark();
    let at = p.cur.eat(TokenKind.AtAt) ?? baml.sys.panic("called at `@@`");
    p.probe((p) -> {
        parse_block_attr(p, at);
    });
    let range = p.cur.text_range(p.cur.range_from(mark));
    p.bogus_since(
        mark,
        InvalidSyntax {
            message: "a `@@` attribute is written inside the body of the class, enum or interface it describes",
            range: range,
        },
    )
}

// port: baml_parser/src/items.rs::unattributed_item @ d9be6853b
// An item at its first token, with the docs read before it. Docs before a
// form that cannot be documented (a removed item, a `let type`, a recovery)
// are one `Bogus` item of their own, and the form is the next item.
function unattributed_item(p: Parser, docs: DocPart[]) -> AnyItem throws never {
    let impl_kw = p.cur.eat_in(IMPLEMENTS_KW);
    if (impl_kw != null) {
        return parse_implements_for(p, docs, impl_kw);
    }
    if (docs.length() == 0 || at_client_value(p.cur)) {
        let client_kw = p.cur.eat(TokenKind.Client);
        if (client_kw != null) {
            // `client Name = ...` is a value; anything else after `client` is the
            // removed config block.
            let name = p.cur.eat_in(IDENT);
            if (name == null) {
                return removed_client(p, client_kw, null);
            }
            let eq = p.cur.eat(TokenKind.Equals);
            if (eq != null) {
                return parse_client_value_def(p, docs, client_kw, name, eq);
            }
            return removed_client(p, client_kw, p.name(name));
        }
    }
    if (!at_removed_legacy_test(p.cur)) {
        let test_kw = p.cur.eat_in(TEST_KW);
        if (test_kw != null) {
            return test_def(p, docs, test_kw, TestPosition.Item);
        }
    }
    let type_kw = p.cur.eat(TokenKind.Type);
    if (type_kw != null) {
        return parse_type_alias_def(p, docs, type_kw);
    }
    if (!at_let_type(p.cur) && at_binding_intro(p.cur)) {
        let introducer = p.cur.eat_in(LET_INTRODUCER);
        if (introducer != null) {
            return let_item(p, docs, introducer);
        }
    }
    reject_docs(p, docs) ?? undocumented_item(p)
}

// port: baml_parser/src/items.rs::unattributed_item (after the docs are rejected) @ d9be6853b
// An item that takes no docs: a removed form, a `let type`, a recovery, or
// stray text.
// deviation: Rust continues inline in `unattributed_item`; split out to keep
// each function to one dispatch.
function undocumented_item(p: Parser) -> AnyItem throws never {
    let client_kw = p.cur.eat(TokenKind.Client);
    if (client_kw != null) {
        // A removed `client<llm> Name { ... }` block; its docs were rejected.
        let name = p.cur.eat_in(IDENT);
        return removed_client(
            p,
            client_kw,
            if (name != null) {
                p.name(name)
            } else {
                null
            },
        );
    }
    let generator_kw = p.cur.eat(TokenKind.Generator);
    if (generator_kw != null) {
        return removed_generator(p, generator_kw);
    }
    if (at_removed_legacy_test(p.cur)) {
        return removed_legacy_test(p, p.cur.eat(TokenKind.Test) ?? baml.sys.panic("checked at `test`"));
    }
    let retry_kw = p.cur.eat(TokenKind.RetryPolicy);
    if (retry_kw != null) {
        return removed_retry_policy(p, retry_kw);
    }
    let template_kw = p.cur.eat(TokenKind.TemplateString);
    if (template_kw != null) {
        return removed_template_string(p, template_kw);
    }
    if (at_let_type(p.cur)) {
        // Only a body can bind a runtime type; lowering reports it here.
        let let_kw = p.cur.eat(TokenKind.Let) ?? baml.sys.panic("checked at `let`");
        let type_kw = p.cur.eat(TokenKind.Type) ?? baml.sys.panic("checked at `type`");
        return parse_type_binding_stmt(p, let_kw, type_kw);
    }
    if (at_removed_type_builder(p.cur)) {
        return removed_type_builder(p, p.cur.eat(TokenKind.TypeBuilder) ?? baml.sys.panic("checked at `type_builder`"));
    }
    if (at_removed_dynamic_def(p.cur)) {
        return removed_dynamic_def(p, p.cur.eat(TokenKind.Dynamic) ?? baml.sys.panic("checked at `dynamic`"));
    }
    let recovered = try_recover_invalid_block(p) ?? try_recover_invalid_type_alias(p);
    if (recovered != null) {
        return recovered;
    }
    // Nothing an item begins with: one `Bogus` over everything up to the next
    // item head or line-leading item keyword, reported once at its first
    // token, so stray text is one diagnostic and not one per token.
    let mark = p.cur.mark();
    let error = p.unexpected_error("top-level declaration");
    p.cur.skip();
    while (!p.cur.at_end() && !at_item_start(p.cur)) {
        p.cur.skip();
    }
    p.bogus_since(mark, error)
}

// port: baml_parser/src/items.rs::class_body_ends @ d9be6853b
// Whether a class body is missing its `}`: a top-level keyword (other than
// the members a class may hold) starts here. `interface` and `client` are
// also member names, so their declaration shapes decide.
function class_body_ends(cur: Cursor) -> bool throws never {
    let recover_top_level_item = if (cur.at(TokenKind.Interface)) {
        looks_like_interface_declaration_start(cur)
    } else if (cur.at(TokenKind.Client)) {
        looks_like_client_declaration_start(cur)
    } else {
        cur.at_in(TOP_LEVEL_KEYWORD)
    };
    recover_top_level_item
        && !cur.at(TokenKind.Function)
        && !cur.at(TokenKind.Implements)
        && !cur.at(TokenKind.Implement)
}

// port: baml_parser/src/items.rs::let_item @ d9be6853b
// A file-scope `let`/`const` after its introducer, with its docs.
function let_item(p: Parser, docs: DocPart[], introducer: int) -> LetItem throws never {
    let mark = prefixed_mark(docs, introducer);
    let doc_nodes = alloc_docs(p, docs, DocOwnerOther {});
    let stmt = let_stmt(p, introducer, Semi.Own);
    LetItem { span: p.span_from(mark), docs: doc_nodes, stmt: stmt }
}

// port: baml_parser/src/items.rs::at_client_value @ d9be6853b
// `client Name =`: a client value, the one `client` form that takes docs.
function at_client_value(cur: Cursor) -> bool throws never {
    cur.at(TokenKind.Client) && cur.nth_is_ident(1) && cur.nth_is(2, TokenKind.Equals)
}

// port: baml_parser/src/items.rs::diagnose_unclosed_block_comments @ d9be6853b
// A `/*` with no `*/` swallowed the rest of the file as a comment: trivia to
// the grammar, reported once here.
function diagnose_unclosed_block_comments(p: Parser) -> void throws never {
    let kinds = p.cur.tokens().kinds;
    for (let idx = 0; idx < kinds.length(); idx += 1) {
        if (kinds[idx] == TokenKind.UnclosedBlockComment) {
            p.error(
                "unclosed block comment: expected `*/` before the end of the file",
                p.cur.token_range(idx),
            );
        }
    }
}

// port: baml_parser/src/items.rs::diagnose_header_comments @ d9be6853b
// A `//#` line is a statement in a block or a function's title; anywhere
// else it is an error. One inside a `Bogus` (recovered text, or a template
// interior not parsed yet) is not checked.
function diagnose_header_comments(p: Parser) -> void throws never {
    let bogus_ranges = p.out.bogus_spans();
    let owned = p.out.owned_header_tokens();
    let kinds = p.cur.tokens().kinds;
    for (let idx = 0; idx < kinds.length(); idx += 1) {
        let unowned = kinds[idx] == TokenKind.HeaderComment
            && !owned.includes(idx)
            && !bogus_ranges.some((r) -> {
                r.start <= idx && idx < r.end
            });
        if (unowned) {
            p.error(HEADER_COMMENT_MISPLACED, p.cur.token_range(idx));
        }
    }
}
