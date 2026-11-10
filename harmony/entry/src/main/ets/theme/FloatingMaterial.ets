import { uiMaterial } from '@kit.ArkUI';
import { uiEffect } from '@kit.ArkGraphics2D';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsEffect, hdsMaterial } from '@kit.UIDesignKit';
import { iconResource } from '../model/Icons';
import { materialLevel } from './MaterialPreference';

function immersiveMaterial(colorInvert: boolean = true): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.apiAvailable('26.0.0')) {
    if (!uiMaterial.isImmersiveMaterialSupported()) { return undefined; }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      colorInvert: colorInvert,
      materialColor: colorInvert ? undefined : '#B31C1D20',
      interactive: true,
      lightEffect: { color: undefined }
    });
  }
  return undefined;
}

export const buttonPressShadowSupported = canIUse('SystemCapability.UIDesign.HDSComponent.Core');
export function sessionMaterialSupported(): boolean {
  return deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
}

function sessionSystemMaterial(level: hdsMaterial.MaterialLevel): uiMaterial.ImmersiveMaterial {
  const exquisite = level === hdsMaterial.MaterialLevel.EXQUISITE;
  const style = exquisite || level === hdsMaterial.MaterialLevel.SMOOTH ? uiMaterial.ImmersiveStyle.THIN :
    level === hdsMaterial.MaterialLevel.GENTLE ? uiMaterial.ImmersiveStyle.REGULAR : uiMaterial.ImmersiveStyle.THICK;
  return new uiMaterial.ImmersiveMaterial({
    style: style, materialColor: exquisite ? '#261C1D20' : undefined, colorInvert: false, applyShadow: false
  });
}

@Component
export struct SessionMaterialBackplate {
  @StorageProp('hdsMaterialLevel') level: hdsMaterial.MaterialLevel = materialLevel();
  @Prop radius: Length | BorderRadiuses = 24;
  @Prop nodeId: string = '';

  build() {
    // The Toggle renders system material on the page while the foreground control owns input.
    Toggle({ type: ToggleType.Button, isOn: false }) {}
      .width(LayoutPolicy.matchParent).height(LayoutPolicy.matchParent).padding(0).borderRadius(this.radius)
      .backgroundColor(Color.Transparent).systemMaterial(sessionSystemMaterial(this.level))
      .touchable(false).focusable(false).hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants').id(this.nodeId)
  }
}

const pressEdgeFlow: hdsEffect.ShaderEffectParams = {
  effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
  animation: { duration: 420, autoPlay: true },
  params: {
    firstEdgeFlowLight: { startPos: 0, endPos: 0.5, color: '#E6FFFFFF' },
    secondEdgeFlowLight: { startPos: 0, endPos: -0.5, color: '#E6FFFFFF' }
  }
};

interface SessionFloatingIconOptions {
  icon: string;
  dark: boolean;
  id: string;
  pressed: boolean;
}

@Builder
export function buttonPressEdgeLayer(radius: Length | BorderRadiuses, id: string) {
  Stack() {}
    .width(LayoutPolicy.matchParent).height(LayoutPolicy.matchParent).borderRadius(radius).clip(true)
    .visualEffect(new hdsEffect.HdsEffectBuilder().shaderEffect(pressEdgeFlow).buildEffect())
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no').id(id)
}

@Builder
export function sessionFloatingIcon($$: SessionFloatingIconOptions) {
  Stack() {
    if (sessionMaterialSupported()) {
      SessionMaterialBackplate({ radius: 24, nodeId: $$.id + '.material' })
    }
    if (buttonPressShadowSupported && $$.pressed) {
      buttonPressEdgeLayer('50%', $$.id + '.press-glow')
    }
    Image(iconResource($$.icon, $$.dark, false)).width(24).height(24)
      .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain)
      .draggable(false).accessibilityLevel('no').id($$.id + '.icon')
  }.width('100%').height('100%')
}

