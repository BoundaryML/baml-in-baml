// port: baml_tests/src/type_spec/harness.rs @ d9be6853b
//
// `//^^^ ty` annotation checks and `check_infer`-style dumps (after
// rust-analyzer's `check_types` / `check_infer`) against our `hir_ty`.
//
// A fixture is a single BAML file. Annotation lines are comments whose first
// non-space content after `//` is a caret run; the carets select a byte range
// on the nearest preceding non-annotation line, and the rest of the line is
// the expected type, rendered from the canonical viewpoint
// (`Viewpoint.canonical`). A caret range matches an expression span, a
// binding-pattern span, a binding's name, or (`throws <ty>`) a function's
// name. The check is strict in both directions: an annotation that matches
// nothing fails, an annotation whose type differs fails, and a fixture with
// no annotations fails. Fixtures must be ASCII (caret columns are byte
// offsets, and our string slicing is by character).
//
// hir_ty's error channel is asserted too, clean by default: every recorded
// type mismatch, failed or undecided implements goal, and non-exhaustive
// match must be annotated (`mismatch: expected X, got Y`, `implements:
// <verdict>`, `non-exhaustive`), and every such annotation must match a
// recorded entry at its exact range.
//
// Restructured:
// - A range key `(start, end)` is one int, `start * 2^32 + end`
//   (`range_key`): it orders as Rust's tuple does, and BAML tuples are not
//   map keys. Rust's `BTreeMap<(u32, u32), _>` is `map<int, _>` read in
//   sorted key order.
// - `run_fixture` takes the Db (one stdlib Db shared by every fixture, each
//   fixture its own workspace root) instead of building one per fixture.
// - `FixtureOutcome.hir_ty` is the failure list (empty is Rust's `Ok(())`);
//   `to_result`, which only joins it, folds into the summary.
// - Failure messages are `line:col expected=<...> ours=<...>` (the summary's
//   format) instead of Rust's prose; the same cases fail. `line` is the
//   annotated code line, `col` the 1-based caret column; an unannotated
//   channel entry reports the position of its range (`line_col`, added).
//   `Annotation.code_col` is added for this.
// - `&mut` out-params (`failures`, `msg`) are returned or pushed to arrays.
//
// Not ported: `check_types` (an inline-test entry point Rust marks unused).

// port: baml_tests/src/type_spec/harness.rs::Annotation @ d9be6853b
// One caret annotation: the source range it selects, the expectation, and
// the 1-based line (and caret column) of the annotated code.
class Annotation {
    range: root.syntax.TextRange,
    kind: AnnotationKind,
    expected: string,
    code_line: int,
    code_col: int,
}

// port: baml_tests/src/type_spec/harness.rs::AnnotationKind @ d9be6853b
// What a caret asserts. `Ty` checks the inferred type. `Mismatch`,
// `Implements` and `NonExhaustive` assert hir_ty's error channel.
enum AnnotationKind {
    Ty,
    // `// ^ mismatch: expected <ty>, got <ty>`
    Mismatch,
    // `// ^ implements: <verdict>`, one of the renderings of
    // `implements_verdict`.
    Implements,
    // `// ^ non-exhaustive`
    NonExhaustive,
}

// port: baml_tests/src/type_spec/harness.rs::FixtureOutcome @ d9be6853b
// Annotation-check failures (empty when every check passes) plus an
// optional rendered infer dump.
class FixtureOutcome {
    hir_ty: string[],
    dump: string,
}

