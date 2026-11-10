import { iconResource } from '../model/Icons';
import { tr } from '../model/I18n';
import { buttonPressShadow, buttonPressShadowSupported, floatingFeedback, pressedButtonAfterTouch,
  SessionMaterialBackplate, sessionMaterialSupported, sessionMenuFrame, sessionMenuMaterial } from '../theme/FloatingMaterial';
import { SessionToolbarAction } from './SessionToolbar';

const EDITOR_ID: string = 'session.toolbar.editor';

@Component
export struct SessionToolbarEditor {
  @Prop available: SessionToolbarAction[] = [];
  @Prop selected: string[] = [];
  @Prop limit: number = 4;
  @State pressedButton: string = '';
  onToggle: (id: string) => void = () => {};
  onMove: (id: string, direction: number) => void = () => {};
  onClose: () => void = () => {};

  private selectedActions(): SessionToolbarAction[] {
    const actions: SessionToolbarAction[] = [];
    for (const id of this.selected) {
      const action = this.available.find((item: SessionToolbarAction) => item.id === id);
      if (action !== undefined) { actions.push(action); }
    }
    return actions;
  }

  @Builder
  actionLabel(action: SessionToolbarAction) {
    Image(iconResource(action.icon, true, false)).width(20).height(20).objectFit(ImageFit.Contain)
      .fillColor($r('app.color.session_text'))
      .draggable(false).accessibilityLevel('no')
    Text(action.label).fontSize(14).fontColor($r('app.color.session_text')).layoutWeight(1)
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  moveButton(action: SessionToolbarAction, direction: number) {
    Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
      Image(iconResource('chevron', true, false)).width(16).height(16)
        .rotate({ angle: direction < 0 ? -90 : 90 }).draggable(false).accessibilityLevel('no')
    }.width(40).height(40).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
      .attributeModifier(floatingFeedback)
      .enabled(direction < 0 ? this.selected.indexOf(action.id) > 0 : this.selected.indexOf(action.id) < this.selected.length - 1)
      .id(EDITOR_ID + (direction < 0 ? '.up.' : '.down.') + action.id)
      .accessibilityText(tr(direction < 0 ? '上移' : '下移') + ' ' + action.label)
      .visualEffect(buttonPressShadow(this.pressedButton === (direction < 0 ? 'up.' : 'down.') + action.id))
      .onTouch((event: TouchEvent) => {
        this.pressedButton = pressedButtonAfterTouch(this.pressedButton, (direction < 0 ? 'up.' : 'down.') + action.id, event);
      })
      .onClick(() => { this.onMove(action.id, direction); })
  }

  @Builder
  selectedRow(action: SessionToolbarAction) {
    Stack() {
      if (sessionMaterialSupported()) {
        SessionMaterialBackplate({ radius: 8, nodeId: EDITOR_ID + '.selected.' + action.id + '.material' })
      }
      Row({ space: 8 }) {
        this.actionLabel(action)
        Row() {
          this.moveButton(action, -1)
          this.moveButton(action, 1)
          Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
            Image(iconResource('close', true, false)).width(16).height(16).draggable(false).accessibilityLevel('no')
          }.width(40).height(40).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
            .attributeModifier(floatingFeedback).id(EDITOR_ID + '.remove.' + action.id)
            .accessibilityText(tr('移除') + ' ' + action.label)
            .visualEffect(buttonPressShadow(this.pressedButton === 'remove.' + action.id))
            .onTouch((event: TouchEvent) => {
              this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'remove.' + action.id, event);
            })
            .onClick(() => { this.onToggle(action.id); })
        }
      }.width('100%').height('100%').padding({ left: 8, right: 4 })
    }.width('100%').height(48).borderRadius(8)
      .backgroundColor(sessionMaterialSupported() ? Color.Transparent : $r('app.color.session_glass'))
      .id(EDITOR_ID + '.selected.' + action.id)
  }

  @Builder
  availableRow(action: SessionToolbarAction) {
    Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
      Stack() {
        if (sessionMaterialSupported()) {
          SessionMaterialBackplate({ radius: 8, nodeId: EDITOR_ID + '.add.' + action.id + '.material' })
        }
        Row({ space: 8 }) {
          this.actionLabel(action)
          Image($r('app.media.keyboard_add')).width(18).height(18).fillColor($r('app.color.session_text'))
            .draggable(false).accessibilityLevel('no')
        }.width('100%').height('100%').padding({ left: 8, right: 12 })
      }.width('100%').height('100%')
    }.width('100%').height(48).padding(0).borderRadius(8)
      .backgroundColor(sessionMaterialSupported() ? Color.Transparent : $r('app.color.session_glass'))
      .attributeModifier(floatingFeedback).enabled(this.selected.length < this.limit)
      .id(EDITOR_ID + '.add.' + action.id).accessibilityText(tr('添加') + ' ' + action.label)
      .visualEffect(buttonPressShadow(this.pressedButton === 'add.' + action.id))
      .onTouch((event: TouchEvent) => {
        this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'add.' + action.id, event);
      })
      .onClick(() => { this.onToggle(action.id); })
  }

  build() {
    Stack() {
      if (sessionMaterialSupported()) {
        SessionMaterialBackplate({ radius: $r('sys.float.corner_radius_level8'), nodeId: EDITOR_ID + '.material' })
      }
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(tr('自定义工具条')).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.session_text')).maxLines(1).layoutWeight(1)
          Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
            Stack() {
              if (sessionMaterialSupported()) {
                SessionMaterialBackplate({ radius: 8, nodeId: EDITOR_ID + '.done.material' })
              }
              Text(tr('完成')).fontSize(14).fontColor($r('app.color.session_text')).padding({ left: 12, right: 12 })
            }.height('100%')
          }.height(40).padding(0).borderRadius(8)
            .backgroundColor(sessionMaterialSupported() ? Color.Transparent : $r('app.color.session_glass'))
            .attributeModifier(floatingFeedback).id(EDITOR_ID + '.done')
            .visualEffect(buttonPressShadow(this.pressedButton === 'done'))
            .onTouch((event: TouchEvent) => {
              this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'done', event);
            })
            .onClick(() => { this.onClose(); })
        }.width('100%')
        Scroll() {
          Column({ space: 6 }) {
            Row() {
              Text(tr('已选按钮')).fontSize(14).fontColor($r('app.color.session_text')).layoutWeight(1)
              Text(this.selected.length + '/' + this.limit).fontSize(14).fontColor($r('app.color.session_text'))
            }.width('100%')
            ForEach(this.selectedActions(), (action: SessionToolbarAction) => {
              this.selectedRow(action)
            }, (action: SessionToolbarAction) => action.id + ':' + action.label + ':' + action.icon)
            if (this.available.some((action: SessionToolbarAction) => !this.selected.includes(action.id))) {
              Text(tr('可添加按钮')).fontSize(14).fontColor($r('app.color.session_text')).margin({ top: 8 })
              ForEach(this.available.filter((action: SessionToolbarAction) => !this.selected.includes(action.id)),
                (action: SessionToolbarAction) => { this.availableRow(action) },
                (action: SessionToolbarAction) => action.id + ':' + action.label + ':' + action.icon)
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto).id(EDITOR_ID + '.scroll')
      }.width('100%').height('100%').padding(12)
    }.width('100%').height('100%').id(EDITOR_ID)
      .borderRadius($r('sys.float.corner_radius_level8'))
      .attributeModifier(sessionMaterialSupported() ? sessionMenuFrame : sessionMenuMaterial)
  }
}
