// port: baml_compiler2_ast/src/lower_tree/templates.rs @ d9be6853b
//
// Backtick templates. The text goes through the BEP-049 pipeline the rowan
// lowering applies (whole-literal dedent, section 12, with the non-text parts
// held out; block-tag whitespace control, section 13; then escape decoding),
// and the structural parts become `TemplateSegment`s. The two desugarings
// (`elaborate_default_segments`, `elaborate_tagged_body`) are
// `LoweringContext`'s and run on the segments unchanged.
//
// The text rules see the literal flat: text, block tags and interpolations in
// order, with nesting forgotten. Both the flat read and the segment walk
// visit the parts in the same order, so the text that lands between two
// consecutive non-text parts is handed to the segment walk one gap at a time
// (`Texts`).

// port: baml_compiler2_ast/src/lower_tree/templates.rs::backtick_expr @ d9be6853b
// An untagged `` `…` `` (BEP section 11). The realization is
// compiler-generated: its nodes are synthetic, the segments' are not.
function backtick_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.BacktickString,
) -> int throws never {
    let span = v.range(node.span);
    let segments = template_segments(ctx, v, node);
    let prev_synth = ctx.synthesizing;
    ctx.synthesizing = true;
    let elaborated = ctx.elaborate_default_segments(segments, span);
    ctx.synthesizing = prev_synth;
    ctx.alloc_expr(
        ExprTemplate { tag: TemplateTagDefault { elaborated: elaborated }, segments: segments },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::tagged_template_expr @ d9be6853b
// A tagged `` tag`…` `` (BEP section 10). A bare `prompt` tag is the stdlib
// `ai.prompt` (BAML has no prelude); same expression id, so the span stays
// the written one.
function tagged_template_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.TaggedTemplateExpr,
) -> int throws never {
    let span = v.range(node.span);
    let tag = expression(ctx, v, node.tag);
    if let path: ExprPath = ctx.exprs[tag] {
        let names = path.value.segments;
        if (names.length() == 1 && names[0] == "prompt") {
            ctx.exprs[tag] = ExprPath { value: root.base.Path.compiler(["ai", "prompt"]) };
        }
    }
    let segments = template_segments(ctx, v, node.template);
    let prev_synth = ctx.synthesizing;
    ctx.synthesizing = true;
    let body = ctx.elaborate_tagged_body(segments, span);
    ctx.synthesizing = prev_synth;
    ctx.alloc_expr(
        ExprTemplate { tag: TemplateTagCustom { tag: tag, body: body }, segments: segments },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::template_segments @ d9be6853b
function template_segments(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.BacktickString,
) -> TemplateSegment[] throws never {
    let texts = Texts.read(v, node.parts);
    let out = segments(ctx, v, node.parts, texts);
    texts.drain_into(out);
    out
}

// ── Segments ──────────────────────────────────────────────────────────────

// port: baml_compiler2_ast/src/lower_tree/templates.rs::segments @ d9be6853b
// The segments of one parts list. The text before each non-text part is taken
// from `texts`; the text after the last one belongs to whoever closes the
// list, which knows whether a tag follows it. A stray tag was reported; it
// contributes nothing.
function segments(
    ctx: LoweringContext,
    v: View,
    parts: root.syntax.AnyTemplatePart[],
    texts: Texts,
) -> TemplateSegment[] throws never {
    let out: TemplateSegment[] = [];
    for (let part in parts) {
        match (part) {
            root.syntax.AnyTemplatePartChunk => {},
            let p: root.syntax.TemplateInterp => {
                texts.drain_into(out);
                out.push(interpolation(ctx, v, p));
            },
            let p: root.syntax.TemplateFor => {
                texts.drain_into(out);
                out.push(template_for(ctx, v, p, texts));
            },
            let p: root.syntax.TemplateIf => {
                texts.drain_into(out);
                out.push(template_if(ctx, v, p, texts));
            },
            root.syntax.Bogus => texts.drain_into(out),
        }
    }
    out
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::interpolation @ d9be6853b
// `${…}`: the inner block, raw. An interpolation with no value runs for its
// effects in the template's own scope. The block is `{ … }`: its brace is the
// `${` token's second byte.
function interpolation(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.TemplateInterp,
) -> TemplateSegment throws never {
    let span = v.range(node.span);
    if (!node.stmts && node.tail == null) {
        ctx.diags.push(LoweringDiagnosticEmptyInterpolation { span: span });
    }
    let block_span = root.syntax.TextRange { start: span.start + 1, end: span.end };
    let block = block_body(ctx, v, node.stmts, node.tail, block_span);
    let stmts = ctx.unit_interp_stmts(block, span);
    if (stmts != null) {
        return TemplateSegmentEffect { block: block, stmts: stmts };
    }
    TemplateSegmentInterp { value: block }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::template_for @ d9be6853b
// `${for …}…${endfor}`, in either header form. A header the parser could not
// read leaves the same holes the host `for` does.
function template_for(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.TemplateFor,
    texts: Texts,
) -> TemplateSegment throws never {
    let open_span = v.range(node.open.span);
    match (node.open.header) {
        let header: root.syntax.CForHeader => {
            let init = match (header.init) {
                let s: root.syntax.LetStmt => let_stmt(ctx, v, s),
                _ => ctx.alloc_stmt(StmtMissing {}, open_span),
            };
            let cond_node = header.cond;
            let cond = if (cond_node != null) {
                expression(ctx, v, cond_node)
            } else {
                ctx.alloc_expr(ExprMissing {}, open_span)
            };
            let step_node = header.step;
            let step = if (step_node != null) {
                step_stmt(ctx, v, step_node)
            } else {
                null
            };
            let body = tag_body(ctx, v, node.body, texts);
            TemplateSegmentCStyleFor { init: init, cond: cond, step: step, body: body }
        },
        let header: root.syntax.ForInHeader => iterator_for(ctx, v, node, header, open_span, texts),
        let paren: root.syntax.ParenForInHeader => {
            iterator_for(ctx, v, node, paren.header, open_span, texts)
        },
        root.syntax.Bogus | root.syntax.Missing => {
            iterator_for(ctx, v, node, null, open_span, texts)
        },
    }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::iterator_for @ d9be6853b
// The iterator form, `${for let p in c}`. The collection is lowered before the
// pattern, as the rowan lowering orders them.
function iterator_for(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.TemplateFor,
    header: root.syntax.ForInHeader?,
    open_span: root.syntax.TextRange,
    texts: Texts,
) -> TemplateSegment throws never {
    let collection: int? = null;
    let binding: int? = null;
    if (header != null) {
        if let e: root.syntax.AnyExpr = header.iter {
            collection = expression(ctx, v, e);
        }
        warn_const_introducer(ctx, v, header.introducer);
        if let p: root.syntax.AnyPattern = header.pattern {
            binding = pattern(ctx, v, p);
        }
    }
    let collection_id = collection ?? ctx.alloc_expr(ExprMissing {}, open_span);
    let binding_id = binding ?? ctx.alloc_pattern(PatternWildcard {}, open_span);
    let body = tag_body(ctx, v, node.body, texts);
    TemplateSegmentFor { binding: binding_id, collection: collection_id, body: body }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::template_if @ d9be6853b
// `${if c}…${else if c}…${else}…${endif}`: each condition, then its body.
function template_if(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.TemplateIf,
    texts: Texts,
) -> TemplateSegment throws never {
    let branches: TemplateIfBranch[] = [];
    let condition = expr_or_missing(ctx, v, node.open.cond, v.range(node.open.span));
    let body = tag_body(ctx, v, node.then_parts, texts);
    branches.push(TemplateIfBranch { condition: condition, body: body });
    for (let elif in node.elifs) {
        let elif_condition = expr_or_missing(ctx, v, elif.cond, elif_head_span(v, elif));
        let elif_body = tag_body(ctx, v, elif.parts, texts);
        branches.push(TemplateIfBranch { condition: elif_condition, body: elif_body });
    }
    let else_part = node.else_part;
    let else_segments = if (else_part != null) {
        tag_body(ctx, v, else_part.parts, texts)
    } else {
        null
    };
    TemplateSegmentIf { branches: branches, else_body: else_segments }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::tag_body @ d9be6853b
// The parts between two block tags, trailing text included.
function tag_body(
    ctx: LoweringContext,
    v: View,
    parts: root.syntax.AnyTemplatePart[],
    texts: Texts,
) -> TemplateSegment[] throws never {
    let body = segments(ctx, v, parts, texts);
    texts.drain_into(body);
    body
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::elif_head_span @ d9be6853b
// `${else if c}` alone, without the parts that follow it in the node.
function elif_head_span(
    v: View,
    node: root.syntax.TemplateElif,
) -> root.syntax.TextRange throws never {
    let start = v.token_range(node.open).start;
    let close = node.close;
    let cond = node.cond;
    let end = if let c: int = close {
        v.token_range(c).end
    } else if let e: root.syntax.AnyExpr = cond {
        v.range(root.syntax.node_span(e)).end
    } else {
        v.token_range(node.if_kw).end
    };
    root.syntax.TextRange { start: start, end: end }
}

// ── Text ──────────────────────────────────────────────────────────────────

// port: baml_compiler2_ast/src/lower_tree/templates.rs::Flat @ d9be6853b
// The literal read flat, as the text rules see it.
type Flat = FlatText | FlatTag | FlatInterp;

class FlatText {
    value: string,
}

// A block tag: `${for …}`, `${if …}`, `${else if …}`, `${else}`, `${endfor}`,
// `${endif}`, or a stray one.
class FlatTag {
}

// A `${…}` interpolation.
class FlatInterp {
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::Texts @ d9be6853b
// The decoded text of a template, one gap at a time: the text before each
// non-text part in order, then the text after the last one.
// deviation: Rust's `vec::IntoIter` is the array and the index of the next gap.
class Texts {
    gaps: (string | null)[],
    next: int,

    // port: baml_compiler2_ast/src/lower_tree/templates.rs::Texts::read @ d9be6853b
    function read(v: View, parts: root.syntax.AnyTemplatePart[]) -> Texts throws never {
        let flat: Flat[] = [];
        flatten(v, parts, flat);
        let stripped = strip_around_block_tags(dedent(flat));
        let gaps: (string | null)[] = [];
        let current: string? = null;
        for (let part in stripped) {
            match (part) {
                let text: FlatText => {
                    current
                        = `${current ?? ""}${root.base.unescape_backtick_string_literal(text.value)}`;
                },
                FlatTag | FlatInterp => {
                    gaps.push(current);
                    current = null;
                },
            }
        }
        gaps.push(current);
        Texts { gaps: gaps, next: 0 }
    }

    // port: baml_compiler2_ast/src/lower_tree/templates.rs::Texts::drain_into @ d9be6853b
    // Append the next gap's text, if there is any, as a segment.
    function drain_into(self, out: TemplateSegment[]) -> void throws never {
        let gap = self.gaps.at(self.next);
        self.next += 1;
        if (gap) {
            out.push(TemplateSegmentText { value: gap });
        }
    }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::flatten @ d9be6853b
// The parts in order with nesting forgotten; adjacent text joined. Every tag
// is a part, a missing closing tag included, so the two walks agree.
function flatten(v: View, parts: root.syntax.AnyTemplatePart[], out: Flat[]) -> void throws never {
    for (let part in parts) {
        match (part) {
            let chunk: root.syntax.AnyTemplatePartChunk => push_text(out, v.text(chunk.token)),
            root.syntax.TemplateInterp => {
                out.push(FlatInterp {});
            },
            let node: root.syntax.TemplateFor => {
                out.push(FlatTag {});
                flatten(v, node.body, out);
                out.push(FlatTag {});
            },
            let node: root.syntax.TemplateIf => {
                out.push(FlatTag {});
                flatten(v, node.then_parts, out);
                for (let elif in node.elifs) {
                    out.push(FlatTag {});
                    flatten(v, elif.parts, out);
                }
                let else_part = node.else_part;
                if (else_part != null) {
                    out.push(FlatTag {});
                    flatten(v, else_part.parts, out);
                }
                out.push(FlatTag {});
            },
            root.syntax.Bogus => {
                out.push(FlatTag {});
            },
        }
    }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::push_text @ d9be6853b
function push_text(out: Flat[], text: string) -> void throws never {
    if (!text) {
        return;
    }
    if let last: FlatText = out.at(out.length() - 1) {
        last.value = `${last.value}${text}`;
    } else {
        out.push(FlatText { value: text });
    }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::dedent @ d9be6853b
// BEP section 12: dedent the literal as a whole, with each non-text part
// standing in as one placeholder character so that whitespace inside `${…}`
// is never counted (rule 8). A literal on one line is left alone.
// deviation: returns the new parts where Rust rewrites `flat` in place.
function dedent(flat: Flat[]) -> Flat[] throws never {
    let multiline = flat.some((part) -> {
        match (part) {
            let text: FlatText => text.value.includes("\n") || text.value.includes("\r"),
            _ => false,
        }
    });
    if (!multiline) {
        return flat;
    }
    let content = flat
        .filter_map((part) -> {
            match (part) {
                let text: FlatText => text.value,
                _ => null,
            }
        })
        .join("");
    let placeholder = private_use_char_absent_from(content);
    let joined = "";
    let markers: Flat[] = [];
    for (let part in flat) {
        match (part) {
            let text: FlatText => {
                joined = `${joined}${text.value}`;
            },
            _ => {
                joined = `${joined}${placeholder}`;
                markers.push(part);
            },
        }
    }
    let out: Flat[] = [];
    let pieces = dedent_backtick(joined).split(placeholder);
    for (let i = 0; i < pieces.length(); i += 1) {
        if (i > 0 && i - 1 < markers.length()) {
            out.push(markers[i - 1]);
        }
        if (pieces[i]) {
            out.push(FlatText { value: pieces[i] });
        }
    }
    out
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::dedent (the placeholder) @ d9be6853b
// deviation: split out of `dedent`. The first private-use character
// (U+E000..U+F8FF) `content` does not hold, else U+F8FF.
function private_use_char_absent_from(content: string) -> string throws never {
    for (let cp = 57344; cp <= 63743; cp += 1) {
        let c = string.from_code_points([cp]) catch (e) {
            baml.errors.InvalidArgument => {
                baml.sys.panic("a private-use code point is a scalar value")
            },
        };
        if (!content.includes(c)) {
            return c;
        }
    }
    "\u{F8FF}"
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::Strip @ d9be6853b
// How much to cut off a text part: `(index, length)` at the edge next to the
// tag. Lengths count characters where Rust counts bytes; every cut is of
// spaces, tabs and a line break, so the two agree.
type Strip = (int, int)?;

// port: baml_compiler2_ast/src/lower_tree/templates.rs::strip_around_block_tags @ d9be6853b
// BEP section 13: a block tag alone on its source line takes the line with
// it: the whitespace before it and the whitespace and line break after it.
// Inline `${…}` interpolations keep their surroundings; one on the tag's line
// means the tag is not alone. Two tags on consecutive lines share the text
// between them: applied last to first, each strip's count still refers to the
// edge it measured.
// deviation: returns the kept parts where Rust retains them in place.
function strip_around_block_tags(flat: Flat[]) -> Flat[] throws never {
    let plans: (Strip, Strip)[] = [];
    for (let i = 0; i < flat.length(); i += 1) {
        if (flat[i] is FlatTag) {
            let plan = alone_on_line(flat, i);
            if (plan != null) {
                plans.push(plan);
            }
        }
    }
    for (let p = plans.length() - 1; p >= 0; p -= 1) {
        strip_edge(flat, plans[p].0, true);
        strip_edge(flat, plans[p].1, false);
    }
    flat.filter((part) -> {
        match (part) {
            let text: FlatText => text.value != "",
            _ => true,
        }
    })
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::strip_around_block_tags (one cut) @ d9be6853b
// deviation: split out of `strip_around_block_tags`. Cut `strip` off the end
// of its text part (the text before a tag) or off its start (the text after).
function strip_edge(flat: Flat[], strip: Strip, at_end: bool) -> void throws never {
    if (strip == null) {
        return;
    }
    if let text: FlatText = flat.at(strip.0) {
        let len = text.value.length();
        let cut = if (strip.1 < len) {
            strip.1
        } else {
            len
        };
        text.value
            = if (at_end) {
                text.value.slice(0, len - cut)
            } else {
                text.value.slice(cut, len)
            };
    }
}

// port: baml_compiler2_ast/src/lower_tree/templates.rs::alone_on_line @ d9be6853b
// The strips for the tag at `tag`, or null when something other than blanks
// shares its line. Backwards to the previous line break or the start of the
// literal; forwards to the next line break (stripped too) or the end.
function alone_on_line(flat: Flat[], tag: int) -> (Strip, Strip)? throws never {
    let blank = (text: string) -> bool {
        text.chars().every((c) -> {
            c == " " || c == "\t"
        })
    };
    let before: Strip = null;
    for (let j = tag - 1; j >= 0; j -= 1) {
        let part = flat[j];
        if (!(part is FlatText)) {
            return null;
        }
        let text = part.value;
        let newline = text.last_index_of("\n");
        if (newline != null) {
            let tail = text.slice(newline + 1, text.length());
            if (!blank(tail)) {
                return null;
            }
            if (tail) {
                before = (j, tail.length());
            }
            break;
        }
        if (!blank(text)) {
            return null;
        }
        if (text) {
            before = (j, text.length());
        }
    }
    let after: Strip = null;
    for (let j = tag + 1; j < flat.length(); j += 1) {
        let part = flat[j];
        if (!(part is FlatText)) {
            return null;
        }
        let text = part.value;
        let newline = text.index_of("\n");
        if (newline != null) {
            if (!blank(text.slice(0, newline))) {
                return null;
            }
            after = (j, newline + 1);
            break;
        }
        if (!blank(text)) {
            return null;
        }
        if (text) {
            after = (j, text.length());
        }
    }
    (before, after)
}

// needs foundation: baml_base/src/dedent.rs::dedent_backtick. Strip the layout
// of a backtick string literal (BEP-049 section 12): `\r\n` and lone `\r`
// become `\n`; a single-line literal is unchanged; a multiline one loses
// every leading line break and all body-final ASCII layout whitespace, then
// the longest exact leading-whitespace prefix shared by its nonblank lines;
// lines of only ASCII layout become empty and leading empty lines go.
function dedent_backtick(text: string) -> string throws never {
    let normalized = text.replace_all("\r\n", "\n").replace_all("\r", "\n");
    if (!normalized.includes("\n")) {
        return normalized;
    }
    let chars = normalized.chars();
    let start = 0;
    while (start < chars.length() && chars[start] == "\n") {
        start += 1;
    }
    let end = chars.length();
    while (end > start && is_layout_whitespace(chars[end - 1])) {
        end -= 1;
    }
    let body = chars.slice(start, end).join("");
    let lines = if (body) {
        body.split("\n")
    } else {
        []
    };
    let strip = common_indent(lines);
    let dedented = lines.map((line) -> {
        if (
            line.chars().some((c) -> {
                !is_layout_whitespace(c)
            })
        ) {
            line.slice(strip.length(), line.length())
        } else {
            ""
        }
    });
    let first = 0;
    while (first < dedented.length() && !dedented[first]) {
        first += 1;
    }
    dedented.slice(first, dedented.length()).join("\n")
}

// needs foundation: baml_base/src/dedent.rs::is_layout_whitespace. Whitespace
// that is source layout rather than authored Unicode text.
function is_layout_whitespace(c: string) -> bool throws never {
    c == " " || c == "\t" || c == "\n"
}

// needs foundation: baml_base/src/dedent.rs::common_indent. The longest exact
// leading-whitespace prefix across the nonblank lines.
function common_indent(lines: string[]) -> string throws never {
    let common: string? = null;
    for (let line in lines) {
        if (
            line.chars().every((c) -> {
                is_layout_whitespace(c)
            })
        ) {
            continue;
        }
        let chars = line.chars();
        let n = 0;
        while (n < chars.length() && chars[n].is_whitespace()) {
            n += 1;
        }
        let ws = chars.slice(0, n);
        if (common == null) {
            common = ws.join("");
        } else {
            // The longest common prefix, character by character.
            let prev = common.chars();
            let k = 0;
            while (k < prev.length() && k < ws.length() && prev[k] == ws[k]) {
                k += 1;
            }
            common = prev.slice(0, k).join("");
        }
    }
    common ?? ""
}
