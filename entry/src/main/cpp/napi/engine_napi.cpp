#include "engine_napi.h"

#include "napi_converter.h"
#include "native_error.h"
#include "rust_engine_bridge.h"

#include <cstdint>
#include <new>
#include <string>
#include <utility>
#include <vector>

namespace {
constexpr int32_t DEFAULT_CANDIDATE_PAGE_SIZE = 50;

struct AsyncEngineCreateContext {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string config;
    EngineBridgeCreateResult result = {IME_ENGINE_INTERNAL_ERROR, 0};
};

struct AsyncProcessKeyContext {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    uint32_t handle = 0;
    std::string key;
    RustCallResult result = {IME_ENGINE_INTERNAL_ERROR, RustBuffer()};
};

#ifndef IME_NATIVE_ABI
#define IME_NATIVE_ABI "unknown"
#endif
#ifndef IME_RUST_ARCHIVE_SHA256
#define IME_RUST_ARCHIVE_SHA256 "unknown"
#endif
#ifndef IME_NATIVE_BUILD_FINGERPRINT
#define IME_NATIVE_BUILD_FINGERPRINT "unknown"
#endif

void ThrowNativeError(napi_env env, int32_t code, const std::string& message) {
    napi_throw_error(env, std::to_string(code).c_str(), message.c_str());
}

void RejectAsyncOperation(napi_env env, napi_deferred deferred, int32_t code, const std::string& message) {
    napi_value codeValue = nullptr;
    napi_value messageValue = nullptr;
    napi_value error = nullptr;
    napi_create_string_utf8(env, std::to_string(code).c_str(), NAPI_AUTO_LENGTH, &codeValue);
    napi_create_string_utf8(env, message.c_str(), NAPI_AUTO_LENGTH, &messageValue);
    if (napi_create_error(env, codeValue, messageValue, &error) == napi_ok) {
        napi_reject_deferred(env, deferred, error);
    }
}

void ExecuteCreateEngine(napi_env, void* data) {
    auto* context = static_cast<AsyncEngineCreateContext*>(data);
    if (GetRustAbiVersion() != STAGE7_ABI_VERSION) {
        context->result = {IME_ABI_VERSION_MISMATCH, 0};
        return;
    }
    context->result = CreateRegisteredEngine(context->config);
}

void CompleteCreateEngine(napi_env env, napi_status status, void* data) {
    auto* context = static_cast<AsyncEngineCreateContext*>(data);
    if (status != napi_ok) {
        if (context->result.code == IME_SUCCESS && context->result.id > 0) {
            DestroyRegisteredEngine(context->result.id);
        }
        RejectAsyncOperation(env, context->deferred, IME_NATIVE_BRIDGE_ERROR, "asynchronous engine creation failed");
    } else if (context->result.code != IME_SUCCESS) {
        RejectAsyncOperation(
            env,
            context->deferred,
            context->result.code,
            ErrorMessageForCode(context->result.code));
    } else {
        napi_value id = nullptr;
        if (napi_create_uint32(env, context->result.id, &id) != napi_ok) {
            DestroyRegisteredEngine(context->result.id);
            RejectAsyncOperation(
                env,
                context->deferred,
                IME_NATIVE_BRIDGE_ERROR,
                "unable to return asynchronous engine handle");
        } else if (napi_resolve_deferred(env, context->deferred, id) != napi_ok) {
            DestroyRegisteredEngine(context->result.id);
        }
    }
    napi_delete_async_work(env, context->work);
    delete context;
}

void ExecuteProcessKey(napi_env, void* data) {
    auto* context = static_cast<AsyncProcessKeyContext*>(data);
    context->result = ProcessRegisteredEngineKey(context->handle, context->key);
}

void CompleteProcessKey(napi_env env, napi_status status, void* data) {
    auto* context = static_cast<AsyncProcessKeyContext*>(data);
    if (status != napi_ok) {
        RejectAsyncOperation(
            env,
            context->deferred,
            IME_NATIVE_BRIDGE_ERROR,
            "asynchronous key processing failed");
    } else {
        napi_value result = context->result.code == IME_SUCCESS
            ? ConvertCompositionJsonToArkObject(env, context->result.payload)
            : CreateCompositionErrorResult(
                  env,
                  context->result.code,
                  ErrorMessageForCode(context->result.code));
        if (napi_resolve_deferred(env, context->deferred, result) != napi_ok) {
            RejectAsyncOperation(
                env,
                context->deferred,
                IME_NATIVE_BRIDGE_ERROR,
                "unable to resolve asynchronous key result");
        }
    }
    napi_delete_async_work(env, context->work);
    delete context;
}

bool ReadArguments(napi_env env, napi_callback_info info, size_t expected, napi_value* args) {
    size_t argc = expected;
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return status == napi_ok && argc >= expected;
}

bool ReadUint32Value(napi_env env, napi_value value, uint32_t& out) {
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_number) {
        return false;
    }
    int64_t raw = 0;
    if (napi_get_value_int64(env, value, &raw) != napi_ok || raw <= 0 || raw > UINT32_MAX) {
        return false;
    }
    out = static_cast<uint32_t>(raw);
    return true;
}

