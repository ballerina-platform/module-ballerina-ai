/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.creators.ErrorCreator;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.FunctionType;
import io.ballerina.runtime.api.types.MapType;
import io.ballerina.runtime.api.types.Parameter;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.types.ReferenceType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BFunctionPointer;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;

import static io.ballerina.stdlib.ai.ModuleUtils.isModuleDefinedError;

public class Utils {
    private static final String CONTEXT_TYPE_NAME = "Context";
    private static final String AI_MODULE_NAME = "ai";

    @SuppressWarnings("unused")
    public static BMap<BString, Object> getParameterTypes(BFunctionPointer functionPointer) {
        FunctionType functionType = (FunctionType) functionPointer.getType();
        Parameter[] parameters = functionType.getParameters();
        BMap<BString, Object> typedefs = ValueCreator.createMapValue();
        Arrays.stream(parameters).forEach(param -> typedefs.put(StringUtils.fromString(param.name),
                ValueCreator.createTypedescValue(param.type)));
        return typedefs;
    }

    @SuppressWarnings("unused")
    public static boolean isContextType(BTypedesc targetTypedesc, BTypedesc contextTypedesc) {
        return TypeUtils.isSameType(contextTypedesc.getDescribingType(), targetTypedesc.getDescribingType());
    }

    @SuppressWarnings("unused")
    public static boolean isMapType(BTypedesc typedesc) {
        if (typedesc.getDescribingType() instanceof ReferenceType referenceType) {
            return isMapType(referenceType.getReferredType());
        }
        return isMapType(typedesc.getDescribingType());
    }

    private static boolean isMapType(Type type) {
        return type instanceof MapType || type instanceof RecordType;
    }

    @SuppressWarnings("unused")
    public static BString getFunctionName(BFunctionPointer functionPointer) {
        return StringUtils.fromString(functionPointer.getType().getName());
    }

    @SuppressWarnings("unused")
    public static BMap<BString, Object> getArgsWithDefaultsExcludingContext(Environment env,
                                                                            BFunctionPointer functionPointer,
                                                                            BMap<BString, Object> args) {
        FunctionType functionType = (FunctionType) functionPointer.getType();
        Parameter[] parameters = functionType.getParameters();
        LinkedHashMap<String, Object> argsWithDefaultValues = new LinkedHashMap<>();
        Optional<BString> contextParamName = Optional.empty();

        for (Parameter parameter : parameters) {
            // Tool parameters must be either anydata or ai:Context.
            if (isContextType(parameter.type)) {
                contextParamName = Optional.of(StringUtils.fromString(parameter.name));
            } else if (!parameter.type.isAnydata()) {
                continue;
            }

            BString parameterName = StringUtils.fromString(parameter.name);
            Object value = args.containsKey(parameterName) ? args.get(parameterName) :
                    getDefaultParameterValue(env, functionPointer, parameter, argsWithDefaultValues.values().toArray());
            argsWithDefaultValues.put(parameter.name, value);
        }
        MapType anydataMapType = TypeCreator.createMapType(PredefinedTypes.TYPE_ANYDATA);
        BMap<BString, Object> parametersWithDefaultValue = ValueCreator.createMapValue(anydataMapType);
        argsWithDefaultValues
                .forEach((key, value) -> parametersWithDefaultValue.put(StringUtils.fromString(key), value));
        // Skip setting default values for ai:Context parameter.
        contextParamName.ifPresent(parametersWithDefaultValue::remove);
        return parametersWithDefaultValue;
    }

    private static boolean isContextType(Type paramType) {
        return paramType.getName().equals(CONTEXT_TYPE_NAME)
                && paramType.getPackage().getName().equals(AI_MODULE_NAME);
    }

    private static Object getDefaultParameterValue(Environment env, BFunctionPointer functionPointer,
                                                   Parameter parameter,
                                                   Object[] previousPositionalArgs) {
        if (!parameter.isDefault) {
            return null;
        }
        return env.getRuntime().callFunction(functionPointer.getType().getPackage(),
                parameter.defaultFunctionName, null, previousPositionalArgs
        );
    }

    public static void notifySuccess(CompletableFuture<Object> future, Object result) {
        if (result instanceof BError error) {
            if (!isModuleDefinedError(error)) {
                error.printStackTrace();
            }
        }
        future.complete(result);
    }

    public static Object getResult(CompletableFuture<Object> balFuture) {
        try {
            return balFuture.get();
        } catch (BError error) {
            throw error;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw ErrorCreator.createError(e);
        } catch (Throwable throwable) {
            throw ErrorCreator.createError(throwable);
        }
    }
}

