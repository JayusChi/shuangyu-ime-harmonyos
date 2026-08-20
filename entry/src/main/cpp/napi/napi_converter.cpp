#include "napi_converter.h"

#include "native_error.h"

#include <algorithm>
#include <utility>
#include <vector>

namespace {
struct Candidate {
    std::string id;
    std::string text;
    std::string reading;
};

struct FormalCandidate {
    std::string id;
    std::string text;
    std::string reading;
    std::string source;
};

struct EngineResult {
    bool success = false;
    int32_t errorCode = IME_SERIALIZATION_ERROR;
    std::string errorMessage = "Invalid Rust JSON";
    std::string rawInput;
    std::string preeditText;
    std::string engineVersion;
    std::vector<Candidate> candidates;
};

struct CompositionResult {
    bool success = false;
    int32_t errorCode = IME_SERIALIZATION_ERROR;
    std::string errorMessage = "Invalid Rust JSON";
    std::string rawInput;
    std::string preeditText;
    std::vector<std::string> parsedSyllables;
    std::string pendingCode;
    std::vector<std::string> displaySegments;
    std::vector<int32_t> segmentBoundaries;
    std::string currentPinyin;
    std::vector<std::string> pinyinCombinations;
    std::string parserState;
    std::vector<FormalCandidate> candidates;
    int32_t highlightedIndex = -1;
    bool hasNextPage = false;
    bool hasPreviousPage = false;
    int32_t candidatePage = 0;
    std::string commitText;
    bool hasAction = false;
    std::string actionType;
    std::string actionFormatId;
    std::string actionText;
    int32_t actionCursorOffsetUtf16 = 0;
    bool compositionFinished = false;
};

struct UserModelStatus {
    bool loaded = false;
    bool enabled = false;
    bool sessionLearningAllowed = false;
    bool dirty = false;
    int32_t recordCount = 0;
    int32_t formatVersion = 0;
    int32_t dataVersion = 0;
    std::string lastErrorCode;
};

bool ExtractString(const std::string& json, const std::string& key, std::string& out) {
    const std::string token = "\"" + key + "\":\"";
    size_t start = json.find(token);
    if (start == std::string::npos) {
        return false;
    }
    start += token.length();
    size_t end = start;
    bool escaped = false;
    while (end < json.length()) {
        char ch = json[end];
        if (ch == '"' && !escaped) {
            out = json.substr(start, end - start);
            return true;
        }
        escaped = ch == '\\' && !escaped;
        if (ch != '\\') {
            escaped = false;
        }
        ++end;
    }
    return false;
}

bool ExtractBool(const std::string& json, const std::string& key, bool& out) {
    const std::string token = "\"" + key + "\":";
    size_t start = json.find(token);
    if (start == std::string::npos) {
        return false;
    }
    start += token.length();
    if (json.compare(start, 4, "true") == 0) {
        out = true;
        return true;
    }
    if (json.compare(start, 5, "false") == 0) {
        out = false;
        return true;
    }
    return false;
}

bool ExtractInt(const std::string& json, const std::string& key, int32_t& out) {
    const std::string token = "\"" + key + "\":";
    size_t start = json.find(token);
    if (start == std::string::npos) {
        return false;
    }
    start += token.length();
    size_t end = start;
    if (end < json.length() && json[end] == '-') {
        ++end;
    }
    while (end < json.length() && json[end] >= '0' && json[end] <= '9') {
        ++end;
    }
    if (start == end || (json[start] == '-' && start + 1 == end)) {
        return false;
    }
    out = std::stoi(json.substr(start, end - start));
    return true;
}

std::vector<Candidate> ExtractCandidates(const std::string& json) {
    std::vector<Candidate> candidates;
    size_t start = json.find("\"candidates\":[");
    if (start == std::string::npos) {
        return candidates;
    }
    const size_t arrayEnd = json.find(']', start);
    if (arrayEnd != std::string::npos) {
        candidates.reserve(static_cast<size_t>(
            std::count(json.begin() + static_cast<std::string::difference_type>(start),
                       json.begin() + static_cast<std::string::difference_type>(arrayEnd), '{')));
    }
    start = json.find('{', start);
    while (start != std::string::npos) {
        size_t end = json.find('}', start);
        if (end == std::string::npos) {
            break;
        }
        std::string item = json.substr(start, end - start + 1);
        Candidate candidate;
        if (ExtractString(item, "id", candidate.id) && ExtractString(item, "text", candidate.text) &&
            ExtractString(item, "reading", candidate.reading)) {
            candidates.push_back(std::move(candidate));
        }
        start = json.find('{', end + 1);
    }
    return candidates;
}

std::vector<std::string> ExtractStringArray(const std::string& json, const std::string& key, bool& ok) {
    std::vector<std::string> values;
    ok = false;
    const std::string token = "\"" + key + "\":[";
    size_t start = json.find(token);
    if (start == std::string::npos) {
        return values;
    }
    start += token.length();
    size_t end = json.find(']', start);
    if (end == std::string::npos) {
        return values;
    }

    size_t index = start;
    while (index < end) {
        while (index < end && (json[index] == ' ' || json[index] == ',')) {
            ++index;
        }
        if (index >= end) {
            break;
        }
        if (json[index] != '"') {
            return values;
        }
        ++index;
        size_t valueEnd = index;
        bool escaped = false;
        while (valueEnd < end) {
            char ch = json[valueEnd];
            if (ch == '"' && !escaped) {
                values.push_back(json.substr(index, valueEnd - index));
                index = valueEnd + 1;
                break;
            }
            escaped = ch == '\\' && !escaped;
            if (ch != '\\') {
                escaped = false;
            }
            ++valueEnd;
        }
        if (valueEnd >= end) {
            return values;
        }
    }

    ok = true;
    return values;
}

std::vector<int32_t> ExtractIntArray(const std::string& json, const std::string& key, bool& ok) {
    std::vector<int32_t> values;
    ok = false;
    const std::string token = "\"" + key + "\":[";
    size_t start = json.find(token);
    if (start == std::string::npos) {
        return values;
    }
    start += token.length();
    size_t end = json.find(']', start);
    if (end == std::string::npos) {
        return values;
    }

    size_t index = start;
    while (index < end) {
        while (index < end && (json[index] == ' ' || json[index] == ',')) {
            ++index;
        }
        if (index >= end) {
            break;
        }
        size_t valueEnd = index;
        while (valueEnd < end && json[valueEnd] >= '0' && json[valueEnd] <= '9') {
            ++valueEnd;
        }
        if (valueEnd == index) {
            return values;
        }
        values.push_back(std::stoi(json.substr(index, valueEnd - index)));
        index = valueEnd;
    }
    ok = true;
    return values;
}

std::vector<FormalCandidate> ExtractFormalCandidates(const std::string& json, bool& ok) {
    std::vector<FormalCandidate> candidates;
    ok = false;
    size_t arrayStart = json.find("\"candidates\":[");
    if (arrayStart == std::string::npos) {
        return candidates;
    }
    size_t arrayEnd = json.find(']', arrayStart);
    if (arrayEnd == std::string::npos) {
        return candidates;
    }
    candidates.reserve(static_cast<size_t>(
        std::count(json.begin() + static_cast<std::string::difference_type>(arrayStart),
                   json.begin() + static_cast<std::string::difference_type>(arrayEnd), '{')));
    size_t start = json.find('{', arrayStart);
    while (start != std::string::npos && start < arrayEnd) {
        size_t end = json.find('}', start);
        if (end == std::string::npos || end > arrayEnd) {
            return candidates;
        }
        std::string item = json.substr(start, end - start + 1);
        FormalCandidate candidate;
        if (ExtractString(item, "id", candidate.id) && ExtractString(item, "text", candidate.text) &&
            ExtractString(item, "reading", candidate.reading) && ExtractString(item, "source", candidate.source)) {
            candidates.push_back(std::move(candidate));
        } else {
            return candidates;
        }
        start = json.find('{', end + 1);
    }
    ok = true;
    return candidates;
}

bool ParseEngineResult(const std::string& json, EngineResult& out) {
    return ExtractBool(json, "success", out.success) && ExtractInt(json, "errorCode", out.errorCode) &&
           ExtractString(json, "errorMessage", out.errorMessage) && ExtractString(json, "rawInput", out.rawInput) &&
           ExtractString(json, "preeditText", out.preeditText) &&
           ExtractString(json, "engineVersion", out.engineVersion) &&
           !(out.candidates = ExtractCandidates(json)).empty();
}

bool ParseCompositionResult(const std::string& json, CompositionResult& out) {
    bool parsedSyllablesOk = false;
    bool displaySegmentsOk = false;
    bool segmentBoundariesOk = false;
    bool pinyinCombinationsOk = false;
    bool candidatesOk = false;
    out.parsedSyllables = ExtractStringArray(json, "parsedSyllables", parsedSyllablesOk);
    out.displaySegments = ExtractStringArray(json, "displaySegments", displaySegmentsOk);
    out.segmentBoundaries = ExtractIntArray(json, "segmentBoundaries", segmentBoundariesOk);
    out.pinyinCombinations = ExtractStringArray(json, "pinyinCombinations", pinyinCombinationsOk);
    out.candidates = ExtractFormalCandidates(json, candidatesOk);

    const std::string actionToken = "\"action\":";
    const size_t actionStart = json.find(actionToken);
    if (actionStart == std::string::npos) {
        return false;
    }
    const size_t actionValueStart = actionStart + actionToken.length();
    if (json.compare(actionValueStart, 4, "null") == 0) {
        out.hasAction = false;
    } else {
        const size_t objectStart = json.find('{', actionValueStart);
        const size_t objectEnd = json.find('}', objectStart);
        if (objectStart != actionValueStart || objectEnd == std::string::npos) {
            return false;
        }
        const std::string actionJson = json.substr(objectStart, objectEnd - objectStart + 1);
        if (!ExtractString(actionJson, "type", out.actionType) ||
            !ExtractString(actionJson, "formatId", out.actionFormatId) ||
            !ExtractString(actionJson, "text", out.actionText) ||
            !ExtractInt(actionJson, "cursorOffsetUtf16", out.actionCursorOffsetUtf16)) {
            return false;
        }
        if (out.actionType == "DATE_TIME_TEXT") {
            if (out.actionText.length() != 0 || out.actionCursorOffsetUtf16 != 0 ||
                (out.actionFormatId != "DATE_ISO" && out.actionFormatId != "DATE_LOCAL" &&
                 out.actionFormatId != "TIME_HM" && out.actionFormatId != "DATETIME_LOCAL")) {
                return false;
            }
        } else if (out.actionType == "INSERT_PAIR") {
            if (!out.actionFormatId.empty() || out.actionText.empty() || out.actionText.length() > 128 ||
                out.actionCursorOffsetUtf16 <= 0 || out.actionCursorOffsetUtf16 > 16) {
                return false;
            }
        } else if (out.actionType == "REPEAT_COMMIT" || out.actionType == "UNDO_COMMIT" ||
                   out.actionType == "MOVE_LINE_END") {
            if (!out.actionFormatId.empty() || !out.actionText.empty() ||
                out.actionCursorOffsetUtf16 != 0) {
                return false;
            }
        } else {
            return false;
        }
        out.hasAction = true;
    }

    const bool commonValid =
           ExtractBool(json, "success", out.success) && ExtractInt(json, "errorCode", out.errorCode) &&
           ExtractString(json, "errorMessage", out.errorMessage) && ExtractString(json, "rawInput", out.rawInput) &&
           ExtractString(json, "preeditText", out.preeditText) && parsedSyllablesOk && displaySegmentsOk &&
           segmentBoundariesOk && pinyinCombinationsOk &&
           ExtractString(json, "currentPinyin", out.currentPinyin) &&
           ExtractString(json, "pendingCode", out.pendingCode) && ExtractString(json, "parserState", out.parserState) &&
           candidatesOk && ExtractInt(json, "highlightedIndex", out.highlightedIndex) &&
           ExtractBool(json, "hasNextPage", out.hasNextPage) &&
           ExtractBool(json, "hasPreviousPage", out.hasPreviousPage) &&
           ExtractInt(json, "candidatePage", out.candidatePage) &&
           ExtractString(json, "commitText", out.commitText) && ExtractBool(json, "compositionFinished", out.compositionFinished);
    return commonValid && !(out.hasAction && !out.commitText.empty());
}

bool ParseUserModelStatus(const std::string& json, UserModelStatus& out) {
    return ExtractBool(json, "loaded", out.loaded) && ExtractBool(json, "enabled", out.enabled) &&
           ExtractBool(json, "sessionLearningAllowed", out.sessionLearningAllowed) &&
           ExtractBool(json, "dirty", out.dirty) && ExtractInt(json, "recordCount", out.recordCount) &&
           ExtractInt(json, "formatVersion", out.formatVersion) && ExtractInt(json, "dataVersion", out.dataVersion) &&
           ExtractString(json, "lastErrorCode", out.lastErrorCode);
}

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

void SetNamedStringArray(napi_env env, napi_value object, const char* name, const std::vector<std::string>& values) {
    napi_value array = nullptr;
    napi_create_array_with_length(env, values.size(), &array);
    for (size_t index = 0; index < values.size(); ++index) {
        napi_set_element(env, array, index, CreateString(env, values[index]));
    }
    SetNamedProperty(env, object, name, array);
}

void SetNamedIntArray(napi_env env, napi_value object, const char* name, const std::vector<int32_t>& values) {
    napi_value array = nullptr;
    napi_create_array_with_length(env, values.size(), &array);
    for (size_t index = 0; index < values.size(); ++index) {
        napi_value value = nullptr;
        napi_create_int32(env, values[index], &value);
        napi_set_element(env, array, index, value);
    }
    SetNamedProperty(env, object, name, array);
}

void SetEmptyFormalCandidateArray(napi_env env, napi_value object) {
    napi_value candidates = nullptr;
    napi_create_array_with_length(env, 0, &candidates);
    SetNamedProperty(env, object, "candidates", candidates);
}
} // namespace

