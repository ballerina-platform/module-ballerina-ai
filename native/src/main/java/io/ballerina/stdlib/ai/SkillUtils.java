/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.ai;

import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BString;

import java.io.IOException;
import java.nio.file.InvalidPathException;
import java.nio.file.Path;

import static io.ballerina.stdlib.ai.ModuleUtils.createError;

/**
 * Native helpers used to load Agent Skills.
 */
public final class SkillUtils {

    private SkillUtils() {
    }

    /**
     * Resolves a path to its real path, following symbolic links.
     * <p>
     * {@code file:normalizePath(path, file:SYMLINK)} from {@code ballerina/file} is not a substitute: it uses
     * {@link java.nio.file.Files#readSymbolicLink}, which only reads the target of the last path element (one link,
     * possibly relative), does not resolve symbolic links in parent directories, and fails if the path is not a link.
     * A skill resource must be checked against the location it really points to, so {@link Path#toRealPath} is used.
     *
     * @param path the path to resolve
     * @return the real path, or an error if the path cannot be resolved
     */
    public static Object getRealPath(BString path) {
        try {
            return StringUtils.fromString(Path.of(path.getValue()).toRealPath().toString());
        } catch (IOException | InvalidPathException | SecurityException e) {
            return createError("Failed to resolve path '" + path.getValue() + "': " + e.getMessage());
        }
    }
}
