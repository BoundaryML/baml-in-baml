// port: baml_compiler2_ast/src/lower_tree/templates.rs::tests @ d9be6853b

// The text of each part, null for a tag or an interpolation.
function flat_texts(flat: Flat[]) -> (string | null)[] throws never {
    flat.map((part) -> {
        match (part) {
            let text: FlatText => text.value,
            _ => null,
        }
    })
}

test "tag alone on its line takes the line" {
    let flat: Flat[] = [
        FlatText { value: "a\n  " },
        FlatTag {},
        FlatText { value: "  \n  b\n" },
        FlatTag {},
        FlatText { value: "\nc" },
    ];
    assert.equal(flat_texts(strip_around_block_tags(flat)), ["a\n", null, "  b\n", null, "c"])
}

test "inline tag keeps its line" {
    let flat: Flat[] = [FlatText { value: "a " }, FlatTag {}, FlatText { value: " b\n" }];
    assert.equal(flat_texts(strip_around_block_tags(flat)), ["a ", null, " b\n"])
}

test "interpolation on the line means not alone" {
    let flat: Flat[] = [
        FlatText { value: "\n  " },
        FlatTag {},
        FlatText { value: " " },
        FlatInterp {},
        FlatText { value: "\n" },
    ];
    assert.equal(flat_texts(strip_around_block_tags(flat)), ["\n  ", null, " ", null, "\n"])
}

test "dedent holds interpolations out" {
    let flat: Flat[] = [FlatText { value: "\n    a " }, FlatInterp {}, FlatText { value: "\n      b\n  " }];
    assert.equal(flat_texts(dedent(flat)), ["a ", null, "\n  b"])
}
