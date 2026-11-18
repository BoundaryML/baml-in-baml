// port: baml_type/src/accepts_null.rs @ d9be6853b
//
// Whether `null` is a value of a type, by what the type means rather than how
// it is spelled. A class field may be left out of a class literal, and may be
// missing from JSON, exactly when `null` is a value of its type: `int?` spells
// that with a union, but `unknown` admits `null` too, and so does
// `baml.json.json`, an alias whose union contains `null`.
//
// Rust abstracts over the representation with the `NullForms` trait
// (implemented for `Ty` and the interned `Ty`). Here a representation passes
// its one-level reading as a function; `null_form` is the `Ty` one. The head
// parameter `H` is DeclName, the only head.

// port: baml_type/src/accepts_null.rs::NullForm @ d9be6853b
// One level of a type, as accepts_null reads it: `NullFormAdmits` (`null`
// itself, or `unknown`, which admits every value), `NullFormUnion` (admits
// `null` when a member does), `NullFormAlias` (admits `null` when its
// definition does), `NullFormRefuses` (any other type). Rust's enum is
// generic over the member type; BAML has no generic type alias, so the
// union is spelled out where it is used.
class NullFormAdmits {
}

class NullFormUnion<T> {
    members: T[],
}

class NullFormAlias {
    head: DeclName,
}

class NullFormRefuses {
}

// port: baml_type/src/accepts_null.rs::NullForms for Ty::null_form @ d9be6853b
function null_form(
    ty: Ty,
) -> NullFormAdmits | NullFormUnion<Ty> | NullFormAlias | NullFormRefuses throws never {
    match (ty) {
        TyNull | TyUnknown => NullFormAdmits {},
        let u: TyUnion => NullFormUnion { members: u.members },
        let a: TyTypeAlias => NullFormAlias { head: a.name },
        _ => NullFormRefuses {},
    }
}

// port: baml_type/src/accepts_null.rs::accepts_null @ d9be6853b
// Whether `null` is a value of `ty`: `ty` is `null` or `unknown`, a union
// with such a member, or a type alias whose definition is one of these.
// `alias_def` gives an alias's definition; an alias it does not know admits
// nothing.
function accepts_null<T>(
    ty: T,
    form: (T) -> NullFormAdmits | NullFormUnion<T> | NullFormAlias | NullFormRefuses,
    alias_def: (DeclName) -> Ty?,
) -> bool {
    accepts_null_within(ty, form, alias_def, [])
}

// port: baml_type/src/accepts_null.rs::accepts_null_within @ d9be6853b
// accepts_null inside the aliases in `within`: an alias met again adds
// nothing. An alias's definition is a plain Ty, read with `null_form`.
function accepts_null_within<T>(
    ty: T,
    form: (T) -> NullFormAdmits | NullFormUnion<T> | NullFormAlias | NullFormRefuses,
    alias_def: (DeclName) -> Ty?,
    within: DeclName[],
) -> bool {
    match (form(ty)) {
        NullFormAdmits => true,
        NullFormRefuses => false,
        let u: NullFormUnion<T> => {
            u.members.some((member) -> {
                accepts_null_within(member, form, alias_def, within)
            })
        },
        let a: NullFormAlias => {
            if (within.includes(a.head)) {
                return false;
            }
            let definition = alias_def(a.head)
                ?? return false;
            within.push(a.head);
            let accepts = accepts_null_within(definition, null_form, alias_def, within);
            within.pop();
            accepts
        },
    }
}
