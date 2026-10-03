# pjrt

## Headers

<!-- headers:begin -->
PJRT C ABI headers from [OpenXLA](https://github.com/openxla/xla) at [`7caecda6`](https://github.com/openxla/xla/commit/7caecda6be7bbbc49a3e907a2a9704e9a6e820b4) — API version `0.116`.
<!-- headers:end -->

PJRT runtime libraries together with the exact PJRT C ABI headers, taken from
public wheels. Headers are always present; the libraries are fetched on demand.

- `xla/` — the PJRT C ABI headers (filtered from `openxla/xla`).
- `xla/pjrt/pjrt_loader.h` — `dlopen` + ABI gating helpers.
- `fetch.sh` — download runtimes from the latest release into the tree below.
- `pjrt.cmake` — CMake interface target `pjrt::pjrt`.

## Fetch

```sh
./fetch.sh all        # everything in the release
./fetch.sh cpu        # CPU plugin for this arch
./fetch.sh cuda12     # cuda/12 for this arch (also fetches cpu)
./fetch.sh rocm7      # rocm/7
./fetch.sh mps        # Apple GPU (arm64)
```

Runtimes land next to `xla/`:

```
cpu/{x86_64,aarch64}/
cuda/{11/x86_64, 12/{x86_64,aarch64}, 13/{x86_64,aarch64}}/
rocm/{6,7,10}/x86_64/
xpu/x86_64/   tpu/x86_64/   mps/arm64/
```

GitHub shows a SHA256 digest next to every asset in each release, if you want to
check a download by hand.

## Use

```cmake
include(pjrt.cmake)
target_link_libraries(app PRIVATE pjrt::pjrt)
```

```cpp
#include "xla/pjrt/c/pjrt_c_api.h"        // headers; also their "xla/..." includes
#include "xla/pjrt/pjrt_loader.h"         // pjrt::load, PJRT_HAS, find_extension
```

`pjrt::load(path)` does `dlopen` + `dlsym("GetPjrtApi")`; `PJRT_HAS` /
`find_extension` / `PJRT_EXT` gate core fields, extension lookup (incl. the
pre-0.45 layout) and extension fields on `struct_size`. Compile as C++17.

## Maintain

```sh
scripts/sync_headers.sh    # refresh xla/ + the Headers block above from openxla/xla
scripts/collect.sh         # build/{family}/{variant}/{arch}/ from public wheels
scripts/release.sh         # publish one pjrt-YYYY-MM-DD release
```

CI (`.github/workflows/`) runs the header sync (opens a PR on drift) and the
daily release.