bool ReadStringValue(napi_env env, napi_value value, std::string& out) {
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
        return false;
    }

    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::vector<char> buffer(length + 1);
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return false;
    }
    out.assign(buffer.data(), length);
    return true;
}

bool ReadNamedInt32(napi_env env, napi_value object, const char* name, int32_t& out) {
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_number) {
        return false;
    }
    return napi_get_value_int32(env, value, &out) == napi_ok;
}

bool ReadNamedString(napi_env env, napi_value object, const char* name, std::string& out) {
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    return ReadStringValue(env, value, out);
}

bool ReadOptionalNamedString(napi_env env, napi_value object, const char* name, std::string& out) {
    bool hasProperty = false;
    if (napi_has_named_property(env, object, name, &hasProperty) != napi_ok || !hasProperty) {
        out.clear();
        return true;
    }
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok) {
        return false;
    }
    if (type == napi_undefined || type == napi_null) {
        out.clear();
        return true;
    }
    return ReadStringValue(env, value, out);
}

bool ReadOptionalNamedInt32(napi_env env, napi_value object, const char* name, int32_t& out, int32_t defaultValue) {
    bool hasProperty = false;
    if (napi_has_named_property(env, object, name, &hasProperty) != napi_ok || !hasProperty) {
        out = defaultValue;
        return true;
    }
    napi_value value = nullptr;
    if (napi_get_named_property(env, object, name, &value) != napi_ok) {
        return false;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok) {
        return false;
    }
    if (type == napi_undefined || type == napi_null) {
        out = defaultValue;
        return true;
    }
    if (type != napi_number) {
        return false;
    }
    return napi_get_value_int32(env, value, &out) == napi_ok;
}

bool ReadOptionalNamedBool(napi_env env, napi_value object, const char* name, bool& out, bool defaultValue) {
    bool hasProperty = false;
    if (napi_has_named_property(env, object, name, &hasProperty) != napi_ok || !hasProperty) {
        out = defaultValue;
        return true;
    }
    napi_value value = nullptr;
    napi_valuetype type = napi_undefined;
    if (napi_get_named_property(env, object, name, &value) != napi_ok ||
        napi_typeof(env, value, &type) != napi_ok) {
        return false;
    }
    if (type == napi_undefined || type == napi_null) {
        out = defaultValue;
        return true;
    }
    return type == napi_boolean && napi_get_value_bool(env, value, &out) == napi_ok;
}

bool ReadOptionalNamedStringArray(
    napi_env env, napi_value object, const char* name, std::vector<std::string>& out) {
    bool hasProperty = false;
    if (napi_has_named_property(env, object, name, &hasProperty) != napi_ok || !hasProperty) {
        out.clear();
        return true;
    }
    napi_value value = nullptr;
    bool isArray = false;
    uint32_t length = 0;
    if (napi_get_named_property(env, object, name, &value) != napi_ok ||
        napi_is_array(env, value, &isArray) != napi_ok || !isArray ||
        napi_get_array_length(env, value, &length) != napi_ok || length > 8) {
        return false;
    }
    out.clear();
    for (uint32_t index = 0; index < length; ++index) {
        napi_value item = nullptr;
        std::string text;
        if (napi_get_element(env, value, index, &item) != napi_ok || !ReadStringValue(env, item, text)) {
            return false;
        }
        out.push_back(text);
    }
    return true;
}

