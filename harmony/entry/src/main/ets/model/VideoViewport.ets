export class VideoViewport {
  static readonly maxScale: number = 4;

  static fit(width: number, height: number, videoWidth: number, videoHeight: number): number[] {
    const ratio = Math.max(videoWidth, 1) / Math.max(videoHeight, 1);
    const w = Math.min(width, height * ratio);
    const h = w / ratio;
    return [(width - w) / 2, (height - h) / 2, w, h];
  }

  static rect(fit: number[], scale: number, x: number, y: number): number[] {
    return [fit[0] + fit[2] * (1 - scale) / 2 + x,
      fit[1] + fit[3] * (1 - scale) / 2 + y, fit[2] * scale, fit[3] * scale];
  }

  static offset(fit: number[], width: number, height: number, scale: number, x: number, y: number): number[] {
    const limitX = Math.max(0, (fit[2] * scale - width) / 2);
    const limitY = Math.max(0, (fit[3] * scale - height) / 2);
    return [Math.max(-limitX, Math.min(limitX, x)), Math.max(-limitY, Math.min(limitY, y))];
  }

  static point(rect: number[], x: number, y: number): number[] | null {
    if (rect[2] <= 0 || rect[3] <= 0 || x < rect[0] || x > rect[0] + rect[2] ||
      y < rect[1] || y > rect[1] + rect[3]) { return null; }
    return [(x - rect[0]) / rect[2], (y - rect[1]) / rect[3]];
  }

  static clampPoint(rect: number[], width: number, height: number, x: number, y: number): number[] | null {
    const left = Math.max(0, rect[0]);
    const top = Math.max(0, rect[1]);
    const right = Math.min(width, rect[0] + rect[2]);
    const bottom = Math.min(height, rect[1] + rect[3]);
    if (right <= left || bottom <= top) { return null; }
    return VideoViewport.point(rect, Math.max(left, Math.min(right, x)), Math.max(top, Math.min(bottom, y)));
  }
}
