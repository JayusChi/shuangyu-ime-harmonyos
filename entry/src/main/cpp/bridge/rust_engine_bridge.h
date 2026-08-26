#ifndef RUST_ENGINE_BRIDGE_H
#define RUST_ENGINE_BRIDGE_H

#include "rust_buffer.h"

#include <cstdint>
#include <cstddef>
#include <string>

struct RustCallResult {
    int32_t code;
    RustBuffer payload;
};

constexpr uint32_t CURRENT_INTERFACE_VERSION = 10;
constexpr uint32_t CURRENT_ABI_VERSION = 10;
constexpr uint32_t STAGE7_INTERFACE_VERSION = CURRENT_INTERFACE_VERSION;
constexpr uint32_t STAGE7_ABI_VERSION = CURRENT_ABI_VERSION;
constexpr uint32_t STAGE5_INTERFACE_VERSION = CURRENT_INTERFACE_VERSION;
constexpr uint32_t STAGE5_ABI_VERSION = CURRENT_ABI_VERSION;

uint32_t GetRustAbiVersion();
RustCallResult GetRustEngineVersion();
struct EngineBridgeCreateResult {
    int32_t code;
    uint32_t id;
};

EngineBridgeCreateResult CreateRegisteredEngine(const std::string& config);
int32_t DestroyRegisteredEngine(uint32_t id);
RustCallResult ProcessRegisteredEngineKey(uint32_t id, const std::string& key);
RustCallResult InsertRegisteredEngineSegmentBoundary(uint32_t id);
RustCallResult BackspaceRegisteredEngine(uint32_t id);
RustCallResult ResetRegisteredEngine(uint32_t id);
RustCallResult ChangeRegisteredEngineScheme(uint32_t id, const std::string& schemeId);
RustCallResult SelectRegisteredEngineCandidate(uint32_t id, size_t candidateIndex);
RustCallResult SelectRegisteredEnginePinyinCombination(uint32_t id, size_t combinationIndex);
RustCallResult NextRegisteredEngineCandidatePage(uint32_t id);
RustCallResult PreviousRegisteredEngineCandidatePage(uint32_t id);
RustCallResult GetRegisteredEngineLocalAssociations(uint32_t id);
RustCallResult GetRegisteredEngineCodeTableCategoryConfig(uint32_t id);
RustCallResult SetRegisteredEngineCodeTableCategories(uint32_t id, const std::string& categoryIdsJson);
RustCallResult SetRegisteredEngineCodeTableCommitPolicy(uint32_t id, const std::string& policyJson);
RustCallResult ReloadRegisteredEngineUserLexicon(uint32_t id);
RustCallResult LoadUserLexiconDocument(const std::string& path);
RustCallResult SaveUserLexiconDocument(
    const std::string& path, const std::string& expectedRevision, const std::string& content);
RustCallResult SetRegisteredEngineUserModelPath(uint32_t id, const std::string& path);
RustCallResult LoadRegisteredEngineUserModel(uint32_t id);
RustCallResult FlushRegisteredEngineUserModel(uint32_t id);
RustCallResult ClearRegisteredEngineUserModel(uint32_t id);
RustCallResult SetRegisteredEngineUserLearningEnabled(uint32_t id, bool enabled);
RustCallResult SetRegisteredEngineSessionLearningAllowed(uint32_t id, bool allowed);
void ClearRegisteredEngines();

#endif
