export enum ImeErrorCode {
  SUCCESS = 0,
  INVALID_ARGUMENT = 1001,
  INVALID_HANDLE = 1002,
  UNSUPPORTED_OPERATION = 1003,
  INVALID_UTF8 = 1004,
  SERIALIZATION_ERROR = 1005,
  BUFFER_ALLOCATION_FAILED = 1006,
  ENGINE_NOT_INITIALIZED = 1007,
  ENGINE_INTERNAL_ERROR = 1008,
  NATIVE_BRIDGE_ERROR = 1009,
  ABI_VERSION_MISMATCH = 1010,
  INVALID_CONFIG = 1011,
  INVALID_SCHEME = 1012,
  LEXICON_NOT_FOUND = 1013,
  LEXICON_LOAD_FAILED = 1014,
  INVALID_PAGE = 1015,
  INVALID_CANDIDATE = 1016,
  UNKNOWN_ERROR = 1099
}

export interface ImeError {
  code: ImeErrorCode;
  message: string;
  layer: string;
}

export function imeErrorMessage(code: number): string {
  switch (code) {
    case ImeErrorCode.SUCCESS:
      return 'success';
    case ImeErrorCode.INVALID_ARGUMENT:
      return 'invalid argument';
    case ImeErrorCode.INVALID_HANDLE:
      return 'invalid handle';
    case ImeErrorCode.UNSUPPORTED_OPERATION:
      return 'unsupported operation';
    case ImeErrorCode.INVALID_UTF8:
      return 'invalid utf-8';
    case ImeErrorCode.SERIALIZATION_ERROR:
      return 'serialization error';
    case ImeErrorCode.BUFFER_ALLOCATION_FAILED:
      return 'buffer allocation failed';
    case ImeErrorCode.ENGINE_NOT_INITIALIZED:
      return 'engine not initialized';
    case ImeErrorCode.ENGINE_INTERNAL_ERROR:
      return 'engine internal error';
    case ImeErrorCode.NATIVE_BRIDGE_ERROR:
      return 'native bridge error';
    case ImeErrorCode.ABI_VERSION_MISMATCH:
      return 'abi version mismatch';
    case ImeErrorCode.INVALID_CONFIG:
      return 'invalid config';
    case ImeErrorCode.INVALID_SCHEME:
      return 'invalid scheme';
    case ImeErrorCode.LEXICON_NOT_FOUND:
      return 'lexicon not found';
    case ImeErrorCode.LEXICON_LOAD_FAILED:
      return 'lexicon load failed';
    case ImeErrorCode.INVALID_PAGE:
      return 'invalid candidate page';
    case ImeErrorCode.INVALID_CANDIDATE:
      return 'invalid candidate';
    default:
      return 'unknown error';
  }
}
