// port: baml_compiler2_ast/src/lib.rs @ d9be6853b (the code above the tests)
//
// Namespace `ast`: the AST and the CST → AST lowering. This layer isolates the
// CST's messiness; after lowering, the CST is never needed again.

// port: lib.rs::DEFAULT_RECEIVER_KEYWORD. The BEP-044 `default` receiver: in
// an `implements` block, `default.method(...)` calls the interface's default
// body, bypassing the class's override. A contextual keyword recognized by
// name at the root of a path, so a local named `default` shadows it.
const DEFAULT_RECEIVER_KEYWORD: string = "default";

// port: baml_compiler2_ast/src/lib.rs::parse_string_attr_value @ d9be6853b
// A quoted string attribute value (the raw, still-quoted token text of a
// `RawAttributeArg.value`) as its runtime string; null when it is not a
// recognized string literal. The single source of truth for `@alias` /
// `@description` values, so the emitter and HIR validation agree.
function parse_string_attr_value(raw: string) -> string? throws never {
    let quoted_by = (q: string) -> bool {
        raw.starts_with(q) && raw.ends_with(q) && raw.byte_length() >= 2
    };
    // Double-quoted "text" or single-quoted 'text'.
    if (quoted_by("\"") || quoted_by("'")) {
        return root.base.unescape_string_literal(raw.slice(1, raw.length() - 1));
    }
    null
}

// port: baml_compiler2_ast/src/lib.rs::push_num_lit_error @ d9be6853b
// Push diagnostics for a failed numeric literal: `InvalidDigits` gets one per
// offending digit spanning that digit (rustc-style); every other error spans
// the whole token.
function push_num_lit_error(
    error: root.base.IntLitError,
    token_range: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> void throws never {
    if (error is root.base.IntLitErrorInvalidDigits) {
        for (let position in error.positions) {
            let (let offset, let ch) = position;
            let start = token_range.start + offset;
            let span = root.syntax.TextRange { start: start, end: start + ch.byte_length() };
            diags.push(LoweringDiagnosticInvalidNumericLiteral { error: error, span: span });
        }
    } else {
        diags.push(LoweringDiagnosticInvalidNumericLiteral { error: error, span: token_range });
    }
}

// port: baml_compiler2_ast/src/lib.rs::lower_int_literal @ d9be6853b
// The value of an `INTEGER_LITERAL` token's text (`42`, `1_000`, `0xFF`,
// `0o755`, `0b1010`); on an invalid literal, diagnostics and the placeholder
// `0` (compilation already failed). Signs are the caller's.
function lower_int_literal(
    text: string,
    token_range: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> int throws never {
    let result = root.base.parse_int_literal(text);
    match (result) {
        let v: int => v,
        let e: root.base.IntLitError => {
            push_num_lit_error(e, token_range, diags);
            0
        },
    }
}

// port: baml_compiler2_ast/src/lib.rs::lower_bigint_literal @ d9be6853b
// The value of a `BIGINT_LITERAL` token's text (digits plus the `n` suffix
// the lexer guarantees, `42n`, `0xFFn`); on an invalid literal, diagnostics
// and the placeholder `0n`.
function lower_bigint_literal(
    text: string,
    token_range: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> bigint throws never {
    if (!text.ends_with("n")) {
        baml.sys.panic(`BIGINT_LITERAL missing 'n' suffix: ${root.base.rust_debug_string(text)}`);
    }
    let digits = text.slice(0, text.length() - 1);
    match (root.base.parse_bigint_literal_with_max_bits(digits, root.base.MAX_BIGINT_BITS)) {
        let v: bigint => v,
        let e: root.base.IntLitError => {
            push_num_lit_error(e, token_range, diags);
            0n
        },
    }
}
