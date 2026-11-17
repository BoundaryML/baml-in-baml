# bib-compiler

The BAML compiler, written in BAML. See `../PORTING.md`.

```bash
baml agent install                 # once per toolchain update; check/test refuse without it
BAML_TELEMETRY=off baml check
BAML_TELEMETRY=off baml test
baml codequality --functions
```

Toolchain: the `nightly` channel (`baml toolchain update` to advance).
