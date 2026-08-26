#include "napi_converter.h"

#include "native_error.h"

#include <vector>

namespace {
void SetNamedProperty(napi_env env, napi_value object, const char* name, napi_value value) {
    napi_set_named_property(env, object, name, value);
}

void SetNamedString(napi_env env, napi_value object, const char* name, const std::string& value) {
    SetNamedProperty(env, object, name, CreateString(env, value));
}

void SetNamedInt(napi_env env, napi_value object, const char* name, int32_t value) {
    napi_value napiValue = nullptr;
    napi_create_int32(env, value, &napiValue);
    SetNamedProperty(env, object, name, napiValue);
}

void SetNamedBool(napi_env env, napi_value object, const char* name, bool value) {
    napi_value napiValue = nullptr;
    napi_get_boolean(env, value, &napiValue);
    SetNamedProperty(env, object, name, napiValue);
}

void SetNamedStringArray(
    napi_env env, napi_value object, const char* name, const std::vector<std::string>& values) {
    napi_value array = nullptr;
    napi_create_array_with_length(env, values.size(), &array);
    for (size_t index = 0; index < values.size(); ++index) {
        napi_set_element(env, array, index, CreateString(env, values[index]));
    }
    SetNamedProperty(env, object, name, array);
}

void SetNamedIntArray(
    napi_env env, napi_value object, const char* name, const std::vector<int32_t>& values) {
    napi_value array = nullptr;
    napi_create_array_with_length(env, values.size(), &array);
    for (size_t index = 0; index < values.size(); ++index) {
        napi_value value = nullptr;
        napi_create_int32(env, values[index], &value);
        napi_set_element(env, array, index, value);
    }
    SetNamedProperty(env, object, name, array);
}

void ClearPendingException(napi_env env) {
    bool pending = false;
    if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
        napi_value exception = nullptr;
        napi_get_and_clear_last_exception(env, &exception);
    }
}

napi_value ParseRustJson(napi_env env, const RustBuffer& json) {
    if (json.Empty()) {
        return nullptr;
    }

    napi_value source = nullptr;
    if (napi_create_string_utf8(env, json.Data(), json.Size(), &source) != napi_ok) {
        ClearPendingException(env);
        return nullptr;
    }

    napi_value global = nullptr;
    napi_value jsonObject = nullptr;
    napi_value parse = nullptr;
    if (napi_get_global(env, &global) != napi_ok ||
        napi_get_named_property(env, global, "JSON", &jsonObject) != napi_ok ||
        napi_get_named_property(env, jsonObject, "parse", &parse) != napi_ok) {
        ClearPendingException(env);
        return nullptr;
    }

    napi_value result = nullptr;
    napi_value args[] = {source};
    if (napi_call_function(env, jsonObject, parse, 1, args, &result) != napi_ok) {
        ClearPendingException(env);
        return nullptr;
    }

    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, result, &type) != napi_ok || type != napi_object) {
        return nullptr;
    }
    return result;
}

void SetEmptyFormalCandidateArray(napi_env env, napi_value object) {
    napi_value candidates = nullptr;
    napi_create_array_with_length(env, 0, &candidates);
    SetNamedProperty(env, object, "candidates", candidates);
}

napi_value CreateUserModelStatusError(napi_env env) {
    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetNamedBool(env, object, "loaded", false);
    SetNamedBool(env, object, "enabled", false);
    SetNamedBool(env, object, "sessionLearningAllowed", false);
    SetNamedBool(env, object, "dirty", false);
    SetNamedInt(env, object, "recordCount", 0);
    SetNamedInt(env, object, "formatVersion", 0);
    SetNamedInt(env, object, "dataVersion", 0);
    SetNamedString(env, object, "lastErrorCode", "serialization_error");
    return object;
}
} // namespace

napi_value CreateString(napi_env env, const std::string& value) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
    return result;
}

napi_value CreateString(napi_env env, const RustBuffer& value) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.Data(), value.Size(), &result);
    return result;
}

napi_value CreateErrorResult(napi_env env, int32_t errorCode, const std::string& message) {
    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetNamedBool(env, object, "success", false);
    SetNamedInt(env, object, "errorCode", errorCode);
    SetNamedString(env, object, "errorMessage", message);
    SetNamedString(env, object, "rawInput", "");
    SetNamedString(env, object, "preeditText", "");
    SetNamedString(env, object, "engineVersion", "");

    napi_value candidates = nullptr;
    napi_create_array_with_length(env, 0, &candidates);
    SetNamedProperty(env, object, "candidates", candidates);
    return object;
}

napi_value CreateCompositionErrorResult(napi_env env, int32_t errorCode, const std::string& message) {
    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetNamedBool(env, object, "success", false);
    SetNamedInt(env, object, "errorCode", errorCode);
    SetNamedString(env, object, "errorMessage", message);
    SetNamedString(env, object, "rawInput", "");
    SetNamedString(env, object, "preeditText", "");
    SetNamedStringArray(env, object, "parsedSyllables", {});
    SetNamedStringArray(env, object, "displaySegments", {});
    SetNamedIntArray(env, object, "segmentBoundaries", {});
    SetNamedString(env, object, "currentPinyin", "");
    SetNamedStringArray(env, object, "pinyinCombinations", {});
    SetNamedString(env, object, "pendingCode", "");
    SetNamedString(env, object, "parserState", "empty");
    SetEmptyFormalCandidateArray(env, object);
    SetNamedInt(env, object, "highlightedIndex", -1);
    SetNamedBool(env, object, "hasNextPage", false);
    SetNamedBool(env, object, "hasPreviousPage", false);
    SetNamedInt(env, object, "candidatePage", 0);
    SetNamedString(env, object, "commitText", "");
    napi_value noAction = nullptr;
    napi_get_null(env, &noAction);
    SetNamedProperty(env, object, "action", noAction);
    SetNamedBool(env, object, "compositionFinished", false);
    return object;
}

napi_value ConvertEngineJsonToArkObject(napi_env env, const RustBuffer& json) {
    napi_value result = ParseRustJson(env, json);
    return result != nullptr
        ? result
        : CreateErrorResult(env, IME_SERIALIZATION_ERROR, "Rust returned invalid JSON");
}

napi_value ConvertCompositionJsonToArkObject(napi_env env, const RustBuffer& json) {
    napi_value result = ParseRustJson(env, json);
    return result != nullptr
        ? result
        : CreateCompositionErrorResult(
              env, IME_SERIALIZATION_ERROR, "Rust returned invalid composition JSON");
}

napi_value ConvertUserModelStatusJsonToArkObject(napi_env env, const RustBuffer& json) {
    napi_value result = ParseRustJson(env, json);
    return result != nullptr ? result : CreateUserModelStatusError(env);
}