std::string EscapeJson(const std::string& value) {
    std::string escaped;
    escaped.reserve(value.length());
    for (char ch : value) {
        switch (ch) {
        case '\\':
            escaped += "\\\\";
            break;
        case '"':
            escaped += "\\\"";
            break;
        case '\n':
            escaped += "\\n";
            break;
        case '\r':
            escaped += "\\r";
            break;
        case '\t':
            escaped += "\\t";
            break;
        default:
            escaped.push_back(ch);
            break;
        }
    }
    return escaped;
}

bool ReadEngineConfigJson(napi_env env, napi_callback_info info, std::string& outConfig) {
    napi_value args[1] = {nullptr};
    if (!ReadArguments(env, info, 1, args)) {
        return false;
    }

    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, args[0], &type) != napi_ok || type != napi_object) {
        return false;
    }

    int32_t interfaceVersion = 0;
    std::string schemeId;
    if (!ReadNamedInt32(env, args[0], "interfaceVersion", interfaceVersion) ||
        !ReadNamedString(env, args[0], "schemeId", schemeId)) {
        return false;
    }
    if (interfaceVersion != static_cast<int32_t>(STAGE7_INTERFACE_VERSION)) {
        outConfig.clear();
        return true;
    }
    std::string lexiconPath;
    std::string codeTableBundlePath;
    std::string userLexiconPath;
    std::string codeTableActionFixturePath;
    std::string codeTableActionFixtureSha256;
    int32_t candidatePageSize = DEFAULT_CANDIDATE_PAGE_SIZE;
    int32_t quanpinConfigVersion = 1;
    bool spellingCorrectionEnabled = false;
    std::vector<std::string> fuzzyOptions;
    int32_t quanpinContextRerankingConfigVersion = 2;
    bool quanpinContextRerankingEnabled = false;
    std::string quanpinContextModelPath;
    std::string quanpinContextModelSha256;
    if (!ReadOptionalNamedString(env, args[0], "lexiconPath", lexiconPath) ||
        !ReadOptionalNamedString(env, args[0], "codeTableBundlePath", codeTableBundlePath) ||
        !ReadOptionalNamedString(env, args[0], "userLexiconPath", userLexiconPath) ||
        !ReadOptionalNamedString(env, args[0], "codeTableActionFixturePath", codeTableActionFixturePath) ||
        !ReadOptionalNamedString(env, args[0], "codeTableActionFixtureSha256", codeTableActionFixtureSha256) ||
        !ReadOptionalNamedInt32(
            env, args[0], "candidatePageSize", candidatePageSize, DEFAULT_CANDIDATE_PAGE_SIZE) ||
        !ReadOptionalNamedInt32(env, args[0], "quanpinConfigVersion", quanpinConfigVersion, 1) ||
        !ReadOptionalNamedBool(env, args[0], "spellingCorrectionEnabled", spellingCorrectionEnabled, false) ||
        !ReadOptionalNamedStringArray(env, args[0], "fuzzyOptions", fuzzyOptions) ||
        !ReadOptionalNamedInt32(
            env, args[0], "quanpinContextRerankingConfigVersion", quanpinContextRerankingConfigVersion, 2) ||
        !ReadOptionalNamedBool(
            env, args[0], "quanpinContextRerankingEnabled", quanpinContextRerankingEnabled, false) ||
        !ReadOptionalNamedString(env, args[0], "quanpinContextModelPath", quanpinContextModelPath) ||
        !ReadOptionalNamedString(env, args[0], "quanpinContextModelSha256", quanpinContextModelSha256) ||
        candidatePageSize <= 0 || quanpinConfigVersion != 1 || quanpinContextRerankingConfigVersion != 2) {
        return false;
    }

    outConfig = "{\"interfaceVersion\":" + std::to_string(interfaceVersion) + ",\"schemeId\":\"" +
                EscapeJson(schemeId) + "\",\"candidatePageSize\":" + std::to_string(candidatePageSize) +
                ",\"quanpinConfigVersion\":" + std::to_string(quanpinConfigVersion) +
                ",\"spellingCorrectionEnabled\":" + (spellingCorrectionEnabled ? "true" : "false") +
                ",\"quanpinContextRerankingConfigVersion\":" +
                std::to_string(quanpinContextRerankingConfigVersion) +
                ",\"quanpinContextRerankingEnabled\":" +
                (quanpinContextRerankingEnabled ? "true" : "false") +
                ",\"fuzzyOptions\":[";
    for (size_t index = 0; index < fuzzyOptions.size(); ++index) {
        if (index > 0) {
            outConfig += ",";
        }
        outConfig += "\"" + EscapeJson(fuzzyOptions[index]) + "\"";
    }
    outConfig += "]";
    if (!lexiconPath.empty()) {
        outConfig += ",\"lexiconPath\":\"" + EscapeJson(lexiconPath) + "\"";
    }
    if (!quanpinContextModelPath.empty()) {
        outConfig += ",\"quanpinContextModelPath\":\"" + EscapeJson(quanpinContextModelPath) + "\"";
    }
    if (!quanpinContextModelSha256.empty()) {
        outConfig += ",\"quanpinContextModelSha256\":\"" + EscapeJson(quanpinContextModelSha256) + "\"";
    }
    if (!codeTableBundlePath.empty()) {
        outConfig += ",\"codeTableBundlePath\":\"" + EscapeJson(codeTableBundlePath) + "\"";
    }
    if (!userLexiconPath.empty()) {
        outConfig += ",\"userLexiconPath\":\"" + EscapeJson(userLexiconPath) + "\"";
    }
    if (!codeTableActionFixturePath.empty()) {
        outConfig += ",\"codeTableActionFixturePath\":\"" + EscapeJson(codeTableActionFixturePath) + "\"";
    }
    if (!codeTableActionFixtureSha256.empty()) {
        outConfig += ",\"codeTableActionFixtureSha256\":\"" + EscapeJson(codeTableActionFixtureSha256) + "\"";
    }
    outConfig += "}";
    return true;
}