export function buttonPressShadow(pressed: boolean, edgeFlow: boolean = true): VisualEffect {
  if (!buttonPressShadowSupported) { return uiEffect.createEffect(); }
  const type = pressed ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE;
  const effect = new hdsEffect.HdsEffectBuilder().pressShadow(type);
  if (pressed && edgeFlow) { effect.shaderEffect(pressEdgeFlow); }
  return effect.buildEffect();
}

export function pressedButtonAfterTouch(current: string, id: string, event: TouchEvent): string {
  if (!buttonPressShadowSupported) { return current; }
  if (event.type === TouchType.Down) { return id; }
  if (current === id && (event.type === TouchType.Up || event.type === TouchType.Cancel)) { return ''; }
  return current;
}

export class FloatingControlModifier implements AttributeModifier<CommonAttribute> {
  private session: boolean;
  private navigationTitle: boolean;
  private fallbackBlur: boolean;

  constructor(session: boolean, navigationTitle: boolean = false, fallbackBlur: boolean = true) {
    this.session = session;
    this.navigationTitle = navigationTitle;
    this.fallbackBlur = fallbackBlur;
  }

  applyNormalAttribute(node: CommonAttribute): void {
    node.backgroundColor(Color.Transparent);
    // ArkUI limits immersive material on ordinary controls to title bars and bottom tab bars.
    const material = this.navigationTitle ? immersiveMaterial(!this.session) : undefined;
    if (material !== undefined) {
      node.clickEffect(null);
      node.systemMaterial(material);
      return;
    }
    if (this.fallbackBlur) {
      node.backgroundEffect({ radius: 12, color: this.session ? '#B31C1D20' : '#33FFFFFF' });
    }
    node.clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 });
    if (this.session) { node.outline({ width: 0.5, color: '#33FFFFFF', radius: 28 }); }
  }
}

export const floatingControl: FloatingControlModifier = new FloatingControlModifier(false, true);
export const sessionFloatingControl: FloatingControlModifier = new FloatingControlModifier(true);
const sessionFloatingFrame: FloatingControlModifier = new FloatingControlModifier(true, false, false);
export function sessionSurfaceControl(): FloatingControlModifier {
  return sessionMaterialSupported() ? sessionFloatingFrame : sessionFloatingControl;
}
export const sessionTitleFloatingControl: FloatingControlModifier = new FloatingControlModifier(true, true);

export class FloatingFeedbackModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    node.clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 });
  }
}

export const floatingFeedback: FloatingFeedbackModifier = new FloatingFeedbackModifier();

export class FloatingSearchModifier implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    const material = immersiveMaterial();
    if (material !== undefined) { node.systemMaterial(material); }
  }
}

export const floatingSearch: FloatingSearchModifier = new FloatingSearchModifier();

export class SessionMenuModifier implements AttributeModifier<CommonAttribute> {
  private fallbackBlur: boolean;
  private outlineEnabled: boolean;

  constructor(fallbackBlur: boolean = true, outlineEnabled: boolean = true) {
    this.fallbackBlur = fallbackBlur;
    this.outlineEnabled = outlineEnabled;
  }

  applyNormalAttribute(node: CommonAttribute): void {
    node.backgroundColor(Color.Transparent);
    node.backgroundBlurStyle(BlurStyle.NONE);
    if (this.fallbackBlur) {
      node.backgroundEffect({ radius: 40, saturation: 0.35, color: $r('app.color.session_menu_tint') });
    }
    if (this.outlineEnabled) {
      node.outline({ width: 1, color: $r('app.color.session_glass_stroke'), radius: $r('sys.float.corner_radius_level8') });
    }
    node.shadow({ radius: 16, color: '#66000000', offsetX: 0, offsetY: 4 });
  }
}

export const sessionMenuMaterial: SessionMenuModifier = new SessionMenuModifier();
export const sessionMenuFrame: SessionMenuModifier = new SessionMenuModifier(false);
export const sessionKeyboardFrame: SessionMenuModifier = new SessionMenuModifier(false, false);

