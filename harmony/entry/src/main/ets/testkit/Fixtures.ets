import { DeviceInfo, PortMapRule, SessionSnapshot, SessionPhase } from '../model/Models';

/** Fixed data from appendix C (fixtures.json). Synthetic values only. */
export class Fixtures {
  static readonly LONG_DEVICE_NAME: string =
    '实验室用于远程开发和调试的工作站名称测试ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static devices(): DeviceInfo[] {
    return [
      {
        id: 'demo-win-01',
        name: '办公室 Windows',
        platform: 'Windows',
        online: true,
        statusText: '在线 · 可连接',
        capabilities: ['desktop', 'files', 'terminal', 'textInput'],
        connectLabel: '连接'
      },
      {
        id: 'demo-linux-01',
        name: '实验室 Linux',
        platform: 'Linux',
        online: true,
        statusText: '在线 · 可连接',
        capabilities: ['desktop', 'files', 'terminal', 'portmap'],
        connectLabel: '连接'
      },
      {
        id: 'demo-mac-01',
        name: '家中的 Mac',
        platform: 'macOS',
        online: false,
        statusText: '离线',
        capabilities: ['desktop'],
        connectLabel: '设备离线'
      }
    ];
  }

  static onlineDevices(): DeviceInfo[] {
    return Fixtures.devices().filter((d: DeviceInfo) => d.online);
  }

  static longNameDevices(): DeviceInfo[] {
    const list = Fixtures.devices();
    list[0].name = Fixtures.LONG_DEVICE_NAME;
    return list;
  }

  static session(): SessionSnapshot {
    return {
      phase: SessionPhase.Connecting,
      sessionId: 'demo-session-001',
      generation: 1,
      resourceEpoch: 1,
      targetId: 'demo-win-01',
      targetName: '办公室 Windows',
      viewOnly: false,
      firstFrameReceived: false,
      error: null,
      videoWidth: 1920,
      videoHeight: 1080
    };
  }

  static portMapRule(): PortMapRule {
    return {
      id: 'demo-rule-001',
      listenAddress: '127.0.0.1',
      listenPort: 8800,
      targetHost: '127.0.0.1',
      targetPort: 22,
      allowLan: false
    };
  }

  static readonly QR_PAYLOAD: string = 'TEST-ONLY-NOT-A-LOGIN-CREDENTIAL';
  static readonly CONNECT_ID: string = 'demo-partner-id';
  static readonly VERIFY_CODE: string = 'demo-only-code';
}