// port: baml_tests/src/type_spec/harness.rs::run_fixture @ d9be6853b
// Infer `fixture` (as `test.baml`, a new workspace root of `db`) and check
// every caret and error-channel annotation. Render the full node dump only
// for an explicitly selected golden.
function run_fixture(
    db: root.hir.Db,
    fixture: string,
    render_dump: bool,
) -> FixtureOutcome throws never {
    if (!fixture.is_ascii()) {
        baml.sys.panic("fixtures must be ASCII");
    }
    let annotations = extract_annotations(fixture);
    if (annotations.length() == 0) {
        baml.sys.panic("fixture has no //^ annotations; check_types requires at least one");
    }

    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    let file = root.db.add_file(db, workspace, "test.baml", fixture);

    let hir_ty_nodes = collect_hir_ty_nodes(db, file, fixture);
    let channel = collect_hir_ty_error_channel(db, file);

    let hir_ty_failures = check_annotations(hir_ty_nodes, fixture, annotations).concat(
        check_error_channel(channel, fixture, annotations),
    );

    let dump = if (render_dump) {
        render_infer(hir_ty_nodes, fixture) + render_error_channel(channel, fixture)
    } else {
        ""
    };
    FixtureOutcome { hir_ty: hir_ty_failures, dump: dump }
}

// port: baml_tests/src/type_spec/harness.rs::ErrorChannel @ d9be6853b
// hir_ty's recorded error channel for one file: type mismatches (rendered
// `expected X, got Y`), implements verdicts, and non-exhaustive matches,
// each at its expression's source range (keys are `range_key`s).
class ErrorChannel {
    mismatches: map<int, string[]>,
    // `implements_`: `implements` is a keyword.
    implements_: map<int, string[]>,
    non_exhaustive: root.syntax.TextRange[],
}

// port: baml_tests/src/type_spec/harness.rs::implements_verdict @ d9be6853b
// The rendering of an implements goal that failed or could not be decided,
// or null for any other diagnostic.
function implements_verdict(
    error: root.hir_ty.TirTypeError,
    vp: root.hir_ty.Viewpoint,
) -> string? throws never {
    let render = (ty: root.types.Ty) -> string {
        root.hir_ty.ty_spell(ty, vp)
    };
    match (error) {
        let e: root.hir_ty.TirTypeErrorTypeDoesNotImplementInterface => {
            `${render(e.value_type)} does not implement ${render(e.interface_)}`
        },
        let e: root.hir_ty.TirTypeErrorBlanketBoundNotSatisfied => {
            `${render(e.value_type)} does not satisfy ${render(e.bound)}`
        },
        let e: root.hir_ty.TirTypeErrorNotIterable => `${render(e.ty)} is not iterable`,
        let e: root.hir_ty.TirTypeErrorBoundedTypeArgNotConcrete => {
            let bound = e.bound.map((interface_) -> {
                root.hir_ty.interface_spell(interface_, vp)
            });
            `${render(e.arg)} is not concrete, as ${bound.join(" & ")} requires`
        },
        let e: root.hir_ty.TirTypeErrorAmbiguousImplementation => {
            `${render(e.value_type)} implements ${render(e.interface_)} more than one way`
        },
        _ => null,
    }
}

// port: baml_tests/src/type_spec/harness.rs::collect_hir_ty_error_channel @ d9be6853b
function collect_hir_ty_error_channel(db: root.hir.Db, file: int) -> ErrorChannel throws never {
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let channel = ErrorChannel { mismatches: {}, implements_: {}, non_exhaustive: [] };
    for (let owner in root.hir.file_body_owners(db, file)) {
        let body = root.hir.body(db, owner);
        if (root.hir.owner_body_expr_body(body) == null) {
            continue;
        }
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        let result = root.hir_ty.infer_body(db, owner);
        for (let expr_id in result.type_mismatches.keys()) {
            let pair = result.type_mismatches[expr_id];
            let rendered = `expected ${root.hir_ty.ty_spell(pair.0, vp)}, got ${root.hir_ty.ty_spell(pair.1, vp)}`;
            push_unique(channel.mismatches, range_key(source_map.expr_span(expr_id)), rendered);
        }
        for (let diagnostic in result.diagnostics) {
            let expr_id = match (diagnostic.primary) {
                let e: root.hir_ty.DiagnosticLocationExpr => e.value,
                _ => {
                    continue;
                },
            };
            let rendered = implements_verdict(diagnostic.error, vp)
                ?? continue;
            push_unique(channel.implements_, range_key(source_map.expr_span(expr_id)), rendered);
        }
        for (let expr_id in result.non_exhaustive_matches.keys()) {
            let range = source_map.expr_span(expr_id);
            if (!channel.non_exhaustive.includes(range)) {
                channel.non_exhaustive.push(range);
            }
        }
    }
    channel.non_exhaustive.sort_by_key((range) -> {
        range_key(range)
    });
    channel
}

