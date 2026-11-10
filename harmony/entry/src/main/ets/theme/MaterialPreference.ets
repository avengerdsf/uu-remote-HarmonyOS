import { hdsMaterial } from '@kit.UIDesignKit';
import { MaterialPreference } from '../model/Models';

export function materialLevel(preference: MaterialPreference = 'system'): hdsMaterial.MaterialLevel {
  if (!hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE)) {
    return hdsMaterial.MaterialLevel.SMOOTH;
  }
  switch (preference) {
    case 'exquisite': return hdsMaterial.MaterialLevel.EXQUISITE;
    case 'gentle': return hdsMaterial.MaterialLevel.GENTLE;
    case 'smooth': return hdsMaterial.MaterialLevel.SMOOTH;
    default: return hdsMaterial.MaterialLevel.ADAPTIVE;
  }
}

export function applyMaterialPreference(preference: MaterialPreference): void {
  AppStorage.setOrCreate('materialPreference', preference);
  AppStorage.setOrCreate('hdsMaterialLevel', materialLevel(preference));
}
