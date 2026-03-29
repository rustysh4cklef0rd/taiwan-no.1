import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

part 'app_database.g.dart';

class Taps extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get wordId => integer()();
  IntColumn get tappedAt => integer()(); // Unix ms
}

@DriftDatabase(tables: [Taps])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(path.join(dir.path, 'chinese_widget.db'));
    return NativeDatabase.createInBackground(file);
  });
}

Future<String> getDatabasePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return path.join(dir.path, 'chinese_widget.db');
}
