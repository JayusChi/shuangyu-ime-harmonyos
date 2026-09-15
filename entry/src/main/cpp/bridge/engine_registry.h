#ifndef ENGINE_REGISTRY_H
#define ENGINE_REGISTRY_H

#include "rust_engine_bridge.h"
#include "rust_engine_handle.h"

#include <cstdint>
#include <mutex>
#include <unordered_map>

struct EngineCreateResult {
    int32_t code;
    uint32_t id;
};

class EngineRegistry {
  public:
    static EngineRegistry& Instance();

    EngineCreateResult Create(const std::string& config);
    int32_t Destroy(uint32_t id);
    RustCallResult ProcessKey(uint32_t id, const std::string& key);
    RustCallResult InsertSegmentBoundary(uint32_t id);
    RustCallResult Backspace(uint32_t id);
    RustCallResult Reset(uint32_t id);
    RustCallResult ChangeScheme(uint32_t id, const std::string& schemeId);
    RustCallResult SelectCandidate(uint32_t id, size_t candidateIndex);
    RustCallResult SelectPinyinCombination(uint32_t id, size_t combinationIndex);
    RustCallResult NextCandidatePage(uint32_t id);
    RustCallResult PreviousCandidatePage(uint32_t id);
    RustCallResult GetLocalAssociations(uint32_t id);
    RustCallResult ReverseLookup(uint32_t id, const std::string& text);
    RustCallResult GetCodeTableCategoryConfig(uint32_t id);
    RustCallResult SetCodeTableCategories(uint32_t id, const std::string& categoryIdsJson);
    RustCallResult SetCodeTableCommitPolicy(uint32_t id, const std::string& policyJson);
    RustCallResult ReloadUserLexicon(uint32_t id);
    RustCallResult SetUserModelPath(uint32_t id, const std::string& path);
    RustCallResult LoadUserModel(uint32_t id);
    RustCallResult FlushUserModel(uint32_t id);
    RustCallResult ClearUserModel(uint32_t id);
    RustCallResult SetUserLearningEnabled(uint32_t id, bool enabled);
    RustCallResult SetSessionLearningAllowed(uint32_t id, bool allowed);
    void Clear();

  private:
    EngineRegistry() = default;
    uint32_t NextIdLocked();

    std::mutex mutex_;
    std::unordered_map<uint32_t, RustEngineHandle> engines_;
    uint32_t nextId_ = 1;
};

#endif
