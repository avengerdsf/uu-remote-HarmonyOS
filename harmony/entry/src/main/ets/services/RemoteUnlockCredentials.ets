import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { userAuth } from '@kit.UserAuthenticationKit';

const FINGERPRINT = userAuth.UserAuthType.FINGERPRINT;
const TRUST_LEVEL = userAuth.AuthTrustLevel.ATL3;
const MAX_SECRET_BYTES = 1024;
const AUTH_VALIDITY_SECONDS = 5;
const ASSET_NOT_FOUND = 24000002;
const CREDENTIAL_ERROR = 'Remote unlock credential unavailable';

/** Local credentials are isolated by the caller's full account and remote device scope. */
export class RemoteUnlockCredentials {
  static available(): boolean {
    if (!canIUse('SystemCapability.Security.Asset') || !canIUse('SystemCapability.UserIAM.UserAuth.Core') ||
      !canIUse('SystemCapability.Security.CryptoFramework')) { return false; }
    try {
      userAuth.getAvailableStatus(FINGERPRINT, TRUST_LEVEL);
      return true;
    } catch (_) {
      return false;
    }
  }

  static async has(scope: string): Promise<boolean> {
    try {
      const query = RemoteUnlockCredentials.queryFor(scope);
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
      const matches = await asset.query(query);
      return matches[0]?.get(asset.Tag.AUTH_TYPE) === asset.AuthType.ANY;
    } catch (error) {
      if ((error as BusinessError).code === ASSET_NOT_FOUND) { return false; }
      throw new Error(CREDENTIAL_ERROR);
    }
  }

  static async save(scope: string, password: string): Promise<void> {
    if (!RemoteUnlockCredentials.available() || password.length === 0 || password.length > MAX_SECRET_BYTES) {
      throw new Error(CREDENTIAL_ERROR);
    }
    const secret = new util.TextEncoder().encodeInto(password);
    try {
      if (secret.byteLength > MAX_SECRET_BYTES) { throw new Error(CREDENTIAL_ERROR); }
      const attributes = RemoteUnlockCredentials.queryFor(scope);
      attributes.set(asset.Tag.SECRET, secret);
      attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
      attributes.set(asset.Tag.REQUIRE_PASSWORD_SET, true);
      attributes.set(asset.Tag.AUTH_TYPE, asset.AuthType.ANY);
      attributes.set(asset.Tag.AUTH_VALIDITY_PERIOD, AUTH_VALIDITY_SECONDS);
      attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
      attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
      await asset.add(attributes);
    } catch (_) {
      throw new Error(CREDENTIAL_ERROR);
    } finally {
      secret.fill(0);
    }
  }

  static async remove(scope: string): Promise<void> {
    try {
      await asset.remove(RemoteUnlockCredentials.queryFor(scope));
    } catch (error) {
      if ((error as BusinessError).code !== ASSET_NOT_FOUND) { throw new Error(CREDENTIAL_ERROR); }
    }
  }

  static async read(scope: string, title: string): Promise<string | null> {
    if (!RemoteUnlockCredentials.available()) { throw new Error(CREDENTIAL_ERROR); }
    let challenge: Uint8Array | undefined;
    let token: Uint8Array | null = null;
    let secret: Uint8Array | undefined;
    try {
      const query = RemoteUnlockCredentials.queryFor(scope);
      query.set(asset.Tag.AUTH_TYPE, asset.AuthType.ANY);
      challenge = await asset.preQuery(query);
      if (challenge.byteLength !== 32) { throw new Error(CREDENTIAL_ERROR); }
      token = await RemoteUnlockCredentials.authenticate(challenge, title);
      if (token === null) { return null; }
      query.set(asset.Tag.AUTH_CHALLENGE, challenge);
      query.set(asset.Tag.AUTH_TOKEN, token);
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const matches = await asset.query(query);
      const value = matches[0]?.get(asset.Tag.SECRET);
      if (!(value instanceof Uint8Array)) { throw new Error(CREDENTIAL_ERROR); }
      secret = value;
      if (secret.byteLength === 0 || secret.byteLength > MAX_SECRET_BYTES) { throw new Error(CREDENTIAL_ERROR); }
      return util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(secret);
    } catch (_) {
      throw new Error(CREDENTIAL_ERROR);
    } finally {
      secret?.fill(0);
      token?.fill(0);
      if (challenge !== undefined) {
        const handle: asset.AssetMap = new Map();
        handle.set(asset.Tag.AUTH_CHALLENGE, challenge);
        try { await asset.postQuery(handle); } catch (_) { /* The authentication data is still cleared. */ }
        challenge.fill(0);
      }
    }
  }

  private static queryFor(scope: string): asset.AssetMap {
    if (scope.length === 0) { throw new Error(CREDENTIAL_ERROR); }
    const encoded = new util.TextEncoder().encodeInto('uu.remote.unlock.v1:' + scope);
    try {
      const digest = cryptoFramework.createMd('SHA256');
      digest.updateSync({ data: encoded });
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, digest.digestSync().data);
      return query;
    } finally {
      encoded.fill(0);
    }
  }

  private static async authenticate(challenge: Uint8Array, title: string): Promise<Uint8Array | null> {
    const auth = userAuth.getUserAuthInstance({ challenge: challenge, authType: [FINGERPRINT],
      authTrustLevel: TRUST_LEVEL }, { title: title });
    try {
      return await new Promise<Uint8Array | null>((resolve, reject) => {
        auth.on('result', {
          onResult(result: userAuth.UserAuthResult): void {
            const token = result.token;
            if (result.result === userAuth.UserAuthResultCode.SUCCESS && token !== undefined && token.byteLength > 0 &&
              (result.authType === undefined || result.authType === FINGERPRINT)) {
              resolve(token);
              return;
            }
            token?.fill(0);
            if (result.result === userAuth.UserAuthResultCode.CANCELED ||
              result.result === userAuth.UserAuthResultCode.CANCELED_FROM_WIDGET) { resolve(null); }
            else { reject(new Error(CREDENTIAL_ERROR)); }
          }
        });
        auth.start();
      });
    } finally {
      try { auth.off('result'); } catch (_) { /* This instance is used for a single prompt. */ }
    }
  }
}
