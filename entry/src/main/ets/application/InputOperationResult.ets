import { ImeErrorCode, imeErrorMessage } from '../common/error/ImeError';

export interface InputOperationResult {
  success: boolean;
  errorCode: ImeErrorCode;
  errorMessage: string;
}

export function inputOperationOk(): InputOperationResult {
  return {
    success: true,
    errorCode: ImeErrorCode.SUCCESS,
    errorMessage: imeErrorMessage(ImeErrorCode.SUCCESS)
  };
}

export function inputOperationFailed(code: ImeErrorCode, message?: string): InputOperationResult {
  return {
    success: false,
    errorCode: code,
    errorMessage: message ?? imeErrorMessage(code)
  };
}
