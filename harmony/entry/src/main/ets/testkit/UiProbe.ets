import { UIContext } from '@kit.ArkUI';

export interface ProbeRect {
  id: string;
  source: string;
  unit: string;
  coordinateSpace: string;
  bounds: number[];
  matchCount: number;
  text: string | null;
  enabled: boolean | null;
  fontScale: number | null;
}

function lengthToNumber(value: Length | undefined): number {
  if (value === undefined) {
    return 0;
  }
  if (typeof value === 'number') {
    return value;
  }
  const parsed = Number.parseFloat(`${value}`);
  return Number.isNaN(parsed) ? 0 : parsed;
}

/**
 * Runtime geometry recorder. Tests may read only values actually observed from
 * onAreaChange or ComponentUtils; expected rectangles from ui_contract.json are
 * never copied into actual records.
 */
export class UiProbe {
  private static records: Map<string, ProbeRect> = new Map<string, ProbeRect>();

  static record(id: string, area: Area, text: string | null = null, enabled: boolean | null = null): void {
    const position = area.position;
    const rect: ProbeRect = {
      id: id,
      source: 'onAreaChange',
      unit: 'vp',
      coordinateSpace: 'page',
      bounds: [lengthToNumber(position.x), lengthToNumber(position.y),
        lengthToNumber(area.width), lengthToNumber(area.height)],
      matchCount: 1,
      text: text,
      enabled: enabled,
      fontScale: AppStorage.get<number>('fontScale') ?? null
    };
    UiProbe.records.set(id, rect);
  }

  static measure(uiContext: UIContext, ids: string[]): ProbeRect[] {
    const utils = uiContext.getComponentUtils();
    const result: ProbeRect[] = [];
    for (const id of ids) {
      try {
        const info = utils.getRectangleById(id);
        if (info === undefined || info === null) {
          continue;
        }
        const x = uiContext.px2vp(info.windowOffset.x);
        const y = uiContext.px2vp(info.windowOffset.y);
        const w = uiContext.px2vp(info.size.width);
        const h = uiContext.px2vp(info.size.height);
        result.push({
          id: id,
          source: 'ComponentUtils.getRectangleById',
          unit: 'vp',
          coordinateSpace: 'window',
          bounds: [x, y, w, h],
          matchCount: 1,
          text: null,
          enabled: null,
          fontScale: AppStorage.get<number>('fontScale') ?? null
        });
      } catch (error) {
        result.push({
          id: id,
          source: 'ComponentUtils.getRectangleById',
          unit: 'vp',
          coordinateSpace: 'window',
          bounds: [],
          matchCount: 0,
          text: null,
          enabled: null,
          fontScale: null
        });
      }
    }
    return result;
  }

  static get(id: string): ProbeRect | null {
    return UiProbe.records.get(id) ?? null;
  }

  static dump(): string {
    return JSON.stringify(Array.from(UiProbe.records.values()));
  }

  static clear(): void {
    UiProbe.records.clear();
  }
}
