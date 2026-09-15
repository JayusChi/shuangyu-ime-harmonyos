#include "rust_engine_bridge.h"

#include "engine_registry.h"
#include "ime_engine_ffi.h"
#include "native_error.h"
#include "rust_buffer.h"

#include <utility>

namespace {
RustCallResult CopyRustBuffer(int32_t code, RustBuffer& buffer) {
    if (code != IME_SUCCESS) {
        return {code, RustBuffer()};
    }
    if (buffer.Empty()) {
        return {IME_BUFFER_ALLOCATION_FAILED, RustBuffer()};
    }
    return {code, std::move(buffer)};
}
} // namespace

uint32_t GetRustAbiVersion() {
    return ime_engine_get_abi_version();
}

RustCallResult GetRustEngineVersion() {
    RustBuffer buffer;
    int32_t code = ime_engine_get_version(buffer.Out());
    return CopyRustBuffer(code, buffer);
}

EngineBridgeCreateResult CreateRegisteredEngine(const std::string& config) {
    EngineCreateResult result = EngineRegistry::Instance().Create(config);
    return {result.code, result.id};
}

int32_t DestroyRegisteredEngine(uint32_t id) {
    return EngineRegistry::Instance().Destroy(id);
}

RustCallResult ProcessRegisteredEngineKey(uint32_t id, const std::string& key) {
    return EngineRegistry::Instance().ProcessKey(id, key);
}

RustCallResult InsertRegisteredEngineSegmentBoundary(uint32_t id) {
    return EngineRegistry::Instance().InsertSegmentBoundary(id);
}

RustCallResult BackspaceRegisteredEngine(uint32_t id) {
    return EngineRegistry::Instance().Backspace(id);
}

RustCallResult ResetRegisteredEngine(uint32_t id) {
    return EngineRegistry::Instance().Reset(id);
}

RustCallResult ChangeRegisteredEngineScheme(uint32_t id, const std::string& schemeId) {
    return EngineRegistry::Instance().ChangeScheme(id, schemeId);
}

RustCallResult SelectRegisteredEngineCandidate(uint32_t id, size_t candidateIndex) {
    return EngineRegistry::Instance().SelectCandidate(id, candidateIndex);
}

RustCallResult SelectRegisteredEnginePinyinCombination(uint32_t id, size_t combinationIndex) {
    return EngineRegistry::Instance().SelectPinyinCombination(id, combinationIndex);
}

RustCallResult NextRegisteredEngineCandidatePage(uint32_t id) {
    return EngineRegistry::Instance().NextCandidatePage(id);
}

RustCallResult PreviousRegisteredEngineCandidatePage(uint32_t id) {
    return EngineRegistry::Instance().PreviousCandidatePage(id);
}

RustCallResult ReverseLookupRegisteredEngine(uint32_t id, const std::string& text) {
    return EngineRegistry::Instance().ReverseLookup(id, text);
}

RustCallResult GetRegisteredEngineLocalAssociations(uint32_t id) {
    return EngineRegistry::Instance().GetLocalAssociations(id);
}

RustCallResult GetRegisteredEngineCodeTableCategoryConfig(uint32_t id) {
    return EngineRegistry::Instance().GetCodeTableCategoryConfig(id);
}

RustCallResult SetRegisteredEngineCodeTableCategories(uint32_t id, const std::string& categoryIdsJson) {
    return EngineRegistry::Instance().SetCodeTableCategories(id, categoryIdsJson);
}

RustCallResult SetRegisteredEngineCodeTableCommitPolicy(uint32_t id, const std::string& policyJson) {
    return EngineRegistry::Instance().SetCodeTableCommitPolicy(id, policyJson);
}

RustCallResult ReloadRegisteredEngineUserLexicon(uint32_t id) {
    return EngineRegistry::Instance().ReloadUserLexicon(id);
}

RustCallResult LoadUserLexiconDocument(const std::string& path) {
    RustBuffer buffer;
    auto* pathBytes = reinterpret_cast<const uint8_t*>(path.data());
    int32_t code = ime_user_lexicon_load(pathBytes, path.length(), buffer.Out());
    return CopyRustBuffer(code, buffer);
}

RustCallResult SaveUserLexiconDocument(
    const std::string& path, const std::string& expectedRevision, const std::string& content) {
    RustBuffer buffer;
    auto* pathBytes = reinterpret_cast<const uint8_t*>(path.data());
    auto* revisionBytes = reinterpret_cast<const uint8_t*>(expectedRevision.data());
    auto* contentBytes = reinterpret_cast<const uint8_t*>(content.data());
    int32_t code = ime_user_lexicon_save(
        pathBytes,
        path.length(),
        revisionBytes,
        expectedRevision.length(),
        contentBytes,
        content.length(),
        buffer.Out());
    return CopyRustBuffer(code, buffer);
}

RustCallResult SetRegisteredEngineUserModelPath(uint32_t id, const std::string& path) {
    return EngineRegistry::Instance().SetUserModelPath(id, path);
}

RustCallResult LoadRegisteredEngineUserModel(uint32_t id) {
    return EngineRegistry::Instance().LoadUserModel(id);
}

RustCallResult FlushRegisteredEngineUserModel(uint32_t id) {
    return EngineRegistry::Instance().FlushUserModel(id);
}

RustCallResult ClearRegisteredEngineUserModel(uint32_t id) {
    return EngineRegistry::Instance().ClearUserModel(id);
}

RustCallResult SetRegisteredEngineUserLearningEnabled(uint32_t id, bool enabled) {
    return EngineRegistry::Instance().SetUserLearningEnabled(id, enabled);
}

RustCallResult SetRegisteredEngineSessionLearningAllowed(uint32_t id, bool allowed) {
    return EngineRegistry::Instance().SetSessionLearningAllowed(id, allowed);
}

void ClearRegisteredEngines() {
    EngineRegistry::Instance().Clear();
}
