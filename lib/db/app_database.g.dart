// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TapsTable extends Taps with TableInfo<$TapsTable, Tap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tappedAtMeta = const VerificationMeta(
    'tappedAt',
  );
  @override
  late final GeneratedColumn<int> tappedAt = GeneratedColumn<int>(
    'tapped_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, wordId, tappedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'taps';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tap> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('tapped_at')) {
      context.handle(
        _tappedAtMeta,
        tappedAt.isAcceptableOrUnknown(data['tapped_at']!, _tappedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_tappedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tap(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      wordId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}word_id'],
          )!,
      tappedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}tapped_at'],
          )!,
    );
  }

  @override
  $TapsTable createAlias(String alias) {
    return $TapsTable(attachedDatabase, alias);
  }
}

class Tap extends DataClass implements Insertable<Tap> {
  final int id;
  final int wordId;
  final int tappedAt;
  const Tap({required this.id, required this.wordId, required this.tappedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['word_id'] = Variable<int>(wordId);
    map['tapped_at'] = Variable<int>(tappedAt);
    return map;
  }

  TapsCompanion toCompanion(bool nullToAbsent) {
    return TapsCompanion(
      id: Value(id),
      wordId: Value(wordId),
      tappedAt: Value(tappedAt),
    );
  }

  factory Tap.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tap(
      id: serializer.fromJson<int>(json['id']),
      wordId: serializer.fromJson<int>(json['wordId']),
      tappedAt: serializer.fromJson<int>(json['tappedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'wordId': serializer.toJson<int>(wordId),
      'tappedAt': serializer.toJson<int>(tappedAt),
    };
  }

  Tap copyWith({int? id, int? wordId, int? tappedAt}) => Tap(
    id: id ?? this.id,
    wordId: wordId ?? this.wordId,
    tappedAt: tappedAt ?? this.tappedAt,
  );
  Tap copyWithCompanion(TapsCompanion data) {
    return Tap(
      id: data.id.present ? data.id.value : this.id,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      tappedAt: data.tappedAt.present ? data.tappedAt.value : this.tappedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tap(')
          ..write('id: $id, ')
          ..write('wordId: $wordId, ')
          ..write('tappedAt: $tappedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, wordId, tappedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tap &&
          other.id == this.id &&
          other.wordId == this.wordId &&
          other.tappedAt == this.tappedAt);
}

class TapsCompanion extends UpdateCompanion<Tap> {
  final Value<int> id;
  final Value<int> wordId;
  final Value<int> tappedAt;
  const TapsCompanion({
    this.id = const Value.absent(),
    this.wordId = const Value.absent(),
    this.tappedAt = const Value.absent(),
  });
  TapsCompanion.insert({
    this.id = const Value.absent(),
    required int wordId,
    required int tappedAt,
  }) : wordId = Value(wordId),
       tappedAt = Value(tappedAt);
  static Insertable<Tap> custom({
    Expression<int>? id,
    Expression<int>? wordId,
    Expression<int>? tappedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (wordId != null) 'word_id': wordId,
      if (tappedAt != null) 'tapped_at': tappedAt,
    });
  }

  TapsCompanion copyWith({
    Value<int>? id,
    Value<int>? wordId,
    Value<int>? tappedAt,
  }) {
    return TapsCompanion(
      id: id ?? this.id,
      wordId: wordId ?? this.wordId,
      tappedAt: tappedAt ?? this.tappedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (tappedAt.present) {
      map['tapped_at'] = Variable<int>(tappedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TapsCompanion(')
          ..write('id: $id, ')
          ..write('wordId: $wordId, ')
          ..write('tappedAt: $tappedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TapsTable taps = $TapsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [taps];
}

typedef $$TapsTableCreateCompanionBuilder =
    TapsCompanion Function({
      Value<int> id,
      required int wordId,
      required int tappedAt,
    });
typedef $$TapsTableUpdateCompanionBuilder =
    TapsCompanion Function({
      Value<int> id,
      Value<int> wordId,
      Value<int> tappedAt,
    });

class $$TapsTableFilterComposer extends Composer<_$AppDatabase, $TapsTable> {
  $$TapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tappedAt => $composableBuilder(
    column: $table.tappedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TapsTableOrderingComposer extends Composer<_$AppDatabase, $TapsTable> {
  $$TapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tappedAt => $composableBuilder(
    column: $table.tappedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TapsTable> {
  $$TapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get wordId =>
      $composableBuilder(column: $table.wordId, builder: (column) => column);

  GeneratedColumn<int> get tappedAt =>
      $composableBuilder(column: $table.tappedAt, builder: (column) => column);
}

class $$TapsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TapsTable,
          Tap,
          $$TapsTableFilterComposer,
          $$TapsTableOrderingComposer,
          $$TapsTableAnnotationComposer,
          $$TapsTableCreateCompanionBuilder,
          $$TapsTableUpdateCompanionBuilder,
          (Tap, BaseReferences<_$AppDatabase, $TapsTable, Tap>),
          Tap,
          PrefetchHooks Function()
        > {
  $$TapsTableTableManager(_$AppDatabase db, $TapsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$TapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> wordId = const Value.absent(),
                Value<int> tappedAt = const Value.absent(),
              }) => TapsCompanion(id: id, wordId: wordId, tappedAt: tappedAt),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int wordId,
                required int tappedAt,
              }) => TapsCompanion.insert(
                id: id,
                wordId: wordId,
                tappedAt: tappedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TapsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TapsTable,
      Tap,
      $$TapsTableFilterComposer,
      $$TapsTableOrderingComposer,
      $$TapsTableAnnotationComposer,
      $$TapsTableCreateCompanionBuilder,
      $$TapsTableUpdateCompanionBuilder,
      (Tap, BaseReferences<_$AppDatabase, $TapsTable, Tap>),
      Tap,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TapsTableTableManager get taps => $$TapsTableTableManager(_db, _db.taps);
}