// Rust's `entry(key).or_default()` followed by a push unless present.
function push_unique(entries: map<int, string[]>, key: int, rendered: string) -> void throws never {
    if (!entries.has(key)) {
        entries[key] = [];
    }
    let entry = entries[key];
    if (!entry.includes(rendered)) {
        entry.push(rendered);
    }
}

// port: baml_tests/src/type_spec/harness.rs::check_error_channel @ d9be6853b
// The clean-by-default contract, strict in both directions: every
// `mismatch:` / `implements:` / `non-exhaustive` annotation must match a
// recorded entry at its exact range, and every recorded entry must be
// annotated.
function check_error_channel(
    channel: ErrorChannel,
    fixture: string,
    annotations: Annotation[],
) -> string[] throws never {
    let failures = check_keyed_channel("mismatch", channel.mismatches, AnnotationKind.Mismatch, fixture, annotations)
        .concat(
            check_keyed_channel("implements", channel.implements_, AnnotationKind.Implements, fixture, annotations),
        );
    let covered_non_exhaustive: int[] = [];
    for (
        let ann in annotations.filter((ann) -> {
            ann.kind == AnnotationKind.NonExhaustive
        })
    ) {
        if (
            channel.non_exhaustive.some((range) -> {
                range_key(range) == range_key(ann.range)
            })
        ) {
            covered_non_exhaustive.push(range_key(ann.range));
        } else {
            failures.push(
                `${ann.code_line}:${ann.code_col} expected=non-exhaustive ours=<none recorded> at \`${fixture.slice(ann.range.start, ann.range.end)}\``,
            );
        }
    }
    for (let range in channel.non_exhaustive) {
        if (!covered_non_exhaustive.includes(range_key(range))) {
            failures.push(
                `${line_col(fixture, range.start)} expected=<clean> ours=non-exhaustive at \`${ellipsize(fixture.slice(range.start, range.end), 30)}\``,
            );
        }
    }
    failures
}

// port: baml_tests/src/type_spec/harness.rs::check_keyed_channel @ d9be6853b
// One range-keyed channel's half of `check_error_channel`: the annotations of
// `kind` against the entries of `recorded`, both directions.
function check_keyed_channel(
    label: string,
    recorded: map<int, string[]>,
    kind: AnnotationKind,
    fixture: string,
    annotations: Annotation[],
) -> string[] throws never {
    let failures: string[] = [];
    let covered: int[] = [];
    for (
        let ann in annotations.filter((ann) -> {
            ann.kind == kind
        })
    ) {
        let at = `${ann.code_line}:${ann.code_col} expected=${label}: ${ann.expected}`;
        let text = fixture.slice(ann.range.start, ann.range.end);
        let rendered = recorded.get(range_key(ann.range));
        if (rendered == null) {
            failures.push(`${at} ours=<none recorded> at \`${text}\``);
        } else if (!rendered.includes(ann.expected)) {
            failures.push(`${at} ours=${label}: ${rendered.join(" / ")} at \`${text}\``);
        } else {
            covered.push(range_key(ann.range));
        }
    }
    for (let key in sorted_keys(recorded)) {
        if (!covered.includes(key)) {
            let range = range_of_key(key);
            failures.push(
                `${line_col(fixture, range.start)} expected=<clean> ours=${label}: ${recorded[key].join(" / ")} at \`${ellipsize(fixture.slice(range.start, range.end), 30)}\``,
            );
        }
    }
    failures
}

