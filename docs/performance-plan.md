# libsvga Performance Plan

This file tracks the benchmark protocol and optimization backlog for libsvga
parse performance. Keep it updated when measurements change.

## Benchmark Protocol

Primary corpus:

```text
/private/tmp/svga-cos-benchmark-hardlinks-1782807332
```

This is the 3,374-file production zlib-only fixture set that both libsvga and
the archived Objective-C SVGAPlayer-iOS path can parse.

External comparison:

```sh
cd /Users/wendell/Developer/WeNext/svga/benchmarks
make run FIXTURE_DIR=/private/tmp/svga-cos-benchmark-hardlinks-1782807332 ITERATIONS=3
```

Internal phase benchmark:

```sh
cd /Users/wendell/Developer/WeNext/svga/libsvga
zig build -Doptimize=ReleaseFast phase-bench -- \
  --warmup 1 \
  --iterations 3 \
  --tsv /private/tmp/svga-phase-bench.tsv \
  /private/tmp/svga-cos-benchmark-hardlinks-1782807332
```

The phase benchmark excludes file I/O by loading fixtures before timing and
reports:

- `inflate`: zlib/deflate decode for zlib SVGA payloads.
- `protobuf`: protobuf-like movie.binary parse into the parser arena.
- `zip_metadata`: ZIP package parse for ZIP SVGA payloads.
- `model_init`: copy into owned `Movie` plus metadata/path/render table build.
- `destroy`: `Movie.deinit`.
- `unaccounted`: timer overhead plus loop/control flow not covered above.

## Current Baseline

On June 30, 2026, before adding the phase benchmark, the C ABI comparison over
the COS zlib corpus with `ITERATIONS=3` measured:

```text
zig/libsvga files=3374 parses=10122 ns_per_parse=3903483.8
objc/SVGAPlayer-iOS files=3374 parses=10122 ns_per_parse=5148189.0
```

After the Darwin default switched to system zlib and `model_init` avoided empty
path parsing plus duplicate render command work, the same external comparison
measured:

```text
zig/libsvga files=3374 parses=10122 ns_per_parse=1812952.9
objc/SVGAPlayer-iOS files=3374 parses=10122 ns_per_parse=4814519.5
```

This puts native `libsvga` about 2.65x faster than the archived Objective-C
parser on the COS zlib corpus.

After adding `svga_phase_bench`, the default self-contained Zig std-flate build
over the same corpus measured:

```text
zig/libsvga-phase files=3374 iterations=3 warmup=1 parses=10122
total_ns_per_parse=4666009.9
inflate_ns_per_parse=3559448.7     pct_total=76.3
protobuf_ns_per_parse=330224.5     pct_total=7.1
model_init_ns_per_parse=617860.7   pct_total=13.2
destroy_ns_per_parse=113934.1      pct_total=2.4
```

The existing `-Dsystem-zlib=true` backend over the same corpus measured:

```text
zig/libsvga-phase files=3374 iterations=3 warmup=1 parses=10122
total_ns_per_parse=1685351.1
inflate_ns_per_parse=853746.5      pct_total=50.7
protobuf_ns_per_parse=257994.1     pct_total=15.3
model_init_ns_per_parse=454118.8   pct_total=26.9
destroy_ns_per_parse=94911.7       pct_total=5.6
```

Conclusion: default parse time is dominated by Zig std-flate inflation on the
production zlib corpus. After a faster inflater, the next target is
`model_init`, especially metadata/path/render table construction.

After the first optimization pass, explicit portable std-flate and default
Darwin system-zlib measured:

```text
# zig build -Doptimize=ReleaseFast -Dsystem-zlib=false phase-bench -- ...
total_ns_per_parse=3771200.4
inflate_ns_per_parse=2894138.8     pct_total=76.7
protobuf_ns_per_parse=298494.2     pct_total=7.9
model_init_ns_per_parse=443602.0   pct_total=11.8

# zig build -Doptimize=ReleaseFast phase-bench -- ...
total_ns_per_parse=1713289.4
inflate_ns_per_parse=891213.5      pct_total=52.0
protobuf_ns_per_parse=273778.3     pct_total=16.0
model_init_ns_per_parse=421605.0   pct_total=24.6
```

