import { buttonPressEdgeLayer, buttonPressShadow, buttonPressShadowSupported, pressedButtonAfterTouch,
  SessionMaterialBackplate, sessionFloatingIcon, sessionMaterialSupported, sessionSurfaceControl } from '../theme/FloatingMaterial';
import { tr } from '../model/I18n';

const BUTTON_SIZE = 48;
const BUTTON_GAP = 8;
const ZOOM_CAPSULE_WIDTH = 144;
const ZOOM_CAPSULE_COMPACT_WIDTH = 64;
const ZOOM_RESET_ID = 'session.zoom.reset';
const TOOLBAR_RESIZE: AnimateParam = { duration: 220, curve: Curve.EaseInOut };

export interface SessionToolbarAction {
  id: string;
  icon: string;
  label: string;
  enabled: boolean;
  text?: string;
}

export interface SessionToolbarLayout {
  buttonSize: number;
  gap: number;
  capsuleWidth: number;
  trailingWidth: number;
  width: number;
}

export function sessionToolbarLayout(count: number, available: number, zoomed: boolean): SessionToolbarLayout {
  const leadingCount = Math.ceil(count / 2);
  const trailingSlots = zoomed ? leadingCount : count - leadingCount;
  const slots = leadingCount + trailingSlots;
  const fullButtonsWidth = slots * (BUTTON_SIZE + BUTTON_GAP);
  const capsuleWidth = !zoomed ? 0 : fullButtonsWidth + ZOOM_CAPSULE_WIDTH <= available ?
    ZOOM_CAPSULE_WIDTH : ZOOM_CAPSULE_COMPACT_WIDTH;
  const gap = zoomed && fullButtonsWidth + capsuleWidth > available ? 4 : BUTTON_GAP;
  const buttonSize = zoomed && slots > 0 ?
    Math.min(BUTTON_SIZE, Math.max(0, Math.floor((available - capsuleWidth) / slots - gap))) : BUTTON_SIZE;
  return {
    buttonSize: buttonSize,
    gap: gap,
    capsuleWidth: capsuleWidth,
    trailingWidth: Math.max(0, trailingSlots * (buttonSize + gap) - gap),
    width: Math.max(0, slots * (buttonSize + gap) - gap) + (zoomed ? capsuleWidth + gap : 0)
  };
}

@Component
export struct SessionToolbar {
  @Prop actions: SessionToolbarAction[] = [];
  @Prop isDark: boolean = false;
  @Prop menuOverlaps: boolean = false;
  @Prop layout: SessionToolbarLayout = sessionToolbarLayout(0, 0, false);
  @Prop zoomPercent: number = 100;
  @Link menuOpen: boolean;
  @State pressedButton: string = '';
  onAction: (id: string) => void = () => {};
  onResetZoom: () => void = () => {};

  private actionKey(action: SessionToolbarAction): string {
    return action.id + ':' + action.enabled + ':' + action.icon + ':' + action.label + ':' + (action.text ?? '');
  }

  @Builder
  actionButton(action: SessionToolbarAction) {
    Button({ type: ButtonType.Circle, stateEffect: !buttonPressShadowSupported }) {
      if (action.text !== undefined) {
        Stack() {
          if (sessionMaterialSupported()) {
            SessionMaterialBackplate({ radius: 24, nodeId: action.id + '.material' })
          }
          if (buttonPressShadowSupported && action.enabled && !this.menuOpen && this.pressedButton === action.id) {
            buttonPressEdgeLayer('50%', action.id + '.press-glow')
          }
          Text(action.text).width(Math.max(0, this.layout.buttonSize - 8)).fontSize(10).fontColor($r('sys.color.font_primary'))
            .textAlign(TextAlign.Center).wordBreak(WordBreak.BREAK_WORD).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
        }.width('100%').height('100%')
      } else {
        sessionFloatingIcon({ icon: action.icon, dark: this.isDark, id: action.id,
          pressed: action.enabled && !this.menuOpen && this.pressedButton === action.id })
      }
    }.width(this.layout.buttonSize).height(this.layout.buttonSize).animation(TOOLBAR_RESIZE)
      .padding(0).attributeModifier(sessionSurfaceControl())
      .id(action.id).enabled(action.enabled && !this.menuOpen).accessibilityText(action.label)
      .visualEffect(buttonPressShadow(action.enabled && !this.menuOpen && this.pressedButton === action.id, false))
      .onTouch((event: TouchEvent) => { this.pressedButton = pressedButtonAfterTouch(this.pressedButton, action.id, event); })
      .onClick(() => { this.onAction(action.id); })
  }