// port: baml_tests/src/type_spec/harness.rs::render_error_channel @ d9be6853b
// The dump's trailing error-channel section: one line per recorded entry.
function render_error_channel(channel: ErrorChannel, fixture: string) -> string throws never {
    let lines: string[] = [];
    for (let section in [("mismatch", channel.mismatches), ("implements", channel.implements_)]) {
        for (let key in sorted_keys(section.1)) {
            let range = range_of_key(key);
            let text = ellipsize(fixture.slice(range.start, range.end), 15);
            for (let entry in section.1[key]) {
                lines.push(`${range.start}..${range.end} '${text}': [${section.0}] ${entry}\n`);
            }
        }
    }
    for (let range in channel.non_exhaustive) {
        let text = ellipsize(fixture.slice(range.start, range.end), 15);
        lines.push(`${range.start}..${range.end} '${text}': [non-exhaustive]\n`);
    }
    lines.join("")
}

// port: baml_tests/src/type_spec/harness.rs::check_annotations @ d9be6853b
// Checks every type annotation against the typed nodes.
function check_annotations(
    nodes: TypedNode[],
    fixture: string,
    annotations: Annotation[],
) -> string[] throws never {
    let types: map<int, string[]> = {};
    for (let node in nodes) {
        push_unique(types, range_key(node.range), node.ty);
    }

    annotations
        .filter((ann) -> {
            ann.kind == AnnotationKind.Ty
        })
        .filter_map((ann) -> {
            let at = `${ann.code_line}:${ann.code_col} expected=${ann.expected}`;
            let text = fixture.slice(ann.range.start, ann.range.end);
            let rendered = types.get(range_key(ann.range));
            if (rendered == null) {
                `${at} ours=<no inferred type> at \`${text}\`${write_candidates_on_line(fixture, types, ann)}`
            } else if (!rendered.includes(ann.expected)) {
                `${at} ours=${rendered.join(" / ")} at \`${text}\``
            } else {
                null
            }
        })
}

// port: baml_tests/src/type_spec/harness.rs::render_infer @ d9be6853b
// Render inferred nodes as `start..end 'text': ty`. The name-narrowed
// binding entries used by caret matching are excluded: the dump reflects real
// node spans only.
function render_infer(hir_ty: TypedNode[], fixture: string) -> string throws never {
    let merged: map<int, string[]> = {};
    for (let node in hir_ty) {
        if (node.kind == NodeKind.BindingName) {
            continue;
        }
        push_unique(merged, range_key(node.range), node.ty);
    }
    let lines: string[] = [];
    for (let key in sorted_keys(merged)) {
        let range = range_of_key(key);
        let text = ellipsize(fixture.slice(range.start, range.end), 15);
        let tys = merged[key];
        tys.sort_by((a, b) -> {
            a.cmp(b)
        });
        for (let ty in tys) {
            lines.push(`${range.start}..${range.end} '${text}': ${ty}\n`);
        }
    }
    lines.join("")
}

// port: baml_tests/src/type_spec/harness.rs::ellipsize @ d9be6853b
// Shortens `text` to at most `max` bytes with a `...` midsection, escaping
// newlines so every dump entry stays on one line.
function ellipsize(text: string, max: int) -> string throws never {
    let flat = text.replace_all("\n", "\\n");
    if (flat.length() <= max) {
        return flat;
    }
    let prefix = (max - 3) / 2;
    let suffix = max - 3 - prefix;
    `${flat.slice(0, prefix)}...${flat.slice(flat.length() - suffix, flat.length())}`
}

// The 2^32 factor of `range_key`: byte offsets stay below it.
const RANGE_KEY_SHIFT: int = 4294967296;

// port: baml_tests/src/type_spec/harness.rs::range_key @ d9be6853b
// `(start, end)` packed into one int that orders as the tuple does.
function range_key(range: root.syntax.TextRange) -> int throws never {
    range.start * RANGE_KEY_SHIFT + range.end
}

// The range a `range_key` packs.
function range_of_key(key: int) -> root.syntax.TextRange throws never {
    root.syntax.TextRange { start: key / RANGE_KEY_SHIFT, end: key % RANGE_KEY_SHIFT }
}

