/**
 * Minimal application router shared by all three form factors. The route and a
 * monotonically increasing version live in AppStorage so Index.ets re-renders
 * without any page owning navigation state.
 */
export class Router {
  private static stack: string[] = ['devices'];

  static current(): string {
    return Router.stack[Router.stack.length - 1];
  }

  static push(route: string): void {
    Router.stack.push(route);
    Router.publish();
  }

  static replace(route: string): void {
    Router.stack[Router.stack.length - 1] = route;
    Router.publish();
  }

  static back(): boolean {
    if (Router.stack.length <= 1) {
      return false;
    }
    Router.stack.pop();
    Router.publish();
    return true;
  }

  static backTo(route: string): void {
    const index = Router.stack.lastIndexOf(route);
    if (index >= 0) {
      Router.stack = Router.stack.slice(0, index + 1);
    } else {
      Router.stack = [route];
    }
    Router.publish();
  }

  static reset(route: string): void {
    Router.stack = [route];
    Router.publish();
  }

  static depth(): number {
    return Router.stack.length;
  }

  private static publish(): void {
    const version = AppStorage.get<number>('routeVersion') ?? 0;
    AppStorage.setOrCreate('route', Router.current());
    AppStorage.setOrCreate('routeVersion', version + 1);
  }
}
