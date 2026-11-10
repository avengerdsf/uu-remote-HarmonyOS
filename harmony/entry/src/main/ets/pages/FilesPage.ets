import { tr } from '../model/I18n';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { ToolPageShell } from '../components/ToolPageShell';
import { iconResource } from '../model/Icons';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { FileEntry, FilesSnapshot, SessionPhase, SessionSnapshot, TransferInfo } from '../model/Models';
import { Router } from '../model/Router';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { IconView } from '../components/IconView';
import { StatusView } from '../components/StatusView';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { ImmersiveBackdrop } from '../components/ImmersiveBackdrop';
import { UiProbe } from '../testkit/UiProbe';
import { edgeScrollBar } from '../components/EdgeScrollBar';

@Component
export struct FilesPage {
  private directoryScroller: Scroller = new Scroller();
  private transferScroller: Scroller = new Scroller();
  @State files: FilesSnapshot = {
    phase: 'loading',
    path: ':/',
    entries: [],
    transfers: [],
    error: null
  };
  @State session: SessionSnapshot = {
    phase: SessionPhase.Ended,
    sessionId: '',
    generation: 0,
    resourceEpoch: 0,
    targetId: '',
    targetName: '',
    viewOnly: false,
    firstFrameReceived: false,
    error: null,
    videoWidth: 0,
    videoHeight: 0
  };
  @State uploadVisible: boolean = false;
  @State newFolderOpen: boolean = false;
  @State folderName: string = '';
  @StorageProp('currentWidthBreakpoint') widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;
  @StorageProp('isDark') isDark: boolean = false;
  @State pendingRemote: string = '';
  @State pendingUri: string = '';
  private service: SessionService | null = null;
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) {
      return;
    }
    this.service = ServiceHub.service();
    this.session = this.service.sessionSnapshot();
    this.files = this.service.filesSnapshot();
    this.unsubscribe = this.service.onFiles((snapshot: FilesSnapshot) => {
      this.files = snapshot;
    });
    this.service.openFiles(this.files.path);
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  private async pickUpload(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await documentPicker.select(options);
      if (uris.length > 0) {
        this.pendingUri = uris[0];
        this.pendingRemote = this.joinPath(this.files.path, decodeURIComponent(this.pendingUri.split('/').pop() ?? 'upload.bin')); 
        this.uploadVisible = true;
      }
    } catch (error) {
      this.files = {
        phase: this.files.phase,
        path: this.files.path,
        entries: this.files.entries,
        transfers: this.files.transfers,
        error: tr('无法打开文件选择器')
      };
    }
  }

  private async pickDownload(entry: FileEntry): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      let uris: string[] = [];
      if (entry.isDirectory) {
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = 1;
        options.selectMode = picker.DocumentSelectMode.FOLDER;
        uris = await documentPicker.select(options);
      } else {
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [entry.name];
        uris = await documentPicker.save(options);
      }
      if (uris.length > 0) {
        this.service?.startTransfer(entry.path, uris[0], false);
      }
    } catch (error) {
      this.files = {
        phase: this.files.phase,
        path: this.files.path,
        entries: this.files.entries,
        transfers: this.files.transfers,
        error: tr('无法打开保存位置选择器')
      };
    }
  }

  private joinPath(parent: string, name: string): string {
    const separator = parent.includes('\\') ? '\\' : '/';
    return parent.replace(/[\\/]$/, '') + separator + name;
  }
  private goUp(): void {
    const path = this.files.path.replace(/[\\/]$/, '');
    const cut = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    this.service?.openFiles(cut < 0 ? ':/' : path.slice(0, cut + 1));
  }
  private async createFolder(): Promise<void> {
    const name = this.folderName.trim();
    if (name.length === 0 || name === '.' || name === '..' || /[\\/\u0000-\u001f]/.test(name)) { return; }
    try {
      await this.service?.mkdir(this.joinPath(this.files.path, name));
      this.folderName = ''; this.newFolderOpen = false;
    } catch (error) { this.getUIContext().getPromptAction().showToast({ message: (error as Error).message }); }
  }
  private menus(): HdsNavigationMenuItemOptions[] {
    return [
      { content: { label: tr('上传文件'), icon: iconResource('folder', this.isDark, false), componentId: 'files.upload', action: () => { this.pickUpload(); } } },
      { content: { label: tr('新建文件夹'), icon: iconResource('more', this.isDark, false), componentId: 'files.mkdir', action: () => { this.newFolderOpen = !this.newFolderOpen; } } },
      { content: { label: tr('刷新'), icon: iconResource('refresh', this.isDark, false), componentId: 'files.refresh', action: () => { this.service?.openFiles(this.files.path); } } }
    ];
  }

  @Builder
  listRow(entry: FileEntry) {
    Row({ space: 12 }) {
      IconView({ iconKey: entry.isDirectory ? 'folder' : 'check', selected: false, sizeVp: 24, allowImageDrag: !entry.isDirectory })
      Column({ space: 2 }) {
        Text(entry.name)
          .fontSize(16)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!entry.isDirectory) {
          Text(`${entry.sizeBytes} B`)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button(tr('下载'), { type: ButtonType.Capsule })
          .height(48)
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .backgroundColor(Color.Transparent)
          .id(`files.download.${entry.name}`)
          .onClick(() => {
            this.pickDownload(entry);
          })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (entry.isDirectory) {
        this.service?.openFiles(entry.path);
      }
    })
  }

  @Builder
  transfers() {
    if (this.files.transfers.length > 0) {
      Column({ space: 8 }) {
        Text(tr('传输'))
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
        ForEach(this.files.transfers, (transfer: TransferInfo) => {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(transfer.name)
                .fontSize(14)
                .fontColor($r('app.color.primary_text'))
                .maxLines(1)
              Progress({ value: transfer.transferredBytes, total: Math.max(transfer.totalBytes, 1) })
                .width('100%')
                .height(4)
                .color($r('app.color.primary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(transfer.state).fontSize(12).fontColor($r('app.color.secondary_text'))
            if (transfer.state === 'running') {
            Button(tr('取消'), { type: ButtonType.Capsule })
              .height(48)
              .fontSize(14)
              .fontColor($r('app.color.error_text'))
              .backgroundColor(Color.Transparent)
              .id(`transfer.${transfer.id}.cancel`)
              .onClick(() => {
                this.service?.cancelTransfer(transfer.id);
              })
            }
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.glass_input'))
          .border({ width: 1, color: $r('app.color.glass_stroke') })
          .borderRadius($r('sys.float.corner_radius_level8'))
        }, (transfer: TransferInfo) => transfer.id)
      }
      .width('100%')
      .padding(16)
      .id('files.transfers')
    }
  }

  @Builder
  directoryList() {
    Column() {
      if (this.files.phase === 'loading') { StatusView({ text: tr('正在加载目录…'), loading: true }) }
      else if (this.files.entries.length === 0) { StatusView({ text: this.files.error === null ? tr('空目录') : tr('无法读取目录'), detail: this.files.error ?? '' }) }
      else {
        Stack({ alignContent: Alignment.End }) {
        List({ scroller: this.directoryScroller }) {
          ForEach(this.files.entries, (entry: FileEntry) => {
            ListItem() { this.listRow(entry) }.padding({ left: 16, right: 16 })
          }, (entry: FileEntry) => entry.path)
        }.width('100%').height('100%').scrollBar(BarState.Off)
          .divider({ strokeWidth: 1, color: $r('sys.color.comp_divider') }).id('files.list')
          edgeScrollBar(this.directoryScroller, 'files.list')
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%')
  }

  @Builder
  transferScroll(sidebar: boolean) {
    Scroll(this.transferScroller) { this.transfers() }.width('100%').height(sidebar ? '100%' : undefined)
      .constraintSize({ maxHeight: sidebar ? undefined : 200 })
      .scrollBar(BarState.Off).id('files.transfers.scroll')
  }

  build() {
    Stack() {
      ToolPageShell({ title: tr('远端文件'), menus: this.menus(), scroller: this.directoryScroller }) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Button(tr('上级'), { type: ButtonType.Capsule }).onClick(() => { this.goUp(); }).id('files.up')
            TextInput({ text: this.files.path, placeholder: tr('远端目录') }).layoutWeight(1)
              .onSubmit((type: EnterKeyType, event: SubmitEvent) => { this.service?.openFiles(event.text); }).id('files.path')
            Button(tr('主目录'), { type: ButtonType.Capsule }).onClick(() => { this.service?.openFiles('~/'); })
          }.width('100%').padding({ left: 16, right: 16, top: 12 })
          if (this.newFolderOpen) {
            Row({ space: 8 }) {
              TextInput({ text: this.folderName, placeholder: tr('文件夹名称') }).layoutWeight(1)
                .onChange((value: string) => { this.folderName = value; })
                .onSubmit(() => { this.createFolder(); }).id('files.folderName')
              Button(tr('创建'), { type: ButtonType.Capsule }).onClick(() => { this.createFolder(); }).id('files.createFolder')
            }.padding({ left: 16, right: 16 }).width('100%')
          }
          Row() {
            Column() { this.directoryList() }.layoutWeight(1).height('100%')
            if (this.widthBp >= WidthBreakpoint.WIDTH_LG && this.files.transfers.length > 0) {
              Stack({ alignContent: Alignment.End }) {
                this.transferScroll(true)
                edgeScrollBar(this.transferScroller, 'files.transfers.scroll')
              }.width(320).height('100%')
            }
          }.width('100%').layoutWeight(1)
          if (this.widthBp < WidthBreakpoint.WIDTH_LG && this.files.transfers.length > 0) {
            Stack({ alignContent: Alignment.End }) {
              this.transferScroll(false)
              edgeScrollBar(this.transferScroller, 'files.transfers.scroll')
            }.width('100%').constraintSize({ maxHeight: 200 })
          }
          if (this.files.error !== null && this.files.entries.length > 0) {
            Text(this.files.error).fontSize(14).fontColor($r('app.color.error_text')).padding(12)
          }
        }.width('100%').height('100%').id('files.page')
      }
      ConfirmDialog({
        visible: this.uploadVisible, title: tr('上传文件'), body: tr('确认上传所选文件到当前远端目录？'),
        confirmText: tr('上传'), cancelText: tr('取消'),
        onConfirm: () => { this.uploadVisible = false; this.service?.startTransfer(this.pendingRemote, this.pendingUri, true); },
        onCancel: () => { this.uploadVisible = false; }
      })
    }.width('100%').height('100%')
  }
}
