import 'package:auto_service_locator/auto_service_locator.dart';

// TODO(mfeinstein): [11/10/2025] Remove this later
void main() {
  final locator = AutoServiceLocator.instance;
  locator.registerSingleton((get) => A(1));
  locator.registerSingleton((get) async => B(await get()));
}

class A {
  A(this.i);

  int i;
}

class B {
  B(this.a);

  A a;
}
