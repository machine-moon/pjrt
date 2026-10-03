# pjrt.cmake - PJRT C ABI headers as a CMake interface target.
#
#   include(pjrt.cmake)
#   target_link_libraries(myapp PRIVATE pjrt::pjrt)
#
# Headers live under xla/, so `#include "xla/pjrt/c/pjrt_c_api.h"` works as-is.
if(NOT TARGET pjrt)
    add_library(pjrt INTERFACE)
    add_library(pjrt::pjrt ALIAS pjrt)
    target_include_directories(pjrt INTERFACE "${CMAKE_CURRENT_LIST_DIR}")
    target_compile_features(pjrt INTERFACE cxx_std_17)
endif()
