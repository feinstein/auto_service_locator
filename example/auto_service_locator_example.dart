import 'package:auto_service_locator/auto_service_locator.dart';

// TODO(mfeinstein): [11/10/2025] Remove this later
void main() async {
  final locator = AutoServiceLocator();
  locator.registerSingleton((get) => A(1));
  locator.registerSingleton((get) async => B(await get(), await createCAsync()));
  locator.registerSingleton(
    (get) async => B(await get(), await createCAsync()),
    withKey: '2ndB',
  );
  // TODO(mfeinstein): [13/10/2025] Add exception for registering dynamic?
  locator.registerSingleton((get) async => get<B>(withKey: '2ndB'), withKey: '3rdB');
  locator.registerSingleton((get) => 1, withKey: '3rdB');

  // final s = await locator.get<String>();
  final b = await locator.get<B>();
  final b2 = await locator.get<B>(withKey: '2ndB');
  final b3 = await locator.get<B>(withKey: '3rdB');
  final a = await locator.get<A>();

  print(b is B);
  print(b2 is B);
  print(b3 is B);
  print(identical(b2, b3));
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
  await Future<void>.delayed(const Duration(microseconds: 10));
  return C();
}