The model-init micro-optimization reduced `model_init` from about
617,861 ns/parse to about 443,602 ns/parse on the portable backend, while the
Darwin default backend change accounts for the largest total parse win.

The default-run TSV was written to:

```text
/private/tmp/svga-phase-bench.tsv
```

Example outlier commands:

```sh
# Largest average total parse time by file.
awk -F '\t' 'NR>1 {n[$2]++; total[$2]+=$6; inflate[$2]+=$7; proto[$2]+=$8; model[$2]+=$10; bytes[$2]=$4; inflated[$2]=$5} END {for (p in total) printf "%.0f\t%.0f\t%.0f\t%.0f\t%s\t%s\t%s\n", total[p]/n[p], inflate[p]/n[p], proto[p]/n[p], model[p]/n[p], bytes[p], inflated[p], p}' /private/tmp/svga-phase-bench.tsv | sort -nr | head

# Largest average model initialization time by file.
awk -F '\t' 'NR>1 {n[$2]++; model[$2]+=$10; total[$2]+=$6; bytes[$2]=$4; inflated[$2]=$5} END {for (p in model) printf "%.0f\t%.0f\t%s\t%s\t%s\n", model[p]/n[p], total[p]/n[p], bytes[p], inflated[p], p}' /private/tmp/svga-phase-bench.tsv | sort -nr | head
```

Current top model-init outliers are mostly under `background/sync` and
`background/goods/frame`, so use those files first when optimizing
`model_init`.

## Optimization Backlog

1. **Inflater backend comparison**
   - Compare default Zig std-flate with `-Dsystem-zlib=true`.
   - If system zlib wins consistently on Apple, consider an Apple release
     flavor or runtime/backend option while keeping std-flate for portable
     artifacts and WASM.
   - Test `libdeflate` separately before adding a dependency.

2. **Reduce ownership-boundary copies**
   - Current flow is `inflate -> parser arena MovieSpec -> owned Movie`.
   - Investigate letting `Movie` own an arena/string pool for metadata strings,
     sprite frame arrays, and shape/path strings.
   - Keep large image/audio asset bytes separate if needed.

3. **Lazy or configurable render table construction**
   - `Movie.initWithLimits` eagerly builds metadata tables, parsed SVG path
     command tables, render command tables, render item tables, and visual frame
     indices.
   - Consider parse options for metadata-only, bitmap-table-only, and full
     renderer-ready modes.
   - Preserve the current eager default if Swift rendering depends on it.

4. **Path parsing costs**
   - `buildMetadataTables` parses every clip path and vector shape path during
     `Movie` initialization.
   - Use phase benchmark plus TSV rows to identify whether vector-heavy files
     dominate `model_init`.
   - Consider lazy path parsing or a path-command cache keyed by source slice.

5. **Render table algorithm**
   - `buildRenderData` currently counts commands/items, allocates exact tables,
     then traverses again to fill them.
   - If phase timing shows this dominates non-vector files, test a single-pass
     `ArrayList` approach or combined count/fill strategy.

6. **Array allocation strategy during protobuf parse**
   - Parser uses `ArrayList` append for assets, sprites, frames, audios, and
     shapes.
   - A cheap pre-count pass over length-delimited repeated fields may reduce
     growth allocations for large files.

7. **Allocator measurement**
   - Add a counting allocator or Instruments allocation profile around
     `svga_phase_bench`.
   - Track allocation count/bytes by phase before changing data ownership.

8. **Benchmark reproducibility**
   - Keep fixture path order sorted.
   - Run warmup iterations.
   - Report machine load/throttling when numbers vary.
   - Use TSV output for file-level outlier analysis.
