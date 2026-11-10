import { uiObserver } from '@kit.ArkUI';

@Component
struct ActiveScrollBar {
  scroller: Scroller = new Scroller();
  scrollId: string = '';
  @State scrolling: boolean = false;
  private onScroll: (event: uiObserver.ScrollEventInfo) => void = (event: uiObserver.ScrollEventInfo) => {
    this.scrolling = event.scrollEvent === uiObserver.ScrollEventType.SCROLL_START;
  };

  aboutToAppear(): void {
    this.getUIContext().getUIObserver().on('scrollEvent', { id: this.scrollId }, this.onScroll);
  }

  aboutToDisappear(): void {
    this.getUIContext().getUIObserver().off('scrollEvent', { id: this.scrollId }, this.onScroll);
  }

  build() {
    ScrollBar({ scroller: this.scroller, direction: ScrollBarDirection.Vertical, state: BarState.On })
      // API 26's native scroll_bar_margin reserves 4vp inside the track.
      .width(4).height('100%').translate({ x: 4 }).id(this.scrollId + '.scrollbar')
      .visibility(this.scrolling ? Visibility.Visible : Visibility.Hidden)
  }
}

@Builder
export function edgeScrollBar(scroller: Scroller, scrollId: string) {
  ActiveScrollBar({ scroller: scroller, scrollId: scrollId })
}