napi_value CreateString(napi_env env, const std::string& value) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
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

napi_value ConvertEngineJsonToArkObject(napi_env env, const std::string& json) {
    EngineResult result;
    if (!ParseEngineResult(json, result)) {
        return CreateErrorResult(env, IME_SERIALIZATION_ERROR, "Rust returned invalid JSON");
    }

    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetNamedBool(env, object, "success", result.success);
    SetNamedInt(env, object, "errorCode", result.errorCode);
    SetNamedString(env, object, "errorMessage", result.errorMessage);
    SetNamedString(env, object, "rawInput", result.rawInput);
    SetNamedString(env, object, "preeditText", result.preeditText);
    SetNamedString(env, object, "engineVersion", result.engineVersion);

    napi_value candidates = nullptr;
    napi_create_array_with_length(env, result.candidates.size(), &candidates);
    for (size_t index = 0; index < result.candidates.size(); ++index) {
        napi_value candidate = nullptr;
        napi_create_object(env, &candidate);
        SetNamedString(env, candidate, "id", result.candidates[index].id);
        SetNamedString(env, candidate, "text", result.candidates[index].text);
        SetNamedString(env, candidate, "reading", result.candidates[index].reading);
        napi_set_element(env, candidates, index, candidate);
    }
    SetNamedProperty(env, object, "candidates", candidates);
    return object;
}

