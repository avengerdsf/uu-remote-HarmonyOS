import { curves } from '@kit.ArkUI';
import { iconResource } from '../model/Icons';
import { tr } from '../model/I18n';
import { sessionSurfaceControl, sessionFloatingIcon, SessionMaterialBackplate, sessionMaterialSupported,
  sessionMenuMaterial, sessionMenuFrame, floatingFeedback, buttonPressEdgeLayer, buttonPressShadow, buttonPressShadowSupported,
  pressedButtonAfterTouch } from '../theme/FloatingMaterial';

const WHEEL_HOLD_MS = 450;
const WHEEL_REPEAT_MS = 100;
const WHEEL_TICK = 120;
const WHEEL_DEAD_ZONE = 6;

@Component
export struct VirtualMouse {
  @Prop @Watch('onBoundsChanged') pageWidth: number = 360;
  @Prop @Watch('onBoundsChanged') pageHeight: number = 640;
  @Prop @Watch('onBoundsChanged') bottomInset: number = 16;
  @Prop @Watch('onInputEnabled') inputEnabled: boolean = true;
  @Prop @Watch('onViewportChanged') videoRect: number[] = [];
  @Prop showPointer: boolean = true;
  @Prop @Watch('onInitialPositionChanged') initialY: number = -1;
  @Prop @Watch('onCollapseRequested') collapseRequest: number = 0;
  onInput: (input: string) => void = () => {};
  onRelease: () => void = () => {};
  onExpandedChange: (expanded: boolean) => void = () => {};
  onPointerPosition: (x: number, y: number, screenX: number, screenY: number) => void = () => {};
  @State expanded: boolean = false;
  @State wheelExpanded: boolean = false;
  @State dragLocked: boolean = false;
  @State pressedButton: string = '';
  @State x: number = 0;
  @State y: number = 0;
  @State pointerX: number = 0.5;
  @State pointerY: number = 0.5;
  private dragX: number = 0;
  private dragY: number = 0;
  private offsetX: number = 0;
  private offsetY: number = 0;
  private wheelOffset: number = 0;
  private wheelMoved: boolean = false;
  private wheelTouchId: number = -1;
  private wheelStartX: number = 0;
  private wheelStartY: number = 0;
  private wheelDirection: number = 0;
  private wheelHoldTimer: number = -1;
  private wheelRepeatTimer: number = -1;
  private held: number[] = [];
  private manualHeld: number[] = [];
  private positionTouched: boolean = false;
  private globalX: number = 0;
  private globalY: number = 0;
  private dragTouchX: number = 0;
  private dragTouchY: number = 0;
  private dragRect: number[] = [];
  private dragPointerX: number = 0;
  private dragPointerY: number = 0;
  private bodyRadius: OutlineRadiuses = { topLeft: 56, topRight: 56, bottomLeft: 36, bottomRight: 36 };

  aboutToAppear(): void {
    this.y = this.initialY >= 0 ? this.initialY : this.pageHeight - 144;
    this.fitBounds();
  }

  aboutToDisappear(): void {
    this.stopWheelTouch(false);
    this.releaseButtons();
    this.onExpandedChange(false);
  }

  private onCollapseRequested(): void { this.setExpanded(false, false); }

  private onInitialPositionChanged(): void {
    if (!this.positionTouched && this.initialY >= 0) {
      this.y = this.initialY;
      this.fitBounds();
    }
  }

  private fitBounds(): void {
    const right = this.pageWidth - (this.expanded ? 112 : 48) - 16;
    this.x = Math.max(16, this.positionTouched ? Math.min(this.x, right) : right);
    const bottom = Math.max(16, this.pageHeight - (this.expanded ? 144 : 48) - this.bottomInset);
    this.y = Math.max(Math.min(64, bottom), Math.min(this.y, bottom));
  }

  private onBoundsChanged(): void {
    this.fitBounds();
    if (this.expanded) { this.onPointerPosition(this.pointerX, this.pointerY, this.x - 12, this.y - 12); }
  }

  private releaseButtons(releaseRemote: boolean = true): void {
    if (this.held.length > 0 && releaseRemote) { this.onRelease(); }
    this.held = [];
    this.manualHeld = []; this.dragLocked = false;
  }

  private onInputEnabled(): void {
    if (!this.inputEnabled) {
      this.wheelMoved = true;
      this.stopWheelTouch(true);
      this.releaseButtons();
    } else if (this.expanded) { this.sendPointer(); }
  }

