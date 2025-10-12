import 'package:auto_service_locator/auto_service_locator.dart';

// TODO(mfeinstein): [11/10/2025] Remove this later
void main() async {
  final locator = AutoServiceLocator();
  locator.registerSingleton((get) => A(1));
  locator.registerSingleton((get) async => B(await get(), await createCAsync()));

  final b = await locator.get<B>();
  final a = await locator.get<A>();

  print(b is B);
  print(a is A);
}

class A {
  A(this.i);

  int i;
}

class B {
  B(this.a, this.c);

  A a;
  C c;
}

class C {
  int c = 2;
}

Future<C> createCAsync() async {
  Future.delayed(Duration(microseconds: 10));
  return C();
}
