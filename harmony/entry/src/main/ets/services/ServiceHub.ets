import { tr } from '../model/I18n';
import { common } from '@kit.AbilityKit';
import BuildProfile from 'BuildProfile';
import { SessionService } from './SessionService';
import { MockSessionService } from './MockSessionService';
import { NativeSessionService } from './NativeSessionService';

/**
 * Owns the single service instance. Debug builds use the real native service by
 * default (so QR login and the native bridge can be exercised); UI tests opt in
 * to MockSessionService through useMockForTests/replaceForTests.
 */
export class ServiceHub {
  private static instance: SessionService | null = null;
  private static mockOverride: boolean = false;
  private static errorMessage: string = '';

  static async init(context: common.UIAbilityContext): Promise<SessionService> {
    if (ServiceHub.instance !== null) {
      return ServiceHub.instance;
    }
    ServiceHub.errorMessage = '';
    let service: SessionService | null = null;
    try {
      service = BuildProfile.DEBUG && ServiceHub.mockOverride ? new MockSessionService() : new NativeSessionService();
      await service.init(context);
      ServiceHub.instance = service;
    } catch (error) {
      service?.dispose();
      ServiceHub.instance = null;
      ServiceHub.errorMessage = tr('原生核心初始化失败，请检查安装包与系统版本。');
      throw new Error('Native service initialization failed');
    }
    return ServiceHub.instance;
  }

  static service(): SessionService {
    if (ServiceHub.instance === null) {
      throw new Error('ServiceHub is not initialized');
    }
    return ServiceHub.instance;
  }

  static isReady(): boolean {
    return ServiceHub.instance !== null;
  }

  static hasError(): boolean {
    return ServiceHub.errorMessage.length > 0;
  }

  static error(): string {
    return ServiceHub.errorMessage;
  }

  static useMockForTests(): void {
    if (BuildProfile.DEBUG) {
      ServiceHub.mockOverride = true;
    }
  }

  /** Debug-only: exercise the native bridge instead of the deterministic mock. */
  static useNativeForDebug(): void {
    if (BuildProfile.DEBUG) {
      ServiceHub.mockOverride = false;
    }
  }

  static async replaceForTests(service: SessionService, context: common.UIAbilityContext): Promise<void> {
    if (!BuildProfile.DEBUG) {
      return;
    }
    ServiceHub.instance?.dispose();
    await service.init(context);
    ServiceHub.instance = service;
  }
}