bool ReadHandleArgument(napi_env env, napi_callback_info info, uint32_t& handle) {
    napi_value args[1] = {nullptr};
    if (!ReadArguments(env, info, 1, args)) {
        return false;
    }
    return ReadUint32Value(env, args[0], handle);
}

bool ReadHandleAndStringArguments(napi_env env, napi_callback_info info, uint32_t& handle, std::string& value) {
    napi_value args[2] = {nullptr, nullptr};
    if (!ReadArguments(env, info, 2, args)) {
        return false;
    }
    return ReadUint32Value(env, args[0], handle) && ReadStringValue(env, args[1], value);
}

bool ReadThreeStringArguments(
    napi_env env,
    napi_callback_info info,
    std::string& first,
    std::string& second,
    std::string& third) {
    napi_value args[3] = {nullptr, nullptr, nullptr};
    if (!ReadArguments(env, info, 3, args)) {
        return false;
    }
    return ReadStringValue(env, args[0], first) && ReadStringValue(env, args[1], second) &&
           ReadStringValue(env, args[2], third);
}

bool ReadHandleAndBoolArguments(napi_env env, napi_callback_info info, uint32_t& handle, bool& value) {
    napi_value args[2] = {nullptr, nullptr};
    if (!ReadArguments(env, info, 2, args)) {
        return false;
    }
    if (!ReadUint32Value(env, args[0], handle)) {
        return false;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, args[1], &type) != napi_ok || type != napi_boolean) {
        return false;
    }
    return napi_get_value_bool(env, args[1], &value) == napi_ok;
}

bool ReadHandleAndStringArrayArguments(
    napi_env env, napi_callback_info info, uint32_t& handle, std::string& json) {
    napi_value args[2] = {nullptr, nullptr};
    if (!ReadArguments(env, info, 2, args) || !ReadUint32Value(env, args[0], handle)) {
        return false;
    }
    bool isArray = false;
    if (napi_is_array(env, args[1], &isArray) != napi_ok || !isArray) {
        return false;
    }
    uint32_t length = 0;
    if (napi_get_array_length(env, args[1], &length) != napi_ok || length > 256) {
        return false;
    }
    json = "[";
    for (uint32_t index = 0; index < length; ++index) {
        napi_value item = nullptr;
        std::string id;
        if (napi_get_element(env, args[1], index, &item) != napi_ok || !ReadStringValue(env, item, id)) {
            return false;
        }
        if (index > 0) {
            json += ",";
        }
        json += "\"" + EscapeJson(id) + "\"";
    }
    json += "]";
    return true;
}