  @Builder
  zoomReset() {
    Button({ type: ButtonType.Capsule, stateEffect: !buttonPressShadowSupported }) {
      Stack() {
        if (sessionMaterialSupported()) {
          SessionMaterialBackplate({ radius: 24, nodeId: ZOOM_RESET_ID + '.material' })
        }
        if (buttonPressShadowSupported && this.pressedButton === ZOOM_RESET_ID) {
          buttonPressEdgeLayer(24, ZOOM_RESET_ID + '.press-glow')
        }
        Text(this.zoomPercent + '%' + (this.layout.capsuleWidth === ZOOM_CAPSULE_WIDTH ? ' · ' + tr('还原画面') : ''))
          .fontSize(14).fontColor($r('sys.color.font_primary')).padding({ left: 8, right: 8 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).hitTestBehavior(HitTestMode.None)
      }.width('100%').height('100%')
    }.width(this.layout.capsuleWidth).height(48).padding(0).attributeModifier(sessionSurfaceControl())
      .id(ZOOM_RESET_ID).accessibilityText(this.zoomPercent + '% · ' + tr('还原画面'))
      .visualEffect(buttonPressShadow(this.pressedButton === ZOOM_RESET_ID, false))
      .onTouch((event: TouchEvent) => {
        this.pressedButton = pressedButtonAfterTouch(this.pressedButton, ZOOM_RESET_ID, event);
      })
      .onClick(() => { this.onResetZoom(); })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.scale({ x: 0.08, y: 1, centerX: '50%' }).combine(TransitionEffect.OPACITY)
          .animation({ duration: 240, curve: Curve.EaseOut }),
        TransitionEffect.scale({ x: 0.08, y: 1, centerX: '50%' }).combine(TransitionEffect.OPACITY)
          .animation({ duration: 180, curve: Curve.EaseInOut })))
  }

  build() {
    Row() {
      Row({ space: this.layout.gap }) {
        ForEach(this.actions.slice(0, Math.ceil(this.actions.length / 2)), (action: SessionToolbarAction) => {
          this.actionButton(action)
        }, (action: SessionToolbarAction) => this.actionKey(action))
      }.hitTestBehavior(HitTestMode.None)
      Stack() {
        if (this.layout.capsuleWidth > 0) { this.zoomReset() }
      }.width(this.layout.capsuleWidth > 0 ? this.layout.capsuleWidth + 2 * this.layout.gap :
        this.actions.length > 1 ? this.layout.gap : 0)
        .height(48).clip(true).animation(TOOLBAR_RESIZE).hitTestBehavior(HitTestMode.None)
      Row({ space: this.layout.gap }) {
        ForEach(this.actions.slice(Math.ceil(this.actions.length / 2)), (action: SessionToolbarAction) => {
          this.actionButton(action)
        }, (action: SessionToolbarAction) => this.actionKey(action))
      }.width(this.layout.trailingWidth).animation(TOOLBAR_RESIZE).hitTestBehavior(HitTestMode.None)
    }.width(LayoutPolicy.wrapContent).height(48).id('session.toolbar')
      .opacity(this.menuOverlaps ? 0 : 1)
      .translate({ y: this.menuOverlaps ? 8 : 0 })
      .animation({ duration: 180, curve: Curve.Friction })
      .hitTestBehavior(HitTestMode.None)
  }
}
