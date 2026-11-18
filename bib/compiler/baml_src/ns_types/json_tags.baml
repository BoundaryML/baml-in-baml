// port: baml_type/src/json_tags.rs @ d9be6853b
//
// How a union with a `@json.fallback` member tells its members apart. A
// member's literal fields are its tags. The tree reads one key at a time:
// first the keys the fallback class names, which every member has, then
// whatever key still tells the remaining members apart. A value no member
// has is the fallback's. A member reached is the one, so a literal the tree
// never read, or any other field, fails as that member rather than falling
// through to the fallback.
//
// Generic over the literal type `L` as in Rust (the type checker uses
// `root.base.Literal`). A member's literals are `(key, value)` tuples.
// BAML has no generic type alias, so Rust's `TagTree<L>` is spelled
// `TagTreeMember | TagTreeRead<L>` where it is used. Rust's
// `Result<_, Untagged>` throws `Untagged`; `throws` spells out its members
// because the toolchain reports the alias there as extraneous (E0097).

// port: baml_type/src/json_tags.rs::TagTree::Member @ d9be6853b
// This member: an index into the members the tree was built from.
class TagTreeMember {
    value: int,
}

// port: baml_type/src/json_tags.rs::TagTree::Read @ d9be6853b
// Read `key`: each value leads on, and any other value of the same JSON kind
// is the fallback.
class TagTreeRead<L> {
    key: string,
    arms: (L, TagTreeMember | TagTreeRead<L>)[],
}

// port: baml_type/src/json_tags.rs::Untagged @ d9be6853b
// Why a union has no tag tree.
type Untagged = UntaggedNoTag | UntaggedMember | UntaggedOverlap;

// The fallback class has no literal field to name the tag.
class UntaggedNoTag {
}

// This member lacks the tag the fallback class names.
class UntaggedMember {
    value: int,
}

// No key tells these two members apart. Rust's two unnamed fields are named
// `first` and `second`.
class UntaggedOverlap {
    first: int,
    second: int,
}

// port: baml_type/src/json_tags.rs::tag_tree @ d9be6853b
// The tree for `members`, each its literal fields as JSON keys and values,
// given the literal fields of the union's fallback class.
function tag_tree<L>(
    members: (string, L)[][],
    fallback: (string, L)[],
) -> TagTreeMember | TagTreeRead<L> throws UntaggedNoTag | UntaggedMember | UntaggedOverlap {
    let first = fallback.at(0) ?? throw UntaggedNoTag {};
    let tag = first.0;
    let missing = members.find_index((member) -> {
        value_of(member, tag) == null
    });
    if (missing != null) {
        throw UntaggedMember { value: missing }
    }
    let preferred = fallback.map((literal) -> {
        literal.0
    });
    let everyone = baml.Array.generate(members.length(), (index) -> {
        index
    });
    read(members, everyone, tag, preferred)
}

// port: baml_type/src/json_tags.rs::read @ d9be6853b
// Split `candidates` by `key`.
function read<L>(
    members: (string, L)[][],
    candidates: int[],
    key: string,
    preferred: string[],
) -> TagTreeRead<L> throws UntaggedNoTag | UntaggedMember | UntaggedOverlap {
    let groups: (L, int[])[] = [];
    for (let candidate in candidates) {
        let value = value_of(members[candidate], key) ?? throw UntaggedMember { value: candidate };
        let group = groups.find((g) -> {
            g.0 == value
        });
        if (group != null) {
            group.1.push(candidate);
        } else {
            groups.push((value, [candidate]));
        }
    }
    TagTreeRead {
        key: key,
        arms: groups.map((g) -> {
            (g.0, split(members, g.1, preferred))
        }),
    }
}

// port: baml_type/src/json_tags.rs::split @ d9be6853b
// The tree under one tag value: its only member, or the next key that tells
// the members holding that value apart.
function split<L>(
    members: (string, L)[][],
    candidates: int[],
    preferred: string[],
) -> TagTreeMember | TagTreeRead<L> throws UntaggedNoTag | UntaggedMember | UntaggedOverlap {
    let first = candidates.at(0) ?? baml.sys.panic("a tag value has a member");
    let other = candidates.at(1)
        ?? return TagTreeMember { value: first };
    let declared = members[first].map((literal) -> {
        literal.0
    });
    let key = preferred.concat(declared).find((key) -> {
        let values = candidates.map((candidate) -> {
            value_of(members[candidate], key)
        });
        let value = values[0];
        if (value == null) {
            return false;
        }
        let rest = values.slice(1, values.length());
        rest.every((v) -> {
            v != null
        })
            && rest.some((v) -> {
                v != value
            })
    });
    if (key == null) {
        throw UntaggedOverlap { first: first, second: other }
    }
    read(members, candidates, key, preferred)
}

// port: baml_type/src/json_tags.rs::value_of @ d9be6853b
function value_of<L>(member: (string, L)[], key: string) -> L? throws never {
    member.find((literal) -> {
        literal.0 == key
    })?.1
}
