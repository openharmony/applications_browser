// 简单日志占位实现；后续按需替换为更完善的日志能力。

export enum LogLevel {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error',
}

export class Logger {
  private tag: string;

  constructor(tag: string) {
  this.tag = tag;
}

  debug(message: string): void {
    this.log(LogLevel.DEBUG, message);
  }

  info(message: string): void {
    this.log(LogLevel.INFO, message);
  }

  warn(message: string): void {
    this.log(LogLevel.WARN, message);
  }

  error(message: string): void {
    this.log(LogLevel.ERROR, message);
  }

  private log(level: LogLevel, message: string): void {
    // 占位：后续可接入系统日志能力。
    console.log(`[${level}] [${this.tag}] ${message}`);
  }
}
