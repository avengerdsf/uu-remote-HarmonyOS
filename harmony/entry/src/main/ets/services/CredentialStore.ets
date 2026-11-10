import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { CredentialsPayload } from '../model/Models';

/**
 * Login credentials live in the HarmonyOS asset store, never in plaintext
 * preferences or logs. The alias is fixed per installation.
 */
export class CredentialStore {
  private static readonly ALIAS: string = 'uu_remote_credentials';

  private static bytes(value: string): Uint8Array {
    return new util.TextEncoder().encodeInto(value);
  }

  static async save(credentials: CredentialsPayload): Promise<void> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, CredentialStore.bytes(CredentialStore.ALIAS));
      await asset.remove(query);
    } catch (error) {
      // Missing entry is expected on first login.
    }
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, CredentialStore.bytes(CredentialStore.ALIAS));
    attributes.set(asset.Tag.SECRET, CredentialStore.bytes(JSON.stringify(credentials)));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.DATA_LABEL_NORMAL_1, CredentialStore.bytes('uu-remote'));
    await asset.add(attributes);
  }

  static async load(): Promise<CredentialsPayload | null> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, CredentialStore.bytes(CredentialStore.ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result = await asset.query(query);
      if (result.length === 0) {
        return null;
      }
      const secret = result[0].get(asset.Tag.SECRET);
      if (secret === undefined) {
        return null;
      }
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(secret as ArrayBuffer));
      return JSON.parse(text) as CredentialsPayload;
    } catch (error) {
      return null;
    }
  }

  static async clear(): Promise<void> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, CredentialStore.bytes(CredentialStore.ALIAS));
      await asset.remove(query);
    } catch (error) {
      // Nothing to remove.
    }
  }
}
