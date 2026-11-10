/**
 * Layout and style values from ui_contract.json (contract 1.0.0).
 * All layout values are vp; text values are fp. Formulas take the measured
 * drawable width W after window decorations and avoid areas.
 */

export type LayoutMode = 'compact' | 'medium' | 'expanded';

export class Metrics {
  static readonly floatingInset: number = 16;
  static readonly floatingHeaderHeight: number = 48 + Metrics.floatingInset * 2;
  static readonly navigationTitleHeight: number = 56;
  static readonly navigationTopInset: number = Metrics.floatingInset - (Metrics.navigationTitleHeight - 48) / 2;

  static mode(width: number): LayoutMode {
    if (width < 600) {
      return 'compact';
    }
    if (width < 840) {
      return 'medium';
    }
    return 'expanded';
  }

  static navWidth(mode: LayoutMode): number {
    // All breakpoints use the bottom navigation bar; no side rail/sidebar.
    return 0;
  }

  static padding(mode: LayoutMode): number {
    return mode === 'compact' ? 16 : 24;
  }

  static headerHeight(mode: LayoutMode, fontScale: number): number {
    const base = mode === 'compact' ? 56 : 64;
    return Math.max(base, 32 * fontScale + 16);
  }

  static bottomNavHeight(mode: LayoutMode, fontScale: number): number {
    // The three-entry bottom bar is the only navigation surface on every size.
    return Math.max(64, 24 + 4 + 16 * fontScale + 16);
  }

  static bodyWidth(width: number, mode: LayoutMode): number {
    const padding = Metrics.padding(mode);
    return Math.min(width - 2 * padding, 1200);
  }

  static bodyX(width: number, mode: LayoutMode): number {
    const body = Metrics.bodyWidth(width, mode);
    return (width - body) / 2;
  }

  static searchHeight(fontScale: number): number {
    return Math.max(48, 24 * fontScale + 24);
  }

  static columns(bodyWidth: number, mode: LayoutMode, fontScale: number): number {
    if (mode === 'compact') {
      return 1;
    }
    const unit = 264 * Math.min(fontScale, 1.5) + 16;
    const value = Math.floor((bodyWidth + 16) / unit);
    return Math.max(1, Math.min(4, value));
  }

  static cardWidth(bodyWidth: number, columns: number): number {
    return (bodyWidth - 16 * (columns - 1)) / columns;
  }

  static cardTopHeight(fontScale: number): number {
    return Math.max(48, 42 * fontScale);
  }

  static cardStatusHeight(fontScale: number): number {
    return Math.max(20, 20 * fontScale);
  }

  static buttonHeight(fontScale: number): number {
    return Math.max(48, 24 * fontScale + 24);
  }

  static cardMinHeight(fontScale: number): number {
    return 32 + Metrics.cardTopHeight(fontScale) + 12 + Metrics.cardStatusHeight(fontScale) +
      16 + Metrics.buttonHeight(fontScale);
  }

  static gridY(mode: LayoutMode, fontScale: number): number {
    return Metrics.headerHeight(mode, fontScale) + Metrics.padding(mode) +
      Metrics.searchHeight(fontScale) + 16;
  }

  static sessionToolbarHeight(fontScale: number): number {
    return Math.max(64, 24 + 4 + 16 * fontScale + 16);
  }

  static railItemHeight(fontScale: number, lines: number): number {
    return Math.max(60, 44 + 16 * fontScale * lines);
  }
}

export interface Palette {
  background: string;
  surface: string;
  primaryText: string;
  secondaryText: string;
  primary: string;
  onPrimary: string;
  border: string;
  error: string;
  success: string;
  warning: string;
  selection: string;
}

export class Tokens {
  static readonly spacing: number[] = [4, 8, 12, 16, 24, 32];
  static readonly pageTitleFp: number = 24;
  static readonly sectionFp: number = 20;
  static readonly bodyFp: number = 16;
  static readonly secondaryFp: number = 14;
  static readonly labelFp: number = 12;
  static readonly cardRadius: number = 16;
  static readonly panelRadius: number = 20;
  static readonly dialogRadius: number = 24;
  static readonly minTap: number = 48;
  static readonly iconVisual: number = 24;
  static readonly buttonHeight: number = 48;
  static readonly contentMax: number = 1200;
  static readonly formMax: number = 480;
  static readonly loginCardMax: number = 400;
  static readonly qrOuter: number = 240;
  static readonly qrPadding: number = 20;
  static readonly dialogMax: number = 480;
  static readonly dialogMargin: number = 16;
  static readonly settingsGroupWidth: number = 176;
  static readonly settingsGap: number = 16;

  /** Immersive light-sense material tokens. */
  static readonly glassRadius: Resource = $r('sys.float.corner_radius_level8');
  static readonly glassDialogRadius: Resource = $r('sys.float.corner_radius_level8');
  static readonly glassBlur: number = 24;
  static readonly shadowRadius: number = 28;
  static readonly glowRadius: number = 18;
  static readonly motionFast: number = 160;
  static readonly motionBase: number = 260;
  static readonly motionAmbient: number = 14000;

  static readonly light: Palette = {
    background: '#F5F6F8',
    surface: '#FFFFFF',
    primaryText: '#182431',
    secondaryText: '#5F6B7A',
    primary: '#0A59F7',
    onPrimary: '#FFFFFF',
    border: '#D9DEE6',
    error: '#B3261E',
    success: '#1B6B3A',
    warning: '#795400',
    selection: '#E8F0FF'
  };

  static readonly dark: Palette = {
    background: '#121418',
    surface: '#20242B',
    primaryText: '#F1F3F5',
    secondaryText: '#B4BBC4',
    primary: '#8AB4FF',
    onPrimary: '#10233F',
    border: '#454D59',
    error: '#FFB4AB',
    success: '#83D9A2',
    warning: '#F4C86A',
    selection: '#243D64'
  };
}
