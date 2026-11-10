import { iconResource } from '../model/Icons';

@Component
export struct IconView {
  @Prop iconKey: string = 'devices';
  @Prop selected: boolean = false;
  @Prop sizeVp: number = 24;
  @Prop allowImageDrag: boolean = true;
  @Prop imageId: string = '';
  @StorageProp('isDark') isDark: boolean = false;

  build() {
    Image(iconResource(this.iconKey, this.isDark, this.selected))
      .width(this.sizeVp)
      .height(this.sizeVp)
      .objectFit(ImageFit.Contain)
      .draggable(this.allowImageDrag)
      .accessibilityLevel('no')
      .id(this.imageId)
  }
}
