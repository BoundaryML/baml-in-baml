// port: baml_compiler_diagnostics/src/message.rs::tests @ d9be6853b

// The text a highlight covers.
function highlighted(text: DiagnosticText, index: int) -> string throws never {
    let h = text.highlights[index];
    baml.String.from_utf8(text.text_value.to_utf8().slice(h.start, h.end)) catch_all (e) {
        _ => baml.sys.panic("highlight is not on a character boundary"),
    }
}

test "builder preserves plain text and records fragment ranges" {
    let text = DiagnosticText.new()
        .text("expected ")
        .type_expr("map<string, int>")
        .text(", found ")
        .identifier("value", DiagnosticIdentifierKind.Variable);

    assert.equal(text.text_value, "expected `map<string, int>`, found `value`");
    assert.equal(highlighted(text, 0), "map<string, int>");
    assert.equal(highlighted(text, 1), "value")
}

test "string conversion highlights backticked code" {
    let text = diagnostic_text_from("unknown variable `value`");

    assert.equal(text.highlights.length(), 1);
    assert.equal(highlighted(text, 0), "value");
    assert.equal(text.highlights[0].kind, DiagnosticMessageKindCode {})
}
