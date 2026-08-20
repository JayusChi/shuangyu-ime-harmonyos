#include "native_error.h"

std::string ErrorMessageForCode(int32_t code) {
    switch (code) {
    case IME_SUCCESS:
        return "success";
    case IME_INVALID_ARGUMENT:
        return "invalid argument";
    case IME_INVALID_HANDLE:
        return "invalid handle";
    case IME_UNSUPPORTED_OPERATION:
        return "unsupported operation";
    case IME_INVALID_UTF8:
        return "invalid utf-8";
    case IME_SERIALIZATION_ERROR:
        return "serialization error";
    case IME_BUFFER_ALLOCATION_FAILED:
        return "buffer allocation failed";
    case IME_ENGINE_NOT_INITIALIZED:
        return "engine not initialized";
    case IME_ENGINE_INTERNAL_ERROR:
        return "engine internal error";
    case IME_NATIVE_BRIDGE_ERROR:
        return "native bridge error";
    case IME_ABI_VERSION_MISMATCH:
        return "abi version mismatch";
    case IME_INVALID_CONFIG:
        return "invalid config";
    case IME_INVALID_SCHEME:
        return "invalid scheme";
    case IME_LEXICON_NOT_FOUND:
        return "lexicon not found";
    case IME_LEXICON_LOAD_FAILED:
        return "lexicon load failed";
    case IME_INVALID_PAGE:
        return "invalid candidate page";
    case IME_INVALID_CANDIDATE:
        return "invalid candidate";
    case IME_UNKNOWN_ERROR:
        return "unknown error";
    default:
        return "unknown error";
    }
}
