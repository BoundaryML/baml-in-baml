// port: baml_parser/src/function_union.rs @ d9be6853b
//
// Explicit groupings for an ambiguous function/union boundary (E0175).
//
// When a pipe inside an undelimited function's return or `throws` operand is
// followed by a function type, the pipe can either stay in that operand or end
// the function. The parser reports such pipes; this module searches the
// complete parses of the surrounding expression and renders two of them that
// disagree about the reported pipe, parenthesized so each parses back to
// exactly that grouping.
//
// The search runs over a flat item sequence: function heads (a parameter list
// followed by `->`), `throws`, pipes, and atoms. Every bracketed group that is
// not a function head is an opaque atom, since its contents cannot interact
// with the pipes outside it.
//
// Strings and comments are single tokens, so a bracket inside one never
// counts; `>>` is two `>` tokens.
//
// deviation: Rust's data enums `Item` and `Node` are unions of classes named
// `<Enum><Variant>`; a `(value, end)` tuple is a `Parsed<T>`.

// port: baml_parser/src/function_union.rs::SigToken @ d9be6853b
// A non-trivia token of the ambiguous expression.
class SigToken {
    kind: TokenKind,
    text: string,
    // Whether whitespace or a comment separated this token from the previous
    // one; rendered as a single space.
    space_before: bool,
}

// port: baml_parser/src/function_union.rs::MAX_PARSES @ d9be6853b
// Upper bound on complete parses explored. Real expressions have a handful.
const MAX_PARSES: int = 256;

// port: baml_parser/src/function_union.rs::Item @ d9be6853b
type Item = ItemHead | ItemThrows | ItemPipe | ItemAtom;

// Rendered parameter list of a function type; the `->` is implied.
class ItemHead {
    params: string,
}

class ItemThrows {
}

// A pipe, identified by its index in the token slice.
class ItemPipe {
    token: int,
}

// Rendered text, and whether it is a parenthesized function type.
class ItemAtom {
    text: string,
    is_function: bool,
}

// port: baml_parser/src/function_union.rs::Node @ d9be6853b
type Node = NodeAtom | NodeFn;

class NodeAtom {
    item: int,
}

class NodeFn {
    head: int,
    ret: Union,
    throws_clause: Union?,
}

// port: baml_parser/src/function_union.rs::Union @ d9be6853b
// A union and the item indices of the pipes that join its members.
class Union {
    members: Node[],
    pipes: int[],
}

// port: baml_parser/src/function_union.rs::Owner @ d9be6853b
// Which union a pipe joins in one parse: the return (`in_throws` false) or
// throws (true) operand of the function whose head is at item `head`, or the
// top level (`head` null).
// deviation: Rust's `Option<(usize, bool)>` is a class, so `owner_of`'s
// `Option<Owner>` is `Owner?` (null: the pipe is not in this union).
class Owner {
    head: int?,
    in_throws: bool,
}

// A parse and the item index just past it.
class Parsed<T> {
    value: T,
    end: int,
}

// port: baml_parser/src/function_union.rs::groupings @ d9be6853b
// For each token index in `pipes`, two groupings of the whole expression that
// assign that pipe to different unions: first the parser's own grouping, then
// the next complete parse (depth-first, keeping pipes inside the innermost
// function first) that differs at that pipe. Null when no second grouping
// exists or the expression is not well formed.
function groupings(tokens: SigToken[], pipes: int[]) -> (string[] | null)[] throws never {
    let none: (string[] | null)[] = pipes.map((pipe) -> string[]? {
        null
    });
    let flat = items(tokens)
        ?? return none;
    let search = Search { items: flat };
    let parses = search.union(0, false)
        .filter((parse) -> {
            parse.end == flat.length()
        })
        .map((parse) -> {
            parse.value
        });
    let first = parses.at(0)
        ?? return none;
    let top = Owner { head: null, in_throws: false };
    pipes.map((pipe) -> string[]? {
        let item = flat.find_index((it) -> {
            it is ItemPipe && it.token == pipe
        })
            ?? return null;
        let owner = owner_of(first, top, item)
            ?? return null;
        let other = parses.find((parse) -> {
            owner_of(parse, top, item) != owner
        })
            ?? return null;
        [render_union(flat, first, false), render_union(flat, other, false)]
    })
}

