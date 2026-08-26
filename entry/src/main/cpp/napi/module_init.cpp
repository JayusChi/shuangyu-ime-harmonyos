#include "engine_napi.h"

#include "napi/native_api.h"

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"getInterfaceVersion", nullptr, GetInterfaceVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getEngineVersion", nullptr, GetEngineVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getNativeBuildInfo", nullptr, GetNativeBuildInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createEngine", nullptr, CreateEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createEngineAsync", nullptr, CreateEngineAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroyEngine", nullptr, DestroyEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"processKey", nullptr, ProcessKey, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"insertSegmentBoundary", nullptr, InsertSegmentBoundary, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"backspace", nullptr, Backspace, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"reset", nullptr, Reset, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"changeScheme", nullptr, ChangeScheme, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"selectCandidate", nullptr, SelectCandidate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"selectPinyinCombination", nullptr, SelectPinyinCombination, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nextCandidatePage", nullptr, NextCandidatePage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"previousCandidatePage", nullptr, PreviousCandidatePage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLocalAssociations", nullptr, GetLocalAssociations, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCodeTableCategoryConfig", nullptr, GetCodeTableCategoryConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setCodeTableCategories", nullptr, SetCodeTableCategories, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setCodeTableCommitPolicy", nullptr, SetCodeTableCommitPolicy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"reloadUserLexicon", nullptr, ReloadUserLexicon, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadUserLexicon", nullptr, LoadUserLexicon, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"saveUserLexicon", nullptr, SaveUserLexicon, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setUserModelPath", nullptr, SetUserModelPath, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadUserModel", nullptr, LoadUserModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"flushUserModel", nullptr, FlushUserModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearUserModel", nullptr, ClearUserModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setUserLearningEnabled", nullptr, SetUserLearningEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSessionLearningAllowed", nullptr, SetSessionLearningAllowed, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module imeBridgeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "ime_bridge",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterImeBridgeModule(void) {
    napi_module_register(&imeBridgeModule);
}
