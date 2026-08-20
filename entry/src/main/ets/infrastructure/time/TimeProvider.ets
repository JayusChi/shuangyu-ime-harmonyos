export interface TimeProvider {
  now(): Date;
}

export class SystemTimeProvider implements TimeProvider {
  now(): Date {
    return new Date();
  }
}