  private pointerRect(): number[] {
    return this.videoRect.length === 4 ? this.videoRect : [0, 0, this.pageWidth, this.pageHeight];
  }

  private sendPointer(): void {
    if (this.inputEnabled) {
      this.onInput(JSON.stringify({ action: 'mouse_move_absolute', abs_x: this.pointerX, abs_y: this.pointerY }));
    }
  }

  private movePointer(x: number, y: number): void {
    const rect = this.pointerRect();
    if (rect[2] <= 0 || rect[3] <= 0) { return; }
    this.pointerX = Math.max(0, Math.min(1, (x - rect[0]) / rect[2]));
    this.pointerY = Math.max(0, Math.min(1, (y - rect[1]) / rect[3]));
    this.onPointerPosition(this.pointerX, this.pointerY, this.x - 12, this.y - 12);
    this.sendPointer();
  }

  private onViewportChanged(): void {
    if (this.expanded) {
      const rect = this.pointerRect();
      this.x = rect[0] + this.pointerX * rect[2] + 12;
      this.y = rect[1] + this.pointerY * rect[3] + 12;
    }
    this.fitBounds();
    if (this.expanded) { this.onPointerPosition(this.pointerX, this.pointerY, this.x - 12, this.y - 12); }
  }

  private toggle(): void { this.setExpanded(!this.expanded); }

  private setExpanded(expanded: boolean, releaseRemote: boolean = true): void {
    if (expanded === this.expanded) { return; }
    this.positionTouched = true;
    this.pressedButton = '';
    this.stopWheelTouch(false);
    this.releaseButtons(releaseRemote);
    this.getUIContext().animateTo({ curve: curves.responsiveSpringMotion(0.3, 0.86) }, () => {
      this.x += expanded ? -64 : 64;
      this.y += expanded ? -96 : 96;
      this.expanded = expanded;
      this.fitBounds();
      if (expanded) { this.movePointer(this.x - 12, this.y - 12); }
      this.onExpandedChange(expanded);
    });
  }

  private setButton(button: number, down: boolean): void {
    if (!this.inputEnabled || this.held.includes(button) === down) { return; }
    this.held = down ? this.held.concat(button) : this.held.filter((value: number) => value !== button);
    this.onInput(JSON.stringify({ action: down ? 'mouse_press' : 'mouse_release', button: button }));
  }

  private button(button: number, down: boolean): void {
    if (!this.inputEnabled) { return; }
    this.manualHeld = down ? this.manualHeld.filter((value: number) => value !== button).concat(button) :
      this.manualHeld.filter((value: number) => value !== button);
    this.setButton(button, down || (button === 1 && this.dragLocked));
  }

  private toggleDrag(): void {
    if (!this.inputEnabled) { return; }
    this.dragLocked = !this.dragLocked;
    this.setButton(1, this.dragLocked || this.manualHeld.includes(1));
  }

  private click(button: number): void { this.button(button, true); this.button(button, false); }

