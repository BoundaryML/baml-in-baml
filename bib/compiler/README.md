# bib-compiler

The BAML compiler, written in BAML. See `../PORTING.md`.

```bash
baml agent install                 # once per toolchain update; check/test refuse without it
BAML_TELEMETRY=off baml check
BAML_TELEMETRY=off baml test --test-timeout 15m   # the type_spec sweep runs ~8 min
baml codequality --functions
```

Toolchain: the `nightly` channel (`baml toolchain update` to advance).