bool ReadHandleAndIndexArguments(napi_env env, napi_callback_info info, uint32_t& handle, size_t& index) {
    napi_value args[2] = {nullptr, nullptr};
    if (!ReadArguments(env, info, 2, args)) {
        return false;
    }
    if (!ReadUint32Value(env, args[0], handle)) {
        return false;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, args[1], &type) != napi_ok || type != napi_number) {
        return false;
    }
    int64_t raw = 0;
    if (napi_get_value_int64(env, args[1], &raw) != napi_ok || raw < 0) {
        return false;
    }
    index = static_cast<size_t>(raw);
    return true;
}

bool IsSingleCodeTableKey(const std::string& value) {
    return value.length() == 1 &&
           ((value[0] >= 'a' && value[0] <= 'z') ||
            (value[0] >= 'A' && value[0] <= 'Z') ||
            (value[0] >= '0' && value[0] <= '9') || std::string(";`='.+-*/_@").find(value[0]) != std::string::npos);
}
} // namespace

napi_value GetInterfaceVersion(napi_env env, napi_callback_info) {
    napi_value result = nullptr;
    napi_create_uint32(env, STAGE5_INTERFACE_VERSION, &result);
    return result;
}

napi_value GetEngineVersion(napi_env env, napi_callback_info) {
    RustCallResult result = GetRustEngineVersion();
    if (result.code != IME_SUCCESS) {
        napi_throw_error(env, std::to_string(result.code).c_str(), ErrorMessageForCode(result.code).c_str());
        return nullptr;
    }
    return CreateString(env, result.payload);
}

napi_value GetNativeBuildInfo(napi_env env, napi_callback_info) {
    const std::string value =
        "abi=" IME_NATIVE_ABI ";rustArchiveSha256=" IME_RUST_ARCHIVE_SHA256
        ";fingerprint=" IME_NATIVE_BUILD_FINGERPRINT;
    return CreateString(env, value);
}

napi_value CreateEngine(napi_env env, napi_callback_info info) {
    std::string config;
    if (!ReadEngineConfigJson(env, info, config)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "createEngine requires an EngineConfig object");
        return nullptr;
    }
    if (config.empty()) {
        ThrowNativeError(env, IME_ABI_VERSION_MISMATCH, "interface version mismatch");
        return nullptr;
    }
    if (GetRustAbiVersion() != STAGE7_ABI_VERSION) {
        ThrowNativeError(env, IME_ABI_VERSION_MISMATCH, "Rust ABI version mismatch");
        return nullptr;
    }

    EngineBridgeCreateResult result = CreateRegisteredEngine(config);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }

    napi_value id = nullptr;
    napi_create_uint32(env, result.id, &id);
    return id;
}

napi_value CreateEngineAsync(napi_env env, napi_callback_info info) {
    std::string config;
    if (!ReadEngineConfigJson(env, info, config)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "createEngineAsync requires an EngineConfig object");
        return nullptr;
    }
    if (config.empty()) {
        ThrowNativeError(env, IME_ABI_VERSION_MISMATCH, "interface version mismatch");
        return nullptr;
    }

    auto* context = new (std::nothrow) AsyncEngineCreateContext();
    if (context == nullptr) {
        ThrowNativeError(env, IME_BUFFER_ALLOCATION_FAILED, "unable to allocate asynchronous engine context");
        return nullptr;
    }
    context->config = std::move(config);

    napi_value promise = nullptr;
    if (napi_create_promise(env, &context->deferred, &promise) != napi_ok) {
        delete context;
        ThrowNativeError(env, IME_NATIVE_BRIDGE_ERROR, "unable to create engine promise");
        return nullptr;
    }

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "createEngineAsync", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteCreateEngine,
            CompleteCreateEngine,
            context,
            &context->work) != napi_ok) {
        RejectAsyncOperation(env, context->deferred, IME_NATIVE_BRIDGE_ERROR, "unable to create engine async work");
        delete context;
        return promise;
    }
    if (napi_queue_async_work(env, context->work) != napi_ok) {
        napi_delete_async_work(env, context->work);
        RejectAsyncOperation(env, context->deferred, IME_NATIVE_BRIDGE_ERROR, "unable to queue engine async work");
        delete context;
    }
    return promise;
}

