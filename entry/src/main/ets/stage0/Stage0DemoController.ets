import { ImeConnectionService } from '../infrastructure/ime/ImeConnectionService';
import { NativeEngineGateway } from '../infrastructure/native/NativeEngineGateway';

export class Stage0DemoController {
  private readonly imeService: ImeConnectionService = new ImeConnectionService();
  private readonly nativeGateway: NativeEngineGateway = new NativeEngineGateway();

  getEngineVersion(): string {
    return this.nativeGateway.getEngineVersion();
  }

  async insertLetter(letter: string): Promise<boolean> {
    return this.imeService.insertText(letter);
  }

  async deleteBackward(): Promise<boolean> {
    return this.imeService.deleteBackward(1);
  }

  async insertSpace(): Promise<boolean> {
    return this.imeService.insertText(' ');
  }

  async sendEnter(): Promise<boolean> {
    return this.imeService.sendEnter();
  }

  async hideKeyboard(): Promise<boolean> {
    return this.imeService.hideKeyboard();
  }

}