// port: baml_parser/src/function_union.rs::items @ d9be6853b
function items(tokens: SigToken[]) -> Item[]? throws never {
    let out: Item[] = [];
    let i = 0;
    while (i < tokens.length()) {
        let kind = tokens[i].kind;
        let head_close = if (kind == TokenKind.LParen) {
            sig_matching_close(tokens, i)
        } else {
            null
        };
        let is_head = head_close != null && tokens.at(head_close + 1)?.kind == TokenKind.Arrow;
        match (kind) {
            TokenKind.Pipe => {
                out.push(ItemPipe { token: i });
                i += 1;
            },
            TokenKind.Throws => {
                out.push(ItemThrows {});
                i += 1;
            },
            TokenKind.LParen if is_head => {
                let end = head_close
                    ?? return null;
                out.push(ItemHead { params: text(tokens, i, end) });
                i = end + 2;
            },
            _ => {
                let start = i;
                while (
                    i < tokens.length()
                        && tokens[i].kind != TokenKind.Pipe
                        && tokens[i].kind != TokenKind.Throws
                ) {
                    let inner = tokens[i].kind;
                    if (inner == TokenKind.Arrow) {
                        return null;
                    }
                    if (is_open(inner)) {
                        let close = sig_matching_close(tokens, i)
                            ?? return null;
                        i = close + 1;
                    } else {
                        i += 1;
                    }
                }
                out.push(
                    ItemAtom {
                        text: text(tokens, start, i - 1),
                        is_function: wraps_function(tokens, start, i - 1),
                    },
                );
            },
        }
    }
    out
}

// port: baml_parser/src/function_union.rs::wraps_function @ d9be6853b
// Whether `tokens[start..=end]` is a function type in one or more pairs of
// parentheses, like `((C) -> D)`. The parser treats it as a function member.
function wraps_function(tokens: SigToken[], start: int, end: int) -> bool throws never {
    let lo = start;
    let hi = end;
    while (tokens[lo].kind == TokenKind.LParen && sig_matching_close(tokens, lo) == hi) {
        lo += 1;
        hi -= 1;
        if (lo > hi) {
            return false;
        }
        if (tokens[lo].kind == TokenKind.LParen) {
            let close = sig_matching_close(tokens, lo);
            if (close != null && tokens.at(close + 1)?.kind == TokenKind.Arrow) {
                return true;
            }
        }
    }
    false
}

// port: baml_parser/src/function_union.rs::is_open @ d9be6853b
function is_open(kind: TokenKind) -> bool throws never {
    match (kind) {
        TokenKind.LParen | TokenKind.LBracket | TokenKind.LBrace | TokenKind.Less => true,
        _ => false,
    }
}

// port: baml_parser/src/function_union.rs::matching_close @ d9be6853b
// Index of the token closing the group opened at `open`.
// deviation: renamed from `matching_close`, which lookahead.rs's cursor
// version is called in the shared namespace.
function sig_matching_close(tokens: SigToken[], open: int) -> int? throws never {
    let depth = 0;
    for (let i = open; i < tokens.length(); i += 1) {
        let kind = tokens[i].kind;
        match (kind) {
            _ if is_open(kind) => {
                depth += 1;
            },
            TokenKind.RParen | TokenKind.RBracket | TokenKind.RBrace | TokenKind.Greater => {
                if (depth == 0) {
                    return null;
                }
                depth -= 1;
            },
            _ => {},
        }
        if (depth == 0) {
            return i;
        }
    }
    null
}

// port: baml_parser/src/function_union.rs::text @ d9be6853b
function text(tokens: SigToken[], start: int, end: int) -> string throws never {
    tokens.slice(start + 1, end + 1).reduce(
        (out, token) -> string {
            if (token.space_before) {
                `${out} ${token.text}`
            } else {
                `${out}${token.text}`
            }
        },
        tokens[start].text,
    )
}

// port: baml_parser/src/function_union.rs::Search @ d9be6853b
class Search {
    items: Item[],

    // port: baml_parser/src/function_union.rs::Search::union @ d9be6853b
    // Every way to parse a union starting at `pos`, with the item index just
    // past it. Inside a function operand a pipe may also end the union. Longer
    // unions come first, so the first parse keeps each pipe in the innermost
    // function, as the parser does.
    function union(self, pos: int, in_function: bool) -> Parsed<Union>[] throws never {
        let out: Parsed<Union>[] = [];
        for (let parsed in self.member(pos)) {
            let member = parsed.value;
            let next = parsed.end;
            if (self.items.at(next) is ItemPipe) {
                for (let rest in self.union(next + 1, in_function)) {
                    let joined = Union {
                        members: [member].concat(rest.value.members),
                        pipes: [next].concat(rest.value.pipes),
                    };
                    out.push(Parsed { value: joined, end: rest.end });
                    if (out.length() >= MAX_PARSES) {
                        return out;
                    }
                }
            }
            if (in_function || next == self.items.length()) {
                out.push(Parsed { value: Union { members: [member], pipes: [] }, end: next });
            }
            if (out.length() >= MAX_PARSES) {
                return out;
            }
        }
        out
    }

