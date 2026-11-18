// port: baml_type/src/json_tags.rs::tests @ d9be6853b

function read_of(
    key: string,
    arms: (string, TagTreeMember | TagTreeRead<string>)[],
) -> TagTreeMember | TagTreeRead<string> throws never {
    TagTreeRead { key: key, arms: arms }
}

// The tree, or why there is none.
function tag_outcome(
    members: (string, string)[][],
    fallback: (string, string)[],
) -> TagTreeMember | TagTreeRead<string> | Untagged throws never {
    tag_tree(members, fallback) catch_all (e) {
        _ => e,
    }
}

test "a tag decides and other literals are left to the member" {
    // `role` sorts before `type`, and is not what the fallback names.
    let members = [[("role", "admin"), ("type", "manager")], [("role", "user"), ("type", "workspace")]];
    assert.equal(
        tag_outcome(members, [("type", "UNKNOWN")]),
        read_of(
            "type",
            [("manager", TagTreeMember { value: 0 }), ("workspace", TagTreeMember { value: 1 })],
        ),
    )
}

test "members sharing a tag are told apart by the next key" {
    let members = [
        [("service", "s3"), ("type", "storage")],
        [("service", "gcs"), ("type", "storage")],
        [("type", "ai")],
    ];
    assert.equal(
        tag_outcome(members, [("type", "UNKNOWN")]),
        read_of(
            "type",
            [
                (
                    "storage",
                    read_of(
                        "service",
                        [("s3", TagTreeMember { value: 0 }), ("gcs", TagTreeMember { value: 1 })],
                    ),
                ),
                ("ai", TagTreeMember { value: 2 }),
            ],
        ),
    )
}

test "one member is still read so the fallback is reachable" {
    assert.equal(
        tag_outcome([[("type", "a")]], [("type", "UNKNOWN")]),
        read_of("type", [("a", TagTreeMember { value: 0 })]),
    )
}

test "a union that cannot be told apart has no tree" {
    let fallback = [("type", "UNKNOWN")];
    assert.equal(tag_outcome([[("name", "x")]], fallback), UntaggedMember { value: 0 });
    assert.equal(
        tag_outcome([[("type", "a")], [("type", "a")]], fallback),
        UntaggedOverlap { first: 0, second: 1 },
    );
    assert.equal(
        tag_outcome([[("type", "a"), ("kind", "k")], [("type", "a")]], fallback),
        UntaggedOverlap { first: 0, second: 1 },
    );
    assert.equal(tag_outcome([[("type", "a")]], []), UntaggedNoTag {})
}