napi_value DestroyEngine(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "destroyEngine requires a numeric handle");
        return nullptr;
    }

    int32_t code = DestroyRegisteredEngine(handle);
    if (code != IME_SUCCESS) {
        ThrowNativeError(env, code, ErrorMessageForCode(code));
        return nullptr;
    }

    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value ProcessKey(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string key;
    if (!ReadHandleAndStringArguments(env, info, handle, key)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "processKey requires handle and key");
        return nullptr;
    }
    if (!IsSingleCodeTableKey(key)) {
        ThrowNativeError(
            env,
            IME_INVALID_ARGUMENT,
            "processKey requires one ASCII input letter, digit, operator, or guide key");
        return nullptr;
    }

    RustCallResult result = ProcessRegisteredEngineKey(handle, key);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value ProcessKeyAsync(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string key;
    if (!ReadHandleAndStringArguments(env, info, handle, key)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "processKeyAsync requires handle and key");
        return nullptr;
    }
    if (!IsSingleCodeTableKey(key)) {
        ThrowNativeError(
            env,
            IME_INVALID_ARGUMENT,
            "processKeyAsync requires one ASCII input letter, digit, operator, or guide key");
        return nullptr;
    }

    auto* context = new (std::nothrow) AsyncProcessKeyContext();
    if (context == nullptr) {
        ThrowNativeError(env, IME_BUFFER_ALLOCATION_FAILED, "unable to allocate asynchronous key context");
        return nullptr;
    }
    context->handle = handle;
    context->key = std::move(key);

    napi_value promise = nullptr;
    if (napi_create_promise(env, &context->deferred, &promise) != napi_ok) {
        delete context;
        ThrowNativeError(env, IME_NATIVE_BRIDGE_ERROR, "unable to create key promise");
        return nullptr;
    }

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "processKeyAsync", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(
            env,
            nullptr,
            resourceName,
            ExecuteProcessKey,
            CompleteProcessKey,
            context,
            &context->work) != napi_ok) {
        RejectAsyncOperation(env, context->deferred, IME_NATIVE_BRIDGE_ERROR, "unable to create key async work");
        delete context;
        return promise;
    }
    if (napi_queue_async_work(env, context->work) != napi_ok) {
        napi_delete_async_work(env, context->work);
        RejectAsyncOperation(env, context->deferred, IME_NATIVE_BRIDGE_ERROR, "unable to queue key async work");
        delete context;
    }
    return promise;
}

napi_value InsertSegmentBoundary(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "insertSegmentBoundary requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = InsertRegisteredEngineSegmentBoundary(handle);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value Backspace(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "backspace requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = BackspaceRegisteredEngine(handle);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value Reset(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "reset requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = ResetRegisteredEngine(handle);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value ChangeScheme(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string schemeId;
    if (!ReadHandleAndStringArguments(env, info, handle, schemeId)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "changeScheme requires handle and schemeId");
        return nullptr;
    }

    RustCallResult result = ChangeRegisteredEngineScheme(handle, schemeId);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value SelectCandidate(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    size_t candidateIndex = 0;
    if (!ReadHandleAndIndexArguments(env, info, handle, candidateIndex)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "selectCandidate requires handle and candidate index");
        return nullptr;
    }

    RustCallResult result = SelectRegisteredEngineCandidate(handle, candidateIndex);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value SelectPinyinCombination(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    size_t combinationIndex = 0;
    if (!ReadHandleAndIndexArguments(env, info, handle, combinationIndex)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT,
                         "selectPinyinCombination requires handle and combination index");
        return nullptr;
    }

    RustCallResult result = SelectRegisteredEnginePinyinCombination(handle, combinationIndex);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value NextCandidatePage(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "nextCandidatePage requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = NextRegisteredEngineCandidatePage(handle);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value PreviousCandidatePage(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "previousCandidatePage requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = PreviousRegisteredEngineCandidatePage(handle);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value ReverseLookup(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string text;
    if (!ReadHandleAndStringArguments(env, info, handle, text) || text.size() > 4) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "reverseLookup requires handle and one character");
        return nullptr;
    }
    RustCallResult result = ReverseLookupRegisteredEngine(handle, text);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return CreateString(env, result.payload);
}

napi_value GetLocalAssociations(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "getLocalAssociations requires a numeric handle");
        return nullptr;
    }
    RustCallResult result = GetRegisteredEngineLocalAssociations(handle);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return CreateString(env, result.payload);
}

