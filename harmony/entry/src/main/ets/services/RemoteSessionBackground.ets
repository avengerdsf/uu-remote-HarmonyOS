import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { tr } from '../model/I18n';

const NO_TASK = -1;

/** Holds system resources for the lifetime of a remote desktop session. */
export class RemoteSessionBackground {
  private generation: number = -1;
  private activeGeneration: number = -1;
  private connected: boolean = false;
  private audioPlaying: boolean = false;
  private deviceName: string = '';
  private queue: Promise<void> = Promise.resolve();
  private media: avSession.AVSession | null = null;
  private mediaConnected: boolean | null = null;
  private mediaTitle: string = '';
  private launchAgent: WantAgent | null = null;
  private linkTask: number = NO_TASK;
  private audioTask: number = NO_TASK;
  private linkRequested: boolean = false;
  private audioRequested: boolean = false;
  private mediaRequested: boolean = false;
  private listening: boolean = false;
  private context: common.UIAbilityContext;
  private onCancel = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    const kind = info.id === this.linkTask ? 'link' : 'audio';
    if (info.id === this.linkTask) { this.linkTask = NO_TASK; }
    else if (info.id === this.audioTask) { this.audioTask = NO_TASK; }
    else { return; }
    console.info('UU_BG_REMOTE cancelled task=' + kind + ' reason=' + info.reason + ' detail=' + info.detailedReason);
  };

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  update(generation: number, connected: boolean, audioPlaying: boolean, deviceName: string = ''): void {
    if (this.generation === generation && this.connected === connected && this.audioPlaying === audioPlaying &&
      this.deviceName === deviceName) { return; }
    this.generation = generation;
    this.connected = connected;
    this.audioPlaying = audioPlaying;
    this.deviceName = deviceName;
    this.queue = this.queue.then(() => this.reconcile()).catch((error: BusinessError) => {
      this.logFailure('update', error);
    });
  }

  private async reconcile(): Promise<void> {
    const generation = this.generation;
    if (this.activeGeneration !== generation) {
      await this.clear();
      this.activeGeneration = generation;
    }
    if (generation < 0 || generation !== this.generation) { return; }
    if (this.launchAgent === null) {
      const ability = this.context.abilityInfo;
      this.launchAgent = await wantAgent.getWantAgent({
        wants: [{ bundleName: ability.bundleName, abilityName: ability.name, moduleName: ability.moduleName }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
    }
    if (generation !== this.generation) { return; }
    if (!this.linkRequested) {
      this.linkRequested = true;
      this.linkTask = await this.startTask(false, this.launchAgent);
    }
    if (generation !== this.generation) { return; }
    if ((this.connected || this.audioPlaying) && !this.mediaRequested) {
      this.mediaRequested = true;
      await this.startMedia(this.launchAgent);
    }
    if (generation !== this.generation) { return; }
    const connected = this.connected;
    const audioPlaying = this.audioPlaying;
    if (this.media !== null) { await this.updateTitle(this.media); }
    if (this.media !== null && connected !== this.mediaConnected) {
      await this.media.setAVPlaybackState({ state: connected ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_BUFFERING });
      this.mediaConnected = connected;
    }
    if (audioPlaying && this.media !== null && !this.audioRequested) {
      this.audioRequested = true;
      this.audioTask = await this.startTask(true, this.launchAgent);
    } else if (!audioPlaying) {
      this.audioRequested = false;
      const id = this.audioTask;
      this.audioTask = NO_TASK;
      await this.stopTask(id);
    }
  }

  private async startMedia(agent: WantAgent): Promise<void> {
    let media: avSession.AVSession | null = null;
    try {
      media = await avSession.createAVSession(this.context, 'UU Remote', deviceInfo.sdkApiVersion >= 24 ? 'video' : 'audio');
      if (deviceInfo.sdkApiVersion >= 24) {
        await media.setBackgroundPlayMode(avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY);
      }
      await this.updateTitle(media);
      await media.setLaunchAbility(agent);
      await media.activate();
      this.media = media;
      console.info('UU_BG_REMOTE media active');
    } catch (error) {
      await media?.destroy().catch(() => {});
      this.logFailure('media', error as BusinessError);
    }
  }

  private async updateTitle(media: avSession.AVSession): Promise<void> {
    const name = this.deviceName.trim();
    const title = name || tr('远程控制');
    if (title === this.mediaTitle) { return; }
    await media.setAVMetadata({ assetId: 'uu-remote-desktop', title: title, artist: name ? tr('远程控制') : '' });
    this.mediaTitle = title;
  }

  private async startTask(audio: boolean, agent: WantAgent): Promise<number> {
    if (!canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) { return NO_TASK; }
    const kind = audio ? 'audio' : 'link';
    try {
      if (!this.listening) {
        backgroundTaskManager.on('continuousTaskCancel', this.onCancel);
        this.listening = true;
      }
      const request = new backgroundTaskManager.ContinuousTaskRequest();
      request.backgroundTaskModes = [audio ? backgroundTaskManager.BackgroundTaskMode.MODE_AV_PLAYBACK_AND_RECORD :
        backgroundTaskManager.BackgroundTaskMode.MODE_MULTI_DEVICE_CONNECTION];
      request.backgroundTaskSubmodes = [audio ? backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_AVSESSION_AUDIO_PLAYBACK :
        backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_NORMAL_NOTIFICATION];
      request.wantAgent = agent;
      const task = await backgroundTaskManager.startBackgroundRunning(this.context, request);
      console.info('UU_BG_REMOTE task=' + kind + ' id=' + task.continuousTaskId);
      return task.continuousTaskId ?? NO_TASK;
    } catch (error) {
      this.logFailure(kind, error as BusinessError);
      return NO_TASK;
    }
  }

  private async stopTask(id: number): Promise<void> {
    if (id !== NO_TASK) {
      await backgroundTaskManager.stopBackgroundRunning(this.context, id).catch((error: BusinessError) => {
        this.logFailure('stop task', error);
      });
    }
  }

  private async clear(): Promise<void> {
    const link = this.linkTask;
    const audio = this.audioTask;
    const media = this.media;
    this.linkTask = NO_TASK; this.audioTask = NO_TASK; this.media = null;
    this.linkRequested = false; this.audioRequested = false; this.mediaRequested = false; this.mediaConnected = null;
    this.mediaTitle = '';
    await this.stopTask(audio);
    await this.stopTask(link);
    await media?.destroy().catch((error: BusinessError) => { this.logFailure('destroy media', error); });
    if (this.listening) {
      this.listening = false;
      try { backgroundTaskManager.off('continuousTaskCancel', this.onCancel); }
      catch (error) { this.logFailure('cancel listener', error as BusinessError); }
    }
  }

  private logFailure(operation: string, error: BusinessError): void {
    console.warn('UU_BG_REMOTE ' + operation + ' failed code=' + error.code);
  }
}
