/*
 * Copyright (c) 2026 The pjrt Project Authors. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <cstddef>
#include <dlfcn.h>

#include "c/pjrt_c_api.h"

namespace pjrt
{
    /**
     * Loads a PJRT plugin and returns its API table.
     * @param path Path to the plugin shared library.
     * @return The plugin's PJRT_Api, or nullptr on failure.
     * @note The dlopen handle is kept for the process lifetime: dlclose faults
     *       inside some backends' destructors.
     */
    [[nodiscard]] inline const PJRT_Api* load(const char* path) noexcept
    {
        void* handle = ::dlopen(path, RTLD_LAZY | RTLD_LOCAL);
        void* symbol = handle != nullptr ? ::dlsym(handle, "GetPjrtApi") : nullptr;
        return symbol != nullptr ? reinterpret_cast<const PJRT_Api* (*)()>(symbol)() : nullptr;
    }

    /**
     * Type of a pre-0.45 extension base.
     * @param e Extension base pointer.
     * @return The extension type.
     * @note Before PJRT API 0.45 the base was a { type; next; } pair with no
     *       struct_size, so the type sits at offset zero.
     */
    [[nodiscard]] inline PJRT_Extension_Type legacy_type(const PJRT_Extension_Base* e) noexcept
    {
        return *reinterpret_cast<const PJRT_Extension_Type*>(e);
    }

    /**
     * Next pointer of a pre-0.45 extension base.
     * @param e Extension base pointer.
     * @return The next extension base, or nullptr.
     */
    [[nodiscard]] inline const PJRT_Extension_Base* legacy_next(const PJRT_Extension_Base* e) noexcept
    {
        return *reinterpret_cast<const PJRT_Extension_Base* const*>(
            reinterpret_cast<const char*>(e) + sizeof(void*));
    }

    /**
     * Finds the first extension of a given type.
     * @param api  The plugin's API table.
     * @param type Extension type to look for.
     * @return The extension base, or nullptr when the plugin does not have it.
     * @note Handles the pre-0.45 layout, so cuda/11 (PJRT API 0.42) works too.
     */
    [[nodiscard]] inline const PJRT_Extension_Base* find_extension(
        const PJRT_Api* api, PJRT_Extension_Type type) noexcept
    {
        if (api == nullptr)
        {
            return nullptr;
        }
        const bool sized = api->pjrt_api_version.minor_version >= 45;
        for (const PJRT_Extension_Base* e = api->extension_start; e != nullptr;
             e = sized ? e->next : legacy_next(e))
        {
            if ((sized ? e->type : legacy_type(e)) == type)
            {
                return e;
            }
        }
        return nullptr;
    }
} // namespace pjrt

#define PJRT_HAS(api, field) ((api) != nullptr && (api)->struct_size >= PJRT_STRUCT_SIZE(PJRT_Api, field))

#define PJRT_EXT(ext, type, field) ((ext) != nullptr && (ext)->struct_size >= PJRT_STRUCT_SIZE(type, field))