// A range-keyed map's keys in Rust's `BTreeMap` order.
function sorted_keys(entries: map<int, string[]>) -> int[] throws never {
    entries.keys().sort_by((a, b) -> {
        a.cmp(b)
    })
}

// `line:col` (both 1-based) of byte `offset` in `fixture`.
function line_col(fixture: string, offset: int) -> string throws never {
    let before = fixture.slice(0, offset);
    let line_start = (before.last_index_of("\n") ?? -1) + 1;
    `${before.split("\n").length()}:${offset - line_start + 1}`
}

// port: baml_tests/src/type_spec/harness.rs::write_candidates_on_line @ d9be6853b
// The ranges on the annotated line that do have types, so a misaligned
// caret fails with the nearby candidates instead of nothing. Returns the
// text Rust appends to `msg` (empty when there are none).
function write_candidates_on_line(
    fixture: string,
    types: map<int, string[]>,
    ann: Annotation,
) -> string throws never {
    let line_start = (fixture.slice(0, ann.range.start).last_index_of("\n") ?? -1) + 1;
    let rest = fixture.slice(line_start, fixture.length());
    let line_end = line_start + (rest.index_of("\n") ?? rest.length());
    // Rust's `range((line_start, 0)..(line_end, u32::MAX))`.
    let low = line_start * RANGE_KEY_SHIFT;
    let high = line_end * RANGE_KEY_SHIFT + RANGE_KEY_SHIFT - 1;
    let candidates = sorted_keys(types).filter((key) -> {
        key >= low && key < high
    });
    if (candidates.length() == 0) {
        return "";
    }
    let listed = candidates.map((key) -> {
        let range = range_of_key(key);
        ` \`${fixture.slice(range.start, range.end)}\`: \`${types[key].join("` / `")}\``
    });
    `; typed ranges on that line:${listed.join("")}`
}

// port: baml_tests/src/type_spec/harness.rs::extract_annotations @ d9be6853b
// Extracts caret annotations. Stacked annotation lines all target the same
// (nearest preceding non-annotation) line.
function extract_annotations(text: string) -> Annotation[] throws never {
    let annotations: Annotation[] = [];
    // (byte offset, byte length, 1-based line number) of the target line.
    let target: (int, int, int)? = null;
    let offset = 0;
    let lines = text.split("\n");
    for (let idx = 0; idx < lines.length(); idx += 1) {
        let line = lines[idx];
        let parsed = parse_annotation_line(line);
        if (parsed != null) {
            let (let caret_col, let caret_len, let content) = parsed;
            let (let t_offset, let t_len, let t_line) = target ?? baml.sys.panic(`line ${idx + 1}: annotation has no preceding code line`);
            if (caret_col + caret_len > t_len) {
                baml.sys.panic(`line ${idx + 1}: carets extend past the annotated line ${t_line}`);
            }
            let start = t_offset + caret_col;
            let kind_expected: (AnnotationKind, string) = if (content.starts_with("mismatch:")) {
                (AnnotationKind.Mismatch, content.slice(9, content.length()).trim())
            } else if (content.starts_with("implements:")) {
                (AnnotationKind.Implements, content.slice(11, content.length()).trim())
            } else if (content == "non-exhaustive") {
                (AnnotationKind.NonExhaustive, "")
            } else {
                (AnnotationKind.Ty, content)
            };
            annotations.push(
                Annotation {
                    range: root.syntax.TextRange { start: start, end: start + caret_len },
                    kind: kind_expected.0,
                    expected: kind_expected.1,
                    code_line: t_line,
                    code_col: caret_col + 1,
                },
            );
        } else {
            target = (offset, line.length(), idx + 1);
        }
        offset += line.length() + 1;
    }
    annotations
}