napi_value ConvertCompositionJsonToArkObject(napi_env env, const std::string& json) {
    CompositionResult result;
    if (!ParseCompositionResult(json, result)) {
        return CreateCompositionErrorResult(env, IME_SERIALIZATION_ERROR, "Rust returned invalid composition JSON");
    }

    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetNamedBool(env, object, "success", result.success);
    SetNamedInt(env, object, "errorCode", result.errorCode);
    SetNamedString(env, object, "errorMessage", result.errorMessage);
    SetNamedString(env, object, "rawInput", result.rawInput);
    SetNamedString(env, object, "preeditText", result.preeditText);
    SetNamedStringArray(env, object, "parsedSyllables", result.parsedSyllables);
    SetNamedStringArray(env, object, "displaySegments", result.displaySegments);
    SetNamedIntArray(env, object, "segmentBoundaries", result.segmentBoundaries);
    SetNamedString(env, object, "currentPinyin", result.currentPinyin);
    SetNamedStringArray(env, object, "pinyinCombinations", result.pinyinCombinations);
    SetNamedString(env, object, "pendingCode", result.pendingCode);
    SetNamedString(env, object, "parserState", result.parserState);

    napi_value candidates = nullptr;
    napi_create_array_with_length(env, result.candidates.size(), &candidates);
    for (size_t index = 0; index < result.candidates.size(); ++index) {
        napi_value candidate = nullptr;
        napi_create_object(env, &candidate);
        SetNamedString(env, candidate, "id", result.candidates[index].id);
        SetNamedString(env, candidate, "text", result.candidates[index].text);
        SetNamedString(env, candidate, "reading", result.candidates[index].reading);
        SetNamedString(env, candidate, "source", result.candidates[index].source);
        napi_set_element(env, candidates, index, candidate);
    }
    SetNamedProperty(env, object, "candidates", candidates);
    SetNamedInt(env, object, "highlightedIndex", result.highlightedIndex);
    SetNamedBool(env, object, "hasNextPage", result.hasNextPage);
    SetNamedBool(env, object, "hasPreviousPage", result.hasPreviousPage);
    SetNamedInt(env, object, "candidatePage", result.candidatePage);
    SetNamedString(env, object, "commitText", result.commitText);
    if (!result.hasAction) {
        napi_value noAction = nullptr;
        napi_get_null(env, &noAction);
        SetNamedProperty(env, object, "action", noAction);
    } else {
        napi_value action = nullptr;
        napi_create_object(env, &action);
        SetNamedString(env, action, "type", result.actionType);
        SetNamedString(env, action, "formatId", result.actionFormatId);
        SetNamedString(env, action, "text", result.actionText);
        SetNamedInt(env, action, "cursorOffsetUtf16", result.actionCursorOffsetUtf16);
        SetNamedProperty(env, object, "action", action);
    }
    SetNamedBool(env, object, "compositionFinished", result.compositionFinished);
    return object;
}

napi_value ConvertUserModelStatusJsonToArkObject(napi_env env, const std::string& json) {
    UserModelStatus status;
    if (!ParseUserModelStatus(json, status)) {
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

    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetNamedBool(env, object, "loaded", status.loaded);
    SetNamedBool(env, object, "enabled", status.enabled);
    SetNamedBool(env, object, "sessionLearningAllowed", status.sessionLearningAllowed);
    SetNamedBool(env, object, "dirty", status.dirty);
    SetNamedInt(env, object, "recordCount", status.recordCount);
    SetNamedInt(env, object, "formatVersion", status.formatVersion);
    SetNamedInt(env, object, "dataVersion", status.dataVersion);
    SetNamedString(env, object, "lastErrorCode", status.lastErrorCode);
    return object;
}
