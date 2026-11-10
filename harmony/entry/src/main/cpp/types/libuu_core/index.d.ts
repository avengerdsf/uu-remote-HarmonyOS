declare const nativeCore: {
  create(configJson: string): number;
  command(handle: number, commandJson: string): number;
  poll(handle: number): string;
  destroy(handle: number): void;
  decoderCaps(handle: number): string;
  mediaStats(handle: number): string;
  setAudioVolume(handle: number, volume: number): number;
  version(): string;
};

export default nativeCore;