// port: baml_tests/src/type_spec/harness.rs::parse_annotation_line @ d9be6853b
// Parses `  // ^^^ expected` into (caret start column, caret run length,
// expected text); null for non-annotation lines. Columns are byte offsets
// into the whole line so they align with the code line above.
function parse_annotation_line(line: string) -> (int, int, string)? throws never {
    let trimmed = line.trim_start();
    if (!trimmed.starts_with("//")) {
        return null;
    }
    let after = trimmed.slice(2, trimmed.length()).trim_start();
    if (!after.starts_with("^")) {
        return null;
    }
    let caret_col = line.length() - after.length();
    let caret_len = 0;
    while (after.at(caret_len) == "^") {
        caret_len += 1;
    }
    let content = after.slice(caret_len, after.length()).trim();
    if (content.length() == 0) {
        baml.sys.panic(`annotation line \`${line}\` has no expected type after the carets`);
    }
    (caret_col, caret_len, content)
}

// port: baml_tests/src/type_spec/harness.rs::NodeKind @ d9be6853b
enum NodeKind {
    Expr,
    Pattern,
    // A binding re-keyed to just its introduced name (`x`, not `let x`), the
    // natural caret target. Excluded from the dump.
    BindingName,
}

// port: baml_tests/src/type_spec/harness.rs::TypedNode @ d9be6853b
class TypedNode {
    range: root.syntax.TextRange,
    kind: NodeKind,
    ty: string,
}

// port: baml_tests/src/type_spec/harness.rs::OwnerInference @ d9be6853b
// Per-body-owner inference state paired with the maps needed to resolve
// arena ids to source ranges.
class OwnerInference {
    body: root.hir.OwnerBody,
    source_map: root.ast.AstSourceMap,
    result: root.hir_ty.InferenceResult<root.types.Ty>,
}

// port: baml_tests/src/type_spec/harness.rs::collect_hir_ty_nodes @ d9be6853b
// Runs inference over every body owner in `file` and renders each inferred
// expression and binding with its source range. Compiler-synthesized nodes
// are skipped: fixtures assert what the user wrote.
function collect_hir_ty_nodes(
    db: root.hir.Db,
    file: int,
    fixture: string,
) -> TypedNode[] throws never {
    let vp = root.hir_ty.Viewpoint.canonical(db);
    let index = root.hir.file_semantic_index(db, file);
    let render = (ty: root.types.Ty) -> string {
        root.hir_ty.ty_spell(ty, vp)
    };

    // Inference results per body owner, keyed by the owner's file scope id so
    // binding lookups (which start from arbitrary child scopes) can find the
    // arena owner's result.
    let owners: map<int, OwnerInference> = {};
    for (let owner in root.hir.file_body_owners(db, file)) {
        let scope_id = root.hir.body_scope(db, owner)
            ?? continue;
        let body = root.hir.body(db, owner);
        if (root.hir.owner_body_expr_body(body) == null) {
            continue;
        }
        let source_map = root.hir.body_source_map(db, owner)
            ?? continue;
        owners[db.scopes.get(scope_id).id]
            = OwnerInference {
                body: body,
                source_map: source_map,
                result: root.hir_ty.infer_body(db, owner),
            };
    }

    let nodes: TypedNode[] = [];
    // Each function's inferred effect, keyed at the function name range: the
    // caret target for `throws` pins.
    for (let owner_id in root.hir.file_body_owners(db, file)) {
        let function_ = match (owner_id) {
            let f: root.hir.BodyOwnerIdFunction => f.value,
            _ => {
                continue;
            },
        };
        let scope_id = root.hir.body_scope(db, owner_id)
            ?? continue;
        let owner = owners.get(db.scopes.get(scope_id).id)
            ?? continue;
        let name_span = root.hir.function_source_map(db, function_).name_span;
        if (name_span.start != name_span.end) {
            nodes.push(
                TypedNode {
                    range: name_span,
                    kind: NodeKind.Expr,
                    ty: `throws ${render(owner.result.throws_)}`,
                },
            );
        }
    }
    let owner_scopes = owners.keys().sort_by((a, b) -> {
        a.cmp(b)
    });
    for (let owner_scope in owner_scopes) {
        let owner = owners[owner_scope];
        for (let expr_id in owner.result.type_of_expr.keys()) {
            if (owner.source_map.is_synthetic_expr(expr_id)) {
                continue;
            }
            nodes.push(
                TypedNode {
                    range: owner.source_map.expr_span(expr_id),
                    kind: NodeKind.Expr,
                    ty: render(owner.result.type_of_expr[expr_id]),
                },
            );
        }
        let body = root.hir.owner_body_expr_body(owner.body)
            ?? continue;
        for (let pat_id = 0; pat_id < body.patterns.length(); pat_id += 1) {
            if (owner.source_map.synthetic_patterns.has(pat_id)) {
                continue;
            }
            let ty = owner.result.type_of_pat.get(pat_id);
            if (ty != null) {
                nodes.push(
                    TypedNode {
                        range: owner.source_map.pattern_span(pat_id),
                        kind: NodeKind.Pattern,
                        ty: render(ty),
                    },
                );
            }
        }
    }

    // Bindings again, keyed by just the introduced name. A binding lives in
    // the scope that declares it (often a Block), so resolve through the
    // enclosing body owner's result.
    for (let idx = 0; idx < index.scope_bindings.length(); idx += 1) {
        let bindings = index.scope_bindings[idx].bindings;
        if (bindings.length() == 0) {
            continue;
        }
        let owner_scope = enclosing_owner_scope(index, idx)
            ?? continue;
        let owner = owners.get(owner_scope)
            ?? continue;
        for (let binding in bindings) {
            let ty = owner.result.type_of_pat.get(binding.bind_pattern);
            if (ty != null) {
                nodes.push(
                    TypedNode {
                        range: binding_name_range(fixture, binding),
                        kind: NodeKind.BindingName,
                        ty: render(ty),
                    },
                );
            }
        }
    }

    nodes.filter((node) -> {
        node.range.start != node.range.end
    })
}

