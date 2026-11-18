// port: baml_type/src/call_layout.rs::tests @ d9be6853b

// The mismatch `map_to` throws, or null when it maps.
function layout_mismatch(caller: CallLayout, target: CallLayout) -> LayoutMismatch? throws never {
    let _ = caller.map_to(target) catch_all (e) {
        _ => {
            return e;
        },
    };
    null
}

test "reorders named slots and omits implementation extras" {
    let caller = CallLayout { value: [null, "prefix", "suffix"] };
    let target = CallLayout { value: [null, "suffix", "extra", "prefix"] };
    assert.equal(caller.map_to(target), [0, 2, null, 1]);
    assert.equal(CallLayout.positional(1).map_to(target), [0, null, null, null]);
    assert.equal(target.map_to(target), [0, 1, 2, 3])
}

test "invalid shapes fail before mapping values" {
    assert.equal(
        layout_mismatch(CallLayout.positional(2), CallLayout.positional(1)),
        LayoutMismatchExtraRequired { expected: 1, got: 2 },
    );
    assert.equal(
        layout_mismatch(CallLayout.positional(1), CallLayout.positional(2)),
        LayoutMismatchMissingRequired { expected: 2, got: 1 },
    );
    assert.equal(
        layout_mismatch(CallLayout { value: ["a"] }, CallLayout { value: ["b"] }),
        LayoutMismatchUnknownOptional { value: "a" },
    )
}