  private touchButton(event: TouchEvent, button: number): void {
    if (event.source === SourceType.Mouse) { return; }
    if (event.type === TouchType.Down) { this.button(button, true); }
    else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.button(button, false); }
    event.stopPropagation();
  }

  private mouseButton(event: MouseEvent, button: number): void {
    if (event.button === MouseButton.Left) {
      if (event.action === MouseAction.Press) { this.button(button, true); }
      else if (event.action === MouseAction.Release) { this.button(button, false); }
    }
    event.stopPropagation();
  }

  private beginDrag(event: GestureEvent): void {
    this.positionTouched = true;
    this.dragX = this.x; this.dragY = this.y;
    this.dragRect = this.pointerRect().slice();
    this.dragPointerX = this.pointerX; this.dragPointerY = this.pointerY;
    this.offsetX = 0; this.offsetY = 0;
    const finger = event.fingerList.find((value: FingerInfo) => value !== undefined);
    this.dragTouchX = finger === undefined ? this.x + 24 : finger.globalX - this.globalX - event.offsetX;
    this.dragTouchY = finger === undefined ? this.y + 24 : finger.globalY - this.globalY - event.offsetY;
  }

  private edgePointer(origin: number, offset: number, touchOrigin: number, size: number, low: number, high: number): number {
    const touch = touchOrigin + offset;
    if (touch <= 2) { return low; }
    if (touch >= size - 2) { return high; }
    const point = origin + offset;
    const zone = Math.max(1, Math.min(48, offset < 0 ? touchOrigin : size - touchOrigin));
    const weight = Math.max(0, Math.min(1, offset < 0 ? (zone - touch) / zone : (touch - size + zone) / zone));
    return Math.max(low, Math.min(high, point + ((offset < 0 ? low : high) - point) * weight));
  }

  private drag(event: GestureEvent, movePointer: boolean): void {
    if (event.axisVertical !== 0 || event.axisHorizontal !== 0) { return; }
    const dx = event.offsetX - this.offsetX;
    const dy = event.offsetY - this.offsetY;
    this.offsetX = event.offsetX; this.offsetY = event.offsetY;
    if (movePointer && (dx !== 0 || dy !== 0)) {
      const rect = this.dragRect;
      if (rect.length !== 4 || rect[2] <= 0 || rect[3] <= 0) { return; }
      const px = this.edgePointer(rect[0] + this.dragPointerX * rect[2], event.offsetX,
        this.dragTouchX, this.pageWidth, rect[0], rect[0] + rect[2]);
      const py = this.edgePointer(rect[1] + this.dragPointerY * rect[3], event.offsetY,
        this.dragTouchY, this.pageHeight, rect[1], rect[1] + rect[3]);
      this.x = this.dragX + event.offsetX; this.y = this.dragY + event.offsetY;
      this.fitBounds();
      this.pointerX = (px - rect[0]) / rect[2]; this.pointerY = (py - rect[1]) / rect[3];
      this.onPointerPosition(this.pointerX, this.pointerY, this.x - 12, this.y - 12);
      this.sendPointer();
    } else if (!movePointer) {
      this.x = this.dragX + event.offsetX; this.y = this.dragY + event.offsetY;
      this.fitBounds();
    }
  }

  private scroll(dx: number, dy: number): void {
    if (this.inputEnabled && (dx !== 0 || dy !== 0)) {
      this.onInput(JSON.stringify({ action: 'mouse_scroll', delta_x: dx, delta_y: dy }));
    }
  }

  private animateWheel(expanded: boolean): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.Friction }, () => { this.wheelExpanded = expanded; });
  }

  private setWheelDirection(direction: number): void {
    if (direction === this.wheelDirection) { return; }
    clearInterval(this.wheelRepeatTimer);
    this.wheelRepeatTimer = -1;
    this.wheelDirection = direction;
    if (direction !== 0) {
      this.scroll(0, direction * WHEEL_TICK);
      this.wheelRepeatTimer = setInterval(() => { this.scroll(0, direction * WHEEL_TICK); }, WHEEL_REPEAT_MS);
    }
  }

  private stopWheelTouch(animate: boolean): void {
    clearTimeout(this.wheelHoldTimer);
    this.wheelHoldTimer = -1;
    this.setWheelDirection(0);
    this.wheelTouchId = -1;
    if (this.pressedButton === 'wheel') { this.pressedButton = ''; }
    if (this.wheelExpanded) {
      if (animate) { this.animateWheel(false); }
      else { this.wheelExpanded = false; }
    }
  }

  private touchWheel(event: TouchEvent): void {
    event.stopPropagation();
    if (event.type === TouchType.Down && this.wheelTouchId < 0) {
      this.wheelMoved = false;
      this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'wheel', event);
      const touch = event.changedTouches[0];
      if (!this.inputEnabled || event.source === SourceType.Mouse || touch === undefined) { return; }
      this.wheelTouchId = touch.id;
      // Window coordinates remain stable as the pressed wheel changes size.
      this.wheelStartX = touch.windowX;
      this.wheelStartY = touch.windowY;
      this.wheelOffset = 0;
      this.wheelHoldTimer = setTimeout(() => {
        this.wheelHoldTimer = -1;
        this.wheelMoved = true;
        this.animateWheel(true);
      }, WHEEL_HOLD_MS);
      return;
    }
    if (this.wheelTouchId < 0) {
      this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'wheel', event);
      return;
    }
    if (event.source === SourceType.Mouse) { return; }
    const contact = event.changedTouches.find((touch: TouchObject) => touch.id === this.wheelTouchId);
    if (event.type === TouchType.Cancel) {
      this.wheelMoved = true;
      this.stopWheelTouch(true);
    } else if (event.type === TouchType.Up) {
      if (contact !== undefined || !event.touches.some((touch: TouchObject) => touch.id === this.wheelTouchId)) {
        this.stopWheelTouch(true);
      }
    } else if (event.type === TouchType.Move && contact !== undefined) {
      const offset = contact.windowY - this.wheelStartY;
      if (this.wheelExpanded) {
        this.setWheelDirection(offset <= -WHEEL_DEAD_ZONE ? 1 : offset >= WHEEL_DEAD_ZONE ? -1 : 0);
      } else {
        if (!this.wheelMoved) {
          if (Math.max(Math.abs(offset), Math.abs(contact.windowX - this.wheelStartX)) < WHEEL_DEAD_ZONE) { return; }
          clearTimeout(this.wheelHoldTimer);
          this.wheelHoldTimer = -1;
          this.wheelMoved = true;
        }
        const steps = Math.trunc((offset - this.wheelOffset) / 12);
        if (steps !== 0) { this.scroll(0, -steps * WHEEL_TICK); this.wheelOffset += steps * 12; }
      }
    }
  }

  @Builder
  mouseKey(label: string, button: number) {
    Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
      Image(iconResource('assist', true, false)).width(22).height(22)
        .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain)
        .draggable(false).accessibilityLevel('no').id('session.mouse.button.' + button + '.icon')
    }
      .layoutWeight(1).height(56).padding(0)
      .borderRadius({ topLeft: button === 1 ? 56 : 0, topRight: button === 2 ? 56 : 0,
        bottomLeft: 0, bottomRight: 0 }).backgroundColor(Color.Transparent)
      .enabled(this.inputEnabled).focusOnTouch(false).id('session.mouse.button.' + button).accessibilityText(label)
      .attributeModifier(floatingFeedback)
      .visualEffect(buttonPressShadow(this.inputEnabled && this.pressedButton === 'key.' + button))
      .onTouch((event: TouchEvent) => {
        this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'key.' + button, event);
        this.touchButton(event, button);
      })
      .onMouse((event: MouseEvent) => { this.mouseButton(event, button); })
      .onClick((event: ClickEvent) => {
        if (event.source !== SourceType.TouchScreen && event.source !== SourceType.Mouse) { this.click(button); }
      })
  }

  @Builder
  mouseBody() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (sessionMaterialSupported()) {
        SessionMaterialBackplate({ radius: this.bodyRadius, nodeId: 'session.mouse.expanded.material' })
      }
      if (buttonPressShadowSupported && this.pressedButton === 'collapse') {
        buttonPressEdgeLayer(this.bodyRadius, 'session.mouse.expanded.press-glow')
      }
      Column() {
      Row() {
        this.mouseKey(tr('左键'), 1)
        Divider().vertical(true).height(40).color($r('app.color.session_glass_stroke')).margin({ top: 12 })
        this.mouseKey(tr('右键'), 2)
      }.width('100%').height(56)
      Divider().height(1).color($r('app.color.session_glass_stroke'))
      Column() {}.width('100%').height(39).justifyContent(FlexAlign.Center).id('session.mouse.drag')
        .accessibilityText(tr('拖动移动指针'))
        .gesture(PanGesture({ fingers: 1, distance: 3 })
          .onActionStart((event: GestureEvent) => { this.beginDrag(event); })
          .onActionUpdate((event: GestureEvent) => { this.drag(event, true); })
          .onActionEnd((event: GestureEvent) => { this.drag(event, true); })
          .onActionCancel(() => { this.releaseButtons(); }))
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: !buttonPressShadowSupported }) {
          Image(iconResource('drag', true, false)).width(24).height(24)
            .fillColor(this.dragLocked ? $r('app.color.on_primary') : $r('sys.color.icon_primary'))
            .objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
        }.width(40).height(40).padding(0).accessibilityText(tr('拖动'))
          .backgroundColor(this.dragLocked ? $r('app.color.primary') : $r('app.color.session_selection'))
          .enabled(this.inputEnabled).focusOnTouch(false).accessibilitySelected(this.dragLocked)
          .attributeModifier(floatingFeedback)
          .visualEffect(buttonPressShadow(this.inputEnabled && this.pressedButton === 'drag'))
          .onTouch((event: TouchEvent) => {
            this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'drag', event);
          })
          .id('session.mouse.dragLock').onClick(() => { this.toggleDrag(); })
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          Image(iconResource('chevron', true, false)).width(20).height(20).rotate({ angle: 90 })
            .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
        }.width(32).height(32).backgroundColor(Color.Transparent).focusOnTouch(false)
          .attributeModifier(floatingFeedback)
          .onTouch((event: TouchEvent) => {
            this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'collapse', event);
          })
          .id('session.mouse.collapse').accessibilityText(tr('收起虚拟鼠标')).onClick(() => { this.toggle(); })
      }.height(48).justifyContent(FlexAlign.Center).width('100%')
      }.width('100%')
        Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
          Stack() {
            if (buttonPressShadowSupported && this.pressedButton === 'wheel') {
              buttonPressEdgeLayer(this.wheelExpanded ? 18 : 11, 'session.mouse.wheel.press-glow')
            }
            Column({ space: this.wheelExpanded ? 16 : 8 }) {
              Image(iconResource('chevron', true, false)).width(12).height(12).rotate({ angle: -90 })
                .fillColor($r('sys.color.icon_primary')).draggable(false).accessibilityLevel('no')
              Image(iconResource('chevron', true, false)).width(12).height(12).rotate({ angle: 90 })
                .fillColor($r('sys.color.icon_primary')).draggable(false).accessibilityLevel('no')
            }
          }.width('100%').height('100%')
        }.width(this.wheelExpanded ? 36 : 22).height(this.wheelExpanded ? 60 : 52).padding(0)
          .backgroundColor($r('app.color.session_selection'))
          .border({ width: 1, color: $r('app.color.session_glass_stroke') }).borderRadius(this.wheelExpanded ? 18 : 11)
          .position({ x: this.wheelExpanded ? 38 : 45, y: this.wheelExpanded ? 36 : 42 })
          .enabled(this.inputEnabled).focusOnTouch(false)
          .id(this.wheelExpanded ? 'session.mouse.wheel.expanded' : 'session.mouse.wheel').accessibilityText(tr('滚轮'))
          .attributeModifier(floatingFeedback)
          .visualEffect(buttonPressShadow(this.inputEnabled && this.pressedButton === 'wheel', false))
          .onClick((event: ClickEvent) => {
            if (!this.wheelMoved || event.source === SourceType.Mouse) { this.click(4); }
            this.wheelMoved = false;
          })
          .onTouch((event: TouchEvent) => { this.touchWheel(event); })
          .onAxisEvent((event: AxisEvent) => {
            this.scroll(Math.round(event.getHorizontalAxisValue()), -Math.round(event.getVerticalAxisValue()));
          })
    }.width(112).height(144).borderRadius(this.bodyRadius)
      .attributeModifier(sessionMaterialSupported() ? sessionMenuFrame : sessionMenuMaterial)
      .outlineRadius(this.bodyRadius)
      .id('session.mouse.expanded')
      .geometryTransition('session.mouse.shape')
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.94, y: 0.94,
        centerX: '100%', centerY: '100%' })).animation({ duration: 180, curve: Curve.Friction }))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        if (this.expanded) { this.mouseBody() }
        else {
          Button({ type: ButtonType.Circle, stateEffect: !buttonPressShadowSupported }) {
            sessionFloatingIcon({ icon: 'mouse', dark: true, id: 'session.mouse',
              pressed: this.pressedButton === 'collapsed' })
          }.width(48).height(48).padding(0).attributeModifier(sessionSurfaceControl()).focusOnTouch(false)
            .id('session.mouse.collapsed').accessibilityText(tr('展开虚拟鼠标'))
            .visualEffect(buttonPressShadow(this.pressedButton === 'collapsed', false))
            .onTouch((event: TouchEvent) => {
              this.pressedButton = pressedButtonAfterTouch(this.pressedButton, 'collapsed', event);
            })
            .geometryTransition('session.mouse.shape')
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
            .onClick(() => { this.toggle(); })
            .gesture(PanGesture({ fingers: 1, distance: 3 })
              .onActionStart((event: GestureEvent) => { this.beginDrag(event); })
              .onActionUpdate((event: GestureEvent) => { this.drag(event, false); }))
        }
      }.position({ x: this.x, y: this.y }).id('session.mouse').hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
        .onTouch((event: TouchEvent) => { event.stopPropagation(); })
        .onMouse((event: MouseEvent) => { event.stopPropagation(); })
      if (this.expanded && this.showPointer) {
        Image(iconResource('pointer', true, false)).width(24).height(24)
          .fillColor($r('sys.color.icon_primary')).accessibilityLevel('no')
          .position({ x: this.pointerRect()[0] + this.pointerX * this.pointerRect()[2] - 4.56,
            y: this.pointerRect()[1] + this.pointerY * this.pointerRect()[3] - 4.58 })
          .hitTestBehavior(HitTestMode.None).id('session.mouse.fallbackPointer')
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.globalX = Number.parseFloat(`${newValue.globalPosition.x}`);
        this.globalY = Number.parseFloat(`${newValue.globalPosition.y}`);
      })
  }
}
