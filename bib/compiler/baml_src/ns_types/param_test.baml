// port: baml_type/src/param.rs::tests @ d9be6853b

test "frame index distinguishes same named parameters" {
    let outer = ParamTy { index: 0, name: "E" };
    let inner = ParamTy { index: 1, name: "E" };
    let layout = RuntimeGenericLayout.new([outer, inner]);
    assert.is_true(outer != inner);
    assert.equal(layout.slot(outer), 0);
    assert.equal(layout.slot(inner), 1)
}

test "runtime layout omits effect params and compacts slots" {
    let first = ParamTy { index: 0, name: "T" };
    let effect = ParamTy { index: 1, name: "__effect_param_0" };
    let last = ParamTy { index: 2, name: "U" };
    // A scoped binding is a slot whatever it is called.
    let scoped = ParamTy { index: SCOPED_PARAM_BIT | 5, name: "__effect_param_0" };
    let layout = RuntimeGenericLayout.new([first, effect, last, scoped]);
    assert.equal(layout.params, [first, last, scoped]);
    assert.equal(layout.slot(first), 0);
    assert.equal(layout.slot(effect), null);
    assert.equal(layout.slot(last), 1);
    assert.equal(layout.slot(scoped), 2);
    assert.equal(layout.slots(), [0, 1, 2])
}