    // port: baml_parser/src/function_union.rs::Search::member @ d9be6853b
    // Every way to parse one union member at `pos`. A function takes a
    // following `throws` first, and otherwise leaves it to an enclosing one.
    function member(self, pos: int) -> Parsed<Node>[] throws never {
        match (self.items.at(pos)) {
            let _atom: ItemAtom => [Parsed { value: NodeAtom { item: pos }, end: pos + 1 }],
            let _head: ItemHead => {
                let out: Parsed<Node>[] = [];
                for (let parsed in self.union(pos + 1, true)) {
                    let ret = parsed.value;
                    let next = parsed.end;
                    if (self.items.at(next) is ItemThrows) {
                        for (let thrown in self.union(next + 1, true)) {
                            out.push(
                                Parsed {
                                    value: NodeFn { head: pos, ret: ret, throws_clause: thrown.value },
                                    end: thrown.end,
                                },
                            );
                        }
                    }
                    out.push(
                        Parsed {
                            value: NodeFn { head: pos, ret: ret, throws_clause: null },
                            end: next,
                        },
                    );
                    if (out.length() >= MAX_PARSES) {
                        break;
                    }
                }
                out
            },
            _ => [],
        }
    }
}

// port: baml_parser/src/function_union.rs::owner_of @ d9be6853b
function owner_of(union: Union, owner: Owner, pipe: int) -> Owner? throws never {
    if (union.pipes.includes(pipe)) {
        return owner;
    }
    for (let member in union.members) {
        if (member is NodeFn) {
            let in_ret = owner_of(member.ret, Owner { head: member.head, in_throws: false }, pipe);
            if (in_ret != null) {
                return in_ret;
            }
            let thrown = member.throws_clause;
            if (thrown != null) {
                let in_throws = owner_of(thrown, Owner { head: member.head, in_throws: true }, pipe);
                if (in_throws != null) {
                    return in_throws;
                }
            }
        }
    }
    null
}

// port: baml_parser/src/function_union.rs::render_union @ d9be6853b
// Render a union so it parses back to this grouping. Function members are
// parenthesized, except the last member of a function operand, which the
// operand's own parentheses already delimit.
function render_union(items: Item[], union: Union, is_operand: bool) -> string throws never {
    let count = union.members.length();
    let rendered: string[] = [];
    for (let i = 0; i < count; i += 1) {
        let member = union.members[i];
        let text = render_node(items, member);
        let wrap = member is NodeFn && count > 1 && !(is_operand && i == count - 1);
        rendered.push(
            if (wrap) {
                `(${text})`
            } else {
                text
            },
        );
    }
    rendered.join(" | ")
}

// port: baml_parser/src/function_union.rs::render_node @ d9be6853b
function render_node(items: Item[], node: Node) -> string throws never {
    match (node) {
        let atom: NodeAtom => match (items[atom.item]) {
            let item: ItemAtom => item.text,
            _ => baml.sys.panic("atoms index atom items"),
        },
        let fn_node: NodeFn => {
            let params = match (items[fn_node.head]) {
                let head: ItemHead => head.params,
                _ => baml.sys.panic("functions index head items"),
            };
            let out = `${params} -> ${render_operand(items, fn_node.ret)}`;
            let thrown = fn_node.throws_clause;
            if (thrown != null) {
                out = `${out} throws ${render_operand(items, thrown)}`;
            }
            out
        },
    }
}

// port: baml_parser/src/function_union.rs::render_operand @ d9be6853b
// A return or throws operand. A lone function is parenthesized so a later
// `throws` cannot attach to it; a union with a function member (including an
// already parenthesized one) is parenthesized so its pipes cannot end the
// function. Unions of plain types are unambiguous and stay bare.
function render_operand(items: Item[], union: Union) -> string throws never {
    let has_function = union.members.some((member) -> {
        match (member) {
            let _fn: NodeFn => true,
            // A lone parenthesized function is already delimited.
            let atom: NodeAtom => {
                union.members.length() > 1
                    && match (items[atom.item]) {
                        let item: ItemAtom => item.is_function,
                        _ => false,
                    }
            },
        }
    });
    let rendered = render_union(items, union, true);
    if (has_function) {
        `(${rendered})`
    } else {
        rendered
    }
}
