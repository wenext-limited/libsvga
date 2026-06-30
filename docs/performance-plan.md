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
  --model-mode full \
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

Investigation-only options:

- `--model-mode full`: current eager production behavior.
- `--model-mode no-paths`: skip parsed SVG path command tables.
- `--model-mode no-render`: skip render command/item tables and visual frame
  indices.
- `--model-mode metadata-only`: keep metadata records but skip path commands and
  render/visual tables.
- `--model-mode copy-only`: copy the parser `MovieSpec` into owned model
  arrays, but skip all derived tables.
- `--model-mode parse-only`: stop after inflate/protobuf and do not construct
  `Movie`.
- `--alloc-stats`: count allocator calls and backing bytes. Use this for
  allocation shape, not as the primary timing protocol.

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

After arena-backed `Movie` ownership and public lazy model modes, the same
external comparison measured:

```text
zig/libsvga files=3374 parses=10122 ns_per_parse=1661328.3
objc/SVGAPlayer-iOS files=3374 parses=10122 ns_per_parse=4571168.0
```

This puts native `libsvga` about 2.75x faster than the archived Objective-C
parser on this run.

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

After adding model-mode and allocation instrumentation, the candidate
investigation measured the following Darwin system-zlib runs over the same COS
corpus:

```text
# full, before SVG number fast path, early run
total_ns_per_parse=1608567.5
protobuf_ns_per_parse=259714.3
model_init_ns_per_parse=389603.6
destroy_ns_per_parse=79784.9

# direct A/B under later machine load, std.fmt.parseFloat
total_ns_per_parse=1690398.9
protobuf_ns_per_parse=270014.6
model_init_ns_per_parse=420279.4
destroy_ns_per_parse=86290.4

# direct A/B under later machine load, SVG number fast path
total_ns_per_parse=1653597.0-1669661.8
protobuf_ns_per_parse=266306.8-268448.9
model_init_ns_per_parse=399215.4-406392.6
destroy_ns_per_parse=84762.2-86583.6

# no-render
total_ns_per_parse=1562100.3
model_init_ns_per_parse=340351.2

# metadata-only
total_ns_per_parse=1495101.2
model_init_ns_per_parse=281715.1

# copy-only
total_ns_per_parse=1338551.9
model_init_ns_per_parse=162199.4
```

Allocator-stat passes with `--warmup 0 --iterations 1 --alloc-stats` measured:

```text
# parse-only
allocs_per_parse=7.8
alloc_bytes_per_parse=4345757.3
peak_live_bytes_per_parse=3186745.6
protobuf_ns_per_parse=243183.1

# copy-only
allocs_per_parse=7859.6
alloc_bytes_per_parse=5720942.5
peak_live_bytes_per_parse=4142932.4

# full
total_ns_per_parse=1682700.5
model_init_ns_per_parse=389460.9
destroy_ns_per_parse=98316.6
allocs_per_parse=8070.6
alloc_bytes_per_parse=6795337.8
peak_live_bytes_per_parse=5117865.1
```

Conclusions:

- Arena/string-pool backed `Movie` ownership is the strongest remaining Zig-side
  candidate. Parser-only uses about 8 backing allocations per parse; model
  ownership copying raises that to about 7,860 allocations before derived
  tables, so the current per-frame/per-shape ownership boundary is expensive.
- Lazy render/path derived tables are worthwhile as an API option, not as an
  unconditional replacement. `metadata-only` saves about 108 us/parse in
  `model_init`; `copy-only` shows a 162 us/parse ownership floor.
- SVG number parsing is a modest average win and a large outlier win. Direct
  A/B runs under the same later machine load showed about 14-21 us/parse lower
  `model_init`, and several vector-heavy files dropped by 1-2.4 ms in model
  initialization.
- Protobuf pre-counting is rejected for now. A build-flag experiment that
  pre-counted repeated fields before reserving `ArrayList` capacity increased
  parse-only protobuf time from about 243 us/parse to about 303 us/parse.

After integrating arena-backed ownership and exposing lazy model modes, the same
internal phase benchmark measured:

```text
# full
total_ns_per_parse=1482222.2
inflate_ns_per_parse=858128.8
protobuf_ns_per_parse=255804.9
model_init_ns_per_parse=325751.2
destroy_ns_per_parse=20820.7

# no-render
total_ns_per_parse=1505531.4
model_init_ns_per_parse=289731.7
destroy_ns_per_parse=20144.4

# metadata-only
total_ns_per_parse=1425766.2
model_init_ns_per_parse=252487.5
destroy_ns_per_parse=22435.7
```