// port: baml_tests/src/type_spec/harness.rs::binding_name_range @ d9be6853b
// The range of just the introduced identifier. A `let x` / `let x: T` Bind
// pattern's `name_range` can span the whole pattern including the keyword
// and annotation, so narrow to the first word-boundary occurrence of the
// name; ranges that already are the bare name pass through unchanged.
function binding_name_range(
    fixture: string,
    binding: root.hir.LocalBinding,
) -> root.syntax.TextRange throws never {
    let name = binding.name;
    let text = fixture.slice(binding.name_range.start, binding.name_range.end);
    if (text == name) {
        return binding.name_range;
    }
    let is_ident = (c: string) -> bool {
        c.is_ascii_alphanumeric() || c == "_"
    };
    let search_from = 0;
    while (true) {
        let found = text.slice(search_from, text.length()).index_of(name)
            ?? break;
        let idx = search_from + found;
        let before_ok = idx == 0 || !is_ident(text.slice(idx - 1, idx));
        let after = idx + name.length();
        let after_ok = after == text.length() || !is_ident(text.slice(after, after + 1));
        if (before_ok && after_ok) {
            let start = binding.name_range.start + idx;
            return root.syntax.TextRange { start: start, end: start + name.length() };
        }
        search_from = idx + 1;
    }
    binding.name_range
}

// port: baml_tests/src/type_spec/harness.rs::enclosing_owner_scope @ d9be6853b
// Walks to the enclosing scope (self included) that belongs to a body owner
// (function or top-level let): the arena owner for everything nested in it,
// lambdas included.
function enclosing_owner_scope(index: root.hir.FileSemanticIndex, fsi: int) -> int? throws never {
    let current = fsi;
    while (true) {
        let scope = index.scopes[current];
        match (scope.kind) {
            root.hir.ScopeKind.Function | root.hir.ScopeKind.Let => {
                return current;
            },
            _ => {
                current
                    = scope.parent
                        ?? return null;
            },
        }
    }
}