napi_value GetCodeTableCategoryConfig(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "getCodeTableCategoryConfig requires a numeric handle");
        return nullptr;
    }
    RustCallResult result = GetRegisteredEngineCodeTableCategoryConfig(handle);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return CreateString(env, result.payload);
}

napi_value SetCodeTableCategories(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string categoryIdsJson;
    if (!ReadHandleAndStringArrayArguments(env, info, handle, categoryIdsJson)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "setCodeTableCategories requires handle and string array");
        return nullptr;
    }
    RustCallResult result = SetRegisteredEngineCodeTableCategories(handle, categoryIdsJson);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value SetCodeTableCommitPolicy(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string policyJson;
    if (!ReadHandleAndStringArguments(env, info, handle, policyJson) || policyJson.empty()) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "setCodeTableCommitPolicy requires handle and policy JSON");
        return nullptr;
    }
    RustCallResult result = SetRegisteredEngineCodeTableCommitPolicy(handle, policyJson);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value ReloadUserLexicon(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "reloadUserLexicon requires a numeric handle");
        return nullptr;
    }
    RustCallResult result = ReloadRegisteredEngineUserLexicon(handle);
    if (result.code != IME_SUCCESS) {
        return CreateCompositionErrorResult(env, result.code, ErrorMessageForCode(result.code));
    }
    return ConvertCompositionJsonToArkObject(env, result.payload);
}

napi_value LoadUserLexicon(napi_env env, napi_callback_info info) {
    napi_value args[1] = {nullptr};
    std::string path;
    if (!ReadArguments(env, info, 1, args) || !ReadStringValue(env, args[0], path) || path.empty()) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "loadUserLexicon requires a path");
        return nullptr;
    }
    RustCallResult result = LoadUserLexiconDocument(path);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return CreateString(env, result.payload);
}

napi_value SaveUserLexicon(napi_env env, napi_callback_info info) {
    std::string path;
    std::string expectedRevision;
    std::string content;
    if (!ReadThreeStringArguments(env, info, path, expectedRevision, content) || path.empty() ||
        expectedRevision.empty()) {
        ThrowNativeError(
            env, IME_INVALID_ARGUMENT, "saveUserLexicon requires path, revision, and content");
        return nullptr;
    }
    RustCallResult result = SaveUserLexiconDocument(path, expectedRevision, content);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return CreateString(env, result.payload);
}

napi_value SetUserModelPath(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string path;
    if (!ReadHandleAndStringArguments(env, info, handle, path) || path.empty()) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "setUserModelPath requires handle and path");
        return nullptr;
    }

    RustCallResult result = SetRegisteredEngineUserModelPath(handle, path);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return ConvertUserModelStatusJsonToArkObject(env, result.payload);
}

napi_value LoadUserModel(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "loadUserModel requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = LoadRegisteredEngineUserModel(handle);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return ConvertUserModelStatusJsonToArkObject(env, result.payload);
}

napi_value FlushUserModel(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "flushUserModel requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = FlushRegisteredEngineUserModel(handle);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return ConvertUserModelStatusJsonToArkObject(env, result.payload);
}

napi_value ClearUserModel(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    if (!ReadHandleArgument(env, info, handle)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "clearUserModel requires a numeric handle");
        return nullptr;
    }

    RustCallResult result = ClearRegisteredEngineUserModel(handle);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return ConvertUserModelStatusJsonToArkObject(env, result.payload);
}

napi_value SetUserLearningEnabled(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    bool enabled = false;
    if (!ReadHandleAndBoolArguments(env, info, handle, enabled)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "setUserLearningEnabled requires handle and boolean");
        return nullptr;
    }

    RustCallResult result = SetRegisteredEngineUserLearningEnabled(handle, enabled);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return ConvertUserModelStatusJsonToArkObject(env, result.payload);
}

napi_value SetSessionLearningAllowed(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    bool allowed = false;
    if (!ReadHandleAndBoolArguments(env, info, handle, allowed)) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "setSessionLearningAllowed requires handle and boolean");
        return nullptr;
    }

    RustCallResult result = SetRegisteredEngineSessionLearningAllowed(handle, allowed);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return ConvertUserModelStatusJsonToArkObject(env, result.payload);
}
