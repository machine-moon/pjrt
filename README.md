# pjrt

PJRT runtime libraries, each shipped with the exact C ABI headers it was built
against. Headers are vendored in-tree; the libraries are fetched on demand.

<!-- headers:begin -->
PJRT C ABI headers from [OpenXLA](https://github.com/openxla/xla) at [`dcbff804`](https://github.com/openxla/xla/commit/dcbff8047e212c2a63a71bd9fd9b0bf1413cddc2) — API version `0.116`.
<!-- headers:end -->

The repository holds `xla/` (headers), `devices/` (fetched runtimes), `fetch.sh`,
`pjrt.cmake`, `VERSION` (machine-readable provenance, kept in sync with the
headers line by `scripts/sync_headers.sh`), and the maintainer `scripts/`.

## Fetch

```sh
./fetch.sh all        # everything in the release
./fetch.sh cpu        # CPU plugin for this arch
./fetch.sh cuda12     # cuda/12 for this arch (also fetches cpu)
./fetch.sh rocm7      # rocm/7
./fetch.sh mps        # Apple GPU (arm64)
```

Libraries land under `devices/`:

```
devices/cpu/{x86_64,aarch64}/
devices/cuda/{11/x86_64, 12/{x86_64,aarch64}, 13/{x86_64,aarch64}}/
devices/rocm/{6,7,10}/x86_64/
devices/xpu/x86_64/   devices/tpu/x86_64/   devices/mps/arm64/
```

GitHub publishes a SHA256 digest for every release asset.

## Use

```cmake
include(pjrt.cmake)
target_link_libraries(app PRIVATE pjrt::pjrt)
```

```cpp
#include "xla/pjrt/c/pjrt_c_api.h"
#include "xla/pjrt/pjrt_loader.h"   // pjrt::load, PJRT_HAS, PJRT_EXT, find_extension
```

`pjrt::load` opens a plugin (`dlopen` → `GetPjrtApi`). Gate core and extension
fields on `struct_size` with `PJRT_HAS` / `PJRT_EXT`, and look up extensions with
`find_extension` (which also handles the pre-0.45 layout). Compile as C++17.

## Maintain

```sh
scripts/sync_headers.sh   # refresh xla/ and the headers line from openxla/xla
scripts/collect.sh        # extract runtimes from public wheels
scripts/release.sh        # publish one pjrt-YYYY-MM-DD release
```

CI syncs the headers, opening a PR on drift, and publishes a daily release.
