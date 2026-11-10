import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { ServiceHub } from '../../../main/ets/services/ServiceHub';
import { SessionService } from '../../../main/ets/services/SessionService';
import { Router } from '../../../main/ets/model/Router';
import { DeviceInfo, DeviceListPhase, FilesSnapshot, SessionPhase } from '../../../main/ets/model/Models';
import { VideoViewport } from '../../../main/ets/model/VideoViewport';

function pause(ms: number): Promise<void> {
  return new Promise<void>((resolve) => { setTimeout(resolve, ms); });
}

async function report(stage: string, service: SessionService): Promise<void> {
  const state = service.sessionSnapshot();
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_LIVE_SESSION ' + JSON.stringify({
    stage: stage, phase: state.phase, generation: state.generation, viewOnly: state.viewOnly,
    firstFrame: state.firstFrameReceived, error: state.error, stats: service.stats()
  }) + '\n');
}

export default function sessionStability(): void {
  const argumentsInfo = abilityDelegatorRegistry.getArguments();
  if (argumentsInfo === null || argumentsInfo === undefined) { return; }
  const args = argumentsInfo.parameters;
  const targetName = args['-s liveTarget'] ?? args['liveTarget'] ?? '';
  // Explicit opt-in only: routine UI tests must never connect an account device.
  if (targetName.length === 0) { return; }
  let service: SessionService;
  let target: DeviceInfo;
  describe('SessionStability', () => {
    beforeAll(async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.uu.remote.harmony', moduleName: 'entry', abilityName: 'EntryAbility' });
      for (let index = 0; index < 100 && !ServiceHub.isReady(); index++) { await pause(200); }
      expect(ServiceHub.isReady()).assertTrue();
      service = ServiceHub.service();
      expect(service.kind).assertEqual('native');
      const deviceGeneration = service.devicesSnapshot().generation;
      await service.listDevices();
      for (let index = 0; index < 100 && (service.devicesSnapshot().generation <= deviceGeneration ||
        service.devicesSnapshot().phase === DeviceListPhase.Loading); index++) { await pause(200); }
      expect(service.devicesSnapshot().generation > deviceGeneration).assertTrue();
      const matches = service.devicesSnapshot().devices.filter((device: DeviceInfo) => device.name === targetName);
      await delegator.print('UU_LIVE_TARGET ' + JSON.stringify({
        phase: service.devicesSnapshot().phase, matches: matches.length,
        online: matches[0]?.online ?? false, busy: matches[0]?.busy ?? null
      }) + '\n');
      expect(matches.length).assertEqual(1);
      target = matches[0];
      expect(target.online).assertTrue();
    });
    it('readonly_connection_and_takeover', 0, async () => {
      if ((args['-s liveProbe'] ?? args['liveProbe']) === 'true') { return; }
      const force = (args['-s liveForce'] ?? args['liveForce']) === 'true';
      const allowBusy = (args['-s liveAllowBusy'] ?? args['liveAllowBusy']) === 'true';
      const controlProbe = (args['-s liveControlProbe'] ?? args['liveControlProbe']) === 'true';
      const expectRelease = (args['-s liveExpectRelease'] ?? args['liveExpectRelease']) === 'true';
      const holdMs = Math.max(10000, Math.min(300000, Number(args['-s liveHoldMs'] ?? args['liveHoldMs'] ?? '60000')));
      const originalViewOnly: boolean = service.sessionSnapshot().viewOnly;
      const originalKeepScreenOn: boolean = service.settings().keepScreenOn;
      let opened = false;
      try {
        // A force request is supplied only when another test owns this target.
        if (!force && !allowBusy) { expect(target.busy === true).assertFalse(); }
        const previousGeneration = service.sessionSnapshot().generation;
        await service.setKeepScreenOn(true);
        await service.setViewOnly(true);
        await service.connect(target.id, force);
        opened = true;
        Router.reset('session');
        const started = Date.now();
        while (Date.now() - started < 45000) {
          const state = service.sessionSnapshot();
          if (state.generation > previousGeneration) {
            if (state.phase === SessionPhase.Ended) { await report('connect-failed', service); throw new Error('Live connection ended before first frame'); }
            if (state.firstFrameReceived && service.stats().framesRendered > 0) { break; }
          }
          await pause(200);
        }
        await report('ready', service);
        expect(service.sessionSnapshot().firstFrameReceived).assertTrue();
        expect(service.sessionSnapshot().viewOnly).assertTrue();
        expect(service.stats().framesRendered > 0).assertTrue();
        if (controlProbe) {
          await pause(3000);
          await service.setViewOnly(false);
          for (let index = 0; index < 30 && service.sessionSnapshot().viewOnly; index++) { await pause(100); }
          expect(service.sessionSnapshot().viewOnly).assertFalse();
          const tap = async (scan: number): Promise<void> => {
            await service.sendInput(JSON.stringify({ action: 'key', scan: scan, down: true }));
            await service.sendInput(JSON.stringify({ action: 'key', scan: scan, down: false }));
          };
          const baseline = service.stats().inputMessages ?? 0;
          try {
            await tap(41); await pause(300);
            await tap(227); await pause(1500);
            const delegator = abilityDelegatorRegistry.getAbilityDelegator();
            const path = delegator.getAppContext().cacheDir + '/takeover-start-menu.png';
            expect(await Driver.create().screenCap(path)).assertTrue();
            await delegator.print('UU_LIVE_CAPTURE ' + JSON.stringify({ stage: 'takeover-start-menu', path: path }) + '\n');
            await report('takeover-control', service);
          } finally {
            await tap(41); await service.releaseAllInput(); await service.setViewOnly(true);
          }
          await pause(2000);
          expect((service.stats().inputMessages ?? 0) >= baseline + 6).assertTrue();
        }
        const heldInputMessages = service.stats().inputMessages ?? 0;
        if (!controlProbe) { expect(heldInputMessages).assertEqual(0); }
        const until = Date.now() + holdMs;
        let lastFrames = service.stats().framesRendered;
        let lastProgress = Date.now();
        let maxFrameGapMs = 0;
        let lastReport = 0;
        while (Date.now() < until) {
          const state = service.sessionSnapshot();
          if (state.phase === SessionPhase.Ended) {
            await report('released', service);
            expect(expectRelease).assertTrue();
            await pause(3000);
            expect(service.sessionSnapshot().phase).assertEqual(SessionPhase.Ended);
            return;
          }
          expect(state.viewOnly).assertTrue();
          expect(service.stats().inputMessages ?? 0).assertEqual(heldInputMessages);
          const frames = service.stats().framesRendered;
          maxFrameGapMs = Math.max(maxFrameGapMs, Date.now() - lastProgress);
          if (frames > lastFrames) { lastFrames = frames; lastProgress = Date.now(); }
          if (Date.now() - lastReport >= 5000) { await report('holding', service); lastReport = Date.now(); }
          if (Date.now() - lastProgress > 15000) { throw new Error('No rendered frame progress for 15 seconds'); }
          await pause(250);
        }
        expect(expectRelease).assertFalse();
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_LIVE_OUTPUT_GAP ' + JSON.stringify({
          maxSampledGapMs: maxFrameGapMs, holdMs: holdMs, decoderResets: service.stats().decoderResets }) + '\n');
        await report('stable', service);
      } finally {
        if (opened) {
          await service.disconnect();
          await pause(2000);
          await report('disconnected', service);
        }
        Router.reset('devices');
        await service.setViewOnly(originalViewOnly);
        await service.setKeepScreenOn(originalKeepScreenOn);
      }
    });
    if ((args['-s liveFiles'] ?? args['liveFiles']) === 'true') {
      it('remote_root_and_child_directories_load', 0, async () => {
        const originalViewOnly: boolean = service.sessionSnapshot().viewOnly;
        let completed = false;
        let files: FilesSnapshot = service.filesSnapshot();
        const unsubscribe = service.onFiles((snapshot: FilesSnapshot) => {
          files = snapshot; completed = snapshot.phase !== 'loading';
        });
        try {
          await service.selectTarget(target.id);
          await service.openFiles(':/');
          const loading = Date.now();
          while (!completed && Date.now() - loading < 45000) { await pause(200); }
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_LIVE_FILES ' + JSON.stringify({
            stage: 'root', completed: completed, phase: files.phase, entries: files.entries.length, error: files.error,
            desktopPhase: service.sessionSnapshot().phase, frames: service.stats().framesRendered }) + '\n');
          expect(completed).assertTrue(); expect(files.phase).assertEqual('ready'); expect(files.error).assertEqual(null);
          expect(files.entries.length > 0).assertTrue();
          const folder = files.entries.find((entry) => entry.isDirectory);
          expect(folder !== undefined).assertTrue();
          completed = false; await service.openFiles(folder!.path);
          const child = Date.now();
          while (!completed && Date.now() - child < 45000) { await pause(200); }
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_LIVE_FILES ' + JSON.stringify({
            stage: 'child', completed: completed, phase: files.phase, entries: files.entries.length, error: files.error }) + '\n');
          expect(completed).assertTrue(); expect(files.phase).assertEqual('ready'); expect(files.error).assertEqual(null);
        } finally {
          unsubscribe();
          const closing = Date.now();
          await service.disconnect();
          expect(service.sessionSnapshot().phase).assertEqual(SessionPhase.Ended);
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_LIVE_TOOLS_CLOSED ' + JSON.stringify({
            elapsedMs: Date.now() - closing, phase: service.sessionSnapshot().phase }) + '\n');
          if ((args['-s liveObserveRelease'] ?? args['liveObserveRelease']) === 'true') {
            const deadline = Date.now() + 15000;
            let available = false;
            while (Date.now() < deadline) {
              const generation = service.devicesSnapshot().generation;
              await service.listDevices();
              const requested = Date.now();
              while ((service.devicesSnapshot().generation <= generation ||
                service.devicesSnapshot().phase === DeviceListPhase.Loading) && Date.now() - requested < 3000) {
                await pause(50);
              }
              const snapshot = service.devicesSnapshot();
              const current = snapshot.devices.find((device: DeviceInfo) => device.id === target.id);
              const fresh = snapshot.generation > generation && snapshot.phase === DeviceListPhase.Ready;
              await abilityDelegatorRegistry.getAbilityDelegator().print('UU_LIVE_RELEASE ' + JSON.stringify({
                elapsedMs: Date.now() - closing, fresh: fresh, phase: snapshot.phase, online: current?.online ?? null,
                busy: current?.busy ?? null }) + '\n');
              available = fresh && current?.online === true && current?.busy === false;
              if (available) { break; }
              await pause(1000);
            }
            expect(available).assertTrue();
          }
          Router.reset('devices');
          await service.setViewOnly(originalViewOnly);
        }
      });
    }
    if ((args['-s liveRepeat'] ?? args['liveRepeat']) === 'true') {
      it('repeated_connections_release_the_previous_session', 0, async () => {
        const originalViewOnly: boolean = service.sessionSnapshot().viewOnly;
        const originalKeepScreenOn: boolean = service.settings().keepScreenOn;
        try {
          await service.setKeepScreenOn(true);
          for (let round = 1; round <= 3; round++) {
            const generation = service.sessionSnapshot().generation;
            await service.setViewOnly(true); await service.connect(target.id, false);
            Router.reset('session');
            const started = Date.now();
            while (Date.now() - started < 45000) {
              const state = service.sessionSnapshot();
              if (state.generation > generation && state.phase === SessionPhase.Ended) {
                await report('reconnect-failed-' + round, service); throw new Error('Repeated connection ended before first frame');
              }
              if (state.generation > generation && state.firstFrameReceived && service.stats().framesRendered > 0) { break; }
              await pause(200);
            }
            expect(service.sessionSnapshot().firstFrameReceived).assertTrue();
            expect(service.sessionSnapshot().viewOnly).assertTrue();
            await report('reconnect-ready-' + round, service);
            const frames = service.stats().framesRendered;
            await pause(15000);
            expect(service.sessionSnapshot().phase === SessionPhase.Ended).assertFalse();
            expect(service.stats().framesRendered > frames).assertTrue();
            expect(service.stats().inputMessages ?? 0).assertEqual(0);
            await service.disconnect(); await pause(2000);
            expect(service.sessionSnapshot().phase).assertEqual(SessionPhase.Ended);
            const packets = service.stats().mediaPackets;
            await pause(1000); expect(service.stats().mediaPackets).assertEqual(packets);
            await report('reconnect-closed-' + round, service); Router.reset('devices');
          }
        } finally {
          await service.disconnect(); await pause(2000); Router.reset('devices');
          await service.setViewOnly(originalViewOnly); await service.setKeepScreenOn(originalKeepScreenOn);
        }
      });
    }
    if ((args['-s liveInput'] ?? args['liveInput']) === 'true') {
      it('real_windows_input_effects', 0, async () => {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        const driver = Driver.create();
        const original = service.settings();
        const originalViewOnly = service.sessionSnapshot().viewOnly;
        const key = async (scan: number, down: boolean): Promise<void> => {
          await service.sendInput(JSON.stringify({ action: 'key', scan: scan, down: down }));
        };
        const tapKey = async (scan: number): Promise<void> => { await key(scan, true); await key(scan, false); };
        const capture = async (stage: string): Promise<void> => {
          await pause(1500);
          const path = delegator.getAppContext().cacheDir + '/real-windows-' + stage + '.png';
          expect(await driver.screenCap(path)).assertTrue();
          await delegator.print('UU_LIVE_CAPTURE ' + JSON.stringify({ stage: stage, path: path }) + '\n');
          await report(stage, service);
        };
        const move = async (x: number, y: number): Promise<void> => {
          await service.sendInput(JSON.stringify({ action: 'mouse_move_absolute', abs_x: x, abs_y: y }));
        };
        let opened = false;
        try {
          expect(target.busy === true).assertFalse();
          await service.setKeepScreenOn(true); await service.setTouchMode('direct'); await service.setViewOnly(true);
          const generation = service.sessionSnapshot().generation;
          await service.connect(target.id, false); opened = true; Router.reset('session');
          const deadline = Date.now() + 45000;
          while (Date.now() < deadline && !(service.sessionSnapshot().generation > generation &&
            service.sessionSnapshot().firstFrameReceived && service.stats().framesRendered > 0)) {
            if (service.sessionSnapshot().generation > generation && service.sessionSnapshot().phase === SessionPhase.Ended) {
              throw new Error('Real Windows input connection ended before first frame');
            }
            await pause(200);
          }
          expect(service.sessionSnapshot().firstFrameReceived).assertTrue();
          await service.setViewOnly(false);
          for (let index = 0; index < 30 && service.sessionSnapshot().viewOnly; index++) { await pause(100); }
          expect(service.sessionSnapshot().viewOnly).assertFalse();
          await capture('desktop-before');
          // The known Windows test desktop has its centered Start button at this normalized point.
          const surface = await (await driver.findComponent(ON.id('session.video'))).getBounds();
          const session = service.sessionSnapshot();
          const fit = VideoViewport.fit(surface.right - surface.left, surface.bottom - surface.top,
            session.videoWidth, session.videoHeight);
          await driver.click(Math.round(surface.left + fit[0] + fit[2] * 0.454),
            Math.round(surface.top + fit[1] + fit[3] * 0.984));
          await capture('touch-start'); await tapKey(41); await pause(800);
          await move(0.76, 0.35);
          await pause(300);
          await service.sendInput(JSON.stringify({ action: 'mouse_click', button: 2 }));
          await capture('right-click'); await tapKey(41);
          await service.sendInput(JSON.stringify({ action: 'mouse_press', button: 2 }));
          await service.sendInput(JSON.stringify({ action: 'mouse_release', button: 2 }));
          await capture('right-press-release'); await tapKey(41);
          await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await pause(800);
          await (await driver.findComponent(ON.id('session.mouse.button.2'))).click();
          await capture('virtual-right-click'); await tapKey(41);
          await (await driver.findComponent(ON.id('session.mouse.collapse'))).click(); await pause(600);
          await move(0.70, 0.30);
          await service.sendInput(JSON.stringify({ action: 'mouse_press', button: 1 }));
          for (let step = 1; step <= 8; step++) {
            await move(0.70 + step * 0.02, 0.30 + step * 0.025); await pause(70);
          }
          await capture('drag-held');
          await service.sendInput(JSON.stringify({ action: 'mouse_release', button: 1 }));
          await key(227, true); await tapKey(21); await key(227, false);
          await pause(800); await key(224, true); await tapKey(4); await key(224, false);
          await service.sendText('uu interoperability check');
          await capture('text-entry');
          await key(224, true); await tapKey(4); await key(224, false); await tapKey(42); await tapKey(41);
          await service.releaseAllInput(); await service.setViewOnly(true);
          for (let index = 0; index < 30 && !service.sessionSnapshot().viewOnly; index++) { await pause(100); }
          expect(service.sessionSnapshot().viewOnly).assertTrue();
          await pause(3000);
          const blocked = service.stats().inputMessages ?? 0;
          await tapKey(227); await capture('readonly-blocked');
          expect(service.stats().inputMessages ?? 0).assertEqual(blocked);
        } finally {
          if (opened) { await service.releaseAllInput(); await service.disconnect(); }
          Router.reset('devices'); await service.setViewOnly(originalViewOnly);
          await service.setTouchMode(original.touchMode); await service.setKeepScreenOn(original.keepScreenOn);
        }
      });
      it('input_commands_reach_live_session_and_restore_readonly', 0, async () => {
        const force: boolean = (args['-s liveForce'] ?? args['liveForce']) === 'true';
        const originalViewOnly: boolean = service.sessionSnapshot().viewOnly;
        const originalKeepScreenOn: boolean = service.settings().keepScreenOn;
        let opened = false;
        try {
          if (!force) { expect(target.busy === true).assertFalse(); }
          const previousGeneration = service.sessionSnapshot().generation;
          await service.setKeepScreenOn(true);
          await service.setViewOnly(true);
          await service.connect(target.id, force);
          opened = true;
          Router.reset('session');
          const started = Date.now();
          while (Date.now() - started < 45000) {
            const state = service.sessionSnapshot();
            if (state.generation > previousGeneration && state.firstFrameReceived && service.stats().framesRendered > 0) { break; }
            if (state.generation > previousGeneration && state.phase === SessionPhase.Ended) { throw new Error('Live input session ended before first frame'); }
            await pause(200);
          }
          expect(service.sessionSnapshot().firstFrameReceived).assertTrue();
          expect(service.sessionSnapshot().viewOnly).assertTrue();
          await report('input-before', service);
          await pause(15000);
          await service.setViewOnly(false);
          for (let index = 0; index < 30 && service.sessionSnapshot().viewOnly; index++) { await pause(100); }
          expect(service.sessionSnapshot().viewOnly).assertFalse();
          const baseline = service.stats().inputMessages ?? 0;
          await service.sendInput(JSON.stringify({ action: 'mouse_move_absolute', abs_x: 0.4, abs_y: 0.45 }));
          await pause(500);
          await service.sendInput(JSON.stringify({ action: 'mouse_move_absolute', abs_x: 0.6, abs_y: 0.45 }));
          await report('input-pointer', service);
          await pause(15000);
          await service.sendInput(JSON.stringify({ action: 'key', scan: 227, down: true }));
          await service.sendInput(JSON.stringify({ action: 'key', scan: 227, down: false }));
          await pause(1500);
          await report('input-active', service);
          await pause(30000);
          await service.sendInput(JSON.stringify({ action: 'key', scan: 41, down: true }));
          await service.sendInput(JSON.stringify({ action: 'key', scan: 41, down: false }));
          await pause(3000);
          await report('input-restored', service);
          expect((service.stats().inputMessages ?? 0) >= baseline + 6).assertTrue();
          await service.releaseAllInput();
          await service.setViewOnly(true);
          for (let index = 0; index < 30 && !service.sessionSnapshot().viewOnly; index++) { await pause(100); }
          expect(service.sessionSnapshot().viewOnly).assertTrue();
          await pause(3000);
          const blocked = service.stats().inputMessages ?? 0;
          await service.sendInput(JSON.stringify({ action: 'mouse_move_absolute', abs_x: 0.5, abs_y: 0.45 }));
          await pause(3000);
          expect(service.stats().inputMessages ?? 0).assertEqual(blocked);
          expect(service.sessionSnapshot().phase === SessionPhase.Ended).assertFalse();
          await report('input-readonly-blocked', service);
        } finally {
          if (opened) {
            await service.releaseAllInput();
            await service.disconnect();
            await pause(2000);
            await report('disconnected', service);
          }
          Router.reset('devices');
          await service.setViewOnly(originalViewOnly);
          await service.setKeepScreenOn(originalKeepScreenOn);
        }
      });
    }
  });
}
