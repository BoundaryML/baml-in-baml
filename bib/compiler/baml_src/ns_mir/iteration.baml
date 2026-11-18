// port: baml_compiler2_mir/src/iteration.rs @ d9be6853b
//
// Recognition shared by escape analysis and native array iteration.

// port: baml_compiler2_mir/src/iteration.rs::unary_iteration_call @ d9be6853b
// A unary call to the installed standard library's `Iterable.iter` or
// `Iterator.next`, as `(method, receiver local, destination local)`.
//
// The interface head is a declaration identity (package root and path), not
// its display spelling: an unrelated interface with an `iter` or `next`
// method keeps ordinary virtual dispatch and its unknown effects. Callers
// must additionally prove that the receiver is an array or its builtin
// iterator before replacing the call with array operations.
function unary_iteration_call(
    db: root.hir.Db,
    terminator: Terminator,
) -> (string, int, int)? throws never {
    let call = match (terminator) {
        let t: TerminatorVirtualCall => t,
        _ => {
            return null;
        },
    };
    if (call.has_trace || call.ntypeargs != 0 || call.self_arg != 0) {
        return null;
    }
    let destination = match (call.destination) {
        let l: PlaceLocal => l.value,
        _ => {
            return null;
        },
    };
    let baml = root.hir.lang_roots(db).get(root.base.LangPackage.Baml)
        ?? return null;
    let name = call.iface.name;
    let iteration_pair = (name.name == "Iterable" && call.method == "iter")
        || (name.name == "Iterator" && call.method == "next");
    let layout_names_a_slot = call.argument_layout?.value?.some((slot) -> {
        slot != null
    })
        ?? false;
    if (
        name.pkg != baml
            || name.namespace.length() != 1
            || name.namespace[0] != "iter"
            || !iteration_pair
            || call.iface.generics.length() != 0
            || layout_names_a_slot
    ) {
        return null;
    }
    if (call.args.length() != 1) {
        return null;
    }
    let receiver = match (call.args[0]) {
        OperandCopy { value: PlaceLocal { value: let local } } => local,
        OperandMove { value: PlaceLocal { value: let local } } => local,
        _ => {
            return null;
        },
    };
    (call.method, receiver, destination)
}