The full-mode allocation-stat pass measured:

```text
total_ns_per_parse=1504319.5
model_init_ns_per_parse=335644.6
destroy_ns_per_parse=21750.1
allocs_per_parse=215.5
alloc_bytes_per_parse=7653016.5
peak_live_bytes_per_parse=5943092.0
```

Compared with the pre-arena full-mode allocator pass, allocation calls dropped
from about 8,070 to about 216 per parse and `destroy` dropped from about
98.3 us/parse to about 21.8 us/parse. The normal phase runs show the same
teardown improvement, from about 85 us/parse to about 21 us/parse. The
arena-backed model intentionally
trades fewer allocator calls and much cheaper teardown for larger arena chunk
retention during a parsed movie's lifetime.

The default-run TSV was written to:

```text
/private/tmp/svga-phase-bench.tsv
```

Example outlier commands:

```sh
# Largest average total parse time by file.
awk -F '\t' 'NR>1 {n[$2]++; total[$2]+=$7; inflate[$2]+=$8; proto[$2]+=$9; model[$2]+=$11; bytes[$2]=$5; inflated[$2]=$6} END {for (p in total) printf "%.0f\t%.0f\t%.0f\t%.0f\t%s\t%s\t%s\n", total[p]/n[p], inflate[p]/n[p], proto[p]/n[p], model[p]/n[p], bytes[p], inflated[p], p}' /private/tmp/svga-phase-bench.tsv | sort -nr | head

# Largest average model initialization time by file.
awk -F '\t' 'NR>1 {n[$2]++; model[$2]+=$11; total[$2]+=$7; bytes[$2]=$5; inflated[$2]=$6} END {for (p in model) printf "%.0f\t%.0f\t%s\t%s\t%s\n", model[p]/n[p], total[p]/n[p], bytes[p], inflated[p], p}' /private/tmp/svga-phase-bench.tsv | sort -nr | head
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

2. **Reduce ownership-boundary copies** — implemented
   - Current flow is `inflate -> parser arena MovieSpec -> owned Movie`.
   - `Movie` now owns an arena for metadata strings, sprite frame arrays, shape
     arrays, path strings, and derived tables.
   - Keep large image/audio asset bytes separate if needed.
   - Evidence: `parse-only` averages about 8 backing allocations per parse,
     while old `copy-only` averaged about 7,860. Integrated full-mode parsing
     now averages about 216 allocation calls per parse.

3. **Lazy or configurable render table construction** — implemented for parse APIs
   - `Movie.initWithLimits` eagerly builds metadata tables, parsed SVG path
     command tables, render command tables, render item tables, and visual frame
     indices.
   - Existing parse APIs preserve the full eager default.
   - New Zig/C parse modes expose `full`, `no_render`, and `metadata_only`.
   - Evidence: with arena ownership, `metadata-only` reduces `model_init` from
     about 326 us/parse to about 252 us/parse.

4. **Path parsing costs**
   - `buildMetadataTables` parses every clip path and vector shape path during
     `Movie` initialization.
   - Use phase benchmark plus TSV rows to identify whether vector-heavy files
     dominate `model_init`.
   - Consider lazy path parsing or a path-command cache keyed by source slice
     for vector-heavy files.
   - Status: fast decimal parsing is implemented and helps outliers; average
     corpus win is modest because most files are not path-heavy.

5. **Render table algorithm**
   - `buildRenderData` currently counts commands/items, allocates exact tables,
     then traverses again to fill them.
   - If phase timing shows this dominates non-vector files, test a single-pass
     `ArrayList` approach or combined count/fill strategy.

6. **Array allocation strategy during protobuf parse**
   - Parser uses `ArrayList` append for assets, sprites, frames, audios, and
     shapes.
   - Status: pre-count pass is rejected for now. It reduced no meaningful
     allocation pressure and increased parse-only protobuf time by about
     60 us/parse.

7. **Allocator measurement**
   - `svga_phase_bench --alloc-stats` now tracks allocation count/bytes for
     candidate comparison.
   - A future per-phase allocator snapshot would make arena/string-pool work
     easier to validate.

8. **Benchmark reproducibility**
   - For `svga_phase_bench`, keep fixture path order sorted.
   - Run warmup iterations.
   - Report machine load/throttling when numbers vary.
   - Use TSV output for file-level outlier analysis.
   - The external C/Objective-C harness currently uses filesystem traversal
     order and no separate warmup phase; keep those numbers separate from
     `svga_phase_bench` timings unless the harness protocol is changed.
