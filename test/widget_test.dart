import 'package:flutter_test/flutter_test.dart';
import 'package:moto_mesh_intercom/main.dart';

void main() {
  testWidgets('MotoMeshApp renders offline intercom home screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MotoMeshApp());
    expect(find.text('MotoMesh Offline'), findsOneWidget);
    expect(find.text('INICIAR RODADA OFFLINE'), findsOneWidget);
  });
}
