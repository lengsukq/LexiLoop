// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $WordsTable extends Words with TableInfo<$WordsTable, WordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WordsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _termMeta = const VerificationMeta('term');
  @override
  late final GeneratedColumn<String> term = GeneratedColumn<String>(
    'term',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedTermMeta = const VerificationMeta(
    'normalizedTerm',
  );
  @override
  late final GeneratedColumn<String> normalizedTerm = GeneratedColumn<String>(
    'normalized_term',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceLanguageMeta = const VerificationMeta(
    'sourceLanguage',
  );
  @override
  late final GeneratedColumn<String> sourceLanguage = GeneratedColumn<String>(
    'source_language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetLanguageMeta = const VerificationMeta(
    'targetLanguage',
  );
  @override
  late final GeneratedColumn<String> targetLanguage = GeneratedColumn<String>(
    'target_language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceLanguageNameMeta =
      const VerificationMeta('sourceLanguageName');
  @override
  late final GeneratedColumn<String> sourceLanguageName =
      GeneratedColumn<String>(
        'source_language_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _targetLanguageNameMeta =
      const VerificationMeta('targetLanguageName');
  @override
  late final GeneratedColumn<String> targetLanguageName =
      GeneratedColumn<String>(
        'target_language_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<EntryType, String> entryType =
      GeneratedColumn<String>(
        'entry_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EntryType>($WordsTable.$converterentryType);
  @override
  late final GeneratedColumnWithTypeConverter<LexicalContentType, String>
  contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('WORD'),
  ).withConverter<LexicalContentType>($WordsTable.$convertercontentType);
  static const VerificationMeta _sourceCreatedAtMeta = const VerificationMeta(
    'sourceCreatedAt',
  );
  @override
  late final GeneratedColumn<int> sourceCreatedAt = GeneratedColumn<int>(
    'source_created_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<InitializationStatus, String>
  initializationStatus =
      GeneratedColumn<String>(
        'initialization_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('PENDING'),
      ).withConverter<InitializationStatus>(
        $WordsTable.$converterinitializationStatus,
      );
  @override
  late final GeneratedColumnWithTypeConverter<MasteryLevel, String>
  masteryLevel = GeneratedColumn<String>(
    'mastery_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('NEW'),
  ).withConverter<MasteryLevel>($WordsTable.$convertermasteryLevel);
  static const VerificationMeta _masteryScoreMeta = const VerificationMeta(
    'masteryScore',
  );
  @override
  late final GeneratedColumn<int> masteryScore = GeneratedColumn<int>(
    'mastery_score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isSuspendedMeta = const VerificationMeta(
    'isSuspended',
  );
  @override
  late final GeneratedColumn<bool> isSuspended = GeneratedColumn<bool>(
    'is_suspended',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_suspended" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _userNoteMeta = const VerificationMeta(
    'userNote',
  );
  @override
  late final GeneratedColumn<String> userNote = GeneratedColumn<String>(
    'user_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    term,
    normalizedTerm,
    sourceLanguage,
    targetLanguage,
    sourceLanguageName,
    targetLanguageName,
    entryType,
    contentType,
    sourceCreatedAt,
    initializationStatus,
    masteryLevel,
    masteryScore,
    isSuspended,
    userNote,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'words';
  @override
  VerificationContext validateIntegrity(
    Insertable<WordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('term')) {
      context.handle(
        _termMeta,
        term.isAcceptableOrUnknown(data['term']!, _termMeta),
      );
    } else if (isInserting) {
      context.missing(_termMeta);
    }
    if (data.containsKey('normalized_term')) {
      context.handle(
        _normalizedTermMeta,
        normalizedTerm.isAcceptableOrUnknown(
          data['normalized_term']!,
          _normalizedTermMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedTermMeta);
    }
    if (data.containsKey('source_language')) {
      context.handle(
        _sourceLanguageMeta,
        sourceLanguage.isAcceptableOrUnknown(
          data['source_language']!,
          _sourceLanguageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLanguageMeta);
    }
    if (data.containsKey('target_language')) {
      context.handle(
        _targetLanguageMeta,
        targetLanguage.isAcceptableOrUnknown(
          data['target_language']!,
          _targetLanguageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetLanguageMeta);
    }
    if (data.containsKey('source_language_name')) {
      context.handle(
        _sourceLanguageNameMeta,
        sourceLanguageName.isAcceptableOrUnknown(
          data['source_language_name']!,
          _sourceLanguageNameMeta,
        ),
      );
    }
    if (data.containsKey('target_language_name')) {
      context.handle(
        _targetLanguageNameMeta,
        targetLanguageName.isAcceptableOrUnknown(
          data['target_language_name']!,
          _targetLanguageNameMeta,
        ),
      );
    }
    if (data.containsKey('source_created_at')) {
      context.handle(
        _sourceCreatedAtMeta,
        sourceCreatedAt.isAcceptableOrUnknown(
          data['source_created_at']!,
          _sourceCreatedAtMeta,
        ),
      );
    }
    if (data.containsKey('mastery_score')) {
      context.handle(
        _masteryScoreMeta,
        masteryScore.isAcceptableOrUnknown(
          data['mastery_score']!,
          _masteryScoreMeta,
        ),
      );
    }
    if (data.containsKey('is_suspended')) {
      context.handle(
        _isSuspendedMeta,
        isSuspended.isAcceptableOrUnknown(
          data['is_suspended']!,
          _isSuspendedMeta,
        ),
      );
    }
    if (data.containsKey('user_note')) {
      context.handle(
        _userNoteMeta,
        userNote.isAcceptableOrUnknown(data['user_note']!, _userNoteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {normalizedTerm, sourceLanguage, targetLanguage},
  ];
  @override
  WordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WordRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      term: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term'],
      )!,
      normalizedTerm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_term'],
      )!,
      sourceLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_language'],
      )!,
      targetLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_language'],
      )!,
      sourceLanguageName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_language_name'],
      ),
      targetLanguageName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_language_name'],
      ),
      entryType: $WordsTable.$converterentryType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}entry_type'],
        )!,
      ),
      contentType: $WordsTable.$convertercontentType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}content_type'],
        )!,
      ),
      sourceCreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_created_at'],
      ),
      initializationStatus: $WordsTable.$converterinitializationStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}initialization_status'],
        )!,
      ),
      masteryLevel: $WordsTable.$convertermasteryLevel.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mastery_level'],
        )!,
      ),
      masteryScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mastery_score'],
      )!,
      isSuspended: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_suspended'],
      )!,
      userNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WordsTable createAlias(String alias) {
    return $WordsTable(attachedDatabase, alias);
  }

  static TypeConverter<EntryType, String> $converterentryType =
      const WireEnumConverter<EntryType>(EntryType.values);
  static TypeConverter<LexicalContentType, String> $convertercontentType =
      const WireEnumConverter<LexicalContentType>(LexicalContentType.values);
  static TypeConverter<InitializationStatus, String>
  $converterinitializationStatus =
      const WireEnumConverter<InitializationStatus>(
        InitializationStatus.values,
      );
  static TypeConverter<MasteryLevel, String> $convertermasteryLevel =
      const WireEnumConverter<MasteryLevel>(MasteryLevel.values);
}

class WordRow extends DataClass implements Insertable<WordRow> {
  final int id;
  final String term;
  final String normalizedTerm;
  final String sourceLanguage;
  final String targetLanguage;
  final String? sourceLanguageName;
  final String? targetLanguageName;
  final EntryType entryType;
  final LexicalContentType contentType;
  final int? sourceCreatedAt;
  final InitializationStatus initializationStatus;
  final MasteryLevel masteryLevel;
  final int masteryScore;
  final bool isSuspended;
  final String? userNote;
  final int createdAt;
  final int updatedAt;
  const WordRow({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.sourceLanguageName,
    this.targetLanguageName,
    required this.entryType,
    required this.contentType,
    this.sourceCreatedAt,
    required this.initializationStatus,
    required this.masteryLevel,
    required this.masteryScore,
    required this.isSuspended,
    this.userNote,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['term'] = Variable<String>(term);
    map['normalized_term'] = Variable<String>(normalizedTerm);
    map['source_language'] = Variable<String>(sourceLanguage);
    map['target_language'] = Variable<String>(targetLanguage);
    if (!nullToAbsent || sourceLanguageName != null) {
      map['source_language_name'] = Variable<String>(sourceLanguageName);
    }
    if (!nullToAbsent || targetLanguageName != null) {
      map['target_language_name'] = Variable<String>(targetLanguageName);
    }
    {
      map['entry_type'] = Variable<String>(
        $WordsTable.$converterentryType.toSql(entryType),
      );
    }
    {
      map['content_type'] = Variable<String>(
        $WordsTable.$convertercontentType.toSql(contentType),
      );
    }
    if (!nullToAbsent || sourceCreatedAt != null) {
      map['source_created_at'] = Variable<int>(sourceCreatedAt);
    }
    {
      map['initialization_status'] = Variable<String>(
        $WordsTable.$converterinitializationStatus.toSql(initializationStatus),
      );
    }
    {
      map['mastery_level'] = Variable<String>(
        $WordsTable.$convertermasteryLevel.toSql(masteryLevel),
      );
    }
    map['mastery_score'] = Variable<int>(masteryScore);
    map['is_suspended'] = Variable<bool>(isSuspended);
    if (!nullToAbsent || userNote != null) {
      map['user_note'] = Variable<String>(userNote);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  WordsCompanion toCompanion(bool nullToAbsent) {
    return WordsCompanion(
      id: Value(id),
      term: Value(term),
      normalizedTerm: Value(normalizedTerm),
      sourceLanguage: Value(sourceLanguage),
      targetLanguage: Value(targetLanguage),
      sourceLanguageName: sourceLanguageName == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceLanguageName),
      targetLanguageName: targetLanguageName == null && nullToAbsent
          ? const Value.absent()
          : Value(targetLanguageName),
      entryType: Value(entryType),
      contentType: Value(contentType),
      sourceCreatedAt: sourceCreatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceCreatedAt),
      initializationStatus: Value(initializationStatus),
      masteryLevel: Value(masteryLevel),
      masteryScore: Value(masteryScore),
      isSuspended: Value(isSuspended),
      userNote: userNote == null && nullToAbsent
          ? const Value.absent()
          : Value(userNote),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WordRow(
      id: serializer.fromJson<int>(json['id']),
      term: serializer.fromJson<String>(json['term']),
      normalizedTerm: serializer.fromJson<String>(json['normalizedTerm']),
      sourceLanguage: serializer.fromJson<String>(json['sourceLanguage']),
      targetLanguage: serializer.fromJson<String>(json['targetLanguage']),
      sourceLanguageName: serializer.fromJson<String?>(
        json['sourceLanguageName'],
      ),
      targetLanguageName: serializer.fromJson<String?>(
        json['targetLanguageName'],
      ),
      entryType: serializer.fromJson<EntryType>(json['entryType']),
      contentType: serializer.fromJson<LexicalContentType>(json['contentType']),
      sourceCreatedAt: serializer.fromJson<int?>(json['sourceCreatedAt']),
      initializationStatus: serializer.fromJson<InitializationStatus>(
        json['initializationStatus'],
      ),
      masteryLevel: serializer.fromJson<MasteryLevel>(json['masteryLevel']),
      masteryScore: serializer.fromJson<int>(json['masteryScore']),
      isSuspended: serializer.fromJson<bool>(json['isSuspended']),
      userNote: serializer.fromJson<String?>(json['userNote']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'term': serializer.toJson<String>(term),
      'normalizedTerm': serializer.toJson<String>(normalizedTerm),
      'sourceLanguage': serializer.toJson<String>(sourceLanguage),
      'targetLanguage': serializer.toJson<String>(targetLanguage),
      'sourceLanguageName': serializer.toJson<String?>(sourceLanguageName),
      'targetLanguageName': serializer.toJson<String?>(targetLanguageName),
      'entryType': serializer.toJson<EntryType>(entryType),
      'contentType': serializer.toJson<LexicalContentType>(contentType),
      'sourceCreatedAt': serializer.toJson<int?>(sourceCreatedAt),
      'initializationStatus': serializer.toJson<InitializationStatus>(
        initializationStatus,
      ),
      'masteryLevel': serializer.toJson<MasteryLevel>(masteryLevel),
      'masteryScore': serializer.toJson<int>(masteryScore),
      'isSuspended': serializer.toJson<bool>(isSuspended),
      'userNote': serializer.toJson<String?>(userNote),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  WordRow copyWith({
    int? id,
    String? term,
    String? normalizedTerm,
    String? sourceLanguage,
    String? targetLanguage,
    Value<String?> sourceLanguageName = const Value.absent(),
    Value<String?> targetLanguageName = const Value.absent(),
    EntryType? entryType,
    LexicalContentType? contentType,
    Value<int?> sourceCreatedAt = const Value.absent(),
    InitializationStatus? initializationStatus,
    MasteryLevel? masteryLevel,
    int? masteryScore,
    bool? isSuspended,
    Value<String?> userNote = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => WordRow(
    id: id ?? this.id,
    term: term ?? this.term,
    normalizedTerm: normalizedTerm ?? this.normalizedTerm,
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    sourceLanguageName: sourceLanguageName.present
        ? sourceLanguageName.value
        : this.sourceLanguageName,
    targetLanguageName: targetLanguageName.present
        ? targetLanguageName.value
        : this.targetLanguageName,
    entryType: entryType ?? this.entryType,
    contentType: contentType ?? this.contentType,
    sourceCreatedAt: sourceCreatedAt.present
        ? sourceCreatedAt.value
        : this.sourceCreatedAt,
    initializationStatus: initializationStatus ?? this.initializationStatus,
    masteryLevel: masteryLevel ?? this.masteryLevel,
    masteryScore: masteryScore ?? this.masteryScore,
    isSuspended: isSuspended ?? this.isSuspended,
    userNote: userNote.present ? userNote.value : this.userNote,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WordRow copyWithCompanion(WordsCompanion data) {
    return WordRow(
      id: data.id.present ? data.id.value : this.id,
      term: data.term.present ? data.term.value : this.term,
      normalizedTerm: data.normalizedTerm.present
          ? data.normalizedTerm.value
          : this.normalizedTerm,
      sourceLanguage: data.sourceLanguage.present
          ? data.sourceLanguage.value
          : this.sourceLanguage,
      targetLanguage: data.targetLanguage.present
          ? data.targetLanguage.value
          : this.targetLanguage,
      sourceLanguageName: data.sourceLanguageName.present
          ? data.sourceLanguageName.value
          : this.sourceLanguageName,
      targetLanguageName: data.targetLanguageName.present
          ? data.targetLanguageName.value
          : this.targetLanguageName,
      entryType: data.entryType.present ? data.entryType.value : this.entryType,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      sourceCreatedAt: data.sourceCreatedAt.present
          ? data.sourceCreatedAt.value
          : this.sourceCreatedAt,
      initializationStatus: data.initializationStatus.present
          ? data.initializationStatus.value
          : this.initializationStatus,
      masteryLevel: data.masteryLevel.present
          ? data.masteryLevel.value
          : this.masteryLevel,
      masteryScore: data.masteryScore.present
          ? data.masteryScore.value
          : this.masteryScore,
      isSuspended: data.isSuspended.present
          ? data.isSuspended.value
          : this.isSuspended,
      userNote: data.userNote.present ? data.userNote.value : this.userNote,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WordRow(')
          ..write('id: $id, ')
          ..write('term: $term, ')
          ..write('normalizedTerm: $normalizedTerm, ')
          ..write('sourceLanguage: $sourceLanguage, ')
          ..write('targetLanguage: $targetLanguage, ')
          ..write('sourceLanguageName: $sourceLanguageName, ')
          ..write('targetLanguageName: $targetLanguageName, ')
          ..write('entryType: $entryType, ')
          ..write('contentType: $contentType, ')
          ..write('sourceCreatedAt: $sourceCreatedAt, ')
          ..write('initializationStatus: $initializationStatus, ')
          ..write('masteryLevel: $masteryLevel, ')
          ..write('masteryScore: $masteryScore, ')
          ..write('isSuspended: $isSuspended, ')
          ..write('userNote: $userNote, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    term,
    normalizedTerm,
    sourceLanguage,
    targetLanguage,
    sourceLanguageName,
    targetLanguageName,
    entryType,
    contentType,
    sourceCreatedAt,
    initializationStatus,
    masteryLevel,
    masteryScore,
    isSuspended,
    userNote,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordRow &&
          other.id == this.id &&
          other.term == this.term &&
          other.normalizedTerm == this.normalizedTerm &&
          other.sourceLanguage == this.sourceLanguage &&
          other.targetLanguage == this.targetLanguage &&
          other.sourceLanguageName == this.sourceLanguageName &&
          other.targetLanguageName == this.targetLanguageName &&
          other.entryType == this.entryType &&
          other.contentType == this.contentType &&
          other.sourceCreatedAt == this.sourceCreatedAt &&
          other.initializationStatus == this.initializationStatus &&
          other.masteryLevel == this.masteryLevel &&
          other.masteryScore == this.masteryScore &&
          other.isSuspended == this.isSuspended &&
          other.userNote == this.userNote &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WordsCompanion extends UpdateCompanion<WordRow> {
  final Value<int> id;
  final Value<String> term;
  final Value<String> normalizedTerm;
  final Value<String> sourceLanguage;
  final Value<String> targetLanguage;
  final Value<String?> sourceLanguageName;
  final Value<String?> targetLanguageName;
  final Value<EntryType> entryType;
  final Value<LexicalContentType> contentType;
  final Value<int?> sourceCreatedAt;
  final Value<InitializationStatus> initializationStatus;
  final Value<MasteryLevel> masteryLevel;
  final Value<int> masteryScore;
  final Value<bool> isSuspended;
  final Value<String?> userNote;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const WordsCompanion({
    this.id = const Value.absent(),
    this.term = const Value.absent(),
    this.normalizedTerm = const Value.absent(),
    this.sourceLanguage = const Value.absent(),
    this.targetLanguage = const Value.absent(),
    this.sourceLanguageName = const Value.absent(),
    this.targetLanguageName = const Value.absent(),
    this.entryType = const Value.absent(),
    this.contentType = const Value.absent(),
    this.sourceCreatedAt = const Value.absent(),
    this.initializationStatus = const Value.absent(),
    this.masteryLevel = const Value.absent(),
    this.masteryScore = const Value.absent(),
    this.isSuspended = const Value.absent(),
    this.userNote = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WordsCompanion.insert({
    this.id = const Value.absent(),
    required String term,
    required String normalizedTerm,
    required String sourceLanguage,
    required String targetLanguage,
    this.sourceLanguageName = const Value.absent(),
    this.targetLanguageName = const Value.absent(),
    required EntryType entryType,
    this.contentType = const Value.absent(),
    this.sourceCreatedAt = const Value.absent(),
    this.initializationStatus = const Value.absent(),
    this.masteryLevel = const Value.absent(),
    this.masteryScore = const Value.absent(),
    this.isSuspended = const Value.absent(),
    this.userNote = const Value.absent(),
    required int createdAt,
    required int updatedAt,
  }) : term = Value(term),
       normalizedTerm = Value(normalizedTerm),
       sourceLanguage = Value(sourceLanguage),
       targetLanguage = Value(targetLanguage),
       entryType = Value(entryType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<WordRow> custom({
    Expression<int>? id,
    Expression<String>? term,
    Expression<String>? normalizedTerm,
    Expression<String>? sourceLanguage,
    Expression<String>? targetLanguage,
    Expression<String>? sourceLanguageName,
    Expression<String>? targetLanguageName,
    Expression<String>? entryType,
    Expression<String>? contentType,
    Expression<int>? sourceCreatedAt,
    Expression<String>? initializationStatus,
    Expression<String>? masteryLevel,
    Expression<int>? masteryScore,
    Expression<bool>? isSuspended,
    Expression<String>? userNote,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (term != null) 'term': term,
      if (normalizedTerm != null) 'normalized_term': normalizedTerm,
      if (sourceLanguage != null) 'source_language': sourceLanguage,
      if (targetLanguage != null) 'target_language': targetLanguage,
      if (sourceLanguageName != null)
        'source_language_name': sourceLanguageName,
      if (targetLanguageName != null)
        'target_language_name': targetLanguageName,
      if (entryType != null) 'entry_type': entryType,
      if (contentType != null) 'content_type': contentType,
      if (sourceCreatedAt != null) 'source_created_at': sourceCreatedAt,
      if (initializationStatus != null)
        'initialization_status': initializationStatus,
      if (masteryLevel != null) 'mastery_level': masteryLevel,
      if (masteryScore != null) 'mastery_score': masteryScore,
      if (isSuspended != null) 'is_suspended': isSuspended,
      if (userNote != null) 'user_note': userNote,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WordsCompanion copyWith({
    Value<int>? id,
    Value<String>? term,
    Value<String>? normalizedTerm,
    Value<String>? sourceLanguage,
    Value<String>? targetLanguage,
    Value<String?>? sourceLanguageName,
    Value<String?>? targetLanguageName,
    Value<EntryType>? entryType,
    Value<LexicalContentType>? contentType,
    Value<int?>? sourceCreatedAt,
    Value<InitializationStatus>? initializationStatus,
    Value<MasteryLevel>? masteryLevel,
    Value<int>? masteryScore,
    Value<bool>? isSuspended,
    Value<String?>? userNote,
    Value<int>? createdAt,
    Value<int>? updatedAt,
  }) {
    return WordsCompanion(
      id: id ?? this.id,
      term: term ?? this.term,
      normalizedTerm: normalizedTerm ?? this.normalizedTerm,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      sourceLanguageName: sourceLanguageName ?? this.sourceLanguageName,
      targetLanguageName: targetLanguageName ?? this.targetLanguageName,
      entryType: entryType ?? this.entryType,
      contentType: contentType ?? this.contentType,
      sourceCreatedAt: sourceCreatedAt ?? this.sourceCreatedAt,
      initializationStatus: initializationStatus ?? this.initializationStatus,
      masteryLevel: masteryLevel ?? this.masteryLevel,
      masteryScore: masteryScore ?? this.masteryScore,
      isSuspended: isSuspended ?? this.isSuspended,
      userNote: userNote ?? this.userNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (term.present) {
      map['term'] = Variable<String>(term.value);
    }
    if (normalizedTerm.present) {
      map['normalized_term'] = Variable<String>(normalizedTerm.value);
    }
    if (sourceLanguage.present) {
      map['source_language'] = Variable<String>(sourceLanguage.value);
    }
    if (targetLanguage.present) {
      map['target_language'] = Variable<String>(targetLanguage.value);
    }
    if (sourceLanguageName.present) {
      map['source_language_name'] = Variable<String>(sourceLanguageName.value);
    }
    if (targetLanguageName.present) {
      map['target_language_name'] = Variable<String>(targetLanguageName.value);
    }
    if (entryType.present) {
      map['entry_type'] = Variable<String>(
        $WordsTable.$converterentryType.toSql(entryType.value),
      );
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(
        $WordsTable.$convertercontentType.toSql(contentType.value),
      );
    }
    if (sourceCreatedAt.present) {
      map['source_created_at'] = Variable<int>(sourceCreatedAt.value);
    }
    if (initializationStatus.present) {
      map['initialization_status'] = Variable<String>(
        $WordsTable.$converterinitializationStatus.toSql(
          initializationStatus.value,
        ),
      );
    }
    if (masteryLevel.present) {
      map['mastery_level'] = Variable<String>(
        $WordsTable.$convertermasteryLevel.toSql(masteryLevel.value),
      );
    }
    if (masteryScore.present) {
      map['mastery_score'] = Variable<int>(masteryScore.value);
    }
    if (isSuspended.present) {
      map['is_suspended'] = Variable<bool>(isSuspended.value);
    }
    if (userNote.present) {
      map['user_note'] = Variable<String>(userNote.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WordsCompanion(')
          ..write('id: $id, ')
          ..write('term: $term, ')
          ..write('normalizedTerm: $normalizedTerm, ')
          ..write('sourceLanguage: $sourceLanguage, ')
          ..write('targetLanguage: $targetLanguage, ')
          ..write('sourceLanguageName: $sourceLanguageName, ')
          ..write('targetLanguageName: $targetLanguageName, ')
          ..write('entryType: $entryType, ')
          ..write('contentType: $contentType, ')
          ..write('sourceCreatedAt: $sourceCreatedAt, ')
          ..write('initializationStatus: $initializationStatus, ')
          ..write('masteryLevel: $masteryLevel, ')
          ..write('masteryScore: $masteryScore, ')
          ..write('isSuspended: $isSuspended, ')
          ..write('userNote: $userNote, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $WordContentsTable extends WordContents
    with TableInfo<$WordContentsTable, WordContentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WordContentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _definitionsJsonMeta = const VerificationMeta(
    'definitionsJson',
  );
  @override
  late final GeneratedColumn<String> definitionsJson = GeneratedColumn<String>(
    'definitions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _pronunciationsJsonMeta =
      const VerificationMeta('pronunciationsJson');
  @override
  late final GeneratedColumn<String> pronunciationsJson =
      GeneratedColumn<String>(
        'pronunciations_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _examplesJsonMeta = const VerificationMeta(
    'examplesJson',
  );
  @override
  late final GeneratedColumn<String> examplesJson = GeneratedColumn<String>(
    'examples_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _phrasesJsonMeta = const VerificationMeta(
    'phrasesJson',
  );
  @override
  late final GeneratedColumn<String> phrasesJson = GeneratedColumn<String>(
    'phrases_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _formsJsonMeta = const VerificationMeta(
    'formsJson',
  );
  @override
  late final GeneratedColumn<String> formsJson = GeneratedColumn<String>(
    'forms_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _synonymsJsonMeta = const VerificationMeta(
    'synonymsJson',
  );
  @override
  late final GeneratedColumn<String> synonymsJson = GeneratedColumn<String>(
    'synonyms_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _antonymsJsonMeta = const VerificationMeta(
    'antonymsJson',
  );
  @override
  late final GeneratedColumn<String> antonymsJson = GeneratedColumn<String>(
    'antonyms_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _wordFamilyJsonMeta = const VerificationMeta(
    'wordFamilyJson',
  );
  @override
  late final GeneratedColumn<String> wordFamilyJson = GeneratedColumn<String>(
    'word_family_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _confusedWordsJsonMeta = const VerificationMeta(
    'confusedWordsJson',
  );
  @override
  late final GeneratedColumn<String> confusedWordsJson =
      GeneratedColumn<String>(
        'confused_words_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _rootsJsonMeta = const VerificationMeta(
    'rootsJson',
  );
  @override
  late final GeneratedColumn<String> rootsJson = GeneratedColumn<String>(
    'roots_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _affixesJsonMeta = const VerificationMeta(
    'affixesJson',
  );
  @override
  late final GeneratedColumn<String> affixesJson = GeneratedColumn<String>(
    'affixes_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _summaryJsonMeta = const VerificationMeta(
    'summaryJson',
  );
  @override
  late final GeneratedColumn<String> summaryJson = GeneratedColumn<String>(
    'summary_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(
      '{"shortDefinition":null,"translation":null,'
      '"cefrLevel":null,"frequency":null}',
    ),
  );
  static const VerificationMeta _learningJsonMeta = const VerificationMeta(
    'learningJson',
  );
  @override
  late final GeneratedColumn<String> learningJson = GeneratedColumn<String>(
    'learning_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(
      '{"pronunciationTip":null,"mnemonic":null,"commonMistakes":[]}',
    ),
  );
  static const VerificationMeta _sentenceAnalysisJsonMeta =
      const VerificationMeta('sentenceAnalysisJson');
  @override
  late final GeneratedColumn<String> sentenceAnalysisJson =
      GeneratedColumn<String>(
        'sentence_analysis_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(
          '{"grammarPattern":null,"grammarExplanation":null,"grammarNotes":[],'
          '"keyExpressions":[],"similarExamples":[],"variations":[]}',
        ),
      );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _providerMetadataJsonMeta =
      const VerificationMeta('providerMetadataJson');
  @override
  late final GeneratedColumn<String> providerMetadataJson =
      GeneratedColumn<String>(
        'provider_metadata_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  @override
  late final GeneratedColumnWithTypeConverter<ContentSource, String>
  contentSource = GeneratedColumn<String>(
    'content_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('MIXED'),
  ).withConverter<ContentSource>($WordContentsTable.$convertercontentSource);
  static const VerificationMeta _contentVersionMeta = const VerificationMeta(
    'contentVersion',
  );
  @override
  late final GeneratedColumn<int> contentVersion = GeneratedColumn<int>(
    'content_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _initializedAtMeta = const VerificationMeta(
    'initializedAt',
  );
  @override
  late final GeneratedColumn<int> initializedAt = GeneratedColumn<int>(
    'initialized_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    wordId,
    definitionsJson,
    pronunciationsJson,
    examplesJson,
    phrasesJson,
    formsJson,
    synonymsJson,
    antonymsJson,
    wordFamilyJson,
    confusedWordsJson,
    rootsJson,
    affixesJson,
    summaryJson,
    learningJson,
    sentenceAnalysisJson,
    tagsJson,
    providerMetadataJson,
    contentSource,
    contentVersion,
    initializedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'word_contents';
  @override
  VerificationContext validateIntegrity(
    Insertable<WordContentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    }
    if (data.containsKey('definitions_json')) {
      context.handle(
        _definitionsJsonMeta,
        definitionsJson.isAcceptableOrUnknown(
          data['definitions_json']!,
          _definitionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('pronunciations_json')) {
      context.handle(
        _pronunciationsJsonMeta,
        pronunciationsJson.isAcceptableOrUnknown(
          data['pronunciations_json']!,
          _pronunciationsJsonMeta,
        ),
      );
    }
    if (data.containsKey('examples_json')) {
      context.handle(
        _examplesJsonMeta,
        examplesJson.isAcceptableOrUnknown(
          data['examples_json']!,
          _examplesJsonMeta,
        ),
      );
    }
    if (data.containsKey('phrases_json')) {
      context.handle(
        _phrasesJsonMeta,
        phrasesJson.isAcceptableOrUnknown(
          data['phrases_json']!,
          _phrasesJsonMeta,
        ),
      );
    }
    if (data.containsKey('forms_json')) {
      context.handle(
        _formsJsonMeta,
        formsJson.isAcceptableOrUnknown(data['forms_json']!, _formsJsonMeta),
      );
    }
    if (data.containsKey('synonyms_json')) {
      context.handle(
        _synonymsJsonMeta,
        synonymsJson.isAcceptableOrUnknown(
          data['synonyms_json']!,
          _synonymsJsonMeta,
        ),
      );
    }
    if (data.containsKey('antonyms_json')) {
      context.handle(
        _antonymsJsonMeta,
        antonymsJson.isAcceptableOrUnknown(
          data['antonyms_json']!,
          _antonymsJsonMeta,
        ),
      );
    }
    if (data.containsKey('word_family_json')) {
      context.handle(
        _wordFamilyJsonMeta,
        wordFamilyJson.isAcceptableOrUnknown(
          data['word_family_json']!,
          _wordFamilyJsonMeta,
        ),
      );
    }
    if (data.containsKey('confused_words_json')) {
      context.handle(
        _confusedWordsJsonMeta,
        confusedWordsJson.isAcceptableOrUnknown(
          data['confused_words_json']!,
          _confusedWordsJsonMeta,
        ),
      );
    }
    if (data.containsKey('roots_json')) {
      context.handle(
        _rootsJsonMeta,
        rootsJson.isAcceptableOrUnknown(data['roots_json']!, _rootsJsonMeta),
      );
    }
    if (data.containsKey('affixes_json')) {
      context.handle(
        _affixesJsonMeta,
        affixesJson.isAcceptableOrUnknown(
          data['affixes_json']!,
          _affixesJsonMeta,
        ),
      );
    }
    if (data.containsKey('summary_json')) {
      context.handle(
        _summaryJsonMeta,
        summaryJson.isAcceptableOrUnknown(
          data['summary_json']!,
          _summaryJsonMeta,
        ),
      );
    }
    if (data.containsKey('learning_json')) {
      context.handle(
        _learningJsonMeta,
        learningJson.isAcceptableOrUnknown(
          data['learning_json']!,
          _learningJsonMeta,
        ),
      );
    }
    if (data.containsKey('sentence_analysis_json')) {
      context.handle(
        _sentenceAnalysisJsonMeta,
        sentenceAnalysisJson.isAcceptableOrUnknown(
          data['sentence_analysis_json']!,
          _sentenceAnalysisJsonMeta,
        ),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('provider_metadata_json')) {
      context.handle(
        _providerMetadataJsonMeta,
        providerMetadataJson.isAcceptableOrUnknown(
          data['provider_metadata_json']!,
          _providerMetadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('content_version')) {
      context.handle(
        _contentVersionMeta,
        contentVersion.isAcceptableOrUnknown(
          data['content_version']!,
          _contentVersionMeta,
        ),
      );
    }
    if (data.containsKey('initialized_at')) {
      context.handle(
        _initializedAtMeta,
        initializedAt.isAcceptableOrUnknown(
          data['initialized_at']!,
          _initializedAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wordId};
  @override
  WordContentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WordContentRow(
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      definitionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}definitions_json'],
      )!,
      pronunciationsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pronunciations_json'],
      )!,
      examplesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}examples_json'],
      )!,
      phrasesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phrases_json'],
      )!,
      formsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}forms_json'],
      )!,
      synonymsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}synonyms_json'],
      )!,
      antonymsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}antonyms_json'],
      )!,
      wordFamilyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_family_json'],
      )!,
      confusedWordsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confused_words_json'],
      )!,
      rootsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}roots_json'],
      )!,
      affixesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}affixes_json'],
      )!,
      summaryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_json'],
      )!,
      learningJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}learning_json'],
      )!,
      sentenceAnalysisJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sentence_analysis_json'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      providerMetadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_metadata_json'],
      )!,
      contentSource: $WordContentsTable.$convertercontentSource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}content_source'],
        )!,
      ),
      contentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}content_version'],
      )!,
      initializedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}initialized_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WordContentsTable createAlias(String alias) {
    return $WordContentsTable(attachedDatabase, alias);
  }

  static TypeConverter<ContentSource, String> $convertercontentSource =
      const WireEnumConverter<ContentSource>(ContentSource.values);
}

class WordContentRow extends DataClass implements Insertable<WordContentRow> {
  final int wordId;
  final String definitionsJson;
  final String pronunciationsJson;
  final String examplesJson;
  final String phrasesJson;
  final String formsJson;
  final String synonymsJson;
  final String antonymsJson;
  final String wordFamilyJson;
  final String confusedWordsJson;
  final String rootsJson;
  final String affixesJson;
  final String summaryJson;
  final String learningJson;
  final String sentenceAnalysisJson;
  final String tagsJson;
  final String providerMetadataJson;
  final ContentSource contentSource;
  final int contentVersion;
  final int? initializedAt;
  final int updatedAt;
  const WordContentRow({
    required this.wordId,
    required this.definitionsJson,
    required this.pronunciationsJson,
    required this.examplesJson,
    required this.phrasesJson,
    required this.formsJson,
    required this.synonymsJson,
    required this.antonymsJson,
    required this.wordFamilyJson,
    required this.confusedWordsJson,
    required this.rootsJson,
    required this.affixesJson,
    required this.summaryJson,
    required this.learningJson,
    required this.sentenceAnalysisJson,
    required this.tagsJson,
    required this.providerMetadataJson,
    required this.contentSource,
    required this.contentVersion,
    this.initializedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word_id'] = Variable<int>(wordId);
    map['definitions_json'] = Variable<String>(definitionsJson);
    map['pronunciations_json'] = Variable<String>(pronunciationsJson);
    map['examples_json'] = Variable<String>(examplesJson);
    map['phrases_json'] = Variable<String>(phrasesJson);
    map['forms_json'] = Variable<String>(formsJson);
    map['synonyms_json'] = Variable<String>(synonymsJson);
    map['antonyms_json'] = Variable<String>(antonymsJson);
    map['word_family_json'] = Variable<String>(wordFamilyJson);
    map['confused_words_json'] = Variable<String>(confusedWordsJson);
    map['roots_json'] = Variable<String>(rootsJson);
    map['affixes_json'] = Variable<String>(affixesJson);
    map['summary_json'] = Variable<String>(summaryJson);
    map['learning_json'] = Variable<String>(learningJson);
    map['sentence_analysis_json'] = Variable<String>(sentenceAnalysisJson);
    map['tags_json'] = Variable<String>(tagsJson);
    map['provider_metadata_json'] = Variable<String>(providerMetadataJson);
    {
      map['content_source'] = Variable<String>(
        $WordContentsTable.$convertercontentSource.toSql(contentSource),
      );
    }
    map['content_version'] = Variable<int>(contentVersion);
    if (!nullToAbsent || initializedAt != null) {
      map['initialized_at'] = Variable<int>(initializedAt);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  WordContentsCompanion toCompanion(bool nullToAbsent) {
    return WordContentsCompanion(
      wordId: Value(wordId),
      definitionsJson: Value(definitionsJson),
      pronunciationsJson: Value(pronunciationsJson),
      examplesJson: Value(examplesJson),
      phrasesJson: Value(phrasesJson),
      formsJson: Value(formsJson),
      synonymsJson: Value(synonymsJson),
      antonymsJson: Value(antonymsJson),
      wordFamilyJson: Value(wordFamilyJson),
      confusedWordsJson: Value(confusedWordsJson),
      rootsJson: Value(rootsJson),
      affixesJson: Value(affixesJson),
      summaryJson: Value(summaryJson),
      learningJson: Value(learningJson),
      sentenceAnalysisJson: Value(sentenceAnalysisJson),
      tagsJson: Value(tagsJson),
      providerMetadataJson: Value(providerMetadataJson),
      contentSource: Value(contentSource),
      contentVersion: Value(contentVersion),
      initializedAt: initializedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(initializedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WordContentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WordContentRow(
      wordId: serializer.fromJson<int>(json['wordId']),
      definitionsJson: serializer.fromJson<String>(json['definitionsJson']),
      pronunciationsJson: serializer.fromJson<String>(
        json['pronunciationsJson'],
      ),
      examplesJson: serializer.fromJson<String>(json['examplesJson']),
      phrasesJson: serializer.fromJson<String>(json['phrasesJson']),
      formsJson: serializer.fromJson<String>(json['formsJson']),
      synonymsJson: serializer.fromJson<String>(json['synonymsJson']),
      antonymsJson: serializer.fromJson<String>(json['antonymsJson']),
      wordFamilyJson: serializer.fromJson<String>(json['wordFamilyJson']),
      confusedWordsJson: serializer.fromJson<String>(json['confusedWordsJson']),
      rootsJson: serializer.fromJson<String>(json['rootsJson']),
      affixesJson: serializer.fromJson<String>(json['affixesJson']),
      summaryJson: serializer.fromJson<String>(json['summaryJson']),
      learningJson: serializer.fromJson<String>(json['learningJson']),
      sentenceAnalysisJson: serializer.fromJson<String>(
        json['sentenceAnalysisJson'],
      ),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      providerMetadataJson: serializer.fromJson<String>(
        json['providerMetadataJson'],
      ),
      contentSource: serializer.fromJson<ContentSource>(json['contentSource']),
      contentVersion: serializer.fromJson<int>(json['contentVersion']),
      initializedAt: serializer.fromJson<int?>(json['initializedAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wordId': serializer.toJson<int>(wordId),
      'definitionsJson': serializer.toJson<String>(definitionsJson),
      'pronunciationsJson': serializer.toJson<String>(pronunciationsJson),
      'examplesJson': serializer.toJson<String>(examplesJson),
      'phrasesJson': serializer.toJson<String>(phrasesJson),
      'formsJson': serializer.toJson<String>(formsJson),
      'synonymsJson': serializer.toJson<String>(synonymsJson),
      'antonymsJson': serializer.toJson<String>(antonymsJson),
      'wordFamilyJson': serializer.toJson<String>(wordFamilyJson),
      'confusedWordsJson': serializer.toJson<String>(confusedWordsJson),
      'rootsJson': serializer.toJson<String>(rootsJson),
      'affixesJson': serializer.toJson<String>(affixesJson),
      'summaryJson': serializer.toJson<String>(summaryJson),
      'learningJson': serializer.toJson<String>(learningJson),
      'sentenceAnalysisJson': serializer.toJson<String>(sentenceAnalysisJson),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'providerMetadataJson': serializer.toJson<String>(providerMetadataJson),
      'contentSource': serializer.toJson<ContentSource>(contentSource),
      'contentVersion': serializer.toJson<int>(contentVersion),
      'initializedAt': serializer.toJson<int?>(initializedAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  WordContentRow copyWith({
    int? wordId,
    String? definitionsJson,
    String? pronunciationsJson,
    String? examplesJson,
    String? phrasesJson,
    String? formsJson,
    String? synonymsJson,
    String? antonymsJson,
    String? wordFamilyJson,
    String? confusedWordsJson,
    String? rootsJson,
    String? affixesJson,
    String? summaryJson,
    String? learningJson,
    String? sentenceAnalysisJson,
    String? tagsJson,
    String? providerMetadataJson,
    ContentSource? contentSource,
    int? contentVersion,
    Value<int?> initializedAt = const Value.absent(),
    int? updatedAt,
  }) => WordContentRow(
    wordId: wordId ?? this.wordId,
    definitionsJson: definitionsJson ?? this.definitionsJson,
    pronunciationsJson: pronunciationsJson ?? this.pronunciationsJson,
    examplesJson: examplesJson ?? this.examplesJson,
    phrasesJson: phrasesJson ?? this.phrasesJson,
    formsJson: formsJson ?? this.formsJson,
    synonymsJson: synonymsJson ?? this.synonymsJson,
    antonymsJson: antonymsJson ?? this.antonymsJson,
    wordFamilyJson: wordFamilyJson ?? this.wordFamilyJson,
    confusedWordsJson: confusedWordsJson ?? this.confusedWordsJson,
    rootsJson: rootsJson ?? this.rootsJson,
    affixesJson: affixesJson ?? this.affixesJson,
    summaryJson: summaryJson ?? this.summaryJson,
    learningJson: learningJson ?? this.learningJson,
    sentenceAnalysisJson: sentenceAnalysisJson ?? this.sentenceAnalysisJson,
    tagsJson: tagsJson ?? this.tagsJson,
    providerMetadataJson: providerMetadataJson ?? this.providerMetadataJson,
    contentSource: contentSource ?? this.contentSource,
    contentVersion: contentVersion ?? this.contentVersion,
    initializedAt: initializedAt.present
        ? initializedAt.value
        : this.initializedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WordContentRow copyWithCompanion(WordContentsCompanion data) {
    return WordContentRow(
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      definitionsJson: data.definitionsJson.present
          ? data.definitionsJson.value
          : this.definitionsJson,
      pronunciationsJson: data.pronunciationsJson.present
          ? data.pronunciationsJson.value
          : this.pronunciationsJson,
      examplesJson: data.examplesJson.present
          ? data.examplesJson.value
          : this.examplesJson,
      phrasesJson: data.phrasesJson.present
          ? data.phrasesJson.value
          : this.phrasesJson,
      formsJson: data.formsJson.present ? data.formsJson.value : this.formsJson,
      synonymsJson: data.synonymsJson.present
          ? data.synonymsJson.value
          : this.synonymsJson,
      antonymsJson: data.antonymsJson.present
          ? data.antonymsJson.value
          : this.antonymsJson,
      wordFamilyJson: data.wordFamilyJson.present
          ? data.wordFamilyJson.value
          : this.wordFamilyJson,
      confusedWordsJson: data.confusedWordsJson.present
          ? data.confusedWordsJson.value
          : this.confusedWordsJson,
      rootsJson: data.rootsJson.present ? data.rootsJson.value : this.rootsJson,
      affixesJson: data.affixesJson.present
          ? data.affixesJson.value
          : this.affixesJson,
      summaryJson: data.summaryJson.present
          ? data.summaryJson.value
          : this.summaryJson,
      learningJson: data.learningJson.present
          ? data.learningJson.value
          : this.learningJson,
      sentenceAnalysisJson: data.sentenceAnalysisJson.present
          ? data.sentenceAnalysisJson.value
          : this.sentenceAnalysisJson,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      providerMetadataJson: data.providerMetadataJson.present
          ? data.providerMetadataJson.value
          : this.providerMetadataJson,
      contentSource: data.contentSource.present
          ? data.contentSource.value
          : this.contentSource,
      contentVersion: data.contentVersion.present
          ? data.contentVersion.value
          : this.contentVersion,
      initializedAt: data.initializedAt.present
          ? data.initializedAt.value
          : this.initializedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WordContentRow(')
          ..write('wordId: $wordId, ')
          ..write('definitionsJson: $definitionsJson, ')
          ..write('pronunciationsJson: $pronunciationsJson, ')
          ..write('examplesJson: $examplesJson, ')
          ..write('phrasesJson: $phrasesJson, ')
          ..write('formsJson: $formsJson, ')
          ..write('synonymsJson: $synonymsJson, ')
          ..write('antonymsJson: $antonymsJson, ')
          ..write('wordFamilyJson: $wordFamilyJson, ')
          ..write('confusedWordsJson: $confusedWordsJson, ')
          ..write('rootsJson: $rootsJson, ')
          ..write('affixesJson: $affixesJson, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('learningJson: $learningJson, ')
          ..write('sentenceAnalysisJson: $sentenceAnalysisJson, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('providerMetadataJson: $providerMetadataJson, ')
          ..write('contentSource: $contentSource, ')
          ..write('contentVersion: $contentVersion, ')
          ..write('initializedAt: $initializedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    wordId,
    definitionsJson,
    pronunciationsJson,
    examplesJson,
    phrasesJson,
    formsJson,
    synonymsJson,
    antonymsJson,
    wordFamilyJson,
    confusedWordsJson,
    rootsJson,
    affixesJson,
    summaryJson,
    learningJson,
    sentenceAnalysisJson,
    tagsJson,
    providerMetadataJson,
    contentSource,
    contentVersion,
    initializedAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordContentRow &&
          other.wordId == this.wordId &&
          other.definitionsJson == this.definitionsJson &&
          other.pronunciationsJson == this.pronunciationsJson &&
          other.examplesJson == this.examplesJson &&
          other.phrasesJson == this.phrasesJson &&
          other.formsJson == this.formsJson &&
          other.synonymsJson == this.synonymsJson &&
          other.antonymsJson == this.antonymsJson &&
          other.wordFamilyJson == this.wordFamilyJson &&
          other.confusedWordsJson == this.confusedWordsJson &&
          other.rootsJson == this.rootsJson &&
          other.affixesJson == this.affixesJson &&
          other.summaryJson == this.summaryJson &&
          other.learningJson == this.learningJson &&
          other.sentenceAnalysisJson == this.sentenceAnalysisJson &&
          other.tagsJson == this.tagsJson &&
          other.providerMetadataJson == this.providerMetadataJson &&
          other.contentSource == this.contentSource &&
          other.contentVersion == this.contentVersion &&
          other.initializedAt == this.initializedAt &&
          other.updatedAt == this.updatedAt);
}

class WordContentsCompanion extends UpdateCompanion<WordContentRow> {
  final Value<int> wordId;
  final Value<String> definitionsJson;
  final Value<String> pronunciationsJson;
  final Value<String> examplesJson;
  final Value<String> phrasesJson;
  final Value<String> formsJson;
  final Value<String> synonymsJson;
  final Value<String> antonymsJson;
  final Value<String> wordFamilyJson;
  final Value<String> confusedWordsJson;
  final Value<String> rootsJson;
  final Value<String> affixesJson;
  final Value<String> summaryJson;
  final Value<String> learningJson;
  final Value<String> sentenceAnalysisJson;
  final Value<String> tagsJson;
  final Value<String> providerMetadataJson;
  final Value<ContentSource> contentSource;
  final Value<int> contentVersion;
  final Value<int?> initializedAt;
  final Value<int> updatedAt;
  const WordContentsCompanion({
    this.wordId = const Value.absent(),
    this.definitionsJson = const Value.absent(),
    this.pronunciationsJson = const Value.absent(),
    this.examplesJson = const Value.absent(),
    this.phrasesJson = const Value.absent(),
    this.formsJson = const Value.absent(),
    this.synonymsJson = const Value.absent(),
    this.antonymsJson = const Value.absent(),
    this.wordFamilyJson = const Value.absent(),
    this.confusedWordsJson = const Value.absent(),
    this.rootsJson = const Value.absent(),
    this.affixesJson = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.learningJson = const Value.absent(),
    this.sentenceAnalysisJson = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.providerMetadataJson = const Value.absent(),
    this.contentSource = const Value.absent(),
    this.contentVersion = const Value.absent(),
    this.initializedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WordContentsCompanion.insert({
    this.wordId = const Value.absent(),
    this.definitionsJson = const Value.absent(),
    this.pronunciationsJson = const Value.absent(),
    this.examplesJson = const Value.absent(),
    this.phrasesJson = const Value.absent(),
    this.formsJson = const Value.absent(),
    this.synonymsJson = const Value.absent(),
    this.antonymsJson = const Value.absent(),
    this.wordFamilyJson = const Value.absent(),
    this.confusedWordsJson = const Value.absent(),
    this.rootsJson = const Value.absent(),
    this.affixesJson = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.learningJson = const Value.absent(),
    this.sentenceAnalysisJson = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.providerMetadataJson = const Value.absent(),
    this.contentSource = const Value.absent(),
    this.contentVersion = const Value.absent(),
    this.initializedAt = const Value.absent(),
    required int updatedAt,
  }) : updatedAt = Value(updatedAt);
  static Insertable<WordContentRow> custom({
    Expression<int>? wordId,
    Expression<String>? definitionsJson,
    Expression<String>? pronunciationsJson,
    Expression<String>? examplesJson,
    Expression<String>? phrasesJson,
    Expression<String>? formsJson,
    Expression<String>? synonymsJson,
    Expression<String>? antonymsJson,
    Expression<String>? wordFamilyJson,
    Expression<String>? confusedWordsJson,
    Expression<String>? rootsJson,
    Expression<String>? affixesJson,
    Expression<String>? summaryJson,
    Expression<String>? learningJson,
    Expression<String>? sentenceAnalysisJson,
    Expression<String>? tagsJson,
    Expression<String>? providerMetadataJson,
    Expression<String>? contentSource,
    Expression<int>? contentVersion,
    Expression<int>? initializedAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (wordId != null) 'word_id': wordId,
      if (definitionsJson != null) 'definitions_json': definitionsJson,
      if (pronunciationsJson != null) 'pronunciations_json': pronunciationsJson,
      if (examplesJson != null) 'examples_json': examplesJson,
      if (phrasesJson != null) 'phrases_json': phrasesJson,
      if (formsJson != null) 'forms_json': formsJson,
      if (synonymsJson != null) 'synonyms_json': synonymsJson,
      if (antonymsJson != null) 'antonyms_json': antonymsJson,
      if (wordFamilyJson != null) 'word_family_json': wordFamilyJson,
      if (confusedWordsJson != null) 'confused_words_json': confusedWordsJson,
      if (rootsJson != null) 'roots_json': rootsJson,
      if (affixesJson != null) 'affixes_json': affixesJson,
      if (summaryJson != null) 'summary_json': summaryJson,
      if (learningJson != null) 'learning_json': learningJson,
      if (sentenceAnalysisJson != null)
        'sentence_analysis_json': sentenceAnalysisJson,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (providerMetadataJson != null)
        'provider_metadata_json': providerMetadataJson,
      if (contentSource != null) 'content_source': contentSource,
      if (contentVersion != null) 'content_version': contentVersion,
      if (initializedAt != null) 'initialized_at': initializedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WordContentsCompanion copyWith({
    Value<int>? wordId,
    Value<String>? definitionsJson,
    Value<String>? pronunciationsJson,
    Value<String>? examplesJson,
    Value<String>? phrasesJson,
    Value<String>? formsJson,
    Value<String>? synonymsJson,
    Value<String>? antonymsJson,
    Value<String>? wordFamilyJson,
    Value<String>? confusedWordsJson,
    Value<String>? rootsJson,
    Value<String>? affixesJson,
    Value<String>? summaryJson,
    Value<String>? learningJson,
    Value<String>? sentenceAnalysisJson,
    Value<String>? tagsJson,
    Value<String>? providerMetadataJson,
    Value<ContentSource>? contentSource,
    Value<int>? contentVersion,
    Value<int?>? initializedAt,
    Value<int>? updatedAt,
  }) {
    return WordContentsCompanion(
      wordId: wordId ?? this.wordId,
      definitionsJson: definitionsJson ?? this.definitionsJson,
      pronunciationsJson: pronunciationsJson ?? this.pronunciationsJson,
      examplesJson: examplesJson ?? this.examplesJson,
      phrasesJson: phrasesJson ?? this.phrasesJson,
      formsJson: formsJson ?? this.formsJson,
      synonymsJson: synonymsJson ?? this.synonymsJson,
      antonymsJson: antonymsJson ?? this.antonymsJson,
      wordFamilyJson: wordFamilyJson ?? this.wordFamilyJson,
      confusedWordsJson: confusedWordsJson ?? this.confusedWordsJson,
      rootsJson: rootsJson ?? this.rootsJson,
      affixesJson: affixesJson ?? this.affixesJson,
      summaryJson: summaryJson ?? this.summaryJson,
      learningJson: learningJson ?? this.learningJson,
      sentenceAnalysisJson: sentenceAnalysisJson ?? this.sentenceAnalysisJson,
      tagsJson: tagsJson ?? this.tagsJson,
      providerMetadataJson: providerMetadataJson ?? this.providerMetadataJson,
      contentSource: contentSource ?? this.contentSource,
      contentVersion: contentVersion ?? this.contentVersion,
      initializedAt: initializedAt ?? this.initializedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (definitionsJson.present) {
      map['definitions_json'] = Variable<String>(definitionsJson.value);
    }
    if (pronunciationsJson.present) {
      map['pronunciations_json'] = Variable<String>(pronunciationsJson.value);
    }
    if (examplesJson.present) {
      map['examples_json'] = Variable<String>(examplesJson.value);
    }
    if (phrasesJson.present) {
      map['phrases_json'] = Variable<String>(phrasesJson.value);
    }
    if (formsJson.present) {
      map['forms_json'] = Variable<String>(formsJson.value);
    }
    if (synonymsJson.present) {
      map['synonyms_json'] = Variable<String>(synonymsJson.value);
    }
    if (antonymsJson.present) {
      map['antonyms_json'] = Variable<String>(antonymsJson.value);
    }
    if (wordFamilyJson.present) {
      map['word_family_json'] = Variable<String>(wordFamilyJson.value);
    }
    if (confusedWordsJson.present) {
      map['confused_words_json'] = Variable<String>(confusedWordsJson.value);
    }
    if (rootsJson.present) {
      map['roots_json'] = Variable<String>(rootsJson.value);
    }
    if (affixesJson.present) {
      map['affixes_json'] = Variable<String>(affixesJson.value);
    }
    if (summaryJson.present) {
      map['summary_json'] = Variable<String>(summaryJson.value);
    }
    if (learningJson.present) {
      map['learning_json'] = Variable<String>(learningJson.value);
    }
    if (sentenceAnalysisJson.present) {
      map['sentence_analysis_json'] = Variable<String>(
        sentenceAnalysisJson.value,
      );
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (providerMetadataJson.present) {
      map['provider_metadata_json'] = Variable<String>(
        providerMetadataJson.value,
      );
    }
    if (contentSource.present) {
      map['content_source'] = Variable<String>(
        $WordContentsTable.$convertercontentSource.toSql(contentSource.value),
      );
    }
    if (contentVersion.present) {
      map['content_version'] = Variable<int>(contentVersion.value);
    }
    if (initializedAt.present) {
      map['initialized_at'] = Variable<int>(initializedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WordContentsCompanion(')
          ..write('wordId: $wordId, ')
          ..write('definitionsJson: $definitionsJson, ')
          ..write('pronunciationsJson: $pronunciationsJson, ')
          ..write('examplesJson: $examplesJson, ')
          ..write('phrasesJson: $phrasesJson, ')
          ..write('formsJson: $formsJson, ')
          ..write('synonymsJson: $synonymsJson, ')
          ..write('antonymsJson: $antonymsJson, ')
          ..write('wordFamilyJson: $wordFamilyJson, ')
          ..write('confusedWordsJson: $confusedWordsJson, ')
          ..write('rootsJson: $rootsJson, ')
          ..write('affixesJson: $affixesJson, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('learningJson: $learningJson, ')
          ..write('sentenceAnalysisJson: $sentenceAnalysisJson, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('providerMetadataJson: $providerMetadataJson, ')
          ..write('contentSource: $contentSource, ')
          ..write('contentVersion: $contentVersion, ')
          ..write('initializedAt: $initializedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $WordReviewStatsTable extends WordReviewStats
    with TableInfo<$WordReviewStatsTable, WordReviewStatRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WordReviewStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _totalReviewsMeta = const VerificationMeta(
    'totalReviews',
  );
  @override
  late final GeneratedColumn<int> totalReviews = GeneratedColumn<int>(
    'total_reviews',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _correctReviewsMeta = const VerificationMeta(
    'correctReviews',
  );
  @override
  late final GeneratedColumn<int> correctReviews = GeneratedColumn<int>(
    'correct_reviews',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _recentAgain30dMeta = const VerificationMeta(
    'recentAgain30d',
  );
  @override
  late final GeneratedColumn<int> recentAgain30d = GeneratedColumn<int>(
    'recent_again_30d',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _recentAgain14dMeta = const VerificationMeta(
    'recentAgain14d',
  );
  @override
  late final GeneratedColumn<int> recentAgain14d = GeneratedColumn<int>(
    'recent_again_14d',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _recentWrong14dMeta = const VerificationMeta(
    'recentWrong14d',
  );
  @override
  late final GeneratedColumn<int> recentWrong14d = GeneratedColumn<int>(
    'recent_wrong_14d',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _recentHard14dMeta = const VerificationMeta(
    'recentHard14d',
  );
  @override
  late final GeneratedColumn<int> recentHard14d = GeneratedColumn<int>(
    'recent_hard_14d',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalDurationMsMeta = const VerificationMeta(
    'totalDurationMs',
  );
  @override
  late final GeneratedColumn<int> totalDurationMs = GeneratedColumn<int>(
    'total_duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationCountMeta = const VerificationMeta(
    'durationCount',
  );
  @override
  late final GeneratedColumn<int> durationCount = GeneratedColumn<int>(
    'duration_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReviewedAtMeta = const VerificationMeta(
    'lastReviewedAt',
  );
  @override
  late final GeneratedColumn<int> lastReviewedAt = GeneratedColumn<int>(
    'last_reviewed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    wordId,
    totalReviews,
    correctReviews,
    recentAgain30d,
    recentAgain14d,
    recentWrong14d,
    recentHard14d,
    totalDurationMs,
    durationCount,
    lastReviewedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'word_review_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<WordReviewStatRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    }
    if (data.containsKey('total_reviews')) {
      context.handle(
        _totalReviewsMeta,
        totalReviews.isAcceptableOrUnknown(
          data['total_reviews']!,
          _totalReviewsMeta,
        ),
      );
    }
    if (data.containsKey('correct_reviews')) {
      context.handle(
        _correctReviewsMeta,
        correctReviews.isAcceptableOrUnknown(
          data['correct_reviews']!,
          _correctReviewsMeta,
        ),
      );
    }
    if (data.containsKey('recent_again_30d')) {
      context.handle(
        _recentAgain30dMeta,
        recentAgain30d.isAcceptableOrUnknown(
          data['recent_again_30d']!,
          _recentAgain30dMeta,
        ),
      );
    }
    if (data.containsKey('recent_again_14d')) {
      context.handle(
        _recentAgain14dMeta,
        recentAgain14d.isAcceptableOrUnknown(
          data['recent_again_14d']!,
          _recentAgain14dMeta,
        ),
      );
    }
    if (data.containsKey('recent_wrong_14d')) {
      context.handle(
        _recentWrong14dMeta,
        recentWrong14d.isAcceptableOrUnknown(
          data['recent_wrong_14d']!,
          _recentWrong14dMeta,
        ),
      );
    }
    if (data.containsKey('recent_hard_14d')) {
      context.handle(
        _recentHard14dMeta,
        recentHard14d.isAcceptableOrUnknown(
          data['recent_hard_14d']!,
          _recentHard14dMeta,
        ),
      );
    }
    if (data.containsKey('total_duration_ms')) {
      context.handle(
        _totalDurationMsMeta,
        totalDurationMs.isAcceptableOrUnknown(
          data['total_duration_ms']!,
          _totalDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('duration_count')) {
      context.handle(
        _durationCountMeta,
        durationCount.isAcceptableOrUnknown(
          data['duration_count']!,
          _durationCountMeta,
        ),
      );
    }
    if (data.containsKey('last_reviewed_at')) {
      context.handle(
        _lastReviewedAtMeta,
        lastReviewedAt.isAcceptableOrUnknown(
          data['last_reviewed_at']!,
          _lastReviewedAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wordId};
  @override
  WordReviewStatRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WordReviewStatRow(
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      totalReviews: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_reviews'],
      )!,
      correctReviews: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}correct_reviews'],
      )!,
      recentAgain30d: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recent_again_30d'],
      )!,
      recentAgain14d: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recent_again_14d'],
      )!,
      recentWrong14d: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recent_wrong_14d'],
      )!,
      recentHard14d: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recent_hard_14d'],
      )!,
      totalDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_duration_ms'],
      )!,
      durationCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_count'],
      )!,
      lastReviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_reviewed_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WordReviewStatsTable createAlias(String alias) {
    return $WordReviewStatsTable(attachedDatabase, alias);
  }
}

class WordReviewStatRow extends DataClass
    implements Insertable<WordReviewStatRow> {
  final int wordId;
  final int totalReviews;
  final int correctReviews;
  final int recentAgain30d;
  final int recentAgain14d;
  final int recentWrong14d;
  final int recentHard14d;
  final int totalDurationMs;
  final int durationCount;
  final int? lastReviewedAt;
  final int updatedAt;
  const WordReviewStatRow({
    required this.wordId,
    required this.totalReviews,
    required this.correctReviews,
    required this.recentAgain30d,
    required this.recentAgain14d,
    required this.recentWrong14d,
    required this.recentHard14d,
    required this.totalDurationMs,
    required this.durationCount,
    this.lastReviewedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word_id'] = Variable<int>(wordId);
    map['total_reviews'] = Variable<int>(totalReviews);
    map['correct_reviews'] = Variable<int>(correctReviews);
    map['recent_again_30d'] = Variable<int>(recentAgain30d);
    map['recent_again_14d'] = Variable<int>(recentAgain14d);
    map['recent_wrong_14d'] = Variable<int>(recentWrong14d);
    map['recent_hard_14d'] = Variable<int>(recentHard14d);
    map['total_duration_ms'] = Variable<int>(totalDurationMs);
    map['duration_count'] = Variable<int>(durationCount);
    if (!nullToAbsent || lastReviewedAt != null) {
      map['last_reviewed_at'] = Variable<int>(lastReviewedAt);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  WordReviewStatsCompanion toCompanion(bool nullToAbsent) {
    return WordReviewStatsCompanion(
      wordId: Value(wordId),
      totalReviews: Value(totalReviews),
      correctReviews: Value(correctReviews),
      recentAgain30d: Value(recentAgain30d),
      recentAgain14d: Value(recentAgain14d),
      recentWrong14d: Value(recentWrong14d),
      recentHard14d: Value(recentHard14d),
      totalDurationMs: Value(totalDurationMs),
      durationCount: Value(durationCount),
      lastReviewedAt: lastReviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WordReviewStatRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WordReviewStatRow(
      wordId: serializer.fromJson<int>(json['wordId']),
      totalReviews: serializer.fromJson<int>(json['totalReviews']),
      correctReviews: serializer.fromJson<int>(json['correctReviews']),
      recentAgain30d: serializer.fromJson<int>(json['recentAgain30d']),
      recentAgain14d: serializer.fromJson<int>(json['recentAgain14d']),
      recentWrong14d: serializer.fromJson<int>(json['recentWrong14d']),
      recentHard14d: serializer.fromJson<int>(json['recentHard14d']),
      totalDurationMs: serializer.fromJson<int>(json['totalDurationMs']),
      durationCount: serializer.fromJson<int>(json['durationCount']),
      lastReviewedAt: serializer.fromJson<int?>(json['lastReviewedAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wordId': serializer.toJson<int>(wordId),
      'totalReviews': serializer.toJson<int>(totalReviews),
      'correctReviews': serializer.toJson<int>(correctReviews),
      'recentAgain30d': serializer.toJson<int>(recentAgain30d),
      'recentAgain14d': serializer.toJson<int>(recentAgain14d),
      'recentWrong14d': serializer.toJson<int>(recentWrong14d),
      'recentHard14d': serializer.toJson<int>(recentHard14d),
      'totalDurationMs': serializer.toJson<int>(totalDurationMs),
      'durationCount': serializer.toJson<int>(durationCount),
      'lastReviewedAt': serializer.toJson<int?>(lastReviewedAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  WordReviewStatRow copyWith({
    int? wordId,
    int? totalReviews,
    int? correctReviews,
    int? recentAgain30d,
    int? recentAgain14d,
    int? recentWrong14d,
    int? recentHard14d,
    int? totalDurationMs,
    int? durationCount,
    Value<int?> lastReviewedAt = const Value.absent(),
    int? updatedAt,
  }) => WordReviewStatRow(
    wordId: wordId ?? this.wordId,
    totalReviews: totalReviews ?? this.totalReviews,
    correctReviews: correctReviews ?? this.correctReviews,
    recentAgain30d: recentAgain30d ?? this.recentAgain30d,
    recentAgain14d: recentAgain14d ?? this.recentAgain14d,
    recentWrong14d: recentWrong14d ?? this.recentWrong14d,
    recentHard14d: recentHard14d ?? this.recentHard14d,
    totalDurationMs: totalDurationMs ?? this.totalDurationMs,
    durationCount: durationCount ?? this.durationCount,
    lastReviewedAt: lastReviewedAt.present
        ? lastReviewedAt.value
        : this.lastReviewedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WordReviewStatRow copyWithCompanion(WordReviewStatsCompanion data) {
    return WordReviewStatRow(
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      totalReviews: data.totalReviews.present
          ? data.totalReviews.value
          : this.totalReviews,
      correctReviews: data.correctReviews.present
          ? data.correctReviews.value
          : this.correctReviews,
      recentAgain30d: data.recentAgain30d.present
          ? data.recentAgain30d.value
          : this.recentAgain30d,
      recentAgain14d: data.recentAgain14d.present
          ? data.recentAgain14d.value
          : this.recentAgain14d,
      recentWrong14d: data.recentWrong14d.present
          ? data.recentWrong14d.value
          : this.recentWrong14d,
      recentHard14d: data.recentHard14d.present
          ? data.recentHard14d.value
          : this.recentHard14d,
      totalDurationMs: data.totalDurationMs.present
          ? data.totalDurationMs.value
          : this.totalDurationMs,
      durationCount: data.durationCount.present
          ? data.durationCount.value
          : this.durationCount,
      lastReviewedAt: data.lastReviewedAt.present
          ? data.lastReviewedAt.value
          : this.lastReviewedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WordReviewStatRow(')
          ..write('wordId: $wordId, ')
          ..write('totalReviews: $totalReviews, ')
          ..write('correctReviews: $correctReviews, ')
          ..write('recentAgain30d: $recentAgain30d, ')
          ..write('recentAgain14d: $recentAgain14d, ')
          ..write('recentWrong14d: $recentWrong14d, ')
          ..write('recentHard14d: $recentHard14d, ')
          ..write('totalDurationMs: $totalDurationMs, ')
          ..write('durationCount: $durationCount, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    wordId,
    totalReviews,
    correctReviews,
    recentAgain30d,
    recentAgain14d,
    recentWrong14d,
    recentHard14d,
    totalDurationMs,
    durationCount,
    lastReviewedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordReviewStatRow &&
          other.wordId == this.wordId &&
          other.totalReviews == this.totalReviews &&
          other.correctReviews == this.correctReviews &&
          other.recentAgain30d == this.recentAgain30d &&
          other.recentAgain14d == this.recentAgain14d &&
          other.recentWrong14d == this.recentWrong14d &&
          other.recentHard14d == this.recentHard14d &&
          other.totalDurationMs == this.totalDurationMs &&
          other.durationCount == this.durationCount &&
          other.lastReviewedAt == this.lastReviewedAt &&
          other.updatedAt == this.updatedAt);
}

class WordReviewStatsCompanion extends UpdateCompanion<WordReviewStatRow> {
  final Value<int> wordId;
  final Value<int> totalReviews;
  final Value<int> correctReviews;
  final Value<int> recentAgain30d;
  final Value<int> recentAgain14d;
  final Value<int> recentWrong14d;
  final Value<int> recentHard14d;
  final Value<int> totalDurationMs;
  final Value<int> durationCount;
  final Value<int?> lastReviewedAt;
  final Value<int> updatedAt;
  const WordReviewStatsCompanion({
    this.wordId = const Value.absent(),
    this.totalReviews = const Value.absent(),
    this.correctReviews = const Value.absent(),
    this.recentAgain30d = const Value.absent(),
    this.recentAgain14d = const Value.absent(),
    this.recentWrong14d = const Value.absent(),
    this.recentHard14d = const Value.absent(),
    this.totalDurationMs = const Value.absent(),
    this.durationCount = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WordReviewStatsCompanion.insert({
    this.wordId = const Value.absent(),
    this.totalReviews = const Value.absent(),
    this.correctReviews = const Value.absent(),
    this.recentAgain30d = const Value.absent(),
    this.recentAgain14d = const Value.absent(),
    this.recentWrong14d = const Value.absent(),
    this.recentHard14d = const Value.absent(),
    this.totalDurationMs = const Value.absent(),
    this.durationCount = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<WordReviewStatRow> custom({
    Expression<int>? wordId,
    Expression<int>? totalReviews,
    Expression<int>? correctReviews,
    Expression<int>? recentAgain30d,
    Expression<int>? recentAgain14d,
    Expression<int>? recentWrong14d,
    Expression<int>? recentHard14d,
    Expression<int>? totalDurationMs,
    Expression<int>? durationCount,
    Expression<int>? lastReviewedAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (wordId != null) 'word_id': wordId,
      if (totalReviews != null) 'total_reviews': totalReviews,
      if (correctReviews != null) 'correct_reviews': correctReviews,
      if (recentAgain30d != null) 'recent_again_30d': recentAgain30d,
      if (recentAgain14d != null) 'recent_again_14d': recentAgain14d,
      if (recentWrong14d != null) 'recent_wrong_14d': recentWrong14d,
      if (recentHard14d != null) 'recent_hard_14d': recentHard14d,
      if (totalDurationMs != null) 'total_duration_ms': totalDurationMs,
      if (durationCount != null) 'duration_count': durationCount,
      if (lastReviewedAt != null) 'last_reviewed_at': lastReviewedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WordReviewStatsCompanion copyWith({
    Value<int>? wordId,
    Value<int>? totalReviews,
    Value<int>? correctReviews,
    Value<int>? recentAgain30d,
    Value<int>? recentAgain14d,
    Value<int>? recentWrong14d,
    Value<int>? recentHard14d,
    Value<int>? totalDurationMs,
    Value<int>? durationCount,
    Value<int?>? lastReviewedAt,
    Value<int>? updatedAt,
  }) {
    return WordReviewStatsCompanion(
      wordId: wordId ?? this.wordId,
      totalReviews: totalReviews ?? this.totalReviews,
      correctReviews: correctReviews ?? this.correctReviews,
      recentAgain30d: recentAgain30d ?? this.recentAgain30d,
      recentAgain14d: recentAgain14d ?? this.recentAgain14d,
      recentWrong14d: recentWrong14d ?? this.recentWrong14d,
      recentHard14d: recentHard14d ?? this.recentHard14d,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      durationCount: durationCount ?? this.durationCount,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (totalReviews.present) {
      map['total_reviews'] = Variable<int>(totalReviews.value);
    }
    if (correctReviews.present) {
      map['correct_reviews'] = Variable<int>(correctReviews.value);
    }
    if (recentAgain30d.present) {
      map['recent_again_30d'] = Variable<int>(recentAgain30d.value);
    }
    if (recentAgain14d.present) {
      map['recent_again_14d'] = Variable<int>(recentAgain14d.value);
    }
    if (recentWrong14d.present) {
      map['recent_wrong_14d'] = Variable<int>(recentWrong14d.value);
    }
    if (recentHard14d.present) {
      map['recent_hard_14d'] = Variable<int>(recentHard14d.value);
    }
    if (totalDurationMs.present) {
      map['total_duration_ms'] = Variable<int>(totalDurationMs.value);
    }
    if (durationCount.present) {
      map['duration_count'] = Variable<int>(durationCount.value);
    }
    if (lastReviewedAt.present) {
      map['last_reviewed_at'] = Variable<int>(lastReviewedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WordReviewStatsCompanion(')
          ..write('wordId: $wordId, ')
          ..write('totalReviews: $totalReviews, ')
          ..write('correctReviews: $correctReviews, ')
          ..write('recentAgain30d: $recentAgain30d, ')
          ..write('recentAgain14d: $recentAgain14d, ')
          ..write('recentWrong14d: $recentWrong14d, ')
          ..write('recentHard14d: $recentHard14d, ')
          ..write('totalDurationMs: $totalDurationMs, ')
          ..write('durationCount: $durationCount, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $StudySessionsTable extends StudySessions
    with TableInfo<$StudySessionsTable, StudySessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StudySessionsTable(this.attachedDatabase, [this._alias]);
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
  @override
  late final GeneratedColumnWithTypeConverter<StudyMode, String> sessionType =
      GeneratedColumn<String>(
        'session_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<StudyMode>($StudySessionsTable.$convertersessionType);
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedCountMeta = const VerificationMeta(
    'plannedCount',
  );
  @override
  late final GeneratedColumn<int> plannedCount = GeneratedColumn<int>(
    'planned_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedCountMeta = const VerificationMeta(
    'completedCount',
  );
  @override
  late final GeneratedColumn<int> completedCount = GeneratedColumn<int>(
    'completed_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _correctCountMeta = const VerificationMeta(
    'correctCount',
  );
  @override
  late final GeneratedColumn<int> correctCount = GeneratedColumn<int>(
    'correct_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _wrongCountMeta = const VerificationMeta(
    'wrongCount',
  );
  @override
  late final GeneratedColumn<int> wrongCount = GeneratedColumn<int>(
    'wrong_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _skippedCountMeta = const VerificationMeta(
    'skippedCount',
  );
  @override
  late final GeneratedColumn<int> skippedCount = GeneratedColumn<int>(
    'skipped_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionType,
    sourceType,
    startedAt,
    completedAt,
    plannedCount,
    completedCount,
    correctCount,
    wrongCount,
    skippedCount,
    durationMs,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'study_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StudySessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('planned_count')) {
      context.handle(
        _plannedCountMeta,
        plannedCount.isAcceptableOrUnknown(
          data['planned_count']!,
          _plannedCountMeta,
        ),
      );
    }
    if (data.containsKey('completed_count')) {
      context.handle(
        _completedCountMeta,
        completedCount.isAcceptableOrUnknown(
          data['completed_count']!,
          _completedCountMeta,
        ),
      );
    }
    if (data.containsKey('correct_count')) {
      context.handle(
        _correctCountMeta,
        correctCount.isAcceptableOrUnknown(
          data['correct_count']!,
          _correctCountMeta,
        ),
      );
    }
    if (data.containsKey('wrong_count')) {
      context.handle(
        _wrongCountMeta,
        wrongCount.isAcceptableOrUnknown(data['wrong_count']!, _wrongCountMeta),
      );
    }
    if (data.containsKey('skipped_count')) {
      context.handle(
        _skippedCountMeta,
        skippedCount.isAcceptableOrUnknown(
          data['skipped_count']!,
          _skippedCountMeta,
        ),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StudySessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StudySessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionType: $StudySessionsTable.$convertersessionType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}session_type'],
        )!,
      ),
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at'],
      ),
      plannedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_count'],
      )!,
      completedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_count'],
      )!,
      correctCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}correct_count'],
      )!,
      wrongCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wrong_count'],
      )!,
      skippedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}skipped_count'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $StudySessionsTable createAlias(String alias) {
    return $StudySessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<StudyMode, String> $convertersessionType =
      const WireEnumConverter<StudyMode>(StudyMode.values);
}

class StudySessionRow extends DataClass implements Insertable<StudySessionRow> {
  final int id;
  final StudyMode sessionType;
  final String? sourceType;
  final int startedAt;
  final int? completedAt;
  final int plannedCount;
  final int completedCount;
  final int correctCount;
  final int wrongCount;
  final int skippedCount;
  final int? durationMs;
  final int createdAt;
  const StudySessionRow({
    required this.id,
    required this.sessionType,
    this.sourceType,
    required this.startedAt,
    this.completedAt,
    required this.plannedCount,
    required this.completedCount,
    required this.correctCount,
    required this.wrongCount,
    required this.skippedCount,
    this.durationMs,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['session_type'] = Variable<String>(
        $StudySessionsTable.$convertersessionType.toSql(sessionType),
      );
    }
    if (!nullToAbsent || sourceType != null) {
      map['source_type'] = Variable<String>(sourceType);
    }
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    map['planned_count'] = Variable<int>(plannedCount);
    map['completed_count'] = Variable<int>(completedCount);
    map['correct_count'] = Variable<int>(correctCount);
    map['wrong_count'] = Variable<int>(wrongCount);
    map['skipped_count'] = Variable<int>(skippedCount);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  StudySessionsCompanion toCompanion(bool nullToAbsent) {
    return StudySessionsCompanion(
      id: Value(id),
      sessionType: Value(sessionType),
      sourceType: sourceType == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceType),
      startedAt: Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      plannedCount: Value(plannedCount),
      completedCount: Value(completedCount),
      correctCount: Value(correctCount),
      wrongCount: Value(wrongCount),
      skippedCount: Value(skippedCount),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      createdAt: Value(createdAt),
    );
  }

  factory StudySessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StudySessionRow(
      id: serializer.fromJson<int>(json['id']),
      sessionType: serializer.fromJson<StudyMode>(json['sessionType']),
      sourceType: serializer.fromJson<String?>(json['sourceType']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
      plannedCount: serializer.fromJson<int>(json['plannedCount']),
      completedCount: serializer.fromJson<int>(json['completedCount']),
      correctCount: serializer.fromJson<int>(json['correctCount']),
      wrongCount: serializer.fromJson<int>(json['wrongCount']),
      skippedCount: serializer.fromJson<int>(json['skippedCount']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionType': serializer.toJson<StudyMode>(sessionType),
      'sourceType': serializer.toJson<String?>(sourceType),
      'startedAt': serializer.toJson<int>(startedAt),
      'completedAt': serializer.toJson<int?>(completedAt),
      'plannedCount': serializer.toJson<int>(plannedCount),
      'completedCount': serializer.toJson<int>(completedCount),
      'correctCount': serializer.toJson<int>(correctCount),
      'wrongCount': serializer.toJson<int>(wrongCount),
      'skippedCount': serializer.toJson<int>(skippedCount),
      'durationMs': serializer.toJson<int?>(durationMs),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  StudySessionRow copyWith({
    int? id,
    StudyMode? sessionType,
    Value<String?> sourceType = const Value.absent(),
    int? startedAt,
    Value<int?> completedAt = const Value.absent(),
    int? plannedCount,
    int? completedCount,
    int? correctCount,
    int? wrongCount,
    int? skippedCount,
    Value<int?> durationMs = const Value.absent(),
    int? createdAt,
  }) => StudySessionRow(
    id: id ?? this.id,
    sessionType: sessionType ?? this.sessionType,
    sourceType: sourceType.present ? sourceType.value : this.sourceType,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    plannedCount: plannedCount ?? this.plannedCount,
    completedCount: completedCount ?? this.completedCount,
    correctCount: correctCount ?? this.correctCount,
    wrongCount: wrongCount ?? this.wrongCount,
    skippedCount: skippedCount ?? this.skippedCount,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    createdAt: createdAt ?? this.createdAt,
  );
  StudySessionRow copyWithCompanion(StudySessionsCompanion data) {
    return StudySessionRow(
      id: data.id.present ? data.id.value : this.id,
      sessionType: data.sessionType.present
          ? data.sessionType.value
          : this.sessionType,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      plannedCount: data.plannedCount.present
          ? data.plannedCount.value
          : this.plannedCount,
      completedCount: data.completedCount.present
          ? data.completedCount.value
          : this.completedCount,
      correctCount: data.correctCount.present
          ? data.correctCount.value
          : this.correctCount,
      wrongCount: data.wrongCount.present
          ? data.wrongCount.value
          : this.wrongCount,
      skippedCount: data.skippedCount.present
          ? data.skippedCount.value
          : this.skippedCount,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StudySessionRow(')
          ..write('id: $id, ')
          ..write('sessionType: $sessionType, ')
          ..write('sourceType: $sourceType, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('plannedCount: $plannedCount, ')
          ..write('completedCount: $completedCount, ')
          ..write('correctCount: $correctCount, ')
          ..write('wrongCount: $wrongCount, ')
          ..write('skippedCount: $skippedCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionType,
    sourceType,
    startedAt,
    completedAt,
    plannedCount,
    completedCount,
    correctCount,
    wrongCount,
    skippedCount,
    durationMs,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudySessionRow &&
          other.id == this.id &&
          other.sessionType == this.sessionType &&
          other.sourceType == this.sourceType &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.plannedCount == this.plannedCount &&
          other.completedCount == this.completedCount &&
          other.correctCount == this.correctCount &&
          other.wrongCount == this.wrongCount &&
          other.skippedCount == this.skippedCount &&
          other.durationMs == this.durationMs &&
          other.createdAt == this.createdAt);
}

class StudySessionsCompanion extends UpdateCompanion<StudySessionRow> {
  final Value<int> id;
  final Value<StudyMode> sessionType;
  final Value<String?> sourceType;
  final Value<int> startedAt;
  final Value<int?> completedAt;
  final Value<int> plannedCount;
  final Value<int> completedCount;
  final Value<int> correctCount;
  final Value<int> wrongCount;
  final Value<int> skippedCount;
  final Value<int?> durationMs;
  final Value<int> createdAt;
  const StudySessionsCompanion({
    this.id = const Value.absent(),
    this.sessionType = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.plannedCount = const Value.absent(),
    this.completedCount = const Value.absent(),
    this.correctCount = const Value.absent(),
    this.wrongCount = const Value.absent(),
    this.skippedCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  StudySessionsCompanion.insert({
    this.id = const Value.absent(),
    required StudyMode sessionType,
    this.sourceType = const Value.absent(),
    required int startedAt,
    this.completedAt = const Value.absent(),
    this.plannedCount = const Value.absent(),
    this.completedCount = const Value.absent(),
    this.correctCount = const Value.absent(),
    this.wrongCount = const Value.absent(),
    this.skippedCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    required int createdAt,
  }) : sessionType = Value(sessionType),
       startedAt = Value(startedAt),
       createdAt = Value(createdAt);
  static Insertable<StudySessionRow> custom({
    Expression<int>? id,
    Expression<String>? sessionType,
    Expression<String>? sourceType,
    Expression<int>? startedAt,
    Expression<int>? completedAt,
    Expression<int>? plannedCount,
    Expression<int>? completedCount,
    Expression<int>? correctCount,
    Expression<int>? wrongCount,
    Expression<int>? skippedCount,
    Expression<int>? durationMs,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionType != null) 'session_type': sessionType,
      if (sourceType != null) 'source_type': sourceType,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (plannedCount != null) 'planned_count': plannedCount,
      if (completedCount != null) 'completed_count': completedCount,
      if (correctCount != null) 'correct_count': correctCount,
      if (wrongCount != null) 'wrong_count': wrongCount,
      if (skippedCount != null) 'skipped_count': skippedCount,
      if (durationMs != null) 'duration_ms': durationMs,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  StudySessionsCompanion copyWith({
    Value<int>? id,
    Value<StudyMode>? sessionType,
    Value<String?>? sourceType,
    Value<int>? startedAt,
    Value<int?>? completedAt,
    Value<int>? plannedCount,
    Value<int>? completedCount,
    Value<int>? correctCount,
    Value<int>? wrongCount,
    Value<int>? skippedCount,
    Value<int?>? durationMs,
    Value<int>? createdAt,
  }) {
    return StudySessionsCompanion(
      id: id ?? this.id,
      sessionType: sessionType ?? this.sessionType,
      sourceType: sourceType ?? this.sourceType,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      plannedCount: plannedCount ?? this.plannedCount,
      completedCount: completedCount ?? this.completedCount,
      correctCount: correctCount ?? this.correctCount,
      wrongCount: wrongCount ?? this.wrongCount,
      skippedCount: skippedCount ?? this.skippedCount,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionType.present) {
      map['session_type'] = Variable<String>(
        $StudySessionsTable.$convertersessionType.toSql(sessionType.value),
      );
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (plannedCount.present) {
      map['planned_count'] = Variable<int>(plannedCount.value);
    }
    if (completedCount.present) {
      map['completed_count'] = Variable<int>(completedCount.value);
    }
    if (correctCount.present) {
      map['correct_count'] = Variable<int>(correctCount.value);
    }
    if (wrongCount.present) {
      map['wrong_count'] = Variable<int>(wrongCount.value);
    }
    if (skippedCount.present) {
      map['skipped_count'] = Variable<int>(skippedCount.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StudySessionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionType: $sessionType, ')
          ..write('sourceType: $sourceType, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('plannedCount: $plannedCount, ')
          ..write('completedCount: $completedCount, ')
          ..write('correctCount: $correctCount, ')
          ..write('wrongCount: $wrongCount, ')
          ..write('skippedCount: $skippedCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $StudySessionItemsTable extends StudySessionItems
    with TableInfo<$StudySessionItemsTable, StudySessionItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StudySessionItemsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _studySessionIdMeta = const VerificationMeta(
    'studySessionId',
  );
  @override
  late final GeneratedColumn<int> studySessionId = GeneratedColumn<int>(
    'study_session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES study_sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<double> position = GeneratedColumn<double>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<StudyTaskType, String> taskType =
      GeneratedColumn<String>(
        'task_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<StudyTaskType>(
        $StudySessionItemsTable.$convertertaskType,
      );
  @override
  late final GeneratedColumnWithTypeConverter<QuestionType, String>
  questionType = GeneratedColumn<String>(
    'question_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<QuestionType>($StudySessionItemsTable.$converterquestionType);
  @override
  late final GeneratedColumnWithTypeConverter<StudyItemStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('PENDING'),
      ).withConverter<StudyItemStatus>(
        $StudySessionItemsTable.$converterstatus,
      );
  static const VerificationMeta _answeredAtMeta = const VerificationMeta(
    'answeredAt',
  );
  @override
  late final GeneratedColumn<int> answeredAt = GeneratedColumn<int>(
    'answered_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skipReasonMeta = const VerificationMeta(
    'skipReason',
  );
  @override
  late final GeneratedColumn<String> skipReason = GeneratedColumn<String>(
    'skip_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    studySessionId,
    position,
    wordId,
    taskType,
    questionType,
    status,
    answeredAt,
    skipReason,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'study_session_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<StudySessionItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('study_session_id')) {
      context.handle(
        _studySessionIdMeta,
        studySessionId.isAcceptableOrUnknown(
          data['study_session_id']!,
          _studySessionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_studySessionIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('answered_at')) {
      context.handle(
        _answeredAtMeta,
        answeredAt.isAcceptableOrUnknown(data['answered_at']!, _answeredAtMeta),
      );
    }
    if (data.containsKey('skip_reason')) {
      context.handle(
        _skipReasonMeta,
        skipReason.isAcceptableOrUnknown(data['skip_reason']!, _skipReasonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {studySessionId, position},
  ];
  @override
  StudySessionItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StudySessionItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      studySessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}study_session_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}position'],
      )!,
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      taskType: $StudySessionItemsTable.$convertertaskType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}task_type'],
        )!,
      ),
      questionType: $StudySessionItemsTable.$converterquestionType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}question_type'],
        )!,
      ),
      status: $StudySessionItemsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      answeredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}answered_at'],
      ),
      skipReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}skip_reason'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $StudySessionItemsTable createAlias(String alias) {
    return $StudySessionItemsTable(attachedDatabase, alias);
  }

  static TypeConverter<StudyTaskType, String> $convertertaskType =
      const WireEnumConverter<StudyTaskType>(StudyTaskType.values);
  static TypeConverter<QuestionType, String> $converterquestionType =
      const WireEnumConverter<QuestionType>(QuestionType.values);
  static TypeConverter<StudyItemStatus, String> $converterstatus =
      const WireEnumConverter<StudyItemStatus>(StudyItemStatus.values);
}

class StudySessionItemRow extends DataClass
    implements Insertable<StudySessionItemRow> {
  final int id;
  final int studySessionId;
  final double position;
  final int wordId;
  final StudyTaskType taskType;
  final QuestionType questionType;
  final StudyItemStatus status;
  final int? answeredAt;
  final String? skipReason;
  final int createdAt;
  const StudySessionItemRow({
    required this.id,
    required this.studySessionId,
    required this.position,
    required this.wordId,
    required this.taskType,
    required this.questionType,
    required this.status,
    this.answeredAt,
    this.skipReason,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['study_session_id'] = Variable<int>(studySessionId);
    map['position'] = Variable<double>(position);
    map['word_id'] = Variable<int>(wordId);
    {
      map['task_type'] = Variable<String>(
        $StudySessionItemsTable.$convertertaskType.toSql(taskType),
      );
    }
    {
      map['question_type'] = Variable<String>(
        $StudySessionItemsTable.$converterquestionType.toSql(questionType),
      );
    }
    {
      map['status'] = Variable<String>(
        $StudySessionItemsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || answeredAt != null) {
      map['answered_at'] = Variable<int>(answeredAt);
    }
    if (!nullToAbsent || skipReason != null) {
      map['skip_reason'] = Variable<String>(skipReason);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  StudySessionItemsCompanion toCompanion(bool nullToAbsent) {
    return StudySessionItemsCompanion(
      id: Value(id),
      studySessionId: Value(studySessionId),
      position: Value(position),
      wordId: Value(wordId),
      taskType: Value(taskType),
      questionType: Value(questionType),
      status: Value(status),
      answeredAt: answeredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(answeredAt),
      skipReason: skipReason == null && nullToAbsent
          ? const Value.absent()
          : Value(skipReason),
      createdAt: Value(createdAt),
    );
  }

  factory StudySessionItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StudySessionItemRow(
      id: serializer.fromJson<int>(json['id']),
      studySessionId: serializer.fromJson<int>(json['studySessionId']),
      position: serializer.fromJson<double>(json['position']),
      wordId: serializer.fromJson<int>(json['wordId']),
      taskType: serializer.fromJson<StudyTaskType>(json['taskType']),
      questionType: serializer.fromJson<QuestionType>(json['questionType']),
      status: serializer.fromJson<StudyItemStatus>(json['status']),
      answeredAt: serializer.fromJson<int?>(json['answeredAt']),
      skipReason: serializer.fromJson<String?>(json['skipReason']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'studySessionId': serializer.toJson<int>(studySessionId),
      'position': serializer.toJson<double>(position),
      'wordId': serializer.toJson<int>(wordId),
      'taskType': serializer.toJson<StudyTaskType>(taskType),
      'questionType': serializer.toJson<QuestionType>(questionType),
      'status': serializer.toJson<StudyItemStatus>(status),
      'answeredAt': serializer.toJson<int?>(answeredAt),
      'skipReason': serializer.toJson<String?>(skipReason),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  StudySessionItemRow copyWith({
    int? id,
    int? studySessionId,
    double? position,
    int? wordId,
    StudyTaskType? taskType,
    QuestionType? questionType,
    StudyItemStatus? status,
    Value<int?> answeredAt = const Value.absent(),
    Value<String?> skipReason = const Value.absent(),
    int? createdAt,
  }) => StudySessionItemRow(
    id: id ?? this.id,
    studySessionId: studySessionId ?? this.studySessionId,
    position: position ?? this.position,
    wordId: wordId ?? this.wordId,
    taskType: taskType ?? this.taskType,
    questionType: questionType ?? this.questionType,
    status: status ?? this.status,
    answeredAt: answeredAt.present ? answeredAt.value : this.answeredAt,
    skipReason: skipReason.present ? skipReason.value : this.skipReason,
    createdAt: createdAt ?? this.createdAt,
  );
  StudySessionItemRow copyWithCompanion(StudySessionItemsCompanion data) {
    return StudySessionItemRow(
      id: data.id.present ? data.id.value : this.id,
      studySessionId: data.studySessionId.present
          ? data.studySessionId.value
          : this.studySessionId,
      position: data.position.present ? data.position.value : this.position,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      taskType: data.taskType.present ? data.taskType.value : this.taskType,
      questionType: data.questionType.present
          ? data.questionType.value
          : this.questionType,
      status: data.status.present ? data.status.value : this.status,
      answeredAt: data.answeredAt.present
          ? data.answeredAt.value
          : this.answeredAt,
      skipReason: data.skipReason.present
          ? data.skipReason.value
          : this.skipReason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StudySessionItemRow(')
          ..write('id: $id, ')
          ..write('studySessionId: $studySessionId, ')
          ..write('position: $position, ')
          ..write('wordId: $wordId, ')
          ..write('taskType: $taskType, ')
          ..write('questionType: $questionType, ')
          ..write('status: $status, ')
          ..write('answeredAt: $answeredAt, ')
          ..write('skipReason: $skipReason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    studySessionId,
    position,
    wordId,
    taskType,
    questionType,
    status,
    answeredAt,
    skipReason,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudySessionItemRow &&
          other.id == this.id &&
          other.studySessionId == this.studySessionId &&
          other.position == this.position &&
          other.wordId == this.wordId &&
          other.taskType == this.taskType &&
          other.questionType == this.questionType &&
          other.status == this.status &&
          other.answeredAt == this.answeredAt &&
          other.skipReason == this.skipReason &&
          other.createdAt == this.createdAt);
}

class StudySessionItemsCompanion extends UpdateCompanion<StudySessionItemRow> {
  final Value<int> id;
  final Value<int> studySessionId;
  final Value<double> position;
  final Value<int> wordId;
  final Value<StudyTaskType> taskType;
  final Value<QuestionType> questionType;
  final Value<StudyItemStatus> status;
  final Value<int?> answeredAt;
  final Value<String?> skipReason;
  final Value<int> createdAt;
  const StudySessionItemsCompanion({
    this.id = const Value.absent(),
    this.studySessionId = const Value.absent(),
    this.position = const Value.absent(),
    this.wordId = const Value.absent(),
    this.taskType = const Value.absent(),
    this.questionType = const Value.absent(),
    this.status = const Value.absent(),
    this.answeredAt = const Value.absent(),
    this.skipReason = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  StudySessionItemsCompanion.insert({
    this.id = const Value.absent(),
    required int studySessionId,
    required double position,
    required int wordId,
    required StudyTaskType taskType,
    required QuestionType questionType,
    this.status = const Value.absent(),
    this.answeredAt = const Value.absent(),
    this.skipReason = const Value.absent(),
    required int createdAt,
  }) : studySessionId = Value(studySessionId),
       position = Value(position),
       wordId = Value(wordId),
       taskType = Value(taskType),
       questionType = Value(questionType),
       createdAt = Value(createdAt);
  static Insertable<StudySessionItemRow> custom({
    Expression<int>? id,
    Expression<int>? studySessionId,
    Expression<double>? position,
    Expression<int>? wordId,
    Expression<String>? taskType,
    Expression<String>? questionType,
    Expression<String>? status,
    Expression<int>? answeredAt,
    Expression<String>? skipReason,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (studySessionId != null) 'study_session_id': studySessionId,
      if (position != null) 'position': position,
      if (wordId != null) 'word_id': wordId,
      if (taskType != null) 'task_type': taskType,
      if (questionType != null) 'question_type': questionType,
      if (status != null) 'status': status,
      if (answeredAt != null) 'answered_at': answeredAt,
      if (skipReason != null) 'skip_reason': skipReason,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  StudySessionItemsCompanion copyWith({
    Value<int>? id,
    Value<int>? studySessionId,
    Value<double>? position,
    Value<int>? wordId,
    Value<StudyTaskType>? taskType,
    Value<QuestionType>? questionType,
    Value<StudyItemStatus>? status,
    Value<int?>? answeredAt,
    Value<String?>? skipReason,
    Value<int>? createdAt,
  }) {
    return StudySessionItemsCompanion(
      id: id ?? this.id,
      studySessionId: studySessionId ?? this.studySessionId,
      position: position ?? this.position,
      wordId: wordId ?? this.wordId,
      taskType: taskType ?? this.taskType,
      questionType: questionType ?? this.questionType,
      status: status ?? this.status,
      answeredAt: answeredAt ?? this.answeredAt,
      skipReason: skipReason ?? this.skipReason,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (studySessionId.present) {
      map['study_session_id'] = Variable<int>(studySessionId.value);
    }
    if (position.present) {
      map['position'] = Variable<double>(position.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (taskType.present) {
      map['task_type'] = Variable<String>(
        $StudySessionItemsTable.$convertertaskType.toSql(taskType.value),
      );
    }
    if (questionType.present) {
      map['question_type'] = Variable<String>(
        $StudySessionItemsTable.$converterquestionType.toSql(
          questionType.value,
        ),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $StudySessionItemsTable.$converterstatus.toSql(status.value),
      );
    }
    if (answeredAt.present) {
      map['answered_at'] = Variable<int>(answeredAt.value);
    }
    if (skipReason.present) {
      map['skip_reason'] = Variable<String>(skipReason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StudySessionItemsCompanion(')
          ..write('id: $id, ')
          ..write('studySessionId: $studySessionId, ')
          ..write('position: $position, ')
          ..write('wordId: $wordId, ')
          ..write('taskType: $taskType, ')
          ..write('questionType: $questionType, ')
          ..write('status: $status, ')
          ..write('answeredAt: $answeredAt, ')
          ..write('skipReason: $skipReason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ReviewCardsTable extends ReviewCards
    with TableInfo<$ReviewCardsTable, ReviewCardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
    'due_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stabilityMeta = const VerificationMeta(
    'stability',
  );
  @override
  late final GeneratedColumn<double> stability = GeneratedColumn<double>(
    'stability',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _difficultyMeta = const VerificationMeta(
    'difficulty',
  );
  @override
  late final GeneratedColumn<double> difficulty = GeneratedColumn<double>(
    'difficulty',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _elapsedDaysMeta = const VerificationMeta(
    'elapsedDays',
  );
  @override
  late final GeneratedColumn<int> elapsedDays = GeneratedColumn<int>(
    'elapsed_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledDaysMeta = const VerificationMeta(
    'scheduledDays',
  );
  @override
  late final GeneratedColumn<int> scheduledDays = GeneratedColumn<int>(
    'scheduled_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repsMeta = const VerificationMeta('reps');
  @override
  late final GeneratedColumn<int> reps = GeneratedColumn<int>(
    'reps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lapsesMeta = const VerificationMeta('lapses');
  @override
  late final GeneratedColumn<int> lapses = GeneratedColumn<int>(
    'lapses',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fsrsStateMeta = const VerificationMeta(
    'fsrsState',
  );
  @override
  late final GeneratedColumn<int> fsrsState = GeneratedColumn<int>(
    'fsrs_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _learningStepsMeta = const VerificationMeta(
    'learningSteps',
  );
  @override
  late final GeneratedColumn<int> learningSteps = GeneratedColumn<int>(
    'learning_steps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReviewAtMeta = const VerificationMeta(
    'lastReviewAt',
  );
  @override
  late final GeneratedColumn<int> lastReviewAt = GeneratedColumn<int>(
    'last_review_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    wordId,
    dueAt,
    stability,
    difficulty,
    elapsedDays,
    scheduledDays,
    reps,
    lapses,
    fsrsState,
    learningSteps,
    lastReviewAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewCardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    } else if (isInserting) {
      context.missing(_dueAtMeta);
    }
    if (data.containsKey('stability')) {
      context.handle(
        _stabilityMeta,
        stability.isAcceptableOrUnknown(data['stability']!, _stabilityMeta),
      );
    } else if (isInserting) {
      context.missing(_stabilityMeta);
    }
    if (data.containsKey('difficulty')) {
      context.handle(
        _difficultyMeta,
        difficulty.isAcceptableOrUnknown(data['difficulty']!, _difficultyMeta),
      );
    } else if (isInserting) {
      context.missing(_difficultyMeta);
    }
    if (data.containsKey('elapsed_days')) {
      context.handle(
        _elapsedDaysMeta,
        elapsedDays.isAcceptableOrUnknown(
          data['elapsed_days']!,
          _elapsedDaysMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_elapsedDaysMeta);
    }
    if (data.containsKey('scheduled_days')) {
      context.handle(
        _scheduledDaysMeta,
        scheduledDays.isAcceptableOrUnknown(
          data['scheduled_days']!,
          _scheduledDaysMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledDaysMeta);
    }
    if (data.containsKey('reps')) {
      context.handle(
        _repsMeta,
        reps.isAcceptableOrUnknown(data['reps']!, _repsMeta),
      );
    } else if (isInserting) {
      context.missing(_repsMeta);
    }
    if (data.containsKey('lapses')) {
      context.handle(
        _lapsesMeta,
        lapses.isAcceptableOrUnknown(data['lapses']!, _lapsesMeta),
      );
    } else if (isInserting) {
      context.missing(_lapsesMeta);
    }
    if (data.containsKey('fsrs_state')) {
      context.handle(
        _fsrsStateMeta,
        fsrsState.isAcceptableOrUnknown(data['fsrs_state']!, _fsrsStateMeta),
      );
    } else if (isInserting) {
      context.missing(_fsrsStateMeta);
    }
    if (data.containsKey('learning_steps')) {
      context.handle(
        _learningStepsMeta,
        learningSteps.isAcceptableOrUnknown(
          data['learning_steps']!,
          _learningStepsMeta,
        ),
      );
    }
    if (data.containsKey('last_review_at')) {
      context.handle(
        _lastReviewAtMeta,
        lastReviewAt.isAcceptableOrUnknown(
          data['last_review_at']!,
          _lastReviewAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wordId};
  @override
  ReviewCardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewCardRow(
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_at'],
      )!,
      stability: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stability'],
      )!,
      difficulty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}difficulty'],
      )!,
      elapsedDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_days'],
      )!,
      scheduledDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_days'],
      )!,
      reps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reps'],
      )!,
      lapses: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lapses'],
      )!,
      fsrsState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fsrs_state'],
      )!,
      learningSteps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}learning_steps'],
      )!,
      lastReviewAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_review_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReviewCardsTable createAlias(String alias) {
    return $ReviewCardsTable(attachedDatabase, alias);
  }
}

class ReviewCardRow extends DataClass implements Insertable<ReviewCardRow> {
  final int wordId;
  final int dueAt;
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays;
  final int reps;
  final int lapses;
  final int fsrsState;
  final int learningSteps;
  final int? lastReviewAt;
  final int createdAt;
  final int updatedAt;
  const ReviewCardRow({
    required this.wordId,
    required this.dueAt,
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.reps,
    required this.lapses,
    required this.fsrsState,
    required this.learningSteps,
    this.lastReviewAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word_id'] = Variable<int>(wordId);
    map['due_at'] = Variable<int>(dueAt);
    map['stability'] = Variable<double>(stability);
    map['difficulty'] = Variable<double>(difficulty);
    map['elapsed_days'] = Variable<int>(elapsedDays);
    map['scheduled_days'] = Variable<int>(scheduledDays);
    map['reps'] = Variable<int>(reps);
    map['lapses'] = Variable<int>(lapses);
    map['fsrs_state'] = Variable<int>(fsrsState);
    map['learning_steps'] = Variable<int>(learningSteps);
    if (!nullToAbsent || lastReviewAt != null) {
      map['last_review_at'] = Variable<int>(lastReviewAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ReviewCardsCompanion toCompanion(bool nullToAbsent) {
    return ReviewCardsCompanion(
      wordId: Value(wordId),
      dueAt: Value(dueAt),
      stability: Value(stability),
      difficulty: Value(difficulty),
      elapsedDays: Value(elapsedDays),
      scheduledDays: Value(scheduledDays),
      reps: Value(reps),
      lapses: Value(lapses),
      fsrsState: Value(fsrsState),
      learningSteps: Value(learningSteps),
      lastReviewAt: lastReviewAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReviewCardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewCardRow(
      wordId: serializer.fromJson<int>(json['wordId']),
      dueAt: serializer.fromJson<int>(json['dueAt']),
      stability: serializer.fromJson<double>(json['stability']),
      difficulty: serializer.fromJson<double>(json['difficulty']),
      elapsedDays: serializer.fromJson<int>(json['elapsedDays']),
      scheduledDays: serializer.fromJson<int>(json['scheduledDays']),
      reps: serializer.fromJson<int>(json['reps']),
      lapses: serializer.fromJson<int>(json['lapses']),
      fsrsState: serializer.fromJson<int>(json['fsrsState']),
      learningSteps: serializer.fromJson<int>(json['learningSteps']),
      lastReviewAt: serializer.fromJson<int?>(json['lastReviewAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wordId': serializer.toJson<int>(wordId),
      'dueAt': serializer.toJson<int>(dueAt),
      'stability': serializer.toJson<double>(stability),
      'difficulty': serializer.toJson<double>(difficulty),
      'elapsedDays': serializer.toJson<int>(elapsedDays),
      'scheduledDays': serializer.toJson<int>(scheduledDays),
      'reps': serializer.toJson<int>(reps),
      'lapses': serializer.toJson<int>(lapses),
      'fsrsState': serializer.toJson<int>(fsrsState),
      'learningSteps': serializer.toJson<int>(learningSteps),
      'lastReviewAt': serializer.toJson<int?>(lastReviewAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ReviewCardRow copyWith({
    int? wordId,
    int? dueAt,
    double? stability,
    double? difficulty,
    int? elapsedDays,
    int? scheduledDays,
    int? reps,
    int? lapses,
    int? fsrsState,
    int? learningSteps,
    Value<int?> lastReviewAt = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => ReviewCardRow(
    wordId: wordId ?? this.wordId,
    dueAt: dueAt ?? this.dueAt,
    stability: stability ?? this.stability,
    difficulty: difficulty ?? this.difficulty,
    elapsedDays: elapsedDays ?? this.elapsedDays,
    scheduledDays: scheduledDays ?? this.scheduledDays,
    reps: reps ?? this.reps,
    lapses: lapses ?? this.lapses,
    fsrsState: fsrsState ?? this.fsrsState,
    learningSteps: learningSteps ?? this.learningSteps,
    lastReviewAt: lastReviewAt.present ? lastReviewAt.value : this.lastReviewAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReviewCardRow copyWithCompanion(ReviewCardsCompanion data) {
    return ReviewCardRow(
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      stability: data.stability.present ? data.stability.value : this.stability,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      elapsedDays: data.elapsedDays.present
          ? data.elapsedDays.value
          : this.elapsedDays,
      scheduledDays: data.scheduledDays.present
          ? data.scheduledDays.value
          : this.scheduledDays,
      reps: data.reps.present ? data.reps.value : this.reps,
      lapses: data.lapses.present ? data.lapses.value : this.lapses,
      fsrsState: data.fsrsState.present ? data.fsrsState.value : this.fsrsState,
      learningSteps: data.learningSteps.present
          ? data.learningSteps.value
          : this.learningSteps,
      lastReviewAt: data.lastReviewAt.present
          ? data.lastReviewAt.value
          : this.lastReviewAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewCardRow(')
          ..write('wordId: $wordId, ')
          ..write('dueAt: $dueAt, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('elapsedDays: $elapsedDays, ')
          ..write('scheduledDays: $scheduledDays, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('fsrsState: $fsrsState, ')
          ..write('learningSteps: $learningSteps, ')
          ..write('lastReviewAt: $lastReviewAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    wordId,
    dueAt,
    stability,
    difficulty,
    elapsedDays,
    scheduledDays,
    reps,
    lapses,
    fsrsState,
    learningSteps,
    lastReviewAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewCardRow &&
          other.wordId == this.wordId &&
          other.dueAt == this.dueAt &&
          other.stability == this.stability &&
          other.difficulty == this.difficulty &&
          other.elapsedDays == this.elapsedDays &&
          other.scheduledDays == this.scheduledDays &&
          other.reps == this.reps &&
          other.lapses == this.lapses &&
          other.fsrsState == this.fsrsState &&
          other.learningSteps == this.learningSteps &&
          other.lastReviewAt == this.lastReviewAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ReviewCardsCompanion extends UpdateCompanion<ReviewCardRow> {
  final Value<int> wordId;
  final Value<int> dueAt;
  final Value<double> stability;
  final Value<double> difficulty;
  final Value<int> elapsedDays;
  final Value<int> scheduledDays;
  final Value<int> reps;
  final Value<int> lapses;
  final Value<int> fsrsState;
  final Value<int> learningSteps;
  final Value<int?> lastReviewAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const ReviewCardsCompanion({
    this.wordId = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.elapsedDays = const Value.absent(),
    this.scheduledDays = const Value.absent(),
    this.reps = const Value.absent(),
    this.lapses = const Value.absent(),
    this.fsrsState = const Value.absent(),
    this.learningSteps = const Value.absent(),
    this.lastReviewAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ReviewCardsCompanion.insert({
    this.wordId = const Value.absent(),
    required int dueAt,
    required double stability,
    required double difficulty,
    required int elapsedDays,
    required int scheduledDays,
    required int reps,
    required int lapses,
    required int fsrsState,
    this.learningSteps = const Value.absent(),
    this.lastReviewAt = const Value.absent(),
    required int createdAt,
    required int updatedAt,
  }) : dueAt = Value(dueAt),
       stability = Value(stability),
       difficulty = Value(difficulty),
       elapsedDays = Value(elapsedDays),
       scheduledDays = Value(scheduledDays),
       reps = Value(reps),
       lapses = Value(lapses),
       fsrsState = Value(fsrsState),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ReviewCardRow> custom({
    Expression<int>? wordId,
    Expression<int>? dueAt,
    Expression<double>? stability,
    Expression<double>? difficulty,
    Expression<int>? elapsedDays,
    Expression<int>? scheduledDays,
    Expression<int>? reps,
    Expression<int>? lapses,
    Expression<int>? fsrsState,
    Expression<int>? learningSteps,
    Expression<int>? lastReviewAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (wordId != null) 'word_id': wordId,
      if (dueAt != null) 'due_at': dueAt,
      if (stability != null) 'stability': stability,
      if (difficulty != null) 'difficulty': difficulty,
      if (elapsedDays != null) 'elapsed_days': elapsedDays,
      if (scheduledDays != null) 'scheduled_days': scheduledDays,
      if (reps != null) 'reps': reps,
      if (lapses != null) 'lapses': lapses,
      if (fsrsState != null) 'fsrs_state': fsrsState,
      if (learningSteps != null) 'learning_steps': learningSteps,
      if (lastReviewAt != null) 'last_review_at': lastReviewAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ReviewCardsCompanion copyWith({
    Value<int>? wordId,
    Value<int>? dueAt,
    Value<double>? stability,
    Value<double>? difficulty,
    Value<int>? elapsedDays,
    Value<int>? scheduledDays,
    Value<int>? reps,
    Value<int>? lapses,
    Value<int>? fsrsState,
    Value<int>? learningSteps,
    Value<int?>? lastReviewAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
  }) {
    return ReviewCardsCompanion(
      wordId: wordId ?? this.wordId,
      dueAt: dueAt ?? this.dueAt,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      elapsedDays: elapsedDays ?? this.elapsedDays,
      scheduledDays: scheduledDays ?? this.scheduledDays,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      fsrsState: fsrsState ?? this.fsrsState,
      learningSteps: learningSteps ?? this.learningSteps,
      lastReviewAt: lastReviewAt ?? this.lastReviewAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (stability.present) {
      map['stability'] = Variable<double>(stability.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (elapsedDays.present) {
      map['elapsed_days'] = Variable<int>(elapsedDays.value);
    }
    if (scheduledDays.present) {
      map['scheduled_days'] = Variable<int>(scheduledDays.value);
    }
    if (reps.present) {
      map['reps'] = Variable<int>(reps.value);
    }
    if (lapses.present) {
      map['lapses'] = Variable<int>(lapses.value);
    }
    if (fsrsState.present) {
      map['fsrs_state'] = Variable<int>(fsrsState.value);
    }
    if (learningSteps.present) {
      map['learning_steps'] = Variable<int>(learningSteps.value);
    }
    if (lastReviewAt.present) {
      map['last_review_at'] = Variable<int>(lastReviewAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewCardsCompanion(')
          ..write('wordId: $wordId, ')
          ..write('dueAt: $dueAt, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('elapsedDays: $elapsedDays, ')
          ..write('scheduledDays: $scheduledDays, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('fsrsState: $fsrsState, ')
          ..write('learningSteps: $learningSteps, ')
          ..write('lastReviewAt: $lastReviewAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ReviewLogsTable extends ReviewLogs
    with TableInfo<$ReviewLogsTable, ReviewLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewLogsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _clientAnswerIdMeta = const VerificationMeta(
    'clientAnswerId',
  );
  @override
  late final GeneratedColumn<String> clientAnswerId = GeneratedColumn<String>(
    'client_answer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _studySessionIdMeta = const VerificationMeta(
    'studySessionId',
  );
  @override
  late final GeneratedColumn<int> studySessionId = GeneratedColumn<int>(
    'study_session_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES study_sessions (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _studySessionItemIdMeta =
      const VerificationMeta('studySessionItemId');
  @override
  late final GeneratedColumn<int> studySessionItemId = GeneratedColumn<int>(
    'study_session_item_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES study_session_items (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<int> reviewedAt = GeneratedColumn<int>(
    'reviewed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ReviewRating, String> rating =
      GeneratedColumn<String>(
        'rating',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ReviewRating>($ReviewLogsTable.$converterrating);
  @override
  late final GeneratedColumnWithTypeConverter<QuestionType, String>
  questionType = GeneratedColumn<String>(
    'question_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<QuestionType>($ReviewLogsTable.$converterquestionType);
  static const VerificationMeta _presentedPromptMeta = const VerificationMeta(
    'presentedPrompt',
  );
  @override
  late final GeneratedColumn<String> presentedPrompt = GeneratedColumn<String>(
    'presented_prompt',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userAnswerMeta = const VerificationMeta(
    'userAnswer',
  );
  @override
  late final GeneratedColumn<String> userAnswer = GeneratedColumn<String>(
    'user_answer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expectedAnswerMeta = const VerificationMeta(
    'expectedAnswer',
  );
  @override
  late final GeneratedColumn<String> expectedAnswer = GeneratedColumn<String>(
    'expected_answer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCorrectMeta = const VerificationMeta(
    'isCorrect',
  );
  @override
  late final GeneratedColumn<bool> isCorrect = GeneratedColumn<bool>(
    'is_correct',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_correct" IN (0, 1))',
    ),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardBeforeJsonMeta = const VerificationMeta(
    'cardBeforeJson',
  );
  @override
  late final GeneratedColumn<String> cardBeforeJson = GeneratedColumn<String>(
    'card_before_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardAfterJsonMeta = const VerificationMeta(
    'cardAfterJson',
  );
  @override
  late final GeneratedColumn<String> cardAfterJson = GeneratedColumn<String>(
    'card_after_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientAnswerId,
    wordId,
    studySessionId,
    studySessionItemId,
    reviewedAt,
    rating,
    questionType,
    presentedPrompt,
    userAnswer,
    expectedAnswer,
    isCorrect,
    durationMs,
    cardBeforeJson,
    cardAfterJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('client_answer_id')) {
      context.handle(
        _clientAnswerIdMeta,
        clientAnswerId.isAcceptableOrUnknown(
          data['client_answer_id']!,
          _clientAnswerIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientAnswerIdMeta);
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('study_session_id')) {
      context.handle(
        _studySessionIdMeta,
        studySessionId.isAcceptableOrUnknown(
          data['study_session_id']!,
          _studySessionIdMeta,
        ),
      );
    }
    if (data.containsKey('study_session_item_id')) {
      context.handle(
        _studySessionItemIdMeta,
        studySessionItemId.isAcceptableOrUnknown(
          data['study_session_item_id']!,
          _studySessionItemIdMeta,
        ),
      );
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewedAtMeta);
    }
    if (data.containsKey('presented_prompt')) {
      context.handle(
        _presentedPromptMeta,
        presentedPrompt.isAcceptableOrUnknown(
          data['presented_prompt']!,
          _presentedPromptMeta,
        ),
      );
    }
    if (data.containsKey('user_answer')) {
      context.handle(
        _userAnswerMeta,
        userAnswer.isAcceptableOrUnknown(data['user_answer']!, _userAnswerMeta),
      );
    }
    if (data.containsKey('expected_answer')) {
      context.handle(
        _expectedAnswerMeta,
        expectedAnswer.isAcceptableOrUnknown(
          data['expected_answer']!,
          _expectedAnswerMeta,
        ),
      );
    }
    if (data.containsKey('is_correct')) {
      context.handle(
        _isCorrectMeta,
        isCorrect.isAcceptableOrUnknown(data['is_correct']!, _isCorrectMeta),
      );
    } else if (isInserting) {
      context.missing(_isCorrectMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('card_before_json')) {
      context.handle(
        _cardBeforeJsonMeta,
        cardBeforeJson.isAcceptableOrUnknown(
          data['card_before_json']!,
          _cardBeforeJsonMeta,
        ),
      );
    }
    if (data.containsKey('card_after_json')) {
      context.handle(
        _cardAfterJsonMeta,
        cardAfterJson.isAcceptableOrUnknown(
          data['card_after_json']!,
          _cardAfterJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {clientAnswerId},
  ];
  @override
  ReviewLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      clientAnswerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_answer_id'],
      )!,
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      studySessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}study_session_id'],
      ),
      studySessionItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}study_session_item_id'],
      ),
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reviewed_at'],
      )!,
      rating: $ReviewLogsTable.$converterrating.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}rating'],
        )!,
      ),
      questionType: $ReviewLogsTable.$converterquestionType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}question_type'],
        )!,
      ),
      presentedPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}presented_prompt'],
      ),
      userAnswer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_answer'],
      ),
      expectedAnswer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_answer'],
      ),
      isCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_correct'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      cardBeforeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_before_json'],
      ),
      cardAfterJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_after_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReviewLogsTable createAlias(String alias) {
    return $ReviewLogsTable(attachedDatabase, alias);
  }

  static TypeConverter<ReviewRating, String> $converterrating =
      const WireEnumConverter<ReviewRating>(ReviewRating.values);
  static TypeConverter<QuestionType, String> $converterquestionType =
      const WireEnumConverter<QuestionType>(QuestionType.values);
}

class ReviewLogRow extends DataClass implements Insertable<ReviewLogRow> {
  final int id;
  final String clientAnswerId;
  final int wordId;
  final int? studySessionId;
  final int? studySessionItemId;
  final int reviewedAt;
  final ReviewRating rating;
  final QuestionType questionType;
  final String? presentedPrompt;
  final String? userAnswer;
  final String? expectedAnswer;
  final bool isCorrect;
  final int? durationMs;
  final String? cardBeforeJson;
  final String? cardAfterJson;
  final int createdAt;
  const ReviewLogRow({
    required this.id,
    required this.clientAnswerId,
    required this.wordId,
    this.studySessionId,
    this.studySessionItemId,
    required this.reviewedAt,
    required this.rating,
    required this.questionType,
    this.presentedPrompt,
    this.userAnswer,
    this.expectedAnswer,
    required this.isCorrect,
    this.durationMs,
    this.cardBeforeJson,
    this.cardAfterJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['client_answer_id'] = Variable<String>(clientAnswerId);
    map['word_id'] = Variable<int>(wordId);
    if (!nullToAbsent || studySessionId != null) {
      map['study_session_id'] = Variable<int>(studySessionId);
    }
    if (!nullToAbsent || studySessionItemId != null) {
      map['study_session_item_id'] = Variable<int>(studySessionItemId);
    }
    map['reviewed_at'] = Variable<int>(reviewedAt);
    {
      map['rating'] = Variable<String>(
        $ReviewLogsTable.$converterrating.toSql(rating),
      );
    }
    {
      map['question_type'] = Variable<String>(
        $ReviewLogsTable.$converterquestionType.toSql(questionType),
      );
    }
    if (!nullToAbsent || presentedPrompt != null) {
      map['presented_prompt'] = Variable<String>(presentedPrompt);
    }
    if (!nullToAbsent || userAnswer != null) {
      map['user_answer'] = Variable<String>(userAnswer);
    }
    if (!nullToAbsent || expectedAnswer != null) {
      map['expected_answer'] = Variable<String>(expectedAnswer);
    }
    map['is_correct'] = Variable<bool>(isCorrect);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || cardBeforeJson != null) {
      map['card_before_json'] = Variable<String>(cardBeforeJson);
    }
    if (!nullToAbsent || cardAfterJson != null) {
      map['card_after_json'] = Variable<String>(cardAfterJson);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ReviewLogsCompanion toCompanion(bool nullToAbsent) {
    return ReviewLogsCompanion(
      id: Value(id),
      clientAnswerId: Value(clientAnswerId),
      wordId: Value(wordId),
      studySessionId: studySessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(studySessionId),
      studySessionItemId: studySessionItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(studySessionItemId),
      reviewedAt: Value(reviewedAt),
      rating: Value(rating),
      questionType: Value(questionType),
      presentedPrompt: presentedPrompt == null && nullToAbsent
          ? const Value.absent()
          : Value(presentedPrompt),
      userAnswer: userAnswer == null && nullToAbsent
          ? const Value.absent()
          : Value(userAnswer),
      expectedAnswer: expectedAnswer == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedAnswer),
      isCorrect: Value(isCorrect),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      cardBeforeJson: cardBeforeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(cardBeforeJson),
      cardAfterJson: cardAfterJson == null && nullToAbsent
          ? const Value.absent()
          : Value(cardAfterJson),
      createdAt: Value(createdAt),
    );
  }

  factory ReviewLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewLogRow(
      id: serializer.fromJson<int>(json['id']),
      clientAnswerId: serializer.fromJson<String>(json['clientAnswerId']),
      wordId: serializer.fromJson<int>(json['wordId']),
      studySessionId: serializer.fromJson<int?>(json['studySessionId']),
      studySessionItemId: serializer.fromJson<int?>(json['studySessionItemId']),
      reviewedAt: serializer.fromJson<int>(json['reviewedAt']),
      rating: serializer.fromJson<ReviewRating>(json['rating']),
      questionType: serializer.fromJson<QuestionType>(json['questionType']),
      presentedPrompt: serializer.fromJson<String?>(json['presentedPrompt']),
      userAnswer: serializer.fromJson<String?>(json['userAnswer']),
      expectedAnswer: serializer.fromJson<String?>(json['expectedAnswer']),
      isCorrect: serializer.fromJson<bool>(json['isCorrect']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      cardBeforeJson: serializer.fromJson<String?>(json['cardBeforeJson']),
      cardAfterJson: serializer.fromJson<String?>(json['cardAfterJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'clientAnswerId': serializer.toJson<String>(clientAnswerId),
      'wordId': serializer.toJson<int>(wordId),
      'studySessionId': serializer.toJson<int?>(studySessionId),
      'studySessionItemId': serializer.toJson<int?>(studySessionItemId),
      'reviewedAt': serializer.toJson<int>(reviewedAt),
      'rating': serializer.toJson<ReviewRating>(rating),
      'questionType': serializer.toJson<QuestionType>(questionType),
      'presentedPrompt': serializer.toJson<String?>(presentedPrompt),
      'userAnswer': serializer.toJson<String?>(userAnswer),
      'expectedAnswer': serializer.toJson<String?>(expectedAnswer),
      'isCorrect': serializer.toJson<bool>(isCorrect),
      'durationMs': serializer.toJson<int?>(durationMs),
      'cardBeforeJson': serializer.toJson<String?>(cardBeforeJson),
      'cardAfterJson': serializer.toJson<String?>(cardAfterJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ReviewLogRow copyWith({
    int? id,
    String? clientAnswerId,
    int? wordId,
    Value<int?> studySessionId = const Value.absent(),
    Value<int?> studySessionItemId = const Value.absent(),
    int? reviewedAt,
    ReviewRating? rating,
    QuestionType? questionType,
    Value<String?> presentedPrompt = const Value.absent(),
    Value<String?> userAnswer = const Value.absent(),
    Value<String?> expectedAnswer = const Value.absent(),
    bool? isCorrect,
    Value<int?> durationMs = const Value.absent(),
    Value<String?> cardBeforeJson = const Value.absent(),
    Value<String?> cardAfterJson = const Value.absent(),
    int? createdAt,
  }) => ReviewLogRow(
    id: id ?? this.id,
    clientAnswerId: clientAnswerId ?? this.clientAnswerId,
    wordId: wordId ?? this.wordId,
    studySessionId: studySessionId.present
        ? studySessionId.value
        : this.studySessionId,
    studySessionItemId: studySessionItemId.present
        ? studySessionItemId.value
        : this.studySessionItemId,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    rating: rating ?? this.rating,
    questionType: questionType ?? this.questionType,
    presentedPrompt: presentedPrompt.present
        ? presentedPrompt.value
        : this.presentedPrompt,
    userAnswer: userAnswer.present ? userAnswer.value : this.userAnswer,
    expectedAnswer: expectedAnswer.present
        ? expectedAnswer.value
        : this.expectedAnswer,
    isCorrect: isCorrect ?? this.isCorrect,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    cardBeforeJson: cardBeforeJson.present
        ? cardBeforeJson.value
        : this.cardBeforeJson,
    cardAfterJson: cardAfterJson.present
        ? cardAfterJson.value
        : this.cardAfterJson,
    createdAt: createdAt ?? this.createdAt,
  );
  ReviewLogRow copyWithCompanion(ReviewLogsCompanion data) {
    return ReviewLogRow(
      id: data.id.present ? data.id.value : this.id,
      clientAnswerId: data.clientAnswerId.present
          ? data.clientAnswerId.value
          : this.clientAnswerId,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      studySessionId: data.studySessionId.present
          ? data.studySessionId.value
          : this.studySessionId,
      studySessionItemId: data.studySessionItemId.present
          ? data.studySessionItemId.value
          : this.studySessionItemId,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
      rating: data.rating.present ? data.rating.value : this.rating,
      questionType: data.questionType.present
          ? data.questionType.value
          : this.questionType,
      presentedPrompt: data.presentedPrompt.present
          ? data.presentedPrompt.value
          : this.presentedPrompt,
      userAnswer: data.userAnswer.present
          ? data.userAnswer.value
          : this.userAnswer,
      expectedAnswer: data.expectedAnswer.present
          ? data.expectedAnswer.value
          : this.expectedAnswer,
      isCorrect: data.isCorrect.present ? data.isCorrect.value : this.isCorrect,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      cardBeforeJson: data.cardBeforeJson.present
          ? data.cardBeforeJson.value
          : this.cardBeforeJson,
      cardAfterJson: data.cardAfterJson.present
          ? data.cardAfterJson.value
          : this.cardAfterJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLogRow(')
          ..write('id: $id, ')
          ..write('clientAnswerId: $clientAnswerId, ')
          ..write('wordId: $wordId, ')
          ..write('studySessionId: $studySessionId, ')
          ..write('studySessionItemId: $studySessionItemId, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('rating: $rating, ')
          ..write('questionType: $questionType, ')
          ..write('presentedPrompt: $presentedPrompt, ')
          ..write('userAnswer: $userAnswer, ')
          ..write('expectedAnswer: $expectedAnswer, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('durationMs: $durationMs, ')
          ..write('cardBeforeJson: $cardBeforeJson, ')
          ..write('cardAfterJson: $cardAfterJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientAnswerId,
    wordId,
    studySessionId,
    studySessionItemId,
    reviewedAt,
    rating,
    questionType,
    presentedPrompt,
    userAnswer,
    expectedAnswer,
    isCorrect,
    durationMs,
    cardBeforeJson,
    cardAfterJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewLogRow &&
          other.id == this.id &&
          other.clientAnswerId == this.clientAnswerId &&
          other.wordId == this.wordId &&
          other.studySessionId == this.studySessionId &&
          other.studySessionItemId == this.studySessionItemId &&
          other.reviewedAt == this.reviewedAt &&
          other.rating == this.rating &&
          other.questionType == this.questionType &&
          other.presentedPrompt == this.presentedPrompt &&
          other.userAnswer == this.userAnswer &&
          other.expectedAnswer == this.expectedAnswer &&
          other.isCorrect == this.isCorrect &&
          other.durationMs == this.durationMs &&
          other.cardBeforeJson == this.cardBeforeJson &&
          other.cardAfterJson == this.cardAfterJson &&
          other.createdAt == this.createdAt);
}

class ReviewLogsCompanion extends UpdateCompanion<ReviewLogRow> {
  final Value<int> id;
  final Value<String> clientAnswerId;
  final Value<int> wordId;
  final Value<int?> studySessionId;
  final Value<int?> studySessionItemId;
  final Value<int> reviewedAt;
  final Value<ReviewRating> rating;
  final Value<QuestionType> questionType;
  final Value<String?> presentedPrompt;
  final Value<String?> userAnswer;
  final Value<String?> expectedAnswer;
  final Value<bool> isCorrect;
  final Value<int?> durationMs;
  final Value<String?> cardBeforeJson;
  final Value<String?> cardAfterJson;
  final Value<int> createdAt;
  const ReviewLogsCompanion({
    this.id = const Value.absent(),
    this.clientAnswerId = const Value.absent(),
    this.wordId = const Value.absent(),
    this.studySessionId = const Value.absent(),
    this.studySessionItemId = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.rating = const Value.absent(),
    this.questionType = const Value.absent(),
    this.presentedPrompt = const Value.absent(),
    this.userAnswer = const Value.absent(),
    this.expectedAnswer = const Value.absent(),
    this.isCorrect = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.cardBeforeJson = const Value.absent(),
    this.cardAfterJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ReviewLogsCompanion.insert({
    this.id = const Value.absent(),
    required String clientAnswerId,
    required int wordId,
    this.studySessionId = const Value.absent(),
    this.studySessionItemId = const Value.absent(),
    required int reviewedAt,
    required ReviewRating rating,
    required QuestionType questionType,
    this.presentedPrompt = const Value.absent(),
    this.userAnswer = const Value.absent(),
    this.expectedAnswer = const Value.absent(),
    required bool isCorrect,
    this.durationMs = const Value.absent(),
    this.cardBeforeJson = const Value.absent(),
    this.cardAfterJson = const Value.absent(),
    required int createdAt,
  }) : clientAnswerId = Value(clientAnswerId),
       wordId = Value(wordId),
       reviewedAt = Value(reviewedAt),
       rating = Value(rating),
       questionType = Value(questionType),
       isCorrect = Value(isCorrect),
       createdAt = Value(createdAt);
  static Insertable<ReviewLogRow> custom({
    Expression<int>? id,
    Expression<String>? clientAnswerId,
    Expression<int>? wordId,
    Expression<int>? studySessionId,
    Expression<int>? studySessionItemId,
    Expression<int>? reviewedAt,
    Expression<String>? rating,
    Expression<String>? questionType,
    Expression<String>? presentedPrompt,
    Expression<String>? userAnswer,
    Expression<String>? expectedAnswer,
    Expression<bool>? isCorrect,
    Expression<int>? durationMs,
    Expression<String>? cardBeforeJson,
    Expression<String>? cardAfterJson,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientAnswerId != null) 'client_answer_id': clientAnswerId,
      if (wordId != null) 'word_id': wordId,
      if (studySessionId != null) 'study_session_id': studySessionId,
      if (studySessionItemId != null)
        'study_session_item_id': studySessionItemId,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (rating != null) 'rating': rating,
      if (questionType != null) 'question_type': questionType,
      if (presentedPrompt != null) 'presented_prompt': presentedPrompt,
      if (userAnswer != null) 'user_answer': userAnswer,
      if (expectedAnswer != null) 'expected_answer': expectedAnswer,
      if (isCorrect != null) 'is_correct': isCorrect,
      if (durationMs != null) 'duration_ms': durationMs,
      if (cardBeforeJson != null) 'card_before_json': cardBeforeJson,
      if (cardAfterJson != null) 'card_after_json': cardAfterJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ReviewLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? clientAnswerId,
    Value<int>? wordId,
    Value<int?>? studySessionId,
    Value<int?>? studySessionItemId,
    Value<int>? reviewedAt,
    Value<ReviewRating>? rating,
    Value<QuestionType>? questionType,
    Value<String?>? presentedPrompt,
    Value<String?>? userAnswer,
    Value<String?>? expectedAnswer,
    Value<bool>? isCorrect,
    Value<int?>? durationMs,
    Value<String?>? cardBeforeJson,
    Value<String?>? cardAfterJson,
    Value<int>? createdAt,
  }) {
    return ReviewLogsCompanion(
      id: id ?? this.id,
      clientAnswerId: clientAnswerId ?? this.clientAnswerId,
      wordId: wordId ?? this.wordId,
      studySessionId: studySessionId ?? this.studySessionId,
      studySessionItemId: studySessionItemId ?? this.studySessionItemId,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rating: rating ?? this.rating,
      questionType: questionType ?? this.questionType,
      presentedPrompt: presentedPrompt ?? this.presentedPrompt,
      userAnswer: userAnswer ?? this.userAnswer,
      expectedAnswer: expectedAnswer ?? this.expectedAnswer,
      isCorrect: isCorrect ?? this.isCorrect,
      durationMs: durationMs ?? this.durationMs,
      cardBeforeJson: cardBeforeJson ?? this.cardBeforeJson,
      cardAfterJson: cardAfterJson ?? this.cardAfterJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (clientAnswerId.present) {
      map['client_answer_id'] = Variable<String>(clientAnswerId.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (studySessionId.present) {
      map['study_session_id'] = Variable<int>(studySessionId.value);
    }
    if (studySessionItemId.present) {
      map['study_session_item_id'] = Variable<int>(studySessionItemId.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<int>(reviewedAt.value);
    }
    if (rating.present) {
      map['rating'] = Variable<String>(
        $ReviewLogsTable.$converterrating.toSql(rating.value),
      );
    }
    if (questionType.present) {
      map['question_type'] = Variable<String>(
        $ReviewLogsTable.$converterquestionType.toSql(questionType.value),
      );
    }
    if (presentedPrompt.present) {
      map['presented_prompt'] = Variable<String>(presentedPrompt.value);
    }
    if (userAnswer.present) {
      map['user_answer'] = Variable<String>(userAnswer.value);
    }
    if (expectedAnswer.present) {
      map['expected_answer'] = Variable<String>(expectedAnswer.value);
    }
    if (isCorrect.present) {
      map['is_correct'] = Variable<bool>(isCorrect.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (cardBeforeJson.present) {
      map['card_before_json'] = Variable<String>(cardBeforeJson.value);
    }
    if (cardAfterJson.present) {
      map['card_after_json'] = Variable<String>(cardAfterJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLogsCompanion(')
          ..write('id: $id, ')
          ..write('clientAnswerId: $clientAnswerId, ')
          ..write('wordId: $wordId, ')
          ..write('studySessionId: $studySessionId, ')
          ..write('studySessionItemId: $studySessionItemId, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('rating: $rating, ')
          ..write('questionType: $questionType, ')
          ..write('presentedPrompt: $presentedPrompt, ')
          ..write('userAnswer: $userAnswer, ')
          ..write('expectedAnswer: $expectedAnswer, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('durationMs: $durationMs, ')
          ..write('cardBeforeJson: $cardBeforeJson, ')
          ..write('cardAfterJson: $cardAfterJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $WrongWordStatesTable extends WrongWordStates
    with TableInfo<$WrongWordStatesTable, WrongWordStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WrongWordStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _wrongCountMeta = const VerificationMeta(
    'wrongCount',
  );
  @override
  late final GeneratedColumn<int> wrongCount = GeneratedColumn<int>(
    'wrong_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _hardCountMeta = const VerificationMeta(
    'hardCount',
  );
  @override
  late final GeneratedColumn<int> hardCount = GeneratedColumn<int>(
    'hard_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _consecutiveCorrectMeta =
      const VerificationMeta('consecutiveCorrect');
  @override
  late final GeneratedColumn<int> consecutiveCorrect = GeneratedColumn<int>(
    'consecutive_correct',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastWrongAtMeta = const VerificationMeta(
    'lastWrongAt',
  );
  @override
  late final GeneratedColumn<int> lastWrongAt = GeneratedColumn<int>(
    'last_wrong_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCorrectAtMeta = const VerificationMeta(
    'lastCorrectAt',
  );
  @override
  late final GeneratedColumn<int> lastCorrectAt = GeneratedColumn<int>(
    'last_correct_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<int> resolvedAt = GeneratedColumn<int>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    wordId,
    active,
    wrongCount,
    hardCount,
    consecutiveCorrect,
    lastWrongAt,
    lastCorrectAt,
    resolvedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wrong_word_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<WrongWordStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('wrong_count')) {
      context.handle(
        _wrongCountMeta,
        wrongCount.isAcceptableOrUnknown(data['wrong_count']!, _wrongCountMeta),
      );
    }
    if (data.containsKey('hard_count')) {
      context.handle(
        _hardCountMeta,
        hardCount.isAcceptableOrUnknown(data['hard_count']!, _hardCountMeta),
      );
    }
    if (data.containsKey('consecutive_correct')) {
      context.handle(
        _consecutiveCorrectMeta,
        consecutiveCorrect.isAcceptableOrUnknown(
          data['consecutive_correct']!,
          _consecutiveCorrectMeta,
        ),
      );
    }
    if (data.containsKey('last_wrong_at')) {
      context.handle(
        _lastWrongAtMeta,
        lastWrongAt.isAcceptableOrUnknown(
          data['last_wrong_at']!,
          _lastWrongAtMeta,
        ),
      );
    }
    if (data.containsKey('last_correct_at')) {
      context.handle(
        _lastCorrectAtMeta,
        lastCorrectAt.isAcceptableOrUnknown(
          data['last_correct_at']!,
          _lastCorrectAtMeta,
        ),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wordId};
  @override
  WrongWordStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WrongWordStateRow(
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      wrongCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wrong_count'],
      )!,
      hardCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hard_count'],
      )!,
      consecutiveCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}consecutive_correct'],
      )!,
      lastWrongAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_wrong_at'],
      ),
      lastCorrectAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_correct_at'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WrongWordStatesTable createAlias(String alias) {
    return $WrongWordStatesTable(attachedDatabase, alias);
  }
}

class WrongWordStateRow extends DataClass
    implements Insertable<WrongWordStateRow> {
  final int wordId;
  final bool active;
  final int wrongCount;
  final int hardCount;
  final int consecutiveCorrect;
  final int? lastWrongAt;
  final int? lastCorrectAt;
  final int? resolvedAt;
  final int updatedAt;
  const WrongWordStateRow({
    required this.wordId,
    required this.active,
    required this.wrongCount,
    required this.hardCount,
    required this.consecutiveCorrect,
    this.lastWrongAt,
    this.lastCorrectAt,
    this.resolvedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word_id'] = Variable<int>(wordId);
    map['active'] = Variable<bool>(active);
    map['wrong_count'] = Variable<int>(wrongCount);
    map['hard_count'] = Variable<int>(hardCount);
    map['consecutive_correct'] = Variable<int>(consecutiveCorrect);
    if (!nullToAbsent || lastWrongAt != null) {
      map['last_wrong_at'] = Variable<int>(lastWrongAt);
    }
    if (!nullToAbsent || lastCorrectAt != null) {
      map['last_correct_at'] = Variable<int>(lastCorrectAt);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<int>(resolvedAt);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  WrongWordStatesCompanion toCompanion(bool nullToAbsent) {
    return WrongWordStatesCompanion(
      wordId: Value(wordId),
      active: Value(active),
      wrongCount: Value(wrongCount),
      hardCount: Value(hardCount),
      consecutiveCorrect: Value(consecutiveCorrect),
      lastWrongAt: lastWrongAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastWrongAt),
      lastCorrectAt: lastCorrectAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCorrectAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WrongWordStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WrongWordStateRow(
      wordId: serializer.fromJson<int>(json['wordId']),
      active: serializer.fromJson<bool>(json['active']),
      wrongCount: serializer.fromJson<int>(json['wrongCount']),
      hardCount: serializer.fromJson<int>(json['hardCount']),
      consecutiveCorrect: serializer.fromJson<int>(json['consecutiveCorrect']),
      lastWrongAt: serializer.fromJson<int?>(json['lastWrongAt']),
      lastCorrectAt: serializer.fromJson<int?>(json['lastCorrectAt']),
      resolvedAt: serializer.fromJson<int?>(json['resolvedAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wordId': serializer.toJson<int>(wordId),
      'active': serializer.toJson<bool>(active),
      'wrongCount': serializer.toJson<int>(wrongCount),
      'hardCount': serializer.toJson<int>(hardCount),
      'consecutiveCorrect': serializer.toJson<int>(consecutiveCorrect),
      'lastWrongAt': serializer.toJson<int?>(lastWrongAt),
      'lastCorrectAt': serializer.toJson<int?>(lastCorrectAt),
      'resolvedAt': serializer.toJson<int?>(resolvedAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  WrongWordStateRow copyWith({
    int? wordId,
    bool? active,
    int? wrongCount,
    int? hardCount,
    int? consecutiveCorrect,
    Value<int?> lastWrongAt = const Value.absent(),
    Value<int?> lastCorrectAt = const Value.absent(),
    Value<int?> resolvedAt = const Value.absent(),
    int? updatedAt,
  }) => WrongWordStateRow(
    wordId: wordId ?? this.wordId,
    active: active ?? this.active,
    wrongCount: wrongCount ?? this.wrongCount,
    hardCount: hardCount ?? this.hardCount,
    consecutiveCorrect: consecutiveCorrect ?? this.consecutiveCorrect,
    lastWrongAt: lastWrongAt.present ? lastWrongAt.value : this.lastWrongAt,
    lastCorrectAt: lastCorrectAt.present
        ? lastCorrectAt.value
        : this.lastCorrectAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WrongWordStateRow copyWithCompanion(WrongWordStatesCompanion data) {
    return WrongWordStateRow(
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      active: data.active.present ? data.active.value : this.active,
      wrongCount: data.wrongCount.present
          ? data.wrongCount.value
          : this.wrongCount,
      hardCount: data.hardCount.present ? data.hardCount.value : this.hardCount,
      consecutiveCorrect: data.consecutiveCorrect.present
          ? data.consecutiveCorrect.value
          : this.consecutiveCorrect,
      lastWrongAt: data.lastWrongAt.present
          ? data.lastWrongAt.value
          : this.lastWrongAt,
      lastCorrectAt: data.lastCorrectAt.present
          ? data.lastCorrectAt.value
          : this.lastCorrectAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WrongWordStateRow(')
          ..write('wordId: $wordId, ')
          ..write('active: $active, ')
          ..write('wrongCount: $wrongCount, ')
          ..write('hardCount: $hardCount, ')
          ..write('consecutiveCorrect: $consecutiveCorrect, ')
          ..write('lastWrongAt: $lastWrongAt, ')
          ..write('lastCorrectAt: $lastCorrectAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    wordId,
    active,
    wrongCount,
    hardCount,
    consecutiveCorrect,
    lastWrongAt,
    lastCorrectAt,
    resolvedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WrongWordStateRow &&
          other.wordId == this.wordId &&
          other.active == this.active &&
          other.wrongCount == this.wrongCount &&
          other.hardCount == this.hardCount &&
          other.consecutiveCorrect == this.consecutiveCorrect &&
          other.lastWrongAt == this.lastWrongAt &&
          other.lastCorrectAt == this.lastCorrectAt &&
          other.resolvedAt == this.resolvedAt &&
          other.updatedAt == this.updatedAt);
}

class WrongWordStatesCompanion extends UpdateCompanion<WrongWordStateRow> {
  final Value<int> wordId;
  final Value<bool> active;
  final Value<int> wrongCount;
  final Value<int> hardCount;
  final Value<int> consecutiveCorrect;
  final Value<int?> lastWrongAt;
  final Value<int?> lastCorrectAt;
  final Value<int?> resolvedAt;
  final Value<int> updatedAt;
  const WrongWordStatesCompanion({
    this.wordId = const Value.absent(),
    this.active = const Value.absent(),
    this.wrongCount = const Value.absent(),
    this.hardCount = const Value.absent(),
    this.consecutiveCorrect = const Value.absent(),
    this.lastWrongAt = const Value.absent(),
    this.lastCorrectAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WrongWordStatesCompanion.insert({
    this.wordId = const Value.absent(),
    this.active = const Value.absent(),
    this.wrongCount = const Value.absent(),
    this.hardCount = const Value.absent(),
    this.consecutiveCorrect = const Value.absent(),
    this.lastWrongAt = const Value.absent(),
    this.lastCorrectAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    required int updatedAt,
  }) : updatedAt = Value(updatedAt);
  static Insertable<WrongWordStateRow> custom({
    Expression<int>? wordId,
    Expression<bool>? active,
    Expression<int>? wrongCount,
    Expression<int>? hardCount,
    Expression<int>? consecutiveCorrect,
    Expression<int>? lastWrongAt,
    Expression<int>? lastCorrectAt,
    Expression<int>? resolvedAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (wordId != null) 'word_id': wordId,
      if (active != null) 'active': active,
      if (wrongCount != null) 'wrong_count': wrongCount,
      if (hardCount != null) 'hard_count': hardCount,
      if (consecutiveCorrect != null) 'consecutive_correct': consecutiveCorrect,
      if (lastWrongAt != null) 'last_wrong_at': lastWrongAt,
      if (lastCorrectAt != null) 'last_correct_at': lastCorrectAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WrongWordStatesCompanion copyWith({
    Value<int>? wordId,
    Value<bool>? active,
    Value<int>? wrongCount,
    Value<int>? hardCount,
    Value<int>? consecutiveCorrect,
    Value<int?>? lastWrongAt,
    Value<int?>? lastCorrectAt,
    Value<int?>? resolvedAt,
    Value<int>? updatedAt,
  }) {
    return WrongWordStatesCompanion(
      wordId: wordId ?? this.wordId,
      active: active ?? this.active,
      wrongCount: wrongCount ?? this.wrongCount,
      hardCount: hardCount ?? this.hardCount,
      consecutiveCorrect: consecutiveCorrect ?? this.consecutiveCorrect,
      lastWrongAt: lastWrongAt ?? this.lastWrongAt,
      lastCorrectAt: lastCorrectAt ?? this.lastCorrectAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (wrongCount.present) {
      map['wrong_count'] = Variable<int>(wrongCount.value);
    }
    if (hardCount.present) {
      map['hard_count'] = Variable<int>(hardCount.value);
    }
    if (consecutiveCorrect.present) {
      map['consecutive_correct'] = Variable<int>(consecutiveCorrect.value);
    }
    if (lastWrongAt.present) {
      map['last_wrong_at'] = Variable<int>(lastWrongAt.value);
    }
    if (lastCorrectAt.present) {
      map['last_correct_at'] = Variable<int>(lastCorrectAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<int>(resolvedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WrongWordStatesCompanion(')
          ..write('wordId: $wordId, ')
          ..write('active: $active, ')
          ..write('wrongCount: $wrongCount, ')
          ..write('hardCount: $hardCount, ')
          ..write('consecutiveCorrect: $consecutiveCorrect, ')
          ..write('lastWrongAt: $lastWrongAt, ')
          ..write('lastCorrectAt: $lastCorrectAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ImportBatchesTable extends ImportBatches
    with TableInfo<$ImportBatchesTable, ImportBatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportBatchesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileHashMeta = const VerificationMeta(
    'fileHash',
  );
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
    'file_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ImportMode, String> importMode =
      GeneratedColumn<String>(
        'import_mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ImportMode>($ImportBatchesTable.$converterimportMode);
  static const VerificationMeta _resetLearningProgressMeta =
      const VerificationMeta('resetLearningProgress');
  @override
  late final GeneratedColumn<bool> resetLearningProgress =
      GeneratedColumn<bool>(
        'reset_learning_progress',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("reset_learning_progress" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _totalRowsMeta = const VerificationMeta(
    'totalRows',
  );
  @override
  late final GeneratedColumn<int> totalRows = GeneratedColumn<int>(
    'total_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _validRowsMeta = const VerificationMeta(
    'validRows',
  );
  @override
  late final GeneratedColumn<int> validRows = GeneratedColumn<int>(
    'valid_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _invalidRowsMeta = const VerificationMeta(
    'invalidRows',
  );
  @override
  late final GeneratedColumn<int> invalidRows = GeneratedColumn<int>(
    'invalid_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _duplicateRowsMeta = const VerificationMeta(
    'duplicateRows',
  );
  @override
  late final GeneratedColumn<int> duplicateRows = GeneratedColumn<int>(
    'duplicate_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdWordsMeta = const VerificationMeta(
    'createdWords',
  );
  @override
  late final GeneratedColumn<int> createdWords = GeneratedColumn<int>(
    'created_words',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _existingWordsMeta = const VerificationMeta(
    'existingWords',
  );
  @override
  late final GeneratedColumn<int> existingWords = GeneratedColumn<int>(
    'existing_words',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _queuedInitializationsMeta =
      const VerificationMeta('queuedInitializations');
  @override
  late final GeneratedColumn<int> queuedInitializations = GeneratedColumn<int>(
    'queued_initializations',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ImportBatchStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PENDING'),
  ).withConverter<ImportBatchStatus>($ImportBatchesTable.$converterstatus);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rolledBackAtMeta = const VerificationMeta(
    'rolledBackAt',
  );
  @override
  late final GeneratedColumn<int> rolledBackAt = GeneratedColumn<int>(
    'rolled_back_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    filename,
    fileHash,
    importMode,
    resetLearningProgress,
    totalRows,
    validRows,
    invalidRows,
    duplicateRows,
    createdWords,
    existingWords,
    queuedInitializations,
    status,
    createdAt,
    completedAt,
    rolledBackAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportBatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('file_hash')) {
      context.handle(
        _fileHashMeta,
        fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta),
      );
    }
    if (data.containsKey('reset_learning_progress')) {
      context.handle(
        _resetLearningProgressMeta,
        resetLearningProgress.isAcceptableOrUnknown(
          data['reset_learning_progress']!,
          _resetLearningProgressMeta,
        ),
      );
    }
    if (data.containsKey('total_rows')) {
      context.handle(
        _totalRowsMeta,
        totalRows.isAcceptableOrUnknown(data['total_rows']!, _totalRowsMeta),
      );
    }
    if (data.containsKey('valid_rows')) {
      context.handle(
        _validRowsMeta,
        validRows.isAcceptableOrUnknown(data['valid_rows']!, _validRowsMeta),
      );
    }
    if (data.containsKey('invalid_rows')) {
      context.handle(
        _invalidRowsMeta,
        invalidRows.isAcceptableOrUnknown(
          data['invalid_rows']!,
          _invalidRowsMeta,
        ),
      );
    }
    if (data.containsKey('duplicate_rows')) {
      context.handle(
        _duplicateRowsMeta,
        duplicateRows.isAcceptableOrUnknown(
          data['duplicate_rows']!,
          _duplicateRowsMeta,
        ),
      );
    }
    if (data.containsKey('created_words')) {
      context.handle(
        _createdWordsMeta,
        createdWords.isAcceptableOrUnknown(
          data['created_words']!,
          _createdWordsMeta,
        ),
      );
    }
    if (data.containsKey('existing_words')) {
      context.handle(
        _existingWordsMeta,
        existingWords.isAcceptableOrUnknown(
          data['existing_words']!,
          _existingWordsMeta,
        ),
      );
    }
    if (data.containsKey('queued_initializations')) {
      context.handle(
        _queuedInitializationsMeta,
        queuedInitializations.isAcceptableOrUnknown(
          data['queued_initializations']!,
          _queuedInitializationsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('rolled_back_at')) {
      context.handle(
        _rolledBackAtMeta,
        rolledBackAt.isAcceptableOrUnknown(
          data['rolled_back_at']!,
          _rolledBackAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportBatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportBatchRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      filename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filename'],
      )!,
      fileHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_hash'],
      ),
      importMode: $ImportBatchesTable.$converterimportMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}import_mode'],
        )!,
      ),
      resetLearningProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reset_learning_progress'],
      )!,
      totalRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_rows'],
      )!,
      validRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_rows'],
      )!,
      invalidRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}invalid_rows'],
      )!,
      duplicateRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duplicate_rows'],
      )!,
      createdWords: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_words'],
      )!,
      existingWords: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}existing_words'],
      )!,
      queuedInitializations: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queued_initializations'],
      )!,
      status: $ImportBatchesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at'],
      ),
      rolledBackAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rolled_back_at'],
      ),
    );
  }

  @override
  $ImportBatchesTable createAlias(String alias) {
    return $ImportBatchesTable(attachedDatabase, alias);
  }

  static TypeConverter<ImportMode, String> $converterimportMode =
      const WireEnumConverter<ImportMode>(ImportMode.values);
  static TypeConverter<ImportBatchStatus, String> $converterstatus =
      const WireEnumConverter<ImportBatchStatus>(ImportBatchStatus.values);
}

class ImportBatchRow extends DataClass implements Insertable<ImportBatchRow> {
  final int id;
  final String filename;
  final String? fileHash;
  final ImportMode importMode;
  final bool resetLearningProgress;
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int createdWords;
  final int existingWords;
  final int queuedInitializations;
  final ImportBatchStatus status;
  final int createdAt;
  final int? completedAt;
  final int? rolledBackAt;
  const ImportBatchRow({
    required this.id,
    required this.filename,
    this.fileHash,
    required this.importMode,
    required this.resetLearningProgress,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.createdWords,
    required this.existingWords,
    required this.queuedInitializations,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.rolledBackAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['filename'] = Variable<String>(filename);
    if (!nullToAbsent || fileHash != null) {
      map['file_hash'] = Variable<String>(fileHash);
    }
    {
      map['import_mode'] = Variable<String>(
        $ImportBatchesTable.$converterimportMode.toSql(importMode),
      );
    }
    map['reset_learning_progress'] = Variable<bool>(resetLearningProgress);
    map['total_rows'] = Variable<int>(totalRows);
    map['valid_rows'] = Variable<int>(validRows);
    map['invalid_rows'] = Variable<int>(invalidRows);
    map['duplicate_rows'] = Variable<int>(duplicateRows);
    map['created_words'] = Variable<int>(createdWords);
    map['existing_words'] = Variable<int>(existingWords);
    map['queued_initializations'] = Variable<int>(queuedInitializations);
    {
      map['status'] = Variable<String>(
        $ImportBatchesTable.$converterstatus.toSql(status),
      );
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    if (!nullToAbsent || rolledBackAt != null) {
      map['rolled_back_at'] = Variable<int>(rolledBackAt);
    }
    return map;
  }

  ImportBatchesCompanion toCompanion(bool nullToAbsent) {
    return ImportBatchesCompanion(
      id: Value(id),
      filename: Value(filename),
      fileHash: fileHash == null && nullToAbsent
          ? const Value.absent()
          : Value(fileHash),
      importMode: Value(importMode),
      resetLearningProgress: Value(resetLearningProgress),
      totalRows: Value(totalRows),
      validRows: Value(validRows),
      invalidRows: Value(invalidRows),
      duplicateRows: Value(duplicateRows),
      createdWords: Value(createdWords),
      existingWords: Value(existingWords),
      queuedInitializations: Value(queuedInitializations),
      status: Value(status),
      createdAt: Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      rolledBackAt: rolledBackAt == null && nullToAbsent
          ? const Value.absent()
          : Value(rolledBackAt),
    );
  }

  factory ImportBatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportBatchRow(
      id: serializer.fromJson<int>(json['id']),
      filename: serializer.fromJson<String>(json['filename']),
      fileHash: serializer.fromJson<String?>(json['fileHash']),
      importMode: serializer.fromJson<ImportMode>(json['importMode']),
      resetLearningProgress: serializer.fromJson<bool>(
        json['resetLearningProgress'],
      ),
      totalRows: serializer.fromJson<int>(json['totalRows']),
      validRows: serializer.fromJson<int>(json['validRows']),
      invalidRows: serializer.fromJson<int>(json['invalidRows']),
      duplicateRows: serializer.fromJson<int>(json['duplicateRows']),
      createdWords: serializer.fromJson<int>(json['createdWords']),
      existingWords: serializer.fromJson<int>(json['existingWords']),
      queuedInitializations: serializer.fromJson<int>(
        json['queuedInitializations'],
      ),
      status: serializer.fromJson<ImportBatchStatus>(json['status']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
      rolledBackAt: serializer.fromJson<int?>(json['rolledBackAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'filename': serializer.toJson<String>(filename),
      'fileHash': serializer.toJson<String?>(fileHash),
      'importMode': serializer.toJson<ImportMode>(importMode),
      'resetLearningProgress': serializer.toJson<bool>(resetLearningProgress),
      'totalRows': serializer.toJson<int>(totalRows),
      'validRows': serializer.toJson<int>(validRows),
      'invalidRows': serializer.toJson<int>(invalidRows),
      'duplicateRows': serializer.toJson<int>(duplicateRows),
      'createdWords': serializer.toJson<int>(createdWords),
      'existingWords': serializer.toJson<int>(existingWords),
      'queuedInitializations': serializer.toJson<int>(queuedInitializations),
      'status': serializer.toJson<ImportBatchStatus>(status),
      'createdAt': serializer.toJson<int>(createdAt),
      'completedAt': serializer.toJson<int?>(completedAt),
      'rolledBackAt': serializer.toJson<int?>(rolledBackAt),
    };
  }

  ImportBatchRow copyWith({
    int? id,
    String? filename,
    Value<String?> fileHash = const Value.absent(),
    ImportMode? importMode,
    bool? resetLearningProgress,
    int? totalRows,
    int? validRows,
    int? invalidRows,
    int? duplicateRows,
    int? createdWords,
    int? existingWords,
    int? queuedInitializations,
    ImportBatchStatus? status,
    int? createdAt,
    Value<int?> completedAt = const Value.absent(),
    Value<int?> rolledBackAt = const Value.absent(),
  }) => ImportBatchRow(
    id: id ?? this.id,
    filename: filename ?? this.filename,
    fileHash: fileHash.present ? fileHash.value : this.fileHash,
    importMode: importMode ?? this.importMode,
    resetLearningProgress: resetLearningProgress ?? this.resetLearningProgress,
    totalRows: totalRows ?? this.totalRows,
    validRows: validRows ?? this.validRows,
    invalidRows: invalidRows ?? this.invalidRows,
    duplicateRows: duplicateRows ?? this.duplicateRows,
    createdWords: createdWords ?? this.createdWords,
    existingWords: existingWords ?? this.existingWords,
    queuedInitializations: queuedInitializations ?? this.queuedInitializations,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    rolledBackAt: rolledBackAt.present ? rolledBackAt.value : this.rolledBackAt,
  );
  ImportBatchRow copyWithCompanion(ImportBatchesCompanion data) {
    return ImportBatchRow(
      id: data.id.present ? data.id.value : this.id,
      filename: data.filename.present ? data.filename.value : this.filename,
      fileHash: data.fileHash.present ? data.fileHash.value : this.fileHash,
      importMode: data.importMode.present
          ? data.importMode.value
          : this.importMode,
      resetLearningProgress: data.resetLearningProgress.present
          ? data.resetLearningProgress.value
          : this.resetLearningProgress,
      totalRows: data.totalRows.present ? data.totalRows.value : this.totalRows,
      validRows: data.validRows.present ? data.validRows.value : this.validRows,
      invalidRows: data.invalidRows.present
          ? data.invalidRows.value
          : this.invalidRows,
      duplicateRows: data.duplicateRows.present
          ? data.duplicateRows.value
          : this.duplicateRows,
      createdWords: data.createdWords.present
          ? data.createdWords.value
          : this.createdWords,
      existingWords: data.existingWords.present
          ? data.existingWords.value
          : this.existingWords,
      queuedInitializations: data.queuedInitializations.present
          ? data.queuedInitializations.value
          : this.queuedInitializations,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      rolledBackAt: data.rolledBackAt.present
          ? data.rolledBackAt.value
          : this.rolledBackAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportBatchRow(')
          ..write('id: $id, ')
          ..write('filename: $filename, ')
          ..write('fileHash: $fileHash, ')
          ..write('importMode: $importMode, ')
          ..write('resetLearningProgress: $resetLearningProgress, ')
          ..write('totalRows: $totalRows, ')
          ..write('validRows: $validRows, ')
          ..write('invalidRows: $invalidRows, ')
          ..write('duplicateRows: $duplicateRows, ')
          ..write('createdWords: $createdWords, ')
          ..write('existingWords: $existingWords, ')
          ..write('queuedInitializations: $queuedInitializations, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('rolledBackAt: $rolledBackAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    filename,
    fileHash,
    importMode,
    resetLearningProgress,
    totalRows,
    validRows,
    invalidRows,
    duplicateRows,
    createdWords,
    existingWords,
    queuedInitializations,
    status,
    createdAt,
    completedAt,
    rolledBackAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportBatchRow &&
          other.id == this.id &&
          other.filename == this.filename &&
          other.fileHash == this.fileHash &&
          other.importMode == this.importMode &&
          other.resetLearningProgress == this.resetLearningProgress &&
          other.totalRows == this.totalRows &&
          other.validRows == this.validRows &&
          other.invalidRows == this.invalidRows &&
          other.duplicateRows == this.duplicateRows &&
          other.createdWords == this.createdWords &&
          other.existingWords == this.existingWords &&
          other.queuedInitializations == this.queuedInitializations &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt &&
          other.rolledBackAt == this.rolledBackAt);
}

class ImportBatchesCompanion extends UpdateCompanion<ImportBatchRow> {
  final Value<int> id;
  final Value<String> filename;
  final Value<String?> fileHash;
  final Value<ImportMode> importMode;
  final Value<bool> resetLearningProgress;
  final Value<int> totalRows;
  final Value<int> validRows;
  final Value<int> invalidRows;
  final Value<int> duplicateRows;
  final Value<int> createdWords;
  final Value<int> existingWords;
  final Value<int> queuedInitializations;
  final Value<ImportBatchStatus> status;
  final Value<int> createdAt;
  final Value<int?> completedAt;
  final Value<int?> rolledBackAt;
  const ImportBatchesCompanion({
    this.id = const Value.absent(),
    this.filename = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.importMode = const Value.absent(),
    this.resetLearningProgress = const Value.absent(),
    this.totalRows = const Value.absent(),
    this.validRows = const Value.absent(),
    this.invalidRows = const Value.absent(),
    this.duplicateRows = const Value.absent(),
    this.createdWords = const Value.absent(),
    this.existingWords = const Value.absent(),
    this.queuedInitializations = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rolledBackAt = const Value.absent(),
  });
  ImportBatchesCompanion.insert({
    this.id = const Value.absent(),
    required String filename,
    this.fileHash = const Value.absent(),
    required ImportMode importMode,
    this.resetLearningProgress = const Value.absent(),
    this.totalRows = const Value.absent(),
    this.validRows = const Value.absent(),
    this.invalidRows = const Value.absent(),
    this.duplicateRows = const Value.absent(),
    this.createdWords = const Value.absent(),
    this.existingWords = const Value.absent(),
    this.queuedInitializations = const Value.absent(),
    this.status = const Value.absent(),
    required int createdAt,
    this.completedAt = const Value.absent(),
    this.rolledBackAt = const Value.absent(),
  }) : filename = Value(filename),
       importMode = Value(importMode),
       createdAt = Value(createdAt);
  static Insertable<ImportBatchRow> custom({
    Expression<int>? id,
    Expression<String>? filename,
    Expression<String>? fileHash,
    Expression<String>? importMode,
    Expression<bool>? resetLearningProgress,
    Expression<int>? totalRows,
    Expression<int>? validRows,
    Expression<int>? invalidRows,
    Expression<int>? duplicateRows,
    Expression<int>? createdWords,
    Expression<int>? existingWords,
    Expression<int>? queuedInitializations,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<int>? completedAt,
    Expression<int>? rolledBackAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (filename != null) 'filename': filename,
      if (fileHash != null) 'file_hash': fileHash,
      if (importMode != null) 'import_mode': importMode,
      if (resetLearningProgress != null)
        'reset_learning_progress': resetLearningProgress,
      if (totalRows != null) 'total_rows': totalRows,
      if (validRows != null) 'valid_rows': validRows,
      if (invalidRows != null) 'invalid_rows': invalidRows,
      if (duplicateRows != null) 'duplicate_rows': duplicateRows,
      if (createdWords != null) 'created_words': createdWords,
      if (existingWords != null) 'existing_words': existingWords,
      if (queuedInitializations != null)
        'queued_initializations': queuedInitializations,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (rolledBackAt != null) 'rolled_back_at': rolledBackAt,
    });
  }

  ImportBatchesCompanion copyWith({
    Value<int>? id,
    Value<String>? filename,
    Value<String?>? fileHash,
    Value<ImportMode>? importMode,
    Value<bool>? resetLearningProgress,
    Value<int>? totalRows,
    Value<int>? validRows,
    Value<int>? invalidRows,
    Value<int>? duplicateRows,
    Value<int>? createdWords,
    Value<int>? existingWords,
    Value<int>? queuedInitializations,
    Value<ImportBatchStatus>? status,
    Value<int>? createdAt,
    Value<int?>? completedAt,
    Value<int?>? rolledBackAt,
  }) {
    return ImportBatchesCompanion(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      fileHash: fileHash ?? this.fileHash,
      importMode: importMode ?? this.importMode,
      resetLearningProgress:
          resetLearningProgress ?? this.resetLearningProgress,
      totalRows: totalRows ?? this.totalRows,
      validRows: validRows ?? this.validRows,
      invalidRows: invalidRows ?? this.invalidRows,
      duplicateRows: duplicateRows ?? this.duplicateRows,
      createdWords: createdWords ?? this.createdWords,
      existingWords: existingWords ?? this.existingWords,
      queuedInitializations:
          queuedInitializations ?? this.queuedInitializations,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      rolledBackAt: rolledBackAt ?? this.rolledBackAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (importMode.present) {
      map['import_mode'] = Variable<String>(
        $ImportBatchesTable.$converterimportMode.toSql(importMode.value),
      );
    }
    if (resetLearningProgress.present) {
      map['reset_learning_progress'] = Variable<bool>(
        resetLearningProgress.value,
      );
    }
    if (totalRows.present) {
      map['total_rows'] = Variable<int>(totalRows.value);
    }
    if (validRows.present) {
      map['valid_rows'] = Variable<int>(validRows.value);
    }
    if (invalidRows.present) {
      map['invalid_rows'] = Variable<int>(invalidRows.value);
    }
    if (duplicateRows.present) {
      map['duplicate_rows'] = Variable<int>(duplicateRows.value);
    }
    if (createdWords.present) {
      map['created_words'] = Variable<int>(createdWords.value);
    }
    if (existingWords.present) {
      map['existing_words'] = Variable<int>(existingWords.value);
    }
    if (queuedInitializations.present) {
      map['queued_initializations'] = Variable<int>(
        queuedInitializations.value,
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ImportBatchesTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (rolledBackAt.present) {
      map['rolled_back_at'] = Variable<int>(rolledBackAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportBatchesCompanion(')
          ..write('id: $id, ')
          ..write('filename: $filename, ')
          ..write('fileHash: $fileHash, ')
          ..write('importMode: $importMode, ')
          ..write('resetLearningProgress: $resetLearningProgress, ')
          ..write('totalRows: $totalRows, ')
          ..write('validRows: $validRows, ')
          ..write('invalidRows: $invalidRows, ')
          ..write('duplicateRows: $duplicateRows, ')
          ..write('createdWords: $createdWords, ')
          ..write('existingWords: $existingWords, ')
          ..write('queuedInitializations: $queuedInitializations, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('rolledBackAt: $rolledBackAt')
          ..write(')'))
        .toString();
  }
}

class $ImportRowsTable extends ImportRows
    with TableInfo<$ImportRowsTable, ImportRowRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportRowsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _importBatchIdMeta = const VerificationMeta(
    'importBatchId',
  );
  @override
  late final GeneratedColumn<int> importBatchId = GeneratedColumn<int>(
    'import_batch_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES import_batches (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _rowNumberMeta = const VerificationMeta(
    'rowNumber',
  );
  @override
  late final GeneratedColumn<int> rowNumber = GeneratedColumn<int>(
    'row_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _normalizedTermMeta = const VerificationMeta(
    'normalizedTerm',
  );
  @override
  late final GeneratedColumn<String> normalizedTerm = GeneratedColumn<String>(
    'normalized_term',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<int> wordId = GeneratedColumn<int>(
    'word_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE SET NULL',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ImportRowStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ImportRowStatus>($ImportRowsTable.$converterstatus);
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    importBatchId,
    rowNumber,
    rawJson,
    normalizedTerm,
    wordId,
    status,
    errorCode,
    errorMessage,
    metadataJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportRowRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('import_batch_id')) {
      context.handle(
        _importBatchIdMeta,
        importBatchId.isAcceptableOrUnknown(
          data['import_batch_id']!,
          _importBatchIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_importBatchIdMeta);
    }
    if (data.containsKey('row_number')) {
      context.handle(
        _rowNumberMeta,
        rowNumber.isAcceptableOrUnknown(data['row_number']!, _rowNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_rowNumberMeta);
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    }
    if (data.containsKey('normalized_term')) {
      context.handle(
        _normalizedTermMeta,
        normalizedTerm.isAcceptableOrUnknown(
          data['normalized_term']!,
          _normalizedTermMeta,
        ),
      );
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportRowRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportRowRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      importBatchId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}import_batch_id'],
      )!,
      rowNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_number'],
      )!,
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      ),
      normalizedTerm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_term'],
      ),
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      ),
      status: $ImportRowsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ImportRowsTable createAlias(String alias) {
    return $ImportRowsTable(attachedDatabase, alias);
  }

  static TypeConverter<ImportRowStatus, String> $converterstatus =
      const WireEnumConverter<ImportRowStatus>(ImportRowStatus.values);
}

class ImportRowRow extends DataClass implements Insertable<ImportRowRow> {
  final int id;
  final int importBatchId;
  final int rowNumber;
  final String? rawJson;
  final String? normalizedTerm;
  final int? wordId;
  final ImportRowStatus status;
  final String? errorCode;
  final String? errorMessage;
  final String? metadataJson;
  final int createdAt;
  const ImportRowRow({
    required this.id,
    required this.importBatchId,
    required this.rowNumber,
    this.rawJson,
    this.normalizedTerm,
    this.wordId,
    required this.status,
    this.errorCode,
    this.errorMessage,
    this.metadataJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['import_batch_id'] = Variable<int>(importBatchId);
    map['row_number'] = Variable<int>(rowNumber);
    if (!nullToAbsent || rawJson != null) {
      map['raw_json'] = Variable<String>(rawJson);
    }
    if (!nullToAbsent || normalizedTerm != null) {
      map['normalized_term'] = Variable<String>(normalizedTerm);
    }
    if (!nullToAbsent || wordId != null) {
      map['word_id'] = Variable<int>(wordId);
    }
    {
      map['status'] = Variable<String>(
        $ImportRowsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ImportRowsCompanion toCompanion(bool nullToAbsent) {
    return ImportRowsCompanion(
      id: Value(id),
      importBatchId: Value(importBatchId),
      rowNumber: Value(rowNumber),
      rawJson: rawJson == null && nullToAbsent
          ? const Value.absent()
          : Value(rawJson),
      normalizedTerm: normalizedTerm == null && nullToAbsent
          ? const Value.absent()
          : Value(normalizedTerm),
      wordId: wordId == null && nullToAbsent
          ? const Value.absent()
          : Value(wordId),
      status: Value(status),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
    );
  }

  factory ImportRowRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportRowRow(
      id: serializer.fromJson<int>(json['id']),
      importBatchId: serializer.fromJson<int>(json['importBatchId']),
      rowNumber: serializer.fromJson<int>(json['rowNumber']),
      rawJson: serializer.fromJson<String?>(json['rawJson']),
      normalizedTerm: serializer.fromJson<String?>(json['normalizedTerm']),
      wordId: serializer.fromJson<int?>(json['wordId']),
      status: serializer.fromJson<ImportRowStatus>(json['status']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'importBatchId': serializer.toJson<int>(importBatchId),
      'rowNumber': serializer.toJson<int>(rowNumber),
      'rawJson': serializer.toJson<String?>(rawJson),
      'normalizedTerm': serializer.toJson<String?>(normalizedTerm),
      'wordId': serializer.toJson<int?>(wordId),
      'status': serializer.toJson<ImportRowStatus>(status),
      'errorCode': serializer.toJson<String?>(errorCode),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ImportRowRow copyWith({
    int? id,
    int? importBatchId,
    int? rowNumber,
    Value<String?> rawJson = const Value.absent(),
    Value<String?> normalizedTerm = const Value.absent(),
    Value<int?> wordId = const Value.absent(),
    ImportRowStatus? status,
    Value<String?> errorCode = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    int? createdAt,
  }) => ImportRowRow(
    id: id ?? this.id,
    importBatchId: importBatchId ?? this.importBatchId,
    rowNumber: rowNumber ?? this.rowNumber,
    rawJson: rawJson.present ? rawJson.value : this.rawJson,
    normalizedTerm: normalizedTerm.present
        ? normalizedTerm.value
        : this.normalizedTerm,
    wordId: wordId.present ? wordId.value : this.wordId,
    status: status ?? this.status,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
  );
  ImportRowRow copyWithCompanion(ImportRowsCompanion data) {
    return ImportRowRow(
      id: data.id.present ? data.id.value : this.id,
      importBatchId: data.importBatchId.present
          ? data.importBatchId.value
          : this.importBatchId,
      rowNumber: data.rowNumber.present ? data.rowNumber.value : this.rowNumber,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      normalizedTerm: data.normalizedTerm.present
          ? data.normalizedTerm.value
          : this.normalizedTerm,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      status: data.status.present ? data.status.value : this.status,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportRowRow(')
          ..write('id: $id, ')
          ..write('importBatchId: $importBatchId, ')
          ..write('rowNumber: $rowNumber, ')
          ..write('rawJson: $rawJson, ')
          ..write('normalizedTerm: $normalizedTerm, ')
          ..write('wordId: $wordId, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    importBatchId,
    rowNumber,
    rawJson,
    normalizedTerm,
    wordId,
    status,
    errorCode,
    errorMessage,
    metadataJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportRowRow &&
          other.id == this.id &&
          other.importBatchId == this.importBatchId &&
          other.rowNumber == this.rowNumber &&
          other.rawJson == this.rawJson &&
          other.normalizedTerm == this.normalizedTerm &&
          other.wordId == this.wordId &&
          other.status == this.status &&
          other.errorCode == this.errorCode &&
          other.errorMessage == this.errorMessage &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt);
}

class ImportRowsCompanion extends UpdateCompanion<ImportRowRow> {
  final Value<int> id;
  final Value<int> importBatchId;
  final Value<int> rowNumber;
  final Value<String?> rawJson;
  final Value<String?> normalizedTerm;
  final Value<int?> wordId;
  final Value<ImportRowStatus> status;
  final Value<String?> errorCode;
  final Value<String?> errorMessage;
  final Value<String?> metadataJson;
  final Value<int> createdAt;
  const ImportRowsCompanion({
    this.id = const Value.absent(),
    this.importBatchId = const Value.absent(),
    this.rowNumber = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.normalizedTerm = const Value.absent(),
    this.wordId = const Value.absent(),
    this.status = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ImportRowsCompanion.insert({
    this.id = const Value.absent(),
    required int importBatchId,
    required int rowNumber,
    this.rawJson = const Value.absent(),
    this.normalizedTerm = const Value.absent(),
    this.wordId = const Value.absent(),
    required ImportRowStatus status,
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.metadataJson = const Value.absent(),
    required int createdAt,
  }) : importBatchId = Value(importBatchId),
       rowNumber = Value(rowNumber),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<ImportRowRow> custom({
    Expression<int>? id,
    Expression<int>? importBatchId,
    Expression<int>? rowNumber,
    Expression<String>? rawJson,
    Expression<String>? normalizedTerm,
    Expression<int>? wordId,
    Expression<String>? status,
    Expression<String>? errorCode,
    Expression<String>? errorMessage,
    Expression<String>? metadataJson,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (importBatchId != null) 'import_batch_id': importBatchId,
      if (rowNumber != null) 'row_number': rowNumber,
      if (rawJson != null) 'raw_json': rawJson,
      if (normalizedTerm != null) 'normalized_term': normalizedTerm,
      if (wordId != null) 'word_id': wordId,
      if (status != null) 'status': status,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ImportRowsCompanion copyWith({
    Value<int>? id,
    Value<int>? importBatchId,
    Value<int>? rowNumber,
    Value<String?>? rawJson,
    Value<String?>? normalizedTerm,
    Value<int?>? wordId,
    Value<ImportRowStatus>? status,
    Value<String?>? errorCode,
    Value<String?>? errorMessage,
    Value<String?>? metadataJson,
    Value<int>? createdAt,
  }) {
    return ImportRowsCompanion(
      id: id ?? this.id,
      importBatchId: importBatchId ?? this.importBatchId,
      rowNumber: rowNumber ?? this.rowNumber,
      rawJson: rawJson ?? this.rawJson,
      normalizedTerm: normalizedTerm ?? this.normalizedTerm,
      wordId: wordId ?? this.wordId,
      status: status ?? this.status,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (importBatchId.present) {
      map['import_batch_id'] = Variable<int>(importBatchId.value);
    }
    if (rowNumber.present) {
      map['row_number'] = Variable<int>(rowNumber.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (normalizedTerm.present) {
      map['normalized_term'] = Variable<String>(normalizedTerm.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ImportRowsTable.$converterstatus.toSql(status.value),
      );
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportRowsCompanion(')
          ..write('id: $id, ')
          ..write('importBatchId: $importBatchId, ')
          ..write('rowNumber: $rowNumber, ')
          ..write('rawJson: $rawJson, ')
          ..write('normalizedTerm: $normalizedTerm, ')
          ..write('wordId: $wordId, ')
          ..write('status: $status, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $InitializationJobsTable extends InitializationJobs
    with TableInfo<$InitializationJobsTable, InitializationJobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InitializationJobsTable(this.attachedDatabase, [this._alias]);
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<JobTaskType, String> taskType =
      GeneratedColumn<String>(
        'task_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('INITIALIZE'),
      ).withConverter<JobTaskType>($InitializationJobsTable.$convertertaskType);
  @override
  late final GeneratedColumnWithTypeConverter<InitializationMode, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<InitializationMode>(
        $InitializationJobsTable.$convertermode,
      );
  static const VerificationMeta _requestedFieldsJsonMeta =
      const VerificationMeta('requestedFieldsJson');
  @override
  late final GeneratedColumn<String> requestedFieldsJson =
      GeneratedColumn<String>(
        'requested_fields_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _requestedProvidersJsonMeta =
      const VerificationMeta('requestedProvidersJson');
  @override
  late final GeneratedColumn<String> requestedProvidersJson =
      GeneratedColumn<String>(
        'requested_providers_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<ProviderStrategy, String>
  providerStrategy =
      GeneratedColumn<String>(
        'provider_strategy',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('PARALLEL_MERGE'),
      ).withConverter<ProviderStrategy>(
        $InitializationJobsTable.$converterproviderStrategy,
      );
  @override
  late final GeneratedColumnWithTypeConverter<InitializationStatus, String>
  status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('QUEUED'),
      ).withConverter<InitializationStatus>(
        $InitializationJobsTable.$converterstatus,
      );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _maxAttemptsMeta = const VerificationMeta(
    'maxAttempts',
  );
  @override
  late final GeneratedColumn<int> maxAttempts = GeneratedColumn<int>(
    'max_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(5),
  );
  static const VerificationMeta _availableAtMeta = const VerificationMeta(
    'availableAt',
  );
  @override
  late final GeneratedColumn<int> availableAt = GeneratedColumn<int>(
    'available_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lockedAtMeta = const VerificationMeta(
    'lockedAt',
  );
  @override
  late final GeneratedColumn<int> lockedAt = GeneratedColumn<int>(
    'locked_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lockedByMeta = const VerificationMeta(
    'lockedBy',
  );
  @override
  late final GeneratedColumn<String> lockedBy = GeneratedColumn<String>(
    'locked_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    wordId,
    taskType,
    mode,
    requestedFieldsJson,
    requestedProvidersJson,
    providerStrategy,
    status,
    priority,
    attemptCount,
    maxAttempts,
    availableAt,
    lockedAt,
    lockedBy,
    lastError,
    lastErrorCode,
    createdAt,
    updatedAt,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'initialization_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<InitializationJobRow> instance, {
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
    if (data.containsKey('requested_fields_json')) {
      context.handle(
        _requestedFieldsJsonMeta,
        requestedFieldsJson.isAcceptableOrUnknown(
          data['requested_fields_json']!,
          _requestedFieldsJsonMeta,
        ),
      );
    }
    if (data.containsKey('requested_providers_json')) {
      context.handle(
        _requestedProvidersJsonMeta,
        requestedProvidersJson.isAcceptableOrUnknown(
          data['requested_providers_json']!,
          _requestedProvidersJsonMeta,
        ),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('max_attempts')) {
      context.handle(
        _maxAttemptsMeta,
        maxAttempts.isAcceptableOrUnknown(
          data['max_attempts']!,
          _maxAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('available_at')) {
      context.handle(
        _availableAtMeta,
        availableAt.isAcceptableOrUnknown(
          data['available_at']!,
          _availableAtMeta,
        ),
      );
    }
    if (data.containsKey('locked_at')) {
      context.handle(
        _lockedAtMeta,
        lockedAt.isAcceptableOrUnknown(data['locked_at']!, _lockedAtMeta),
      );
    }
    if (data.containsKey('locked_by')) {
      context.handle(
        _lockedByMeta,
        lockedBy.isAcceptableOrUnknown(data['locked_by']!, _lockedByMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InitializationJobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InitializationJobRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      taskType: $InitializationJobsTable.$convertertaskType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}task_type'],
        )!,
      ),
      mode: $InitializationJobsTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        )!,
      ),
      requestedFieldsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requested_fields_json'],
      ),
      requestedProvidersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requested_providers_json'],
      ),
      providerStrategy: $InitializationJobsTable.$converterproviderStrategy
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}provider_strategy'],
            )!,
          ),
      status: $InitializationJobsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      maxAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_attempts'],
      )!,
      availableAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}available_at'],
      ),
      lockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}locked_at'],
      ),
      lockedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locked_by'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $InitializationJobsTable createAlias(String alias) {
    return $InitializationJobsTable(attachedDatabase, alias);
  }

  static TypeConverter<JobTaskType, String> $convertertaskType =
      const WireEnumConverter<JobTaskType>(JobTaskType.values);
  static TypeConverter<InitializationMode, String> $convertermode =
      const WireEnumConverter<InitializationMode>(InitializationMode.values);
  static TypeConverter<ProviderStrategy, String> $converterproviderStrategy =
      const WireEnumConverter<ProviderStrategy>(ProviderStrategy.values);
  static TypeConverter<InitializationStatus, String> $converterstatus =
      const WireEnumConverter<InitializationStatus>(
        InitializationStatus.values,
      );
}

class InitializationJobRow extends DataClass
    implements Insertable<InitializationJobRow> {
  final int id;
  final int wordId;
  final JobTaskType taskType;
  final InitializationMode mode;
  final String? requestedFieldsJson;
  final String? requestedProvidersJson;
  final ProviderStrategy providerStrategy;
  final InitializationStatus status;
  final int priority;
  final int attemptCount;
  final int maxAttempts;
  final int? availableAt;
  final int? lockedAt;
  final String? lockedBy;
  final String? lastError;
  final String? lastErrorCode;
  final int createdAt;
  final int updatedAt;
  final int? completedAt;
  const InitializationJobRow({
    required this.id,
    required this.wordId,
    required this.taskType,
    required this.mode,
    this.requestedFieldsJson,
    this.requestedProvidersJson,
    required this.providerStrategy,
    required this.status,
    required this.priority,
    required this.attemptCount,
    required this.maxAttempts,
    this.availableAt,
    this.lockedAt,
    this.lockedBy,
    this.lastError,
    this.lastErrorCode,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['word_id'] = Variable<int>(wordId);
    {
      map['task_type'] = Variable<String>(
        $InitializationJobsTable.$convertertaskType.toSql(taskType),
      );
    }
    {
      map['mode'] = Variable<String>(
        $InitializationJobsTable.$convertermode.toSql(mode),
      );
    }
    if (!nullToAbsent || requestedFieldsJson != null) {
      map['requested_fields_json'] = Variable<String>(requestedFieldsJson);
    }
    if (!nullToAbsent || requestedProvidersJson != null) {
      map['requested_providers_json'] = Variable<String>(
        requestedProvidersJson,
      );
    }
    {
      map['provider_strategy'] = Variable<String>(
        $InitializationJobsTable.$converterproviderStrategy.toSql(
          providerStrategy,
        ),
      );
    }
    {
      map['status'] = Variable<String>(
        $InitializationJobsTable.$converterstatus.toSql(status),
      );
    }
    map['priority'] = Variable<int>(priority);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['max_attempts'] = Variable<int>(maxAttempts);
    if (!nullToAbsent || availableAt != null) {
      map['available_at'] = Variable<int>(availableAt);
    }
    if (!nullToAbsent || lockedAt != null) {
      map['locked_at'] = Variable<int>(lockedAt);
    }
    if (!nullToAbsent || lockedBy != null) {
      map['locked_by'] = Variable<String>(lockedBy);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    return map;
  }

  InitializationJobsCompanion toCompanion(bool nullToAbsent) {
    return InitializationJobsCompanion(
      id: Value(id),
      wordId: Value(wordId),
      taskType: Value(taskType),
      mode: Value(mode),
      requestedFieldsJson: requestedFieldsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(requestedFieldsJson),
      requestedProvidersJson: requestedProvidersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(requestedProvidersJson),
      providerStrategy: Value(providerStrategy),
      status: Value(status),
      priority: Value(priority),
      attemptCount: Value(attemptCount),
      maxAttempts: Value(maxAttempts),
      availableAt: availableAt == null && nullToAbsent
          ? const Value.absent()
          : Value(availableAt),
      lockedAt: lockedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedAt),
      lockedBy: lockedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedBy),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory InitializationJobRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InitializationJobRow(
      id: serializer.fromJson<int>(json['id']),
      wordId: serializer.fromJson<int>(json['wordId']),
      taskType: serializer.fromJson<JobTaskType>(json['taskType']),
      mode: serializer.fromJson<InitializationMode>(json['mode']),
      requestedFieldsJson: serializer.fromJson<String?>(
        json['requestedFieldsJson'],
      ),
      requestedProvidersJson: serializer.fromJson<String?>(
        json['requestedProvidersJson'],
      ),
      providerStrategy: serializer.fromJson<ProviderStrategy>(
        json['providerStrategy'],
      ),
      status: serializer.fromJson<InitializationStatus>(json['status']),
      priority: serializer.fromJson<int>(json['priority']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      maxAttempts: serializer.fromJson<int>(json['maxAttempts']),
      availableAt: serializer.fromJson<int?>(json['availableAt']),
      lockedAt: serializer.fromJson<int?>(json['lockedAt']),
      lockedBy: serializer.fromJson<String?>(json['lockedBy']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'wordId': serializer.toJson<int>(wordId),
      'taskType': serializer.toJson<JobTaskType>(taskType),
      'mode': serializer.toJson<InitializationMode>(mode),
      'requestedFieldsJson': serializer.toJson<String?>(requestedFieldsJson),
      'requestedProvidersJson': serializer.toJson<String?>(
        requestedProvidersJson,
      ),
      'providerStrategy': serializer.toJson<ProviderStrategy>(providerStrategy),
      'status': serializer.toJson<InitializationStatus>(status),
      'priority': serializer.toJson<int>(priority),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'maxAttempts': serializer.toJson<int>(maxAttempts),
      'availableAt': serializer.toJson<int?>(availableAt),
      'lockedAt': serializer.toJson<int?>(lockedAt),
      'lockedBy': serializer.toJson<String?>(lockedBy),
      'lastError': serializer.toJson<String?>(lastError),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'completedAt': serializer.toJson<int?>(completedAt),
    };
  }

  InitializationJobRow copyWith({
    int? id,
    int? wordId,
    JobTaskType? taskType,
    InitializationMode? mode,
    Value<String?> requestedFieldsJson = const Value.absent(),
    Value<String?> requestedProvidersJson = const Value.absent(),
    ProviderStrategy? providerStrategy,
    InitializationStatus? status,
    int? priority,
    int? attemptCount,
    int? maxAttempts,
    Value<int?> availableAt = const Value.absent(),
    Value<int?> lockedAt = const Value.absent(),
    Value<String?> lockedBy = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> completedAt = const Value.absent(),
  }) => InitializationJobRow(
    id: id ?? this.id,
    wordId: wordId ?? this.wordId,
    taskType: taskType ?? this.taskType,
    mode: mode ?? this.mode,
    requestedFieldsJson: requestedFieldsJson.present
        ? requestedFieldsJson.value
        : this.requestedFieldsJson,
    requestedProvidersJson: requestedProvidersJson.present
        ? requestedProvidersJson.value
        : this.requestedProvidersJson,
    providerStrategy: providerStrategy ?? this.providerStrategy,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    attemptCount: attemptCount ?? this.attemptCount,
    maxAttempts: maxAttempts ?? this.maxAttempts,
    availableAt: availableAt.present ? availableAt.value : this.availableAt,
    lockedAt: lockedAt.present ? lockedAt.value : this.lockedAt,
    lockedBy: lockedBy.present ? lockedBy.value : this.lockedBy,
    lastError: lastError.present ? lastError.value : this.lastError,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  InitializationJobRow copyWithCompanion(InitializationJobsCompanion data) {
    return InitializationJobRow(
      id: data.id.present ? data.id.value : this.id,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      taskType: data.taskType.present ? data.taskType.value : this.taskType,
      mode: data.mode.present ? data.mode.value : this.mode,
      requestedFieldsJson: data.requestedFieldsJson.present
          ? data.requestedFieldsJson.value
          : this.requestedFieldsJson,
      requestedProvidersJson: data.requestedProvidersJson.present
          ? data.requestedProvidersJson.value
          : this.requestedProvidersJson,
      providerStrategy: data.providerStrategy.present
          ? data.providerStrategy.value
          : this.providerStrategy,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      maxAttempts: data.maxAttempts.present
          ? data.maxAttempts.value
          : this.maxAttempts,
      availableAt: data.availableAt.present
          ? data.availableAt.value
          : this.availableAt,
      lockedAt: data.lockedAt.present ? data.lockedAt.value : this.lockedAt,
      lockedBy: data.lockedBy.present ? data.lockedBy.value : this.lockedBy,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InitializationJobRow(')
          ..write('id: $id, ')
          ..write('wordId: $wordId, ')
          ..write('taskType: $taskType, ')
          ..write('mode: $mode, ')
          ..write('requestedFieldsJson: $requestedFieldsJson, ')
          ..write('requestedProvidersJson: $requestedProvidersJson, ')
          ..write('providerStrategy: $providerStrategy, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('maxAttempts: $maxAttempts, ')
          ..write('availableAt: $availableAt, ')
          ..write('lockedAt: $lockedAt, ')
          ..write('lockedBy: $lockedBy, ')
          ..write('lastError: $lastError, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    wordId,
    taskType,
    mode,
    requestedFieldsJson,
    requestedProvidersJson,
    providerStrategy,
    status,
    priority,
    attemptCount,
    maxAttempts,
    availableAt,
    lockedAt,
    lockedBy,
    lastError,
    lastErrorCode,
    createdAt,
    updatedAt,
    completedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InitializationJobRow &&
          other.id == this.id &&
          other.wordId == this.wordId &&
          other.taskType == this.taskType &&
          other.mode == this.mode &&
          other.requestedFieldsJson == this.requestedFieldsJson &&
          other.requestedProvidersJson == this.requestedProvidersJson &&
          other.providerStrategy == this.providerStrategy &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.attemptCount == this.attemptCount &&
          other.maxAttempts == this.maxAttempts &&
          other.availableAt == this.availableAt &&
          other.lockedAt == this.lockedAt &&
          other.lockedBy == this.lockedBy &&
          other.lastError == this.lastError &&
          other.lastErrorCode == this.lastErrorCode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.completedAt == this.completedAt);
}

class InitializationJobsCompanion
    extends UpdateCompanion<InitializationJobRow> {
  final Value<int> id;
  final Value<int> wordId;
  final Value<JobTaskType> taskType;
  final Value<InitializationMode> mode;
  final Value<String?> requestedFieldsJson;
  final Value<String?> requestedProvidersJson;
  final Value<ProviderStrategy> providerStrategy;
  final Value<InitializationStatus> status;
  final Value<int> priority;
  final Value<int> attemptCount;
  final Value<int> maxAttempts;
  final Value<int?> availableAt;
  final Value<int?> lockedAt;
  final Value<String?> lockedBy;
  final Value<String?> lastError;
  final Value<String?> lastErrorCode;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> completedAt;
  const InitializationJobsCompanion({
    this.id = const Value.absent(),
    this.wordId = const Value.absent(),
    this.taskType = const Value.absent(),
    this.mode = const Value.absent(),
    this.requestedFieldsJson = const Value.absent(),
    this.requestedProvidersJson = const Value.absent(),
    this.providerStrategy = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.maxAttempts = const Value.absent(),
    this.availableAt = const Value.absent(),
    this.lockedAt = const Value.absent(),
    this.lockedBy = const Value.absent(),
    this.lastError = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
  });
  InitializationJobsCompanion.insert({
    this.id = const Value.absent(),
    required int wordId,
    this.taskType = const Value.absent(),
    required InitializationMode mode,
    this.requestedFieldsJson = const Value.absent(),
    this.requestedProvidersJson = const Value.absent(),
    this.providerStrategy = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.maxAttempts = const Value.absent(),
    this.availableAt = const Value.absent(),
    this.lockedAt = const Value.absent(),
    this.lockedBy = const Value.absent(),
    this.lastError = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.completedAt = const Value.absent(),
  }) : wordId = Value(wordId),
       mode = Value(mode),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<InitializationJobRow> custom({
    Expression<int>? id,
    Expression<int>? wordId,
    Expression<String>? taskType,
    Expression<String>? mode,
    Expression<String>? requestedFieldsJson,
    Expression<String>? requestedProvidersJson,
    Expression<String>? providerStrategy,
    Expression<String>? status,
    Expression<int>? priority,
    Expression<int>? attemptCount,
    Expression<int>? maxAttempts,
    Expression<int>? availableAt,
    Expression<int>? lockedAt,
    Expression<String>? lockedBy,
    Expression<String>? lastError,
    Expression<String>? lastErrorCode,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? completedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (wordId != null) 'word_id': wordId,
      if (taskType != null) 'task_type': taskType,
      if (mode != null) 'mode': mode,
      if (requestedFieldsJson != null)
        'requested_fields_json': requestedFieldsJson,
      if (requestedProvidersJson != null)
        'requested_providers_json': requestedProvidersJson,
      if (providerStrategy != null) 'provider_strategy': providerStrategy,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (maxAttempts != null) 'max_attempts': maxAttempts,
      if (availableAt != null) 'available_at': availableAt,
      if (lockedAt != null) 'locked_at': lockedAt,
      if (lockedBy != null) 'locked_by': lockedBy,
      if (lastError != null) 'last_error': lastError,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (completedAt != null) 'completed_at': completedAt,
    });
  }

  InitializationJobsCompanion copyWith({
    Value<int>? id,
    Value<int>? wordId,
    Value<JobTaskType>? taskType,
    Value<InitializationMode>? mode,
    Value<String?>? requestedFieldsJson,
    Value<String?>? requestedProvidersJson,
    Value<ProviderStrategy>? providerStrategy,
    Value<InitializationStatus>? status,
    Value<int>? priority,
    Value<int>? attemptCount,
    Value<int>? maxAttempts,
    Value<int?>? availableAt,
    Value<int?>? lockedAt,
    Value<String?>? lockedBy,
    Value<String?>? lastError,
    Value<String?>? lastErrorCode,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? completedAt,
  }) {
    return InitializationJobsCompanion(
      id: id ?? this.id,
      wordId: wordId ?? this.wordId,
      taskType: taskType ?? this.taskType,
      mode: mode ?? this.mode,
      requestedFieldsJson: requestedFieldsJson ?? this.requestedFieldsJson,
      requestedProvidersJson:
          requestedProvidersJson ?? this.requestedProvidersJson,
      providerStrategy: providerStrategy ?? this.providerStrategy,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      attemptCount: attemptCount ?? this.attemptCount,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      availableAt: availableAt ?? this.availableAt,
      lockedAt: lockedAt ?? this.lockedAt,
      lockedBy: lockedBy ?? this.lockedBy,
      lastError: lastError ?? this.lastError,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
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
    if (taskType.present) {
      map['task_type'] = Variable<String>(
        $InitializationJobsTable.$convertertaskType.toSql(taskType.value),
      );
    }
    if (mode.present) {
      map['mode'] = Variable<String>(
        $InitializationJobsTable.$convertermode.toSql(mode.value),
      );
    }
    if (requestedFieldsJson.present) {
      map['requested_fields_json'] = Variable<String>(
        requestedFieldsJson.value,
      );
    }
    if (requestedProvidersJson.present) {
      map['requested_providers_json'] = Variable<String>(
        requestedProvidersJson.value,
      );
    }
    if (providerStrategy.present) {
      map['provider_strategy'] = Variable<String>(
        $InitializationJobsTable.$converterproviderStrategy.toSql(
          providerStrategy.value,
        ),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $InitializationJobsTable.$converterstatus.toSql(status.value),
      );
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (maxAttempts.present) {
      map['max_attempts'] = Variable<int>(maxAttempts.value);
    }
    if (availableAt.present) {
      map['available_at'] = Variable<int>(availableAt.value);
    }
    if (lockedAt.present) {
      map['locked_at'] = Variable<int>(lockedAt.value);
    }
    if (lockedBy.present) {
      map['locked_by'] = Variable<String>(lockedBy.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InitializationJobsCompanion(')
          ..write('id: $id, ')
          ..write('wordId: $wordId, ')
          ..write('taskType: $taskType, ')
          ..write('mode: $mode, ')
          ..write('requestedFieldsJson: $requestedFieldsJson, ')
          ..write('requestedProvidersJson: $requestedProvidersJson, ')
          ..write('providerStrategy: $providerStrategy, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('maxAttempts: $maxAttempts, ')
          ..write('availableAt: $availableAt, ')
          ..write('lockedAt: $lockedAt, ')
          ..write('lockedBy: $lockedBy, ')
          ..write('lastError: $lastError, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }
}

class $ProviderAttemptsTable extends ProviderAttempts
    with TableInfo<$ProviderAttemptsTable, ProviderAttemptRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProviderAttemptsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _initializationJobIdMeta =
      const VerificationMeta('initializationJobId');
  @override
  late final GeneratedColumn<int> initializationJobId = GeneratedColumn<int>(
    'initialization_job_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES initialization_jobs (id) ON DELETE CASCADE',
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES words (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ProviderAttemptStatus, String>
  status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ProviderAttemptStatus>(
        $ProviderAttemptsTable.$converterstatus,
      );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fieldsReturnedJsonMeta =
      const VerificationMeta('fieldsReturnedJson');
  @override
  late final GeneratedColumn<String> fieldsReturnedJson =
      GeneratedColumn<String>(
        'fields_returned_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    initializationJobId,
    wordId,
    providerId,
    status,
    durationMs,
    fieldsReturnedJson,
    errorCode,
    errorMessage,
    metadataJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'provider_attempts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProviderAttemptRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('initialization_job_id')) {
      context.handle(
        _initializationJobIdMeta,
        initializationJobId.isAcceptableOrUnknown(
          data['initialization_job_id']!,
          _initializationJobIdMeta,
        ),
      );
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_providerIdMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('fields_returned_json')) {
      context.handle(
        _fieldsReturnedJsonMeta,
        fieldsReturnedJson.isAcceptableOrUnknown(
          data['fields_returned_json']!,
          _fieldsReturnedJsonMeta,
        ),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProviderAttemptRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProviderAttemptRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      initializationJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}initialization_job_id'],
      ),
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_id'],
      )!,
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      )!,
      status: $ProviderAttemptsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      fieldsReturnedJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fields_returned_json'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ProviderAttemptsTable createAlias(String alias) {
    return $ProviderAttemptsTable(attachedDatabase, alias);
  }

  static TypeConverter<ProviderAttemptStatus, String> $converterstatus =
      const WireEnumConverter<ProviderAttemptStatus>(
        ProviderAttemptStatus.values,
      );
}

class ProviderAttemptRow extends DataClass
    implements Insertable<ProviderAttemptRow> {
  final int id;
  final int? initializationJobId;
  final int wordId;
  final String providerId;
  final ProviderAttemptStatus status;
  final int? durationMs;
  final String? fieldsReturnedJson;
  final String? errorCode;
  final String? errorMessage;
  final String? metadataJson;
  final int createdAt;
  const ProviderAttemptRow({
    required this.id,
    this.initializationJobId,
    required this.wordId,
    required this.providerId,
    required this.status,
    this.durationMs,
    this.fieldsReturnedJson,
    this.errorCode,
    this.errorMessage,
    this.metadataJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || initializationJobId != null) {
      map['initialization_job_id'] = Variable<int>(initializationJobId);
    }
    map['word_id'] = Variable<int>(wordId);
    map['provider_id'] = Variable<String>(providerId);
    {
      map['status'] = Variable<String>(
        $ProviderAttemptsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || fieldsReturnedJson != null) {
      map['fields_returned_json'] = Variable<String>(fieldsReturnedJson);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ProviderAttemptsCompanion toCompanion(bool nullToAbsent) {
    return ProviderAttemptsCompanion(
      id: Value(id),
      initializationJobId: initializationJobId == null && nullToAbsent
          ? const Value.absent()
          : Value(initializationJobId),
      wordId: Value(wordId),
      providerId: Value(providerId),
      status: Value(status),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      fieldsReturnedJson: fieldsReturnedJson == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldsReturnedJson),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
    );
  }

  factory ProviderAttemptRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProviderAttemptRow(
      id: serializer.fromJson<int>(json['id']),
      initializationJobId: serializer.fromJson<int?>(
        json['initializationJobId'],
      ),
      wordId: serializer.fromJson<int>(json['wordId']),
      providerId: serializer.fromJson<String>(json['providerId']),
      status: serializer.fromJson<ProviderAttemptStatus>(json['status']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      fieldsReturnedJson: serializer.fromJson<String?>(
        json['fieldsReturnedJson'],
      ),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'initializationJobId': serializer.toJson<int?>(initializationJobId),
      'wordId': serializer.toJson<int>(wordId),
      'providerId': serializer.toJson<String>(providerId),
      'status': serializer.toJson<ProviderAttemptStatus>(status),
      'durationMs': serializer.toJson<int?>(durationMs),
      'fieldsReturnedJson': serializer.toJson<String?>(fieldsReturnedJson),
      'errorCode': serializer.toJson<String?>(errorCode),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ProviderAttemptRow copyWith({
    int? id,
    Value<int?> initializationJobId = const Value.absent(),
    int? wordId,
    String? providerId,
    ProviderAttemptStatus? status,
    Value<int?> durationMs = const Value.absent(),
    Value<String?> fieldsReturnedJson = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    int? createdAt,
  }) => ProviderAttemptRow(
    id: id ?? this.id,
    initializationJobId: initializationJobId.present
        ? initializationJobId.value
        : this.initializationJobId,
    wordId: wordId ?? this.wordId,
    providerId: providerId ?? this.providerId,
    status: status ?? this.status,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    fieldsReturnedJson: fieldsReturnedJson.present
        ? fieldsReturnedJson.value
        : this.fieldsReturnedJson,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
  );
  ProviderAttemptRow copyWithCompanion(ProviderAttemptsCompanion data) {
    return ProviderAttemptRow(
      id: data.id.present ? data.id.value : this.id,
      initializationJobId: data.initializationJobId.present
          ? data.initializationJobId.value
          : this.initializationJobId,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      status: data.status.present ? data.status.value : this.status,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      fieldsReturnedJson: data.fieldsReturnedJson.present
          ? data.fieldsReturnedJson.value
          : this.fieldsReturnedJson,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProviderAttemptRow(')
          ..write('id: $id, ')
          ..write('initializationJobId: $initializationJobId, ')
          ..write('wordId: $wordId, ')
          ..write('providerId: $providerId, ')
          ..write('status: $status, ')
          ..write('durationMs: $durationMs, ')
          ..write('fieldsReturnedJson: $fieldsReturnedJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    initializationJobId,
    wordId,
    providerId,
    status,
    durationMs,
    fieldsReturnedJson,
    errorCode,
    errorMessage,
    metadataJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProviderAttemptRow &&
          other.id == this.id &&
          other.initializationJobId == this.initializationJobId &&
          other.wordId == this.wordId &&
          other.providerId == this.providerId &&
          other.status == this.status &&
          other.durationMs == this.durationMs &&
          other.fieldsReturnedJson == this.fieldsReturnedJson &&
          other.errorCode == this.errorCode &&
          other.errorMessage == this.errorMessage &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt);
}

class ProviderAttemptsCompanion extends UpdateCompanion<ProviderAttemptRow> {
  final Value<int> id;
  final Value<int?> initializationJobId;
  final Value<int> wordId;
  final Value<String> providerId;
  final Value<ProviderAttemptStatus> status;
  final Value<int?> durationMs;
  final Value<String?> fieldsReturnedJson;
  final Value<String?> errorCode;
  final Value<String?> errorMessage;
  final Value<String?> metadataJson;
  final Value<int> createdAt;
  const ProviderAttemptsCompanion({
    this.id = const Value.absent(),
    this.initializationJobId = const Value.absent(),
    this.wordId = const Value.absent(),
    this.providerId = const Value.absent(),
    this.status = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.fieldsReturnedJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ProviderAttemptsCompanion.insert({
    this.id = const Value.absent(),
    this.initializationJobId = const Value.absent(),
    required int wordId,
    required String providerId,
    required ProviderAttemptStatus status,
    this.durationMs = const Value.absent(),
    this.fieldsReturnedJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.metadataJson = const Value.absent(),
    required int createdAt,
  }) : wordId = Value(wordId),
       providerId = Value(providerId),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<ProviderAttemptRow> custom({
    Expression<int>? id,
    Expression<int>? initializationJobId,
    Expression<int>? wordId,
    Expression<String>? providerId,
    Expression<String>? status,
    Expression<int>? durationMs,
    Expression<String>? fieldsReturnedJson,
    Expression<String>? errorCode,
    Expression<String>? errorMessage,
    Expression<String>? metadataJson,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (initializationJobId != null)
        'initialization_job_id': initializationJobId,
      if (wordId != null) 'word_id': wordId,
      if (providerId != null) 'provider_id': providerId,
      if (status != null) 'status': status,
      if (durationMs != null) 'duration_ms': durationMs,
      if (fieldsReturnedJson != null)
        'fields_returned_json': fieldsReturnedJson,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ProviderAttemptsCompanion copyWith({
    Value<int>? id,
    Value<int?>? initializationJobId,
    Value<int>? wordId,
    Value<String>? providerId,
    Value<ProviderAttemptStatus>? status,
    Value<int?>? durationMs,
    Value<String?>? fieldsReturnedJson,
    Value<String?>? errorCode,
    Value<String?>? errorMessage,
    Value<String?>? metadataJson,
    Value<int>? createdAt,
  }) {
    return ProviderAttemptsCompanion(
      id: id ?? this.id,
      initializationJobId: initializationJobId ?? this.initializationJobId,
      wordId: wordId ?? this.wordId,
      providerId: providerId ?? this.providerId,
      status: status ?? this.status,
      durationMs: durationMs ?? this.durationMs,
      fieldsReturnedJson: fieldsReturnedJson ?? this.fieldsReturnedJson,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (initializationJobId.present) {
      map['initialization_job_id'] = Variable<int>(initializationJobId.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<int>(wordId.value);
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ProviderAttemptsTable.$converterstatus.toSql(status.value),
      );
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (fieldsReturnedJson.present) {
      map['fields_returned_json'] = Variable<String>(fieldsReturnedJson.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProviderAttemptsCompanion(')
          ..write('id: $id, ')
          ..write('initializationJobId: $initializationJobId, ')
          ..write('wordId: $wordId, ')
          ..write('providerId: $providerId, ')
          ..write('status: $status, ')
          ..write('durationMs: $durationMs, ')
          ..write('fieldsReturnedJson: $fieldsReturnedJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DailyAiSuggestionsTable extends DailyAiSuggestions
    with TableInfo<$DailyAiSuggestionsTable, DailyAiSuggestionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyAiSuggestionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateKeyMeta = const VerificationMeta(
    'dateKey',
  );
  @override
  late final GeneratedColumn<String> dateKey = GeneratedColumn<String>(
    'date_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDateKeyMeta = const VerificationMeta(
    'sourceDateKey',
  );
  @override
  late final GeneratedColumn<String> sourceDateKey = GeneratedColumn<String>(
    'source_date_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityScoreMeta = const VerificationMeta(
    'qualityScore',
  );
  @override
  late final GeneratedColumn<int> qualityScore = GeneratedColumn<int>(
    'quality_score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metricsJsonMeta = const VerificationMeta(
    'metricsJson',
  );
  @override
  late final GeneratedColumn<String> metricsJson = GeneratedColumn<String>(
    'metrics_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _contentJsonMeta = const VerificationMeta(
    'contentJson',
  );
  @override
  late final GeneratedColumn<String> contentJson = GeneratedColumn<String>(
    'content_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _recommendedItemsJsonMeta =
      const VerificationMeta('recommendedItemsJson');
  @override
  late final GeneratedColumn<String> recommendedItemsJson =
      GeneratedColumn<String>(
        'recommended_items_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  @override
  late final GeneratedColumnWithTypeConverter<SuggestionGenerator, String>
  generator =
      GeneratedColumn<String>(
        'generator',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('RULE_BASED'),
      ).withConverter<SuggestionGenerator>(
        $DailyAiSuggestionsTable.$convertergenerator,
      );
  static const VerificationMeta _providerIdMeta = const VerificationMeta(
    'providerId',
  );
  @override
  late final GeneratedColumn<String> providerId = GeneratedColumn<String>(
    'provider_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _generationWarningMeta = const VerificationMeta(
    'generationWarning',
  );
  @override
  late final GeneratedColumn<String> generationWarning =
      GeneratedColumn<String>(
        'generation_warning',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _generatedAtMeta = const VerificationMeta(
    'generatedAt',
  );
  @override
  late final GeneratedColumn<int> generatedAt = GeneratedColumn<int>(
    'generated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    dateKey,
    sourceDateKey,
    qualityScore,
    metricsJson,
    contentJson,
    recommendedItemsJson,
    generator,
    providerId,
    model,
    generationWarning,
    generatedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_ai_suggestions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyAiSuggestionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date_key')) {
      context.handle(
        _dateKeyMeta,
        dateKey.isAcceptableOrUnknown(data['date_key']!, _dateKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dateKeyMeta);
    }
    if (data.containsKey('source_date_key')) {
      context.handle(
        _sourceDateKeyMeta,
        sourceDateKey.isAcceptableOrUnknown(
          data['source_date_key']!,
          _sourceDateKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceDateKeyMeta);
    }
    if (data.containsKey('quality_score')) {
      context.handle(
        _qualityScoreMeta,
        qualityScore.isAcceptableOrUnknown(
          data['quality_score']!,
          _qualityScoreMeta,
        ),
      );
    }
    if (data.containsKey('metrics_json')) {
      context.handle(
        _metricsJsonMeta,
        metricsJson.isAcceptableOrUnknown(
          data['metrics_json']!,
          _metricsJsonMeta,
        ),
      );
    }
    if (data.containsKey('content_json')) {
      context.handle(
        _contentJsonMeta,
        contentJson.isAcceptableOrUnknown(
          data['content_json']!,
          _contentJsonMeta,
        ),
      );
    }
    if (data.containsKey('recommended_items_json')) {
      context.handle(
        _recommendedItemsJsonMeta,
        recommendedItemsJson.isAcceptableOrUnknown(
          data['recommended_items_json']!,
          _recommendedItemsJsonMeta,
        ),
      );
    }
    if (data.containsKey('provider_id')) {
      context.handle(
        _providerIdMeta,
        providerId.isAcceptableOrUnknown(data['provider_id']!, _providerIdMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('generation_warning')) {
      context.handle(
        _generationWarningMeta,
        generationWarning.isAcceptableOrUnknown(
          data['generation_warning']!,
          _generationWarningMeta,
        ),
      );
    }
    if (data.containsKey('generated_at')) {
      context.handle(
        _generatedAtMeta,
        generatedAt.isAcceptableOrUnknown(
          data['generated_at']!,
          _generatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_generatedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {dateKey};
  @override
  DailyAiSuggestionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyAiSuggestionRow(
      dateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date_key'],
      )!,
      sourceDateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_date_key'],
      )!,
      qualityScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quality_score'],
      ),
      metricsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metrics_json'],
      )!,
      contentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_json'],
      )!,
      recommendedItemsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recommended_items_json'],
      )!,
      generator: $DailyAiSuggestionsTable.$convertergenerator.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}generator'],
        )!,
      ),
      providerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_id'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      generationWarning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generation_warning'],
      ),
      generatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generated_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DailyAiSuggestionsTable createAlias(String alias) {
    return $DailyAiSuggestionsTable(attachedDatabase, alias);
  }

  static TypeConverter<SuggestionGenerator, String> $convertergenerator =
      const WireEnumConverter<SuggestionGenerator>(SuggestionGenerator.values);
}

class DailyAiSuggestionRow extends DataClass
    implements Insertable<DailyAiSuggestionRow> {
  final String dateKey;
  final String sourceDateKey;
  final int? qualityScore;
  final String metricsJson;
  final String contentJson;
  final String recommendedItemsJson;
  final SuggestionGenerator generator;
  final String? providerId;
  final String? model;
  final String? generationWarning;
  final int generatedAt;
  final int updatedAt;
  const DailyAiSuggestionRow({
    required this.dateKey,
    required this.sourceDateKey,
    this.qualityScore,
    required this.metricsJson,
    required this.contentJson,
    required this.recommendedItemsJson,
    required this.generator,
    this.providerId,
    this.model,
    this.generationWarning,
    required this.generatedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date_key'] = Variable<String>(dateKey);
    map['source_date_key'] = Variable<String>(sourceDateKey);
    if (!nullToAbsent || qualityScore != null) {
      map['quality_score'] = Variable<int>(qualityScore);
    }
    map['metrics_json'] = Variable<String>(metricsJson);
    map['content_json'] = Variable<String>(contentJson);
    map['recommended_items_json'] = Variable<String>(recommendedItemsJson);
    {
      map['generator'] = Variable<String>(
        $DailyAiSuggestionsTable.$convertergenerator.toSql(generator),
      );
    }
    if (!nullToAbsent || providerId != null) {
      map['provider_id'] = Variable<String>(providerId);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    if (!nullToAbsent || generationWarning != null) {
      map['generation_warning'] = Variable<String>(generationWarning);
    }
    map['generated_at'] = Variable<int>(generatedAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DailyAiSuggestionsCompanion toCompanion(bool nullToAbsent) {
    return DailyAiSuggestionsCompanion(
      dateKey: Value(dateKey),
      sourceDateKey: Value(sourceDateKey),
      qualityScore: qualityScore == null && nullToAbsent
          ? const Value.absent()
          : Value(qualityScore),
      metricsJson: Value(metricsJson),
      contentJson: Value(contentJson),
      recommendedItemsJson: Value(recommendedItemsJson),
      generator: Value(generator),
      providerId: providerId == null && nullToAbsent
          ? const Value.absent()
          : Value(providerId),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      generationWarning: generationWarning == null && nullToAbsent
          ? const Value.absent()
          : Value(generationWarning),
      generatedAt: Value(generatedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DailyAiSuggestionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyAiSuggestionRow(
      dateKey: serializer.fromJson<String>(json['dateKey']),
      sourceDateKey: serializer.fromJson<String>(json['sourceDateKey']),
      qualityScore: serializer.fromJson<int?>(json['qualityScore']),
      metricsJson: serializer.fromJson<String>(json['metricsJson']),
      contentJson: serializer.fromJson<String>(json['contentJson']),
      recommendedItemsJson: serializer.fromJson<String>(
        json['recommendedItemsJson'],
      ),
      generator: serializer.fromJson<SuggestionGenerator>(json['generator']),
      providerId: serializer.fromJson<String?>(json['providerId']),
      model: serializer.fromJson<String?>(json['model']),
      generationWarning: serializer.fromJson<String?>(
        json['generationWarning'],
      ),
      generatedAt: serializer.fromJson<int>(json['generatedAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dateKey': serializer.toJson<String>(dateKey),
      'sourceDateKey': serializer.toJson<String>(sourceDateKey),
      'qualityScore': serializer.toJson<int?>(qualityScore),
      'metricsJson': serializer.toJson<String>(metricsJson),
      'contentJson': serializer.toJson<String>(contentJson),
      'recommendedItemsJson': serializer.toJson<String>(recommendedItemsJson),
      'generator': serializer.toJson<SuggestionGenerator>(generator),
      'providerId': serializer.toJson<String?>(providerId),
      'model': serializer.toJson<String?>(model),
      'generationWarning': serializer.toJson<String?>(generationWarning),
      'generatedAt': serializer.toJson<int>(generatedAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  DailyAiSuggestionRow copyWith({
    String? dateKey,
    String? sourceDateKey,
    Value<int?> qualityScore = const Value.absent(),
    String? metricsJson,
    String? contentJson,
    String? recommendedItemsJson,
    SuggestionGenerator? generator,
    Value<String?> providerId = const Value.absent(),
    Value<String?> model = const Value.absent(),
    Value<String?> generationWarning = const Value.absent(),
    int? generatedAt,
    int? updatedAt,
  }) => DailyAiSuggestionRow(
    dateKey: dateKey ?? this.dateKey,
    sourceDateKey: sourceDateKey ?? this.sourceDateKey,
    qualityScore: qualityScore.present ? qualityScore.value : this.qualityScore,
    metricsJson: metricsJson ?? this.metricsJson,
    contentJson: contentJson ?? this.contentJson,
    recommendedItemsJson: recommendedItemsJson ?? this.recommendedItemsJson,
    generator: generator ?? this.generator,
    providerId: providerId.present ? providerId.value : this.providerId,
    model: model.present ? model.value : this.model,
    generationWarning: generationWarning.present
        ? generationWarning.value
        : this.generationWarning,
    generatedAt: generatedAt ?? this.generatedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DailyAiSuggestionRow copyWithCompanion(DailyAiSuggestionsCompanion data) {
    return DailyAiSuggestionRow(
      dateKey: data.dateKey.present ? data.dateKey.value : this.dateKey,
      sourceDateKey: data.sourceDateKey.present
          ? data.sourceDateKey.value
          : this.sourceDateKey,
      qualityScore: data.qualityScore.present
          ? data.qualityScore.value
          : this.qualityScore,
      metricsJson: data.metricsJson.present
          ? data.metricsJson.value
          : this.metricsJson,
      contentJson: data.contentJson.present
          ? data.contentJson.value
          : this.contentJson,
      recommendedItemsJson: data.recommendedItemsJson.present
          ? data.recommendedItemsJson.value
          : this.recommendedItemsJson,
      generator: data.generator.present ? data.generator.value : this.generator,
      providerId: data.providerId.present
          ? data.providerId.value
          : this.providerId,
      model: data.model.present ? data.model.value : this.model,
      generationWarning: data.generationWarning.present
          ? data.generationWarning.value
          : this.generationWarning,
      generatedAt: data.generatedAt.present
          ? data.generatedAt.value
          : this.generatedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyAiSuggestionRow(')
          ..write('dateKey: $dateKey, ')
          ..write('sourceDateKey: $sourceDateKey, ')
          ..write('qualityScore: $qualityScore, ')
          ..write('metricsJson: $metricsJson, ')
          ..write('contentJson: $contentJson, ')
          ..write('recommendedItemsJson: $recommendedItemsJson, ')
          ..write('generator: $generator, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('generationWarning: $generationWarning, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    dateKey,
    sourceDateKey,
    qualityScore,
    metricsJson,
    contentJson,
    recommendedItemsJson,
    generator,
    providerId,
    model,
    generationWarning,
    generatedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyAiSuggestionRow &&
          other.dateKey == this.dateKey &&
          other.sourceDateKey == this.sourceDateKey &&
          other.qualityScore == this.qualityScore &&
          other.metricsJson == this.metricsJson &&
          other.contentJson == this.contentJson &&
          other.recommendedItemsJson == this.recommendedItemsJson &&
          other.generator == this.generator &&
          other.providerId == this.providerId &&
          other.model == this.model &&
          other.generationWarning == this.generationWarning &&
          other.generatedAt == this.generatedAt &&
          other.updatedAt == this.updatedAt);
}

class DailyAiSuggestionsCompanion
    extends UpdateCompanion<DailyAiSuggestionRow> {
  final Value<String> dateKey;
  final Value<String> sourceDateKey;
  final Value<int?> qualityScore;
  final Value<String> metricsJson;
  final Value<String> contentJson;
  final Value<String> recommendedItemsJson;
  final Value<SuggestionGenerator> generator;
  final Value<String?> providerId;
  final Value<String?> model;
  final Value<String?> generationWarning;
  final Value<int> generatedAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DailyAiSuggestionsCompanion({
    this.dateKey = const Value.absent(),
    this.sourceDateKey = const Value.absent(),
    this.qualityScore = const Value.absent(),
    this.metricsJson = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.recommendedItemsJson = const Value.absent(),
    this.generator = const Value.absent(),
    this.providerId = const Value.absent(),
    this.model = const Value.absent(),
    this.generationWarning = const Value.absent(),
    this.generatedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyAiSuggestionsCompanion.insert({
    required String dateKey,
    required String sourceDateKey,
    this.qualityScore = const Value.absent(),
    this.metricsJson = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.recommendedItemsJson = const Value.absent(),
    this.generator = const Value.absent(),
    this.providerId = const Value.absent(),
    this.model = const Value.absent(),
    this.generationWarning = const Value.absent(),
    required int generatedAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : dateKey = Value(dateKey),
       sourceDateKey = Value(sourceDateKey),
       generatedAt = Value(generatedAt),
       updatedAt = Value(updatedAt);
  static Insertable<DailyAiSuggestionRow> custom({
    Expression<String>? dateKey,
    Expression<String>? sourceDateKey,
    Expression<int>? qualityScore,
    Expression<String>? metricsJson,
    Expression<String>? contentJson,
    Expression<String>? recommendedItemsJson,
    Expression<String>? generator,
    Expression<String>? providerId,
    Expression<String>? model,
    Expression<String>? generationWarning,
    Expression<int>? generatedAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dateKey != null) 'date_key': dateKey,
      if (sourceDateKey != null) 'source_date_key': sourceDateKey,
      if (qualityScore != null) 'quality_score': qualityScore,
      if (metricsJson != null) 'metrics_json': metricsJson,
      if (contentJson != null) 'content_json': contentJson,
      if (recommendedItemsJson != null)
        'recommended_items_json': recommendedItemsJson,
      if (generator != null) 'generator': generator,
      if (providerId != null) 'provider_id': providerId,
      if (model != null) 'model': model,
      if (generationWarning != null) 'generation_warning': generationWarning,
      if (generatedAt != null) 'generated_at': generatedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyAiSuggestionsCompanion copyWith({
    Value<String>? dateKey,
    Value<String>? sourceDateKey,
    Value<int?>? qualityScore,
    Value<String>? metricsJson,
    Value<String>? contentJson,
    Value<String>? recommendedItemsJson,
    Value<SuggestionGenerator>? generator,
    Value<String?>? providerId,
    Value<String?>? model,
    Value<String?>? generationWarning,
    Value<int>? generatedAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return DailyAiSuggestionsCompanion(
      dateKey: dateKey ?? this.dateKey,
      sourceDateKey: sourceDateKey ?? this.sourceDateKey,
      qualityScore: qualityScore ?? this.qualityScore,
      metricsJson: metricsJson ?? this.metricsJson,
      contentJson: contentJson ?? this.contentJson,
      recommendedItemsJson: recommendedItemsJson ?? this.recommendedItemsJson,
      generator: generator ?? this.generator,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      generationWarning: generationWarning ?? this.generationWarning,
      generatedAt: generatedAt ?? this.generatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dateKey.present) {
      map['date_key'] = Variable<String>(dateKey.value);
    }
    if (sourceDateKey.present) {
      map['source_date_key'] = Variable<String>(sourceDateKey.value);
    }
    if (qualityScore.present) {
      map['quality_score'] = Variable<int>(qualityScore.value);
    }
    if (metricsJson.present) {
      map['metrics_json'] = Variable<String>(metricsJson.value);
    }
    if (contentJson.present) {
      map['content_json'] = Variable<String>(contentJson.value);
    }
    if (recommendedItemsJson.present) {
      map['recommended_items_json'] = Variable<String>(
        recommendedItemsJson.value,
      );
    }
    if (generator.present) {
      map['generator'] = Variable<String>(
        $DailyAiSuggestionsTable.$convertergenerator.toSql(generator.value),
      );
    }
    if (providerId.present) {
      map['provider_id'] = Variable<String>(providerId.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (generationWarning.present) {
      map['generation_warning'] = Variable<String>(generationWarning.value);
    }
    if (generatedAt.present) {
      map['generated_at'] = Variable<int>(generatedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyAiSuggestionsCompanion(')
          ..write('dateKey: $dateKey, ')
          ..write('sourceDateKey: $sourceDateKey, ')
          ..write('qualityScore: $qualityScore, ')
          ..write('metricsJson: $metricsJson, ')
          ..write('contentJson: $contentJson, ')
          ..write('recommendedItemsJson: $recommendedItemsJson, ')
          ..write('generator: $generator, ')
          ..write('providerId: $providerId, ')
          ..write('model: $model, ')
          ..write('generationWarning: $generationWarning, ')
          ..write('generatedAt: $generatedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GameHighScoresTable extends GameHighScores
    with TableInfo<$GameHighScoresTable, GameHighScoreRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GameHighScoresTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _gameModeMeta = const VerificationMeta(
    'gameMode',
  );
  @override
  late final GeneratedColumn<String> gameMode = GeneratedColumn<String>(
    'game_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxComboMeta = const VerificationMeta(
    'maxCombo',
  );
  @override
  late final GeneratedColumn<int> maxCombo = GeneratedColumn<int>(
    'max_combo',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  @override
  late final GeneratedColumn<int> accuracy = GeneratedColumn<int>(
    'accuracy',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _elapsedMsMeta = const VerificationMeta(
    'elapsedMs',
  );
  @override
  late final GeneratedColumn<int> elapsedMs = GeneratedColumn<int>(
    'elapsed_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _playedAtMeta = const VerificationMeta(
    'playedAt',
  );
  @override
  late final GeneratedColumn<int> playedAt = GeneratedColumn<int>(
    'played_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gameMode,
    score,
    maxCombo,
    accuracy,
    elapsedMs,
    playedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'game_high_scores';
  @override
  VerificationContext validateIntegrity(
    Insertable<GameHighScoreRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('game_mode')) {
      context.handle(
        _gameModeMeta,
        gameMode.isAcceptableOrUnknown(data['game_mode']!, _gameModeMeta),
      );
    } else if (isInserting) {
      context.missing(_gameModeMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('max_combo')) {
      context.handle(
        _maxComboMeta,
        maxCombo.isAcceptableOrUnknown(data['max_combo']!, _maxComboMeta),
      );
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    }
    if (data.containsKey('elapsed_ms')) {
      context.handle(
        _elapsedMsMeta,
        elapsedMs.isAcceptableOrUnknown(data['elapsed_ms']!, _elapsedMsMeta),
      );
    }
    if (data.containsKey('played_at')) {
      context.handle(
        _playedAtMeta,
        playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GameHighScoreRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GameHighScoreRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      gameMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}game_mode'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      )!,
      maxCombo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_combo'],
      )!,
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accuracy'],
      )!,
      elapsedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_ms'],
      )!,
      playedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}played_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $GameHighScoresTable createAlias(String alias) {
    return $GameHighScoresTable(attachedDatabase, alias);
  }
}

class GameHighScoreRow extends DataClass
    implements Insertable<GameHighScoreRow> {
  final int id;
  final String gameMode;
  final int score;
  final int maxCombo;
  final int accuracy;
  final int elapsedMs;
  final int playedAt;
  final int createdAt;
  const GameHighScoreRow({
    required this.id,
    required this.gameMode,
    required this.score,
    required this.maxCombo,
    required this.accuracy,
    required this.elapsedMs,
    required this.playedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['game_mode'] = Variable<String>(gameMode);
    map['score'] = Variable<int>(score);
    map['max_combo'] = Variable<int>(maxCombo);
    map['accuracy'] = Variable<int>(accuracy);
    map['elapsed_ms'] = Variable<int>(elapsedMs);
    map['played_at'] = Variable<int>(playedAt);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  GameHighScoresCompanion toCompanion(bool nullToAbsent) {
    return GameHighScoresCompanion(
      id: Value(id),
      gameMode: Value(gameMode),
      score: Value(score),
      maxCombo: Value(maxCombo),
      accuracy: Value(accuracy),
      elapsedMs: Value(elapsedMs),
      playedAt: Value(playedAt),
      createdAt: Value(createdAt),
    );
  }

  factory GameHighScoreRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GameHighScoreRow(
      id: serializer.fromJson<int>(json['id']),
      gameMode: serializer.fromJson<String>(json['gameMode']),
      score: serializer.fromJson<int>(json['score']),
      maxCombo: serializer.fromJson<int>(json['maxCombo']),
      accuracy: serializer.fromJson<int>(json['accuracy']),
      elapsedMs: serializer.fromJson<int>(json['elapsedMs']),
      playedAt: serializer.fromJson<int>(json['playedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'gameMode': serializer.toJson<String>(gameMode),
      'score': serializer.toJson<int>(score),
      'maxCombo': serializer.toJson<int>(maxCombo),
      'accuracy': serializer.toJson<int>(accuracy),
      'elapsedMs': serializer.toJson<int>(elapsedMs),
      'playedAt': serializer.toJson<int>(playedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  GameHighScoreRow copyWith({
    int? id,
    String? gameMode,
    int? score,
    int? maxCombo,
    int? accuracy,
    int? elapsedMs,
    int? playedAt,
    int? createdAt,
  }) => GameHighScoreRow(
    id: id ?? this.id,
    gameMode: gameMode ?? this.gameMode,
    score: score ?? this.score,
    maxCombo: maxCombo ?? this.maxCombo,
    accuracy: accuracy ?? this.accuracy,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    playedAt: playedAt ?? this.playedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  GameHighScoreRow copyWithCompanion(GameHighScoresCompanion data) {
    return GameHighScoreRow(
      id: data.id.present ? data.id.value : this.id,
      gameMode: data.gameMode.present ? data.gameMode.value : this.gameMode,
      score: data.score.present ? data.score.value : this.score,
      maxCombo: data.maxCombo.present ? data.maxCombo.value : this.maxCombo,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      elapsedMs: data.elapsedMs.present ? data.elapsedMs.value : this.elapsedMs,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GameHighScoreRow(')
          ..write('id: $id, ')
          ..write('gameMode: $gameMode, ')
          ..write('score: $score, ')
          ..write('maxCombo: $maxCombo, ')
          ..write('accuracy: $accuracy, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('playedAt: $playedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    gameMode,
    score,
    maxCombo,
    accuracy,
    elapsedMs,
    playedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameHighScoreRow &&
          other.id == this.id &&
          other.gameMode == this.gameMode &&
          other.score == this.score &&
          other.maxCombo == this.maxCombo &&
          other.accuracy == this.accuracy &&
          other.elapsedMs == this.elapsedMs &&
          other.playedAt == this.playedAt &&
          other.createdAt == this.createdAt);
}

class GameHighScoresCompanion extends UpdateCompanion<GameHighScoreRow> {
  final Value<int> id;
  final Value<String> gameMode;
  final Value<int> score;
  final Value<int> maxCombo;
  final Value<int> accuracy;
  final Value<int> elapsedMs;
  final Value<int> playedAt;
  final Value<int> createdAt;
  const GameHighScoresCompanion({
    this.id = const Value.absent(),
    this.gameMode = const Value.absent(),
    this.score = const Value.absent(),
    this.maxCombo = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.playedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  GameHighScoresCompanion.insert({
    this.id = const Value.absent(),
    required String gameMode,
    required int score,
    this.maxCombo = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    required int playedAt,
    required int createdAt,
  }) : gameMode = Value(gameMode),
       score = Value(score),
       playedAt = Value(playedAt),
       createdAt = Value(createdAt);
  static Insertable<GameHighScoreRow> custom({
    Expression<int>? id,
    Expression<String>? gameMode,
    Expression<int>? score,
    Expression<int>? maxCombo,
    Expression<int>? accuracy,
    Expression<int>? elapsedMs,
    Expression<int>? playedAt,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gameMode != null) 'game_mode': gameMode,
      if (score != null) 'score': score,
      if (maxCombo != null) 'max_combo': maxCombo,
      if (accuracy != null) 'accuracy': accuracy,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      if (playedAt != null) 'played_at': playedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  GameHighScoresCompanion copyWith({
    Value<int>? id,
    Value<String>? gameMode,
    Value<int>? score,
    Value<int>? maxCombo,
    Value<int>? accuracy,
    Value<int>? elapsedMs,
    Value<int>? playedAt,
    Value<int>? createdAt,
  }) {
    return GameHighScoresCompanion(
      id: id ?? this.id,
      gameMode: gameMode ?? this.gameMode,
      score: score ?? this.score,
      maxCombo: maxCombo ?? this.maxCombo,
      accuracy: accuracy ?? this.accuracy,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      playedAt: playedAt ?? this.playedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (gameMode.present) {
      map['game_mode'] = Variable<String>(gameMode.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (maxCombo.present) {
      map['max_combo'] = Variable<int>(maxCombo.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<int>(accuracy.value);
    }
    if (elapsedMs.present) {
      map['elapsed_ms'] = Variable<int>(elapsedMs.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<int>(playedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GameHighScoresCompanion(')
          ..write('id: $id, ')
          ..write('gameMode: $gameMode, ')
          ..write('score: $score, ')
          ..write('maxCombo: $maxCombo, ')
          ..write('accuracy: $accuracy, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('playedAt: $playedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String valueJson;
  final int updatedAt;
  const SettingRow({
    required this.key,
    required this.valueJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      valueJson: Value(valueJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SettingRow copyWith({String? key, String? valueJson, int? updatedAt}) =>
      SettingRow(
        key: key ?? this.key,
        valueJson: valueJson ?? this.valueJson,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.valueJson == this.valueJson &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String valueJson,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson),
       updatedAt = Value(updatedAt);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WordsTable words = $WordsTable(this);
  late final $WordContentsTable wordContents = $WordContentsTable(this);
  late final $WordReviewStatsTable wordReviewStats = $WordReviewStatsTable(
    this,
  );
  late final $StudySessionsTable studySessions = $StudySessionsTable(this);
  late final $StudySessionItemsTable studySessionItems =
      $StudySessionItemsTable(this);
  late final $ReviewCardsTable reviewCards = $ReviewCardsTable(this);
  late final $ReviewLogsTable reviewLogs = $ReviewLogsTable(this);
  late final $WrongWordStatesTable wrongWordStates = $WrongWordStatesTable(
    this,
  );
  late final $ImportBatchesTable importBatches = $ImportBatchesTable(this);
  late final $ImportRowsTable importRows = $ImportRowsTable(this);
  late final $InitializationJobsTable initializationJobs =
      $InitializationJobsTable(this);
  late final $ProviderAttemptsTable providerAttempts = $ProviderAttemptsTable(
    this,
  );
  late final $DailyAiSuggestionsTable dailyAiSuggestions =
      $DailyAiSuggestionsTable(this);
  late final $GameHighScoresTable gameHighScores = $GameHighScoresTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    words,
    wordContents,
    wordReviewStats,
    studySessions,
    studySessionItems,
    reviewCards,
    reviewLogs,
    wrongWordStates,
    importBatches,
    importRows,
    initializationJobs,
    providerAttempts,
    dailyAiSuggestions,
    gameHighScores,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('word_contents', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('word_review_stats', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'study_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('study_session_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('study_session_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_cards', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_logs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'study_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_logs', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'study_session_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_logs', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('wrong_word_states', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'import_batches',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('import_rows', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('import_rows', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('initialization_jobs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'initialization_jobs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('provider_attempts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'words',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('provider_attempts', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$WordsTableCreateCompanionBuilder = WordsCompanion Function({
  Value<int> id,
  required String term,
  required String normalizedTerm,
  required String sourceLanguage,
  required String targetLanguage,
  Value<String?> sourceLanguageName,
  Value<String?> targetLanguageName,
  required EntryType entryType,
  Value<LexicalContentType> contentType,
  Value<int?> sourceCreatedAt,
  Value<InitializationStatus> initializationStatus,
  Value<MasteryLevel> masteryLevel,
  Value<int> masteryScore,
  Value<bool> isSuspended,
  Value<String?> userNote,
  required int createdAt,
  required int updatedAt,
});
typedef $$WordsTableUpdateCompanionBuilder = WordsCompanion Function({
  Value<int> id,
  Value<String> term,
  Value<String> normalizedTerm,
  Value<String> sourceLanguage,
  Value<String> targetLanguage,
  Value<String?> sourceLanguageName,
  Value<String?> targetLanguageName,
  Value<EntryType> entryType,
  Value<LexicalContentType> contentType,
  Value<int?> sourceCreatedAt,
  Value<InitializationStatus> initializationStatus,
  Value<MasteryLevel> masteryLevel,
  Value<int> masteryScore,
  Value<bool> isSuspended,
  Value<String?> userNote,
  Value<int> createdAt,
  Value<int> updatedAt,
});

final class $$WordsTableReferences
    extends BaseReferences<_$AppDatabase, $WordsTable, WordRow> {
  $$WordsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$WordContentsTable, List<WordContentRow>>
  _wordContentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.wordContents,
    aliasName: 'words__id__word_contents__word_id',
  );

  $$WordContentsTableProcessedTableManager get wordContentsRefs {
    final manager = $$WordContentsTableTableManager(
      $_db,
      $_db.wordContents,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_wordContentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$WordReviewStatsTable, List<WordReviewStatRow>>
  _wordReviewStatsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.wordReviewStats,
    aliasName: 'words__id__word_review_stats__word_id',
  );

  $$WordReviewStatsTableProcessedTableManager get wordReviewStatsRefs {
    final manager = $$WordReviewStatsTableTableManager(
      $_db,
      $_db.wordReviewStats,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _wordReviewStatsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$StudySessionItemsTable, List<StudySessionItemRow>>
  _studySessionItemsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.studySessionItems,
        aliasName: 'words__id__study_session_items__word_id',
      );

  $$StudySessionItemsTableProcessedTableManager get studySessionItemsRefs {
    final manager = $$StudySessionItemsTableTableManager(
      $_db,
      $_db.studySessionItems,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _studySessionItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewCardsTable, List<ReviewCardRow>>
  _reviewCardsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewCards,
    aliasName: 'words__id__review_cards__word_id',
  );

  $$ReviewCardsTableProcessedTableManager get reviewCardsRefs {
    final manager = $$ReviewCardsTableTableManager(
      $_db,
      $_db.reviewCards,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewCardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewLogsTable, List<ReviewLogRow>>
  _reviewLogsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewLogs,
    aliasName: 'words__id__review_logs__word_id',
  );

  $$ReviewLogsTableProcessedTableManager get reviewLogsRefs {
    final manager = $$ReviewLogsTableTableManager(
      $_db,
      $_db.reviewLogs,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$WrongWordStatesTable, List<WrongWordStateRow>>
  _wrongWordStatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.wrongWordStates,
    aliasName: 'words__id__wrong_word_states__word_id',
  );

  $$WrongWordStatesTableProcessedTableManager get wrongWordStatesRefs {
    final manager = $$WrongWordStatesTableTableManager(
      $_db,
      $_db.wrongWordStates,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _wrongWordStatesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ImportRowsTable, List<ImportRowRow>>
  _importRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.importRows,
    aliasName: 'words__id__import_rows__word_id',
  );

  $$ImportRowsTableProcessedTableManager get importRowsRefs {
    final manager = $$ImportRowsTableTableManager(
      $_db,
      $_db.importRows,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_importRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $InitializationJobsTable,
    List<InitializationJobRow>
  >
  _initializationJobsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.initializationJobs,
        aliasName: 'words__id__initialization_jobs__word_id',
      );

  $$InitializationJobsTableProcessedTableManager get initializationJobsRefs {
    final manager = $$InitializationJobsTableTableManager(
      $_db,
      $_db.initializationJobs,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _initializationJobsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProviderAttemptsTable, List<ProviderAttemptRow>>
  _providerAttemptsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.providerAttempts,
    aliasName: 'words__id__provider_attempts__word_id',
  );

  $$ProviderAttemptsTableProcessedTableManager get providerAttemptsRefs {
    final manager = $$ProviderAttemptsTableTableManager(
      $_db,
      $_db.providerAttempts,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _providerAttemptsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WordsTableFilterComposer extends Composer<_$AppDatabase, $WordsTable> {
  $$WordsTableFilterComposer({
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

  ColumnFilters<String> get term => $composableBuilder(
    column: $table.term,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedTerm => $composableBuilder(
    column: $table.normalizedTerm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLanguage => $composableBuilder(
    column: $table.sourceLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetLanguage => $composableBuilder(
    column: $table.targetLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLanguageName => $composableBuilder(
    column: $table.sourceLanguageName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetLanguageName => $composableBuilder(
    column: $table.targetLanguageName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EntryType, EntryType, String> get entryType =>
      $composableBuilder(
        column: $table.entryType,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<LexicalContentType, LexicalContentType, String>
  get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get sourceCreatedAt => $composableBuilder(
    column: $table.sourceCreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    InitializationStatus,
    InitializationStatus,
    String
  >
  get initializationStatus => $composableBuilder(
    column: $table.initializationStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<MasteryLevel, MasteryLevel, String>
  get masteryLevel => $composableBuilder(
    column: $table.masteryLevel,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get masteryScore => $composableBuilder(
    column: $table.masteryScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSuspended => $composableBuilder(
    column: $table.isSuspended,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> wordContentsRefs(
    Expression<bool> Function($$WordContentsTableFilterComposer f) f,
  ) {
    final $$WordContentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wordContents,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordContentsTableFilterComposer(
            $db: $db,
            $table: $db.wordContents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> wordReviewStatsRefs(
    Expression<bool> Function($$WordReviewStatsTableFilterComposer f) f,
  ) {
    final $$WordReviewStatsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wordReviewStats,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordReviewStatsTableFilterComposer(
            $db: $db,
            $table: $db.wordReviewStats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> studySessionItemsRefs(
    Expression<bool> Function($$StudySessionItemsTableFilterComposer f) f,
  ) {
    final $$StudySessionItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.studySessionItems,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionItemsTableFilterComposer(
            $db: $db,
            $table: $db.studySessionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewCardsRefs(
    Expression<bool> Function($$ReviewCardsTableFilterComposer f) f,
  ) {
    final $$ReviewCardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewCards,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewCardsTableFilterComposer(
            $db: $db,
            $table: $db.reviewCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewLogsRefs(
    Expression<bool> Function($$ReviewLogsTableFilterComposer f) f,
  ) {
    final $$ReviewLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewLogs,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewLogsTableFilterComposer(
            $db: $db,
            $table: $db.reviewLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> wrongWordStatesRefs(
    Expression<bool> Function($$WrongWordStatesTableFilterComposer f) f,
  ) {
    final $$WrongWordStatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wrongWordStates,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WrongWordStatesTableFilterComposer(
            $db: $db,
            $table: $db.wrongWordStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> importRowsRefs(
    Expression<bool> Function($$ImportRowsTableFilterComposer f) f,
  ) {
    final $$ImportRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportRowsTableFilterComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> initializationJobsRefs(
    Expression<bool> Function($$InitializationJobsTableFilterComposer f) f,
  ) {
    final $$InitializationJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.initializationJobs,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InitializationJobsTableFilterComposer(
            $db: $db,
            $table: $db.initializationJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> providerAttemptsRefs(
    Expression<bool> Function($$ProviderAttemptsTableFilterComposer f) f,
  ) {
    final $$ProviderAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.providerAttempts,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProviderAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.providerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WordsTableOrderingComposer
    extends Composer<_$AppDatabase, $WordsTable> {
  $$WordsTableOrderingComposer({
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

  ColumnOrderings<String> get term => $composableBuilder(
    column: $table.term,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedTerm => $composableBuilder(
    column: $table.normalizedTerm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLanguage => $composableBuilder(
    column: $table.sourceLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetLanguage => $composableBuilder(
    column: $table.targetLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLanguageName => $composableBuilder(
    column: $table.sourceLanguageName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetLanguageName => $composableBuilder(
    column: $table.targetLanguageName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryType => $composableBuilder(
    column: $table.entryType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceCreatedAt => $composableBuilder(
    column: $table.sourceCreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get initializationStatus => $composableBuilder(
    column: $table.initializationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get masteryLevel => $composableBuilder(
    column: $table.masteryLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get masteryScore => $composableBuilder(
    column: $table.masteryScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSuspended => $composableBuilder(
    column: $table.isSuspended,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WordsTable> {
  $$WordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get term =>
      $composableBuilder(column: $table.term, builder: (column) => column);

  GeneratedColumn<String> get normalizedTerm => $composableBuilder(
    column: $table.normalizedTerm,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLanguage => $composableBuilder(
    column: $table.sourceLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetLanguage => $composableBuilder(
    column: $table.targetLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLanguageName => $composableBuilder(
    column: $table.sourceLanguageName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetLanguageName => $composableBuilder(
    column: $table.targetLanguageName,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<EntryType, String> get entryType =>
      $composableBuilder(column: $table.entryType, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LexicalContentType, String>
  get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceCreatedAt => $composableBuilder(
    column: $table.sourceCreatedAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<InitializationStatus, String>
  get initializationStatus => $composableBuilder(
    column: $table.initializationStatus,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<MasteryLevel, String> get masteryLevel =>
      $composableBuilder(
        column: $table.masteryLevel,
        builder: (column) => column,
      );

  GeneratedColumn<int> get masteryScore => $composableBuilder(
    column: $table.masteryScore,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isSuspended => $composableBuilder(
    column: $table.isSuspended,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userNote =>
      $composableBuilder(column: $table.userNote, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> wordContentsRefs<T extends Object>(
    Expression<T> Function($$WordContentsTableAnnotationComposer a) f,
  ) {
    final $$WordContentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wordContents,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordContentsTableAnnotationComposer(
            $db: $db,
            $table: $db.wordContents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> wordReviewStatsRefs<T extends Object>(
    Expression<T> Function($$WordReviewStatsTableAnnotationComposer a) f,
  ) {
    final $$WordReviewStatsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wordReviewStats,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordReviewStatsTableAnnotationComposer(
            $db: $db,
            $table: $db.wordReviewStats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> studySessionItemsRefs<T extends Object>(
    Expression<T> Function($$StudySessionItemsTableAnnotationComposer a) f,
  ) {
    final $$StudySessionItemsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.studySessionItems,
          getReferencedColumn: (t) => t.wordId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StudySessionItemsTableAnnotationComposer(
                $db: $db,
                $table: $db.studySessionItems,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> reviewCardsRefs<T extends Object>(
    Expression<T> Function($$ReviewCardsTableAnnotationComposer a) f,
  ) {
    final $$ReviewCardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewCards,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewCardsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewLogsRefs<T extends Object>(
    Expression<T> Function($$ReviewLogsTableAnnotationComposer a) f,
  ) {
    final $$ReviewLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewLogs,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> wrongWordStatesRefs<T extends Object>(
    Expression<T> Function($$WrongWordStatesTableAnnotationComposer a) f,
  ) {
    final $$WrongWordStatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wrongWordStates,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WrongWordStatesTableAnnotationComposer(
            $db: $db,
            $table: $db.wrongWordStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> importRowsRefs<T extends Object>(
    Expression<T> Function($$ImportRowsTableAnnotationComposer a) f,
  ) {
    final $$ImportRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> initializationJobsRefs<T extends Object>(
    Expression<T> Function($$InitializationJobsTableAnnotationComposer a) f,
  ) {
    final $$InitializationJobsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.initializationJobs,
          getReferencedColumn: (t) => t.wordId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InitializationJobsTableAnnotationComposer(
                $db: $db,
                $table: $db.initializationJobs,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> providerAttemptsRefs<T extends Object>(
    Expression<T> Function($$ProviderAttemptsTableAnnotationComposer a) f,
  ) {
    final $$ProviderAttemptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.providerAttempts,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProviderAttemptsTableAnnotationComposer(
            $db: $db,
            $table: $db.providerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WordsTable,
          WordRow,
          $$WordsTableFilterComposer,
          $$WordsTableOrderingComposer,
          $$WordsTableAnnotationComposer,
          $$WordsTableCreateCompanionBuilder,
          $$WordsTableUpdateCompanionBuilder,
          (WordRow, $$WordsTableReferences),
          WordRow,
          PrefetchHooks Function({
            bool wordContentsRefs,
            bool wordReviewStatsRefs,
            bool studySessionItemsRefs,
            bool reviewCardsRefs,
            bool reviewLogsRefs,
            bool wrongWordStatesRefs,
            bool importRowsRefs,
            bool initializationJobsRefs,
            bool providerAttemptsRefs,
          })
        > {
  $$WordsTableTableManager(_$AppDatabase db, $WordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> term = const Value.absent(),
                Value<String> normalizedTerm = const Value.absent(),
                Value<String> sourceLanguage = const Value.absent(),
                Value<String> targetLanguage = const Value.absent(),
                Value<String?> sourceLanguageName = const Value.absent(),
                Value<String?> targetLanguageName = const Value.absent(),
                Value<EntryType> entryType = const Value.absent(),
                Value<LexicalContentType> contentType = const Value.absent(),
                Value<int?> sourceCreatedAt = const Value.absent(),
                Value<InitializationStatus> initializationStatus =
                    const Value.absent(),
                Value<MasteryLevel> masteryLevel = const Value.absent(),
                Value<int> masteryScore = const Value.absent(),
                Value<bool> isSuspended = const Value.absent(),
                Value<String?> userNote = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => WordsCompanion(
                id: id,
                term: term,
                normalizedTerm: normalizedTerm,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                sourceLanguageName: sourceLanguageName,
                targetLanguageName: targetLanguageName,
                entryType: entryType,
                contentType: contentType,
                sourceCreatedAt: sourceCreatedAt,
                initializationStatus: initializationStatus,
                masteryLevel: masteryLevel,
                masteryScore: masteryScore,
                isSuspended: isSuspended,
                userNote: userNote,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String term,
                required String normalizedTerm,
                required String sourceLanguage,
                required String targetLanguage,
                Value<String?> sourceLanguageName = const Value.absent(),
                Value<String?> targetLanguageName = const Value.absent(),
                required EntryType entryType,
                Value<LexicalContentType> contentType = const Value.absent(),
                Value<int?> sourceCreatedAt = const Value.absent(),
                Value<InitializationStatus> initializationStatus =
                    const Value.absent(),
                Value<MasteryLevel> masteryLevel = const Value.absent(),
                Value<int> masteryScore = const Value.absent(),
                Value<bool> isSuspended = const Value.absent(),
                Value<String?> userNote = const Value.absent(),
                required int createdAt,
                required int updatedAt,
              }) => WordsCompanion.insert(
                id: id,
                term: term,
                normalizedTerm: normalizedTerm,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                sourceLanguageName: sourceLanguageName,
                targetLanguageName: targetLanguageName,
                entryType: entryType,
                contentType: contentType,
                sourceCreatedAt: sourceCreatedAt,
                initializationStatus: initializationStatus,
                masteryLevel: masteryLevel,
                masteryScore: masteryScore,
                isSuspended: isSuspended,
                userNote: userNote,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WordsTable, WordRow>(table),
                  $$WordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                wordContentsRefs = false,
                wordReviewStatsRefs = false,
                studySessionItemsRefs = false,
                reviewCardsRefs = false,
                reviewLogsRefs = false,
                wrongWordStatesRefs = false,
                importRowsRefs = false,
                initializationJobsRefs = false,
                providerAttemptsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (wordContentsRefs) db.wordContents,
                    if (wordReviewStatsRefs) db.wordReviewStats,
                    if (studySessionItemsRefs) db.studySessionItems,
                    if (reviewCardsRefs) db.reviewCards,
                    if (reviewLogsRefs) db.reviewLogs,
                    if (wrongWordStatesRefs) db.wrongWordStates,
                    if (importRowsRefs) db.importRows,
                    if (initializationJobsRefs) db.initializationJobs,
                    if (providerAttemptsRefs) db.providerAttempts,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (wordContentsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          WordContentRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._wordContentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).wordContentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (wordReviewStatsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          WordReviewStatRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._wordReviewStatsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).wordReviewStatsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (studySessionItemsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          StudySessionItemRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._studySessionItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).studySessionItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewCardsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          ReviewCardRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._reviewCardsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewCardsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewLogsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          ReviewLogRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._reviewLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (wrongWordStatesRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          WrongWordStateRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._wrongWordStatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).wrongWordStatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (importRowsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          ImportRowRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._importRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).importRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (initializationJobsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          InitializationJobRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._initializationJobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).initializationJobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (providerAttemptsRefs)
                        await $_getPrefetchedData<
                          WordRow,
                          $WordsTable,
                          ProviderAttemptRow
                        >(
                          currentTable: table,
                          referencedTable: $$WordsTableReferences
                              ._providerAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WordsTableReferences(
                                db,
                                table,
                                p0,
                              ).providerAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$WordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WordsTable,
      WordRow,
      $$WordsTableFilterComposer,
      $$WordsTableOrderingComposer,
      $$WordsTableAnnotationComposer,
      $$WordsTableCreateCompanionBuilder,
      $$WordsTableUpdateCompanionBuilder,
      (WordRow, $$WordsTableReferences),
      WordRow,
      PrefetchHooks Function({
        bool wordContentsRefs,
        bool wordReviewStatsRefs,
        bool studySessionItemsRefs,
        bool reviewCardsRefs,
        bool reviewLogsRefs,
        bool wrongWordStatesRefs,
        bool importRowsRefs,
        bool initializationJobsRefs,
        bool providerAttemptsRefs,
      })
    >;
typedef $$WordContentsTableCreateCompanionBuilder =
    WordContentsCompanion Function({
      Value<int> wordId,
      Value<String> definitionsJson,
      Value<String> pronunciationsJson,
      Value<String> examplesJson,
      Value<String> phrasesJson,
      Value<String> formsJson,
      Value<String> synonymsJson,
      Value<String> antonymsJson,
      Value<String> wordFamilyJson,
      Value<String> confusedWordsJson,
      Value<String> rootsJson,
      Value<String> affixesJson,
      Value<String> summaryJson,
      Value<String> learningJson,
      Value<String> sentenceAnalysisJson,
      Value<String> tagsJson,
      Value<String> providerMetadataJson,
      Value<ContentSource> contentSource,
      Value<int> contentVersion,
      Value<int?> initializedAt,
      required int updatedAt,
    });
typedef $$WordContentsTableUpdateCompanionBuilder =
    WordContentsCompanion Function({
      Value<int> wordId,
      Value<String> definitionsJson,
      Value<String> pronunciationsJson,
      Value<String> examplesJson,
      Value<String> phrasesJson,
      Value<String> formsJson,
      Value<String> synonymsJson,
      Value<String> antonymsJson,
      Value<String> wordFamilyJson,
      Value<String> confusedWordsJson,
      Value<String> rootsJson,
      Value<String> affixesJson,
      Value<String> summaryJson,
      Value<String> learningJson,
      Value<String> sentenceAnalysisJson,
      Value<String> tagsJson,
      Value<String> providerMetadataJson,
      Value<ContentSource> contentSource,
      Value<int> contentVersion,
      Value<int?> initializedAt,
      Value<int> updatedAt,
    });

final class $$WordContentsTableReferences
    extends BaseReferences<_$AppDatabase, $WordContentsTable, WordContentRow> {
  $$WordContentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('word_contents__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WordContentsTableFilterComposer
    extends Composer<_$AppDatabase, $WordContentsTable> {
  $$WordContentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get definitionsJson => $composableBuilder(
    column: $table.definitionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pronunciationsJson => $composableBuilder(
    column: $table.pronunciationsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get examplesJson => $composableBuilder(
    column: $table.examplesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phrasesJson => $composableBuilder(
    column: $table.phrasesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get formsJson => $composableBuilder(
    column: $table.formsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get synonymsJson => $composableBuilder(
    column: $table.synonymsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get antonymsJson => $composableBuilder(
    column: $table.antonymsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordFamilyJson => $composableBuilder(
    column: $table.wordFamilyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confusedWordsJson => $composableBuilder(
    column: $table.confusedWordsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootsJson => $composableBuilder(
    column: $table.rootsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get affixesJson => $composableBuilder(
    column: $table.affixesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get learningJson => $composableBuilder(
    column: $table.learningJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sentenceAnalysisJson => $composableBuilder(
    column: $table.sentenceAnalysisJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerMetadataJson => $composableBuilder(
    column: $table.providerMetadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ContentSource, ContentSource, String>
  get contentSource => $composableBuilder(
    column: $table.contentSource,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get initializedAt => $composableBuilder(
    column: $table.initializedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WordContentsTableOrderingComposer
    extends Composer<_$AppDatabase, $WordContentsTable> {
  $$WordContentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get definitionsJson => $composableBuilder(
    column: $table.definitionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pronunciationsJson => $composableBuilder(
    column: $table.pronunciationsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get examplesJson => $composableBuilder(
    column: $table.examplesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phrasesJson => $composableBuilder(
    column: $table.phrasesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formsJson => $composableBuilder(
    column: $table.formsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get synonymsJson => $composableBuilder(
    column: $table.synonymsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get antonymsJson => $composableBuilder(
    column: $table.antonymsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordFamilyJson => $composableBuilder(
    column: $table.wordFamilyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confusedWordsJson => $composableBuilder(
    column: $table.confusedWordsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootsJson => $composableBuilder(
    column: $table.rootsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get affixesJson => $composableBuilder(
    column: $table.affixesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get learningJson => $composableBuilder(
    column: $table.learningJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sentenceAnalysisJson => $composableBuilder(
    column: $table.sentenceAnalysisJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerMetadataJson => $composableBuilder(
    column: $table.providerMetadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentSource => $composableBuilder(
    column: $table.contentSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get initializedAt => $composableBuilder(
    column: $table.initializedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WordContentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WordContentsTable> {
  $$WordContentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get definitionsJson => $composableBuilder(
    column: $table.definitionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pronunciationsJson => $composableBuilder(
    column: $table.pronunciationsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get examplesJson => $composableBuilder(
    column: $table.examplesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get phrasesJson => $composableBuilder(
    column: $table.phrasesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get formsJson =>
      $composableBuilder(column: $table.formsJson, builder: (column) => column);

  GeneratedColumn<String> get synonymsJson => $composableBuilder(
    column: $table.synonymsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get antonymsJson => $composableBuilder(
    column: $table.antonymsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wordFamilyJson => $composableBuilder(
    column: $table.wordFamilyJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get confusedWordsJson => $composableBuilder(
    column: $table.confusedWordsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rootsJson =>
      $composableBuilder(column: $table.rootsJson, builder: (column) => column);

  GeneratedColumn<String> get affixesJson => $composableBuilder(
    column: $table.affixesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get learningJson => $composableBuilder(
    column: $table.learningJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sentenceAnalysisJson => $composableBuilder(
    column: $table.sentenceAnalysisJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get providerMetadataJson => $composableBuilder(
    column: $table.providerMetadataJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ContentSource, String> get contentSource =>
      $composableBuilder(
        column: $table.contentSource,
        builder: (column) => column,
      );

  GeneratedColumn<int> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get initializedAt => $composableBuilder(
    column: $table.initializedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WordContentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WordContentsTable,
          WordContentRow,
          $$WordContentsTableFilterComposer,
          $$WordContentsTableOrderingComposer,
          $$WordContentsTableAnnotationComposer,
          $$WordContentsTableCreateCompanionBuilder,
          $$WordContentsTableUpdateCompanionBuilder,
          (WordContentRow, $$WordContentsTableReferences),
          WordContentRow,
          PrefetchHooks Function({bool wordId})
        > {
  $$WordContentsTableTableManager(_$AppDatabase db, $WordContentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WordContentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WordContentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WordContentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<String> definitionsJson = const Value.absent(),
                Value<String> pronunciationsJson = const Value.absent(),
                Value<String> examplesJson = const Value.absent(),
                Value<String> phrasesJson = const Value.absent(),
                Value<String> formsJson = const Value.absent(),
                Value<String> synonymsJson = const Value.absent(),
                Value<String> antonymsJson = const Value.absent(),
                Value<String> wordFamilyJson = const Value.absent(),
                Value<String> confusedWordsJson = const Value.absent(),
                Value<String> rootsJson = const Value.absent(),
                Value<String> affixesJson = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<String> learningJson = const Value.absent(),
                Value<String> sentenceAnalysisJson = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> providerMetadataJson = const Value.absent(),
                Value<ContentSource> contentSource = const Value.absent(),
                Value<int> contentVersion = const Value.absent(),
                Value<int?> initializedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => WordContentsCompanion(
                wordId: wordId,
                definitionsJson: definitionsJson,
                pronunciationsJson: pronunciationsJson,
                examplesJson: examplesJson,
                phrasesJson: phrasesJson,
                formsJson: formsJson,
                synonymsJson: synonymsJson,
                antonymsJson: antonymsJson,
                wordFamilyJson: wordFamilyJson,
                confusedWordsJson: confusedWordsJson,
                rootsJson: rootsJson,
                affixesJson: affixesJson,
                summaryJson: summaryJson,
                learningJson: learningJson,
                sentenceAnalysisJson: sentenceAnalysisJson,
                tagsJson: tagsJson,
                providerMetadataJson: providerMetadataJson,
                contentSource: contentSource,
                contentVersion: contentVersion,
                initializedAt: initializedAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<String> definitionsJson = const Value.absent(),
                Value<String> pronunciationsJson = const Value.absent(),
                Value<String> examplesJson = const Value.absent(),
                Value<String> phrasesJson = const Value.absent(),
                Value<String> formsJson = const Value.absent(),
                Value<String> synonymsJson = const Value.absent(),
                Value<String> antonymsJson = const Value.absent(),
                Value<String> wordFamilyJson = const Value.absent(),
                Value<String> confusedWordsJson = const Value.absent(),
                Value<String> rootsJson = const Value.absent(),
                Value<String> affixesJson = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<String> learningJson = const Value.absent(),
                Value<String> sentenceAnalysisJson = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> providerMetadataJson = const Value.absent(),
                Value<ContentSource> contentSource = const Value.absent(),
                Value<int> contentVersion = const Value.absent(),
                Value<int?> initializedAt = const Value.absent(),
                required int updatedAt,
              }) => WordContentsCompanion.insert(
                wordId: wordId,
                definitionsJson: definitionsJson,
                pronunciationsJson: pronunciationsJson,
                examplesJson: examplesJson,
                phrasesJson: phrasesJson,
                formsJson: formsJson,
                synonymsJson: synonymsJson,
                antonymsJson: antonymsJson,
                wordFamilyJson: wordFamilyJson,
                confusedWordsJson: confusedWordsJson,
                rootsJson: rootsJson,
                affixesJson: affixesJson,
                summaryJson: summaryJson,
                learningJson: learningJson,
                sentenceAnalysisJson: sentenceAnalysisJson,
                tagsJson: tagsJson,
                providerMetadataJson: providerMetadataJson,
                contentSource: contentSource,
                contentVersion: contentVersion,
                initializedAt: initializedAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WordContentsTable, WordContentRow>(table),
                  $$WordContentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({wordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (wordId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.wordId,
                        referencedTable: $$WordContentsTableReferences
                            ._wordIdTable(db),
                        referencedColumn: $$WordContentsTableReferences
                            ._wordIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WordContentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WordContentsTable,
      WordContentRow,
      $$WordContentsTableFilterComposer,
      $$WordContentsTableOrderingComposer,
      $$WordContentsTableAnnotationComposer,
      $$WordContentsTableCreateCompanionBuilder,
      $$WordContentsTableUpdateCompanionBuilder,
      (WordContentRow, $$WordContentsTableReferences),
      WordContentRow,
      PrefetchHooks Function({bool wordId})
    >;
typedef $$WordReviewStatsTableCreateCompanionBuilder =
    WordReviewStatsCompanion Function({
      Value<int> wordId,
      Value<int> totalReviews,
      Value<int> correctReviews,
      Value<int> recentAgain30d,
      Value<int> recentAgain14d,
      Value<int> recentWrong14d,
      Value<int> recentHard14d,
      Value<int> totalDurationMs,
      Value<int> durationCount,
      Value<int?> lastReviewedAt,
      Value<int> updatedAt,
    });
typedef $$WordReviewStatsTableUpdateCompanionBuilder =
    WordReviewStatsCompanion Function({
      Value<int> wordId,
      Value<int> totalReviews,
      Value<int> correctReviews,
      Value<int> recentAgain30d,
      Value<int> recentAgain14d,
      Value<int> recentWrong14d,
      Value<int> recentHard14d,
      Value<int> totalDurationMs,
      Value<int> durationCount,
      Value<int?> lastReviewedAt,
      Value<int> updatedAt,
    });

final class $$WordReviewStatsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $WordReviewStatsTable,
          WordReviewStatRow
        > {
  $$WordReviewStatsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('word_review_stats__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WordReviewStatsTableFilterComposer
    extends Composer<_$AppDatabase, $WordReviewStatsTable> {
  $$WordReviewStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get totalReviews => $composableBuilder(
    column: $table.totalReviews,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get correctReviews => $composableBuilder(
    column: $table.correctReviews,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recentAgain30d => $composableBuilder(
    column: $table.recentAgain30d,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recentAgain14d => $composableBuilder(
    column: $table.recentAgain14d,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recentWrong14d => $composableBuilder(
    column: $table.recentWrong14d,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recentHard14d => $composableBuilder(
    column: $table.recentHard14d,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalDurationMs => $composableBuilder(
    column: $table.totalDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationCount => $composableBuilder(
    column: $table.durationCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WordReviewStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $WordReviewStatsTable> {
  $$WordReviewStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get totalReviews => $composableBuilder(
    column: $table.totalReviews,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get correctReviews => $composableBuilder(
    column: $table.correctReviews,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recentAgain30d => $composableBuilder(
    column: $table.recentAgain30d,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recentAgain14d => $composableBuilder(
    column: $table.recentAgain14d,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recentWrong14d => $composableBuilder(
    column: $table.recentWrong14d,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recentHard14d => $composableBuilder(
    column: $table.recentHard14d,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalDurationMs => $composableBuilder(
    column: $table.totalDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationCount => $composableBuilder(
    column: $table.durationCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WordReviewStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WordReviewStatsTable> {
  $$WordReviewStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get totalReviews => $composableBuilder(
    column: $table.totalReviews,
    builder: (column) => column,
  );

  GeneratedColumn<int> get correctReviews => $composableBuilder(
    column: $table.correctReviews,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recentAgain30d => $composableBuilder(
    column: $table.recentAgain30d,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recentAgain14d => $composableBuilder(
    column: $table.recentAgain14d,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recentWrong14d => $composableBuilder(
    column: $table.recentWrong14d,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recentHard14d => $composableBuilder(
    column: $table.recentHard14d,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalDurationMs => $composableBuilder(
    column: $table.totalDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationCount => $composableBuilder(
    column: $table.durationCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReviewedAt => $composableBuilder(
    column: $table.lastReviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WordReviewStatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WordReviewStatsTable,
          WordReviewStatRow,
          $$WordReviewStatsTableFilterComposer,
          $$WordReviewStatsTableOrderingComposer,
          $$WordReviewStatsTableAnnotationComposer,
          $$WordReviewStatsTableCreateCompanionBuilder,
          $$WordReviewStatsTableUpdateCompanionBuilder,
          (WordReviewStatRow, $$WordReviewStatsTableReferences),
          WordReviewStatRow,
          PrefetchHooks Function({bool wordId})
        > {
  $$WordReviewStatsTableTableManager(
    _$AppDatabase db,
    $WordReviewStatsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WordReviewStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WordReviewStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WordReviewStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<int> totalReviews = const Value.absent(),
                Value<int> correctReviews = const Value.absent(),
                Value<int> recentAgain30d = const Value.absent(),
                Value<int> recentAgain14d = const Value.absent(),
                Value<int> recentWrong14d = const Value.absent(),
                Value<int> recentHard14d = const Value.absent(),
                Value<int> totalDurationMs = const Value.absent(),
                Value<int> durationCount = const Value.absent(),
                Value<int?> lastReviewedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => WordReviewStatsCompanion(
                wordId: wordId,
                totalReviews: totalReviews,
                correctReviews: correctReviews,
                recentAgain30d: recentAgain30d,
                recentAgain14d: recentAgain14d,
                recentWrong14d: recentWrong14d,
                recentHard14d: recentHard14d,
                totalDurationMs: totalDurationMs,
                durationCount: durationCount,
                lastReviewedAt: lastReviewedAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<int> totalReviews = const Value.absent(),
                Value<int> correctReviews = const Value.absent(),
                Value<int> recentAgain30d = const Value.absent(),
                Value<int> recentAgain14d = const Value.absent(),
                Value<int> recentWrong14d = const Value.absent(),
                Value<int> recentHard14d = const Value.absent(),
                Value<int> totalDurationMs = const Value.absent(),
                Value<int> durationCount = const Value.absent(),
                Value<int?> lastReviewedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => WordReviewStatsCompanion.insert(
                wordId: wordId,
                totalReviews: totalReviews,
                correctReviews: correctReviews,
                recentAgain30d: recentAgain30d,
                recentAgain14d: recentAgain14d,
                recentWrong14d: recentWrong14d,
                recentHard14d: recentHard14d,
                totalDurationMs: totalDurationMs,
                durationCount: durationCount,
                lastReviewedAt: lastReviewedAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WordReviewStatsTable, WordReviewStatRow>(table),
                  $$WordReviewStatsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({wordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (wordId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.wordId,
                        referencedTable: $$WordReviewStatsTableReferences
                            ._wordIdTable(db),
                        referencedColumn: $$WordReviewStatsTableReferences
                            ._wordIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WordReviewStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WordReviewStatsTable,
      WordReviewStatRow,
      $$WordReviewStatsTableFilterComposer,
      $$WordReviewStatsTableOrderingComposer,
      $$WordReviewStatsTableAnnotationComposer,
      $$WordReviewStatsTableCreateCompanionBuilder,
      $$WordReviewStatsTableUpdateCompanionBuilder,
      (WordReviewStatRow, $$WordReviewStatsTableReferences),
      WordReviewStatRow,
      PrefetchHooks Function({bool wordId})
    >;
typedef $$StudySessionsTableCreateCompanionBuilder =
    StudySessionsCompanion Function({
      Value<int> id,
      required StudyMode sessionType,
      Value<String?> sourceType,
      required int startedAt,
      Value<int?> completedAt,
      Value<int> plannedCount,
      Value<int> completedCount,
      Value<int> correctCount,
      Value<int> wrongCount,
      Value<int> skippedCount,
      Value<int?> durationMs,
      required int createdAt,
    });
typedef $$StudySessionsTableUpdateCompanionBuilder =
    StudySessionsCompanion Function({
      Value<int> id,
      Value<StudyMode> sessionType,
      Value<String?> sourceType,
      Value<int> startedAt,
      Value<int?> completedAt,
      Value<int> plannedCount,
      Value<int> completedCount,
      Value<int> correctCount,
      Value<int> wrongCount,
      Value<int> skippedCount,
      Value<int?> durationMs,
      Value<int> createdAt,
    });

final class $$StudySessionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $StudySessionsTable, StudySessionRow> {
  $$StudySessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$StudySessionItemsTable, List<StudySessionItemRow>>
  _studySessionItemsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.studySessionItems,
        aliasName: 'study_sessions__id__study_session_items__study_session_id',
      );

  $$StudySessionItemsTableProcessedTableManager get studySessionItemsRefs {
    final manager = $$StudySessionItemsTableTableManager(
      $_db,
      $_db.studySessionItems,
    ).filter((f) => f.studySessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _studySessionItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewLogsTable, List<ReviewLogRow>>
  _reviewLogsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewLogs,
    aliasName: 'study_sessions__id__review_logs__study_session_id',
  );

  $$ReviewLogsTableProcessedTableManager get reviewLogsRefs {
    final manager = $$ReviewLogsTableTableManager(
      $_db,
      $_db.reviewLogs,
    ).filter((f) => f.studySessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$StudySessionsTableFilterComposer
    extends Composer<_$AppDatabase, $StudySessionsTable> {
  $$StudySessionsTableFilterComposer({
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

  ColumnWithTypeConverterFilters<StudyMode, StudyMode, String>
  get sessionType => $composableBuilder(
    column: $table.sessionType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedCount => $composableBuilder(
    column: $table.plannedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedCount => $composableBuilder(
    column: $table.completedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skippedCount => $composableBuilder(
    column: $table.skippedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> studySessionItemsRefs(
    Expression<bool> Function($$StudySessionItemsTableFilterComposer f) f,
  ) {
    final $$StudySessionItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.studySessionItems,
      getReferencedColumn: (t) => t.studySessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionItemsTableFilterComposer(
            $db: $db,
            $table: $db.studySessionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewLogsRefs(
    Expression<bool> Function($$ReviewLogsTableFilterComposer f) f,
  ) {
    final $$ReviewLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewLogs,
      getReferencedColumn: (t) => t.studySessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewLogsTableFilterComposer(
            $db: $db,
            $table: $db.reviewLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StudySessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $StudySessionsTable> {
  $$StudySessionsTableOrderingComposer({
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

  ColumnOrderings<String> get sessionType => $composableBuilder(
    column: $table.sessionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedCount => $composableBuilder(
    column: $table.plannedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedCount => $composableBuilder(
    column: $table.completedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skippedCount => $composableBuilder(
    column: $table.skippedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StudySessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StudySessionsTable> {
  $$StudySessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<StudyMode, String> get sessionType =>
      $composableBuilder(
        column: $table.sessionType,
        builder: (column) => column,
      );

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedCount => $composableBuilder(
    column: $table.plannedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedCount => $composableBuilder(
    column: $table.completedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get skippedCount => $composableBuilder(
    column: $table.skippedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> studySessionItemsRefs<T extends Object>(
    Expression<T> Function($$StudySessionItemsTableAnnotationComposer a) f,
  ) {
    final $$StudySessionItemsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.studySessionItems,
          getReferencedColumn: (t) => t.studySessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StudySessionItemsTableAnnotationComposer(
                $db: $db,
                $table: $db.studySessionItems,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> reviewLogsRefs<T extends Object>(
    Expression<T> Function($$ReviewLogsTableAnnotationComposer a) f,
  ) {
    final $$ReviewLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewLogs,
      getReferencedColumn: (t) => t.studySessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StudySessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StudySessionsTable,
          StudySessionRow,
          $$StudySessionsTableFilterComposer,
          $$StudySessionsTableOrderingComposer,
          $$StudySessionsTableAnnotationComposer,
          $$StudySessionsTableCreateCompanionBuilder,
          $$StudySessionsTableUpdateCompanionBuilder,
          (StudySessionRow, $$StudySessionsTableReferences),
          StudySessionRow,
          PrefetchHooks Function({
            bool studySessionItemsRefs,
            bool reviewLogsRefs,
          })
        > {
  $$StudySessionsTableTableManager(_$AppDatabase db, $StudySessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StudySessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StudySessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StudySessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<StudyMode> sessionType = const Value.absent(),
                Value<String?> sourceType = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int?> completedAt = const Value.absent(),
                Value<int> plannedCount = const Value.absent(),
                Value<int> completedCount = const Value.absent(),
                Value<int> correctCount = const Value.absent(),
                Value<int> wrongCount = const Value.absent(),
                Value<int> skippedCount = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => StudySessionsCompanion(
                id: id,
                sessionType: sessionType,
                sourceType: sourceType,
                startedAt: startedAt,
                completedAt: completedAt,
                plannedCount: plannedCount,
                completedCount: completedCount,
                correctCount: correctCount,
                wrongCount: wrongCount,
                skippedCount: skippedCount,
                durationMs: durationMs,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required StudyMode sessionType,
                Value<String?> sourceType = const Value.absent(),
                required int startedAt,
                Value<int?> completedAt = const Value.absent(),
                Value<int> plannedCount = const Value.absent(),
                Value<int> completedCount = const Value.absent(),
                Value<int> correctCount = const Value.absent(),
                Value<int> wrongCount = const Value.absent(),
                Value<int> skippedCount = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                required int createdAt,
              }) => StudySessionsCompanion.insert(
                id: id,
                sessionType: sessionType,
                sourceType: sourceType,
                startedAt: startedAt,
                completedAt: completedAt,
                plannedCount: plannedCount,
                completedCount: completedCount,
                correctCount: correctCount,
                wrongCount: wrongCount,
                skippedCount: skippedCount,
                durationMs: durationMs,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StudySessionsTable, StudySessionRow>(table),
                  $$StudySessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({studySessionItemsRefs = false, reviewLogsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (studySessionItemsRefs) db.studySessionItems,
                    if (reviewLogsRefs) db.reviewLogs,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (studySessionItemsRefs)
                        await $_getPrefetchedData<
                          StudySessionRow,
                          $StudySessionsTable,
                          StudySessionItemRow
                        >(
                          currentTable: table,
                          referencedTable: $$StudySessionsTableReferences
                              ._studySessionItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$StudySessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).studySessionItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.studySessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewLogsRefs)
                        await $_getPrefetchedData<
                          StudySessionRow,
                          $StudySessionsTable,
                          ReviewLogRow
                        >(
                          currentTable: table,
                          referencedTable: $$StudySessionsTableReferences
                              ._reviewLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$StudySessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.studySessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$StudySessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StudySessionsTable,
      StudySessionRow,
      $$StudySessionsTableFilterComposer,
      $$StudySessionsTableOrderingComposer,
      $$StudySessionsTableAnnotationComposer,
      $$StudySessionsTableCreateCompanionBuilder,
      $$StudySessionsTableUpdateCompanionBuilder,
      (StudySessionRow, $$StudySessionsTableReferences),
      StudySessionRow,
      PrefetchHooks Function({bool studySessionItemsRefs, bool reviewLogsRefs})
    >;
typedef $$StudySessionItemsTableCreateCompanionBuilder =
    StudySessionItemsCompanion Function({
      Value<int> id,
      required int studySessionId,
      required double position,
      required int wordId,
      required StudyTaskType taskType,
      required QuestionType questionType,
      Value<StudyItemStatus> status,
      Value<int?> answeredAt,
      Value<String?> skipReason,
      required int createdAt,
    });
typedef $$StudySessionItemsTableUpdateCompanionBuilder =
    StudySessionItemsCompanion Function({
      Value<int> id,
      Value<int> studySessionId,
      Value<double> position,
      Value<int> wordId,
      Value<StudyTaskType> taskType,
      Value<QuestionType> questionType,
      Value<StudyItemStatus> status,
      Value<int?> answeredAt,
      Value<String?> skipReason,
      Value<int> createdAt,
    });

final class $$StudySessionItemsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $StudySessionItemsTable,
          StudySessionItemRow
        > {
  $$StudySessionItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $StudySessionsTable _studySessionIdTable(_$AppDatabase db) => db
      .studySessions
      .createAlias('study_session_items__study_session_id__study_sessions__id');

  $$StudySessionsTableProcessedTableManager get studySessionId {
    final $_column = $_itemColumn<int>('study_session_id')!;

    final manager = $$StudySessionsTableTableManager(
      $_db,
      $_db.studySessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_studySessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('study_session_items__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ReviewLogsTable, List<ReviewLogRow>>
  _reviewLogsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewLogs,
    aliasName: 'study_session_items__id__review_logs__study_session_item_id',
  );

  $$ReviewLogsTableProcessedTableManager get reviewLogsRefs {
    final manager = $$ReviewLogsTableTableManager($_db, $_db.reviewLogs).filter(
      (f) => f.studySessionItemId.id.sqlEquals($_itemColumn<int>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_reviewLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$StudySessionItemsTableFilterComposer
    extends Composer<_$AppDatabase, $StudySessionItemsTable> {
  $$StudySessionItemsTableFilterComposer({
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

  ColumnFilters<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<StudyTaskType, StudyTaskType, String>
  get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<QuestionType, QuestionType, String>
  get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<StudyItemStatus, StudyItemStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get answeredAt => $composableBuilder(
    column: $table.answeredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skipReason => $composableBuilder(
    column: $table.skipReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$StudySessionsTableFilterComposer get studySessionId {
    final $$StudySessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionId,
      referencedTable: $db.studySessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionsTableFilterComposer(
            $db: $db,
            $table: $db.studySessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> reviewLogsRefs(
    Expression<bool> Function($$ReviewLogsTableFilterComposer f) f,
  ) {
    final $$ReviewLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewLogs,
      getReferencedColumn: (t) => t.studySessionItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewLogsTableFilterComposer(
            $db: $db,
            $table: $db.reviewLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StudySessionItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $StudySessionItemsTable> {
  $$StudySessionItemsTableOrderingComposer({
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

  ColumnOrderings<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get answeredAt => $composableBuilder(
    column: $table.answeredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skipReason => $composableBuilder(
    column: $table.skipReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$StudySessionsTableOrderingComposer get studySessionId {
    final $$StudySessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionId,
      referencedTable: $db.studySessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionsTableOrderingComposer(
            $db: $db,
            $table: $db.studySessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StudySessionItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StudySessionItemsTable> {
  $$StudySessionItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumnWithTypeConverter<StudyTaskType, String> get taskType =>
      $composableBuilder(column: $table.taskType, builder: (column) => column);

  GeneratedColumnWithTypeConverter<QuestionType, String> get questionType =>
      $composableBuilder(
        column: $table.questionType,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<StudyItemStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get answeredAt => $composableBuilder(
    column: $table.answeredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get skipReason => $composableBuilder(
    column: $table.skipReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$StudySessionsTableAnnotationComposer get studySessionId {
    final $$StudySessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionId,
      referencedTable: $db.studySessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.studySessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> reviewLogsRefs<T extends Object>(
    Expression<T> Function($$ReviewLogsTableAnnotationComposer a) f,
  ) {
    final $$ReviewLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewLogs,
      getReferencedColumn: (t) => t.studySessionItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StudySessionItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StudySessionItemsTable,
          StudySessionItemRow,
          $$StudySessionItemsTableFilterComposer,
          $$StudySessionItemsTableOrderingComposer,
          $$StudySessionItemsTableAnnotationComposer,
          $$StudySessionItemsTableCreateCompanionBuilder,
          $$StudySessionItemsTableUpdateCompanionBuilder,
          (StudySessionItemRow, $$StudySessionItemsTableReferences),
          StudySessionItemRow,
          PrefetchHooks Function({
            bool studySessionId,
            bool wordId,
            bool reviewLogsRefs,
          })
        > {
  $$StudySessionItemsTableTableManager(
    _$AppDatabase db,
    $StudySessionItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StudySessionItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StudySessionItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StudySessionItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> studySessionId = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<int> wordId = const Value.absent(),
                Value<StudyTaskType> taskType = const Value.absent(),
                Value<QuestionType> questionType = const Value.absent(),
                Value<StudyItemStatus> status = const Value.absent(),
                Value<int?> answeredAt = const Value.absent(),
                Value<String?> skipReason = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => StudySessionItemsCompanion(
                id: id,
                studySessionId: studySessionId,
                position: position,
                wordId: wordId,
                taskType: taskType,
                questionType: questionType,
                status: status,
                answeredAt: answeredAt,
                skipReason: skipReason,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int studySessionId,
                required double position,
                required int wordId,
                required StudyTaskType taskType,
                required QuestionType questionType,
                Value<StudyItemStatus> status = const Value.absent(),
                Value<int?> answeredAt = const Value.absent(),
                Value<String?> skipReason = const Value.absent(),
                required int createdAt,
              }) => StudySessionItemsCompanion.insert(
                id: id,
                studySessionId: studySessionId,
                position: position,
                wordId: wordId,
                taskType: taskType,
                questionType: questionType,
                status: status,
                answeredAt: answeredAt,
                skipReason: skipReason,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StudySessionItemsTable, StudySessionItemRow>(
                    table,
                  ),
                  $$StudySessionItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                studySessionId = false,
                wordId = false,
                reviewLogsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (reviewLogsRefs) db.reviewLogs],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (studySessionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.studySessionId,
                            referencedTable: $$StudySessionItemsTableReferences
                                ._studySessionIdTable(db),
                            referencedColumn: $$StudySessionItemsTableReferences
                                ._studySessionIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (wordId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.wordId,
                            referencedTable: $$StudySessionItemsTableReferences
                                ._wordIdTable(db),
                            referencedColumn: $$StudySessionItemsTableReferences
                                ._wordIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (reviewLogsRefs)
                        await $_getPrefetchedData<
                          StudySessionItemRow,
                          $StudySessionItemsTable,
                          ReviewLogRow
                        >(
                          currentTable: table,
                          referencedTable: $$StudySessionItemsTableReferences
                              ._reviewLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$StudySessionItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.studySessionItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$StudySessionItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StudySessionItemsTable,
      StudySessionItemRow,
      $$StudySessionItemsTableFilterComposer,
      $$StudySessionItemsTableOrderingComposer,
      $$StudySessionItemsTableAnnotationComposer,
      $$StudySessionItemsTableCreateCompanionBuilder,
      $$StudySessionItemsTableUpdateCompanionBuilder,
      (StudySessionItemRow, $$StudySessionItemsTableReferences),
      StudySessionItemRow,
      PrefetchHooks Function({
        bool studySessionId,
        bool wordId,
        bool reviewLogsRefs,
      })
    >;
typedef $$ReviewCardsTableCreateCompanionBuilder =
    ReviewCardsCompanion Function({
      Value<int> wordId,
      required int dueAt,
      required double stability,
      required double difficulty,
      required int elapsedDays,
      required int scheduledDays,
      required int reps,
      required int lapses,
      required int fsrsState,
      Value<int> learningSteps,
      Value<int?> lastReviewAt,
      required int createdAt,
      required int updatedAt,
    });
typedef $$ReviewCardsTableUpdateCompanionBuilder =
    ReviewCardsCompanion Function({
      Value<int> wordId,
      Value<int> dueAt,
      Value<double> stability,
      Value<double> difficulty,
      Value<int> elapsedDays,
      Value<int> scheduledDays,
      Value<int> reps,
      Value<int> lapses,
      Value<int> fsrsState,
      Value<int> learningSteps,
      Value<int?> lastReviewAt,
      Value<int> createdAt,
      Value<int> updatedAt,
    });

final class $$ReviewCardsTableReferences
    extends BaseReferences<_$AppDatabase, $ReviewCardsTable, ReviewCardRow> {
  $$ReviewCardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('review_cards__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewCardsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewCardsTable> {
  $$ReviewCardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedDays => $composableBuilder(
    column: $table.elapsedDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledDays => $composableBuilder(
    column: $table.scheduledDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fsrsState => $composableBuilder(
    column: $table.fsrsState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get learningSteps => $composableBuilder(
    column: $table.learningSteps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReviewAt => $composableBuilder(
    column: $table.lastReviewAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewCardsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewCardsTable> {
  $$ReviewCardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedDays => $composableBuilder(
    column: $table.elapsedDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledDays => $composableBuilder(
    column: $table.scheduledDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fsrsState => $composableBuilder(
    column: $table.fsrsState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get learningSteps => $composableBuilder(
    column: $table.learningSteps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReviewAt => $composableBuilder(
    column: $table.lastReviewAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewCardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewCardsTable> {
  $$ReviewCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<double> get stability =>
      $composableBuilder(column: $table.stability, builder: (column) => column);

  GeneratedColumn<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get elapsedDays => $composableBuilder(
    column: $table.elapsedDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scheduledDays => $composableBuilder(
    column: $table.scheduledDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reps =>
      $composableBuilder(column: $table.reps, builder: (column) => column);

  GeneratedColumn<int> get lapses =>
      $composableBuilder(column: $table.lapses, builder: (column) => column);

  GeneratedColumn<int> get fsrsState =>
      $composableBuilder(column: $table.fsrsState, builder: (column) => column);

  GeneratedColumn<int> get learningSteps => $composableBuilder(
    column: $table.learningSteps,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReviewAt => $composableBuilder(
    column: $table.lastReviewAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewCardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewCardsTable,
          ReviewCardRow,
          $$ReviewCardsTableFilterComposer,
          $$ReviewCardsTableOrderingComposer,
          $$ReviewCardsTableAnnotationComposer,
          $$ReviewCardsTableCreateCompanionBuilder,
          $$ReviewCardsTableUpdateCompanionBuilder,
          (ReviewCardRow, $$ReviewCardsTableReferences),
          ReviewCardRow,
          PrefetchHooks Function({bool wordId})
        > {
  $$ReviewCardsTableTableManager(_$AppDatabase db, $ReviewCardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<int> dueAt = const Value.absent(),
                Value<double> stability = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int> elapsedDays = const Value.absent(),
                Value<int> scheduledDays = const Value.absent(),
                Value<int> reps = const Value.absent(),
                Value<int> lapses = const Value.absent(),
                Value<int> fsrsState = const Value.absent(),
                Value<int> learningSteps = const Value.absent(),
                Value<int?> lastReviewAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => ReviewCardsCompanion(
                wordId: wordId,
                dueAt: dueAt,
                stability: stability,
                difficulty: difficulty,
                elapsedDays: elapsedDays,
                scheduledDays: scheduledDays,
                reps: reps,
                lapses: lapses,
                fsrsState: fsrsState,
                learningSteps: learningSteps,
                lastReviewAt: lastReviewAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                required int dueAt,
                required double stability,
                required double difficulty,
                required int elapsedDays,
                required int scheduledDays,
                required int reps,
                required int lapses,
                required int fsrsState,
                Value<int> learningSteps = const Value.absent(),
                Value<int?> lastReviewAt = const Value.absent(),
                required int createdAt,
                required int updatedAt,
              }) => ReviewCardsCompanion.insert(
                wordId: wordId,
                dueAt: dueAt,
                stability: stability,
                difficulty: difficulty,
                elapsedDays: elapsedDays,
                scheduledDays: scheduledDays,
                reps: reps,
                lapses: lapses,
                fsrsState: fsrsState,
                learningSteps: learningSteps,
                lastReviewAt: lastReviewAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewCardsTable, ReviewCardRow>(table),
                  $$ReviewCardsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({wordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (wordId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.wordId,
                        referencedTable: $$ReviewCardsTableReferences
                            ._wordIdTable(db),
                        referencedColumn: $$ReviewCardsTableReferences
                            ._wordIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReviewCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewCardsTable,
      ReviewCardRow,
      $$ReviewCardsTableFilterComposer,
      $$ReviewCardsTableOrderingComposer,
      $$ReviewCardsTableAnnotationComposer,
      $$ReviewCardsTableCreateCompanionBuilder,
      $$ReviewCardsTableUpdateCompanionBuilder,
      (ReviewCardRow, $$ReviewCardsTableReferences),
      ReviewCardRow,
      PrefetchHooks Function({bool wordId})
    >;
typedef $$ReviewLogsTableCreateCompanionBuilder = ReviewLogsCompanion Function({
  Value<int> id,
  required String clientAnswerId,
  required int wordId,
  Value<int?> studySessionId,
  Value<int?> studySessionItemId,
  required int reviewedAt,
  required ReviewRating rating,
  required QuestionType questionType,
  Value<String?> presentedPrompt,
  Value<String?> userAnswer,
  Value<String?> expectedAnswer,
  required bool isCorrect,
  Value<int?> durationMs,
  Value<String?> cardBeforeJson,
  Value<String?> cardAfterJson,
  required int createdAt,
});
typedef $$ReviewLogsTableUpdateCompanionBuilder = ReviewLogsCompanion Function({
  Value<int> id,
  Value<String> clientAnswerId,
  Value<int> wordId,
  Value<int?> studySessionId,
  Value<int?> studySessionItemId,
  Value<int> reviewedAt,
  Value<ReviewRating> rating,
  Value<QuestionType> questionType,
  Value<String?> presentedPrompt,
  Value<String?> userAnswer,
  Value<String?> expectedAnswer,
  Value<bool> isCorrect,
  Value<int?> durationMs,
  Value<String?> cardBeforeJson,
  Value<String?> cardAfterJson,
  Value<int> createdAt,
});

final class $$ReviewLogsTableReferences
    extends BaseReferences<_$AppDatabase, $ReviewLogsTable, ReviewLogRow> {
  $$ReviewLogsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('review_logs__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $StudySessionsTable _studySessionIdTable(_$AppDatabase db) => db
      .studySessions
      .createAlias('review_logs__study_session_id__study_sessions__id');

  $$StudySessionsTableProcessedTableManager? get studySessionId {
    final $_column = $_itemColumn<int>('study_session_id');
    if ($_column == null) return null;
    final manager = $$StudySessionsTableTableManager(
      $_db,
      $_db.studySessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_studySessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $StudySessionItemsTable _studySessionItemIdTable(_$AppDatabase db) =>
      db.studySessionItems.createAlias(
        'review_logs__study_session_item_id__study_session_items__id',
      );

  $$StudySessionItemsTableProcessedTableManager? get studySessionItemId {
    final $_column = $_itemColumn<int>('study_session_item_id');
    if ($_column == null) return null;
    final manager = $$StudySessionItemsTableTableManager(
      $_db,
      $_db.studySessionItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_studySessionItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableFilterComposer({
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

  ColumnFilters<String> get clientAnswerId => $composableBuilder(
    column: $table.clientAnswerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ReviewRating, ReviewRating, String>
  get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<QuestionType, QuestionType, String>
  get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get presentedPrompt => $composableBuilder(
    column: $table.presentedPrompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userAnswer => $composableBuilder(
    column: $table.userAnswer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedAnswer => $composableBuilder(
    column: $table.expectedAnswer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardBeforeJson => $composableBuilder(
    column: $table.cardBeforeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardAfterJson => $composableBuilder(
    column: $table.cardAfterJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StudySessionsTableFilterComposer get studySessionId {
    final $$StudySessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionId,
      referencedTable: $db.studySessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionsTableFilterComposer(
            $db: $db,
            $table: $db.studySessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StudySessionItemsTableFilterComposer get studySessionItemId {
    final $$StudySessionItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionItemId,
      referencedTable: $db.studySessionItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionItemsTableFilterComposer(
            $db: $db,
            $table: $db.studySessionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableOrderingComposer({
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

  ColumnOrderings<String> get clientAnswerId => $composableBuilder(
    column: $table.clientAnswerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presentedPrompt => $composableBuilder(
    column: $table.presentedPrompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userAnswer => $composableBuilder(
    column: $table.userAnswer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedAnswer => $composableBuilder(
    column: $table.expectedAnswer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardBeforeJson => $composableBuilder(
    column: $table.cardBeforeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardAfterJson => $composableBuilder(
    column: $table.cardAfterJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StudySessionsTableOrderingComposer get studySessionId {
    final $$StudySessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionId,
      referencedTable: $db.studySessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionsTableOrderingComposer(
            $db: $db,
            $table: $db.studySessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StudySessionItemsTableOrderingComposer get studySessionItemId {
    final $$StudySessionItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionItemId,
      referencedTable: $db.studySessionItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionItemsTableOrderingComposer(
            $db: $db,
            $table: $db.studySessionItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientAnswerId => $composableBuilder(
    column: $table.clientAnswerId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ReviewRating, String> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumnWithTypeConverter<QuestionType, String> get questionType =>
      $composableBuilder(
        column: $table.questionType,
        builder: (column) => column,
      );

  GeneratedColumn<String> get presentedPrompt => $composableBuilder(
    column: $table.presentedPrompt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userAnswer => $composableBuilder(
    column: $table.userAnswer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expectedAnswer => $composableBuilder(
    column: $table.expectedAnswer,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCorrect =>
      $composableBuilder(column: $table.isCorrect, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardBeforeJson => $composableBuilder(
    column: $table.cardBeforeJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardAfterJson => $composableBuilder(
    column: $table.cardAfterJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StudySessionsTableAnnotationComposer get studySessionId {
    final $$StudySessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.studySessionId,
      referencedTable: $db.studySessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StudySessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.studySessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StudySessionItemsTableAnnotationComposer get studySessionItemId {
    final $$StudySessionItemsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.studySessionItemId,
          referencedTable: $db.studySessionItems,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$StudySessionItemsTableAnnotationComposer(
                $db: $db,
                $table: $db.studySessionItems,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ReviewLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewLogsTable,
          ReviewLogRow,
          $$ReviewLogsTableFilterComposer,
          $$ReviewLogsTableOrderingComposer,
          $$ReviewLogsTableAnnotationComposer,
          $$ReviewLogsTableCreateCompanionBuilder,
          $$ReviewLogsTableUpdateCompanionBuilder,
          (ReviewLogRow, $$ReviewLogsTableReferences),
          ReviewLogRow,
          PrefetchHooks Function({
            bool wordId,
            bool studySessionId,
            bool studySessionItemId,
          })
        > {
  $$ReviewLogsTableTableManager(_$AppDatabase db, $ReviewLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> clientAnswerId = const Value.absent(),
                Value<int> wordId = const Value.absent(),
                Value<int?> studySessionId = const Value.absent(),
                Value<int?> studySessionItemId = const Value.absent(),
                Value<int> reviewedAt = const Value.absent(),
                Value<ReviewRating> rating = const Value.absent(),
                Value<QuestionType> questionType = const Value.absent(),
                Value<String?> presentedPrompt = const Value.absent(),
                Value<String?> userAnswer = const Value.absent(),
                Value<String?> expectedAnswer = const Value.absent(),
                Value<bool> isCorrect = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> cardBeforeJson = const Value.absent(),
                Value<String?> cardAfterJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => ReviewLogsCompanion(
                id: id,
                clientAnswerId: clientAnswerId,
                wordId: wordId,
                studySessionId: studySessionId,
                studySessionItemId: studySessionItemId,
                reviewedAt: reviewedAt,
                rating: rating,
                questionType: questionType,
                presentedPrompt: presentedPrompt,
                userAnswer: userAnswer,
                expectedAnswer: expectedAnswer,
                isCorrect: isCorrect,
                durationMs: durationMs,
                cardBeforeJson: cardBeforeJson,
                cardAfterJson: cardAfterJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String clientAnswerId,
                required int wordId,
                Value<int?> studySessionId = const Value.absent(),
                Value<int?> studySessionItemId = const Value.absent(),
                required int reviewedAt,
                required ReviewRating rating,
                required QuestionType questionType,
                Value<String?> presentedPrompt = const Value.absent(),
                Value<String?> userAnswer = const Value.absent(),
                Value<String?> expectedAnswer = const Value.absent(),
                required bool isCorrect,
                Value<int?> durationMs = const Value.absent(),
                Value<String?> cardBeforeJson = const Value.absent(),
                Value<String?> cardAfterJson = const Value.absent(),
                required int createdAt,
              }) => ReviewLogsCompanion.insert(
                id: id,
                clientAnswerId: clientAnswerId,
                wordId: wordId,
                studySessionId: studySessionId,
                studySessionItemId: studySessionItemId,
                reviewedAt: reviewedAt,
                rating: rating,
                questionType: questionType,
                presentedPrompt: presentedPrompt,
                userAnswer: userAnswer,
                expectedAnswer: expectedAnswer,
                isCorrect: isCorrect,
                durationMs: durationMs,
                cardBeforeJson: cardBeforeJson,
                cardAfterJson: cardAfterJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewLogsTable, ReviewLogRow>(table),
                  $$ReviewLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                wordId = false,
                studySessionId = false,
                studySessionItemId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (wordId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.wordId,
                            referencedTable: $$ReviewLogsTableReferences
                                ._wordIdTable(db),
                            referencedColumn: $$ReviewLogsTableReferences
                                ._wordIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (studySessionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.studySessionId,
                            referencedTable: $$ReviewLogsTableReferences
                                ._studySessionIdTable(db),
                            referencedColumn: $$ReviewLogsTableReferences
                                ._studySessionIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (studySessionItemId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.studySessionItemId,
                            referencedTable: $$ReviewLogsTableReferences
                                ._studySessionItemIdTable(db),
                            referencedColumn: $$ReviewLogsTableReferences
                                ._studySessionItemIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ReviewLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewLogsTable,
      ReviewLogRow,
      $$ReviewLogsTableFilterComposer,
      $$ReviewLogsTableOrderingComposer,
      $$ReviewLogsTableAnnotationComposer,
      $$ReviewLogsTableCreateCompanionBuilder,
      $$ReviewLogsTableUpdateCompanionBuilder,
      (ReviewLogRow, $$ReviewLogsTableReferences),
      ReviewLogRow,
      PrefetchHooks Function({
        bool wordId,
        bool studySessionId,
        bool studySessionItemId,
      })
    >;
typedef $$WrongWordStatesTableCreateCompanionBuilder =
    WrongWordStatesCompanion Function({
      Value<int> wordId,
      Value<bool> active,
      Value<int> wrongCount,
      Value<int> hardCount,
      Value<int> consecutiveCorrect,
      Value<int?> lastWrongAt,
      Value<int?> lastCorrectAt,
      Value<int?> resolvedAt,
      required int updatedAt,
    });
typedef $$WrongWordStatesTableUpdateCompanionBuilder =
    WrongWordStatesCompanion Function({
      Value<int> wordId,
      Value<bool> active,
      Value<int> wrongCount,
      Value<int> hardCount,
      Value<int> consecutiveCorrect,
      Value<int?> lastWrongAt,
      Value<int?> lastCorrectAt,
      Value<int?> resolvedAt,
      Value<int> updatedAt,
    });

final class $$WrongWordStatesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $WrongWordStatesTable,
          WrongWordStateRow
        > {
  $$WrongWordStatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('wrong_word_states__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WrongWordStatesTableFilterComposer
    extends Composer<_$AppDatabase, $WrongWordStatesTable> {
  $$WrongWordStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hardCount => $composableBuilder(
    column: $table.hardCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get consecutiveCorrect => $composableBuilder(
    column: $table.consecutiveCorrect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastWrongAt => $composableBuilder(
    column: $table.lastWrongAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCorrectAt => $composableBuilder(
    column: $table.lastCorrectAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WrongWordStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $WrongWordStatesTable> {
  $$WrongWordStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hardCount => $composableBuilder(
    column: $table.hardCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get consecutiveCorrect => $composableBuilder(
    column: $table.consecutiveCorrect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastWrongAt => $composableBuilder(
    column: $table.lastWrongAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCorrectAt => $composableBuilder(
    column: $table.lastCorrectAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WrongWordStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WrongWordStatesTable> {
  $$WrongWordStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hardCount =>
      $composableBuilder(column: $table.hardCount, builder: (column) => column);

  GeneratedColumn<int> get consecutiveCorrect => $composableBuilder(
    column: $table.consecutiveCorrect,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastWrongAt => $composableBuilder(
    column: $table.lastWrongAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCorrectAt => $composableBuilder(
    column: $table.lastCorrectAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WrongWordStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WrongWordStatesTable,
          WrongWordStateRow,
          $$WrongWordStatesTableFilterComposer,
          $$WrongWordStatesTableOrderingComposer,
          $$WrongWordStatesTableAnnotationComposer,
          $$WrongWordStatesTableCreateCompanionBuilder,
          $$WrongWordStatesTableUpdateCompanionBuilder,
          (WrongWordStateRow, $$WrongWordStatesTableReferences),
          WrongWordStateRow,
          PrefetchHooks Function({bool wordId})
        > {
  $$WrongWordStatesTableTableManager(
    _$AppDatabase db,
    $WrongWordStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WrongWordStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WrongWordStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WrongWordStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> wrongCount = const Value.absent(),
                Value<int> hardCount = const Value.absent(),
                Value<int> consecutiveCorrect = const Value.absent(),
                Value<int?> lastWrongAt = const Value.absent(),
                Value<int?> lastCorrectAt = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => WrongWordStatesCompanion(
                wordId: wordId,
                active: active,
                wrongCount: wrongCount,
                hardCount: hardCount,
                consecutiveCorrect: consecutiveCorrect,
                lastWrongAt: lastWrongAt,
                lastCorrectAt: lastCorrectAt,
                resolvedAt: resolvedAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> wordId = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> wrongCount = const Value.absent(),
                Value<int> hardCount = const Value.absent(),
                Value<int> consecutiveCorrect = const Value.absent(),
                Value<int?> lastWrongAt = const Value.absent(),
                Value<int?> lastCorrectAt = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
                required int updatedAt,
              }) => WrongWordStatesCompanion.insert(
                wordId: wordId,
                active: active,
                wrongCount: wrongCount,
                hardCount: hardCount,
                consecutiveCorrect: consecutiveCorrect,
                lastWrongAt: lastWrongAt,
                lastCorrectAt: lastCorrectAt,
                resolvedAt: resolvedAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WrongWordStatesTable, WrongWordStateRow>(table),
                  $$WrongWordStatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({wordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (wordId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.wordId,
                        referencedTable: $$WrongWordStatesTableReferences
                            ._wordIdTable(db),
                        referencedColumn: $$WrongWordStatesTableReferences
                            ._wordIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WrongWordStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WrongWordStatesTable,
      WrongWordStateRow,
      $$WrongWordStatesTableFilterComposer,
      $$WrongWordStatesTableOrderingComposer,
      $$WrongWordStatesTableAnnotationComposer,
      $$WrongWordStatesTableCreateCompanionBuilder,
      $$WrongWordStatesTableUpdateCompanionBuilder,
      (WrongWordStateRow, $$WrongWordStatesTableReferences),
      WrongWordStateRow,
      PrefetchHooks Function({bool wordId})
    >;
typedef $$ImportBatchesTableCreateCompanionBuilder =
    ImportBatchesCompanion Function({
      Value<int> id,
      required String filename,
      Value<String?> fileHash,
      required ImportMode importMode,
      Value<bool> resetLearningProgress,
      Value<int> totalRows,
      Value<int> validRows,
      Value<int> invalidRows,
      Value<int> duplicateRows,
      Value<int> createdWords,
      Value<int> existingWords,
      Value<int> queuedInitializations,
      Value<ImportBatchStatus> status,
      required int createdAt,
      Value<int?> completedAt,
      Value<int?> rolledBackAt,
    });
typedef $$ImportBatchesTableUpdateCompanionBuilder =
    ImportBatchesCompanion Function({
      Value<int> id,
      Value<String> filename,
      Value<String?> fileHash,
      Value<ImportMode> importMode,
      Value<bool> resetLearningProgress,
      Value<int> totalRows,
      Value<int> validRows,
      Value<int> invalidRows,
      Value<int> duplicateRows,
      Value<int> createdWords,
      Value<int> existingWords,
      Value<int> queuedInitializations,
      Value<ImportBatchStatus> status,
      Value<int> createdAt,
      Value<int?> completedAt,
      Value<int?> rolledBackAt,
    });

final class $$ImportBatchesTableReferences
    extends BaseReferences<_$AppDatabase, $ImportBatchesTable, ImportBatchRow> {
  $$ImportBatchesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ImportRowsTable, List<ImportRowRow>>
  _importRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.importRows,
    aliasName: 'import_batches__id__import_rows__import_batch_id',
  );

  $$ImportRowsTableProcessedTableManager get importRowsRefs {
    final manager = $$ImportRowsTableTableManager(
      $_db,
      $_db.importRows,
    ).filter((f) => f.importBatchId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_importRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ImportBatchesTableFilterComposer
    extends Composer<_$AppDatabase, $ImportBatchesTable> {
  $$ImportBatchesTableFilterComposer({
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

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ImportMode, ImportMode, String>
  get importMode => $composableBuilder(
    column: $table.importMode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get resetLearningProgress => $composableBuilder(
    column: $table.resetLearningProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalRows => $composableBuilder(
    column: $table.totalRows,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validRows => $composableBuilder(
    column: $table.validRows,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get invalidRows => $composableBuilder(
    column: $table.invalidRows,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duplicateRows => $composableBuilder(
    column: $table.duplicateRows,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdWords => $composableBuilder(
    column: $table.createdWords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get existingWords => $composableBuilder(
    column: $table.existingWords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queuedInitializations => $composableBuilder(
    column: $table.queuedInitializations,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ImportBatchStatus, ImportBatchStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rolledBackAt => $composableBuilder(
    column: $table.rolledBackAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> importRowsRefs(
    Expression<bool> Function($$ImportRowsTableFilterComposer f) f,
  ) {
    final $$ImportRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.importBatchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportRowsTableFilterComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ImportBatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportBatchesTable> {
  $$ImportBatchesTableOrderingComposer({
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

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importMode => $composableBuilder(
    column: $table.importMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get resetLearningProgress => $composableBuilder(
    column: $table.resetLearningProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalRows => $composableBuilder(
    column: $table.totalRows,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validRows => $composableBuilder(
    column: $table.validRows,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get invalidRows => $composableBuilder(
    column: $table.invalidRows,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duplicateRows => $composableBuilder(
    column: $table.duplicateRows,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdWords => $composableBuilder(
    column: $table.createdWords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get existingWords => $composableBuilder(
    column: $table.existingWords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queuedInitializations => $composableBuilder(
    column: $table.queuedInitializations,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rolledBackAt => $composableBuilder(
    column: $table.rolledBackAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportBatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportBatchesTable> {
  $$ImportBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get fileHash =>
      $composableBuilder(column: $table.fileHash, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ImportMode, String> get importMode =>
      $composableBuilder(
        column: $table.importMode,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get resetLearningProgress => $composableBuilder(
    column: $table.resetLearningProgress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalRows =>
      $composableBuilder(column: $table.totalRows, builder: (column) => column);

  GeneratedColumn<int> get validRows =>
      $composableBuilder(column: $table.validRows, builder: (column) => column);

  GeneratedColumn<int> get invalidRows => $composableBuilder(
    column: $table.invalidRows,
    builder: (column) => column,
  );

  GeneratedColumn<int> get duplicateRows => $composableBuilder(
    column: $table.duplicateRows,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdWords => $composableBuilder(
    column: $table.createdWords,
    builder: (column) => column,
  );

  GeneratedColumn<int> get existingWords => $composableBuilder(
    column: $table.existingWords,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queuedInitializations => $composableBuilder(
    column: $table.queuedInitializations,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ImportBatchStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rolledBackAt => $composableBuilder(
    column: $table.rolledBackAt,
    builder: (column) => column,
  );

  Expression<T> importRowsRefs<T extends Object>(
    Expression<T> Function($$ImportRowsTableAnnotationComposer a) f,
  ) {
    final $$ImportRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.importRows,
      getReferencedColumn: (t) => t.importBatchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.importRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ImportBatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportBatchesTable,
          ImportBatchRow,
          $$ImportBatchesTableFilterComposer,
          $$ImportBatchesTableOrderingComposer,
          $$ImportBatchesTableAnnotationComposer,
          $$ImportBatchesTableCreateCompanionBuilder,
          $$ImportBatchesTableUpdateCompanionBuilder,
          (ImportBatchRow, $$ImportBatchesTableReferences),
          ImportBatchRow,
          PrefetchHooks Function({bool importRowsRefs})
        > {
  $$ImportBatchesTableTableManager(_$AppDatabase db, $ImportBatchesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportBatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> filename = const Value.absent(),
                Value<String?> fileHash = const Value.absent(),
                Value<ImportMode> importMode = const Value.absent(),
                Value<bool> resetLearningProgress = const Value.absent(),
                Value<int> totalRows = const Value.absent(),
                Value<int> validRows = const Value.absent(),
                Value<int> invalidRows = const Value.absent(),
                Value<int> duplicateRows = const Value.absent(),
                Value<int> createdWords = const Value.absent(),
                Value<int> existingWords = const Value.absent(),
                Value<int> queuedInitializations = const Value.absent(),
                Value<ImportBatchStatus> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> completedAt = const Value.absent(),
                Value<int?> rolledBackAt = const Value.absent(),
              }) => ImportBatchesCompanion(
                id: id,
                filename: filename,
                fileHash: fileHash,
                importMode: importMode,
                resetLearningProgress: resetLearningProgress,
                totalRows: totalRows,
                validRows: validRows,
                invalidRows: invalidRows,
                duplicateRows: duplicateRows,
                createdWords: createdWords,
                existingWords: existingWords,
                queuedInitializations: queuedInitializations,
                status: status,
                createdAt: createdAt,
                completedAt: completedAt,
                rolledBackAt: rolledBackAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String filename,
                Value<String?> fileHash = const Value.absent(),
                required ImportMode importMode,
                Value<bool> resetLearningProgress = const Value.absent(),
                Value<int> totalRows = const Value.absent(),
                Value<int> validRows = const Value.absent(),
                Value<int> invalidRows = const Value.absent(),
                Value<int> duplicateRows = const Value.absent(),
                Value<int> createdWords = const Value.absent(),
                Value<int> existingWords = const Value.absent(),
                Value<int> queuedInitializations = const Value.absent(),
                Value<ImportBatchStatus> status = const Value.absent(),
                required int createdAt,
                Value<int?> completedAt = const Value.absent(),
                Value<int?> rolledBackAt = const Value.absent(),
              }) => ImportBatchesCompanion.insert(
                id: id,
                filename: filename,
                fileHash: fileHash,
                importMode: importMode,
                resetLearningProgress: resetLearningProgress,
                totalRows: totalRows,
                validRows: validRows,
                invalidRows: invalidRows,
                duplicateRows: duplicateRows,
                createdWords: createdWords,
                existingWords: existingWords,
                queuedInitializations: queuedInitializations,
                status: status,
                createdAt: createdAt,
                completedAt: completedAt,
                rolledBackAt: rolledBackAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportBatchesTable, ImportBatchRow>(table),
                  $$ImportBatchesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({importRowsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (importRowsRefs) db.importRows],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (importRowsRefs)
                    await $_getPrefetchedData<
                      ImportBatchRow,
                      $ImportBatchesTable,
                      ImportRowRow
                    >(
                      currentTable: table,
                      referencedTable: $$ImportBatchesTableReferences
                          ._importRowsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ImportBatchesTableReferences(
                            db,
                            table,
                            p0,
                          ).importRowsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.importBatchId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ImportBatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportBatchesTable,
      ImportBatchRow,
      $$ImportBatchesTableFilterComposer,
      $$ImportBatchesTableOrderingComposer,
      $$ImportBatchesTableAnnotationComposer,
      $$ImportBatchesTableCreateCompanionBuilder,
      $$ImportBatchesTableUpdateCompanionBuilder,
      (ImportBatchRow, $$ImportBatchesTableReferences),
      ImportBatchRow,
      PrefetchHooks Function({bool importRowsRefs})
    >;
typedef $$ImportRowsTableCreateCompanionBuilder = ImportRowsCompanion Function({
  Value<int> id,
  required int importBatchId,
  required int rowNumber,
  Value<String?> rawJson,
  Value<String?> normalizedTerm,
  Value<int?> wordId,
  required ImportRowStatus status,
  Value<String?> errorCode,
  Value<String?> errorMessage,
  Value<String?> metadataJson,
  required int createdAt,
});
typedef $$ImportRowsTableUpdateCompanionBuilder = ImportRowsCompanion Function({
  Value<int> id,
  Value<int> importBatchId,
  Value<int> rowNumber,
  Value<String?> rawJson,
  Value<String?> normalizedTerm,
  Value<int?> wordId,
  Value<ImportRowStatus> status,
  Value<String?> errorCode,
  Value<String?> errorMessage,
  Value<String?> metadataJson,
  Value<int> createdAt,
});

final class $$ImportRowsTableReferences
    extends BaseReferences<_$AppDatabase, $ImportRowsTable, ImportRowRow> {
  $$ImportRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ImportBatchesTable _importBatchIdTable(_$AppDatabase db) => db
      .importBatches
      .createAlias('import_rows__import_batch_id__import_batches__id');

  $$ImportBatchesTableProcessedTableManager get importBatchId {
    final $_column = $_itemColumn<int>('import_batch_id')!;

    final manager = $$ImportBatchesTableTableManager(
      $_db,
      $_db.importBatches,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importBatchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('import_rows__word_id__words__id');

  $$WordsTableProcessedTableManager? get wordId {
    final $_column = $_itemColumn<int>('word_id');
    if ($_column == null) return null;
    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ImportRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ImportRowsTable> {
  $$ImportRowsTableFilterComposer({
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

  ColumnFilters<int> get rowNumber => $composableBuilder(
    column: $table.rowNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedTerm => $composableBuilder(
    column: $table.normalizedTerm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ImportRowStatus, ImportRowStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ImportBatchesTableFilterComposer get importBatchId {
    final $$ImportBatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importBatchId,
      referencedTable: $db.importBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportBatchesTableFilterComposer(
            $db: $db,
            $table: $db.importBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportRowsTable> {
  $$ImportRowsTableOrderingComposer({
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

  ColumnOrderings<int> get rowNumber => $composableBuilder(
    column: $table.rowNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedTerm => $composableBuilder(
    column: $table.normalizedTerm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ImportBatchesTableOrderingComposer get importBatchId {
    final $$ImportBatchesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importBatchId,
      referencedTable: $db.importBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportBatchesTableOrderingComposer(
            $db: $db,
            $table: $db.importBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportRowsTable> {
  $$ImportRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get rowNumber =>
      $composableBuilder(column: $table.rowNumber, builder: (column) => column);

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<String> get normalizedTerm => $composableBuilder(
    column: $table.normalizedTerm,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ImportRowStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ImportBatchesTableAnnotationComposer get importBatchId {
    final $$ImportBatchesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importBatchId,
      referencedTable: $db.importBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImportBatchesTableAnnotationComposer(
            $db: $db,
            $table: $db.importBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImportRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportRowsTable,
          ImportRowRow,
          $$ImportRowsTableFilterComposer,
          $$ImportRowsTableOrderingComposer,
          $$ImportRowsTableAnnotationComposer,
          $$ImportRowsTableCreateCompanionBuilder,
          $$ImportRowsTableUpdateCompanionBuilder,
          (ImportRowRow, $$ImportRowsTableReferences),
          ImportRowRow,
          PrefetchHooks Function({bool importBatchId, bool wordId})
        > {
  $$ImportRowsTableTableManager(_$AppDatabase db, $ImportRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> importBatchId = const Value.absent(),
                Value<int> rowNumber = const Value.absent(),
                Value<String?> rawJson = const Value.absent(),
                Value<String?> normalizedTerm = const Value.absent(),
                Value<int?> wordId = const Value.absent(),
                Value<ImportRowStatus> status = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => ImportRowsCompanion(
                id: id,
                importBatchId: importBatchId,
                rowNumber: rowNumber,
                rawJson: rawJson,
                normalizedTerm: normalizedTerm,
                wordId: wordId,
                status: status,
                errorCode: errorCode,
                errorMessage: errorMessage,
                metadataJson: metadataJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int importBatchId,
                required int rowNumber,
                Value<String?> rawJson = const Value.absent(),
                Value<String?> normalizedTerm = const Value.absent(),
                Value<int?> wordId = const Value.absent(),
                required ImportRowStatus status,
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                required int createdAt,
              }) => ImportRowsCompanion.insert(
                id: id,
                importBatchId: importBatchId,
                rowNumber: rowNumber,
                rawJson: rawJson,
                normalizedTerm: normalizedTerm,
                wordId: wordId,
                status: status,
                errorCode: errorCode,
                errorMessage: errorMessage,
                metadataJson: metadataJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportRowsTable, ImportRowRow>(table),
                  $$ImportRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({importBatchId = false, wordId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (importBatchId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.importBatchId,
                        referencedTable: $$ImportRowsTableReferences
                            ._importBatchIdTable(db),
                        referencedColumn: $$ImportRowsTableReferences
                            ._importBatchIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (wordId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.wordId,
                        referencedTable: $$ImportRowsTableReferences
                            ._wordIdTable(db),
                        referencedColumn: $$ImportRowsTableReferences
                            ._wordIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ImportRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportRowsTable,
      ImportRowRow,
      $$ImportRowsTableFilterComposer,
      $$ImportRowsTableOrderingComposer,
      $$ImportRowsTableAnnotationComposer,
      $$ImportRowsTableCreateCompanionBuilder,
      $$ImportRowsTableUpdateCompanionBuilder,
      (ImportRowRow, $$ImportRowsTableReferences),
      ImportRowRow,
      PrefetchHooks Function({bool importBatchId, bool wordId})
    >;
typedef $$InitializationJobsTableCreateCompanionBuilder =
    InitializationJobsCompanion Function({
      Value<int> id,
      required int wordId,
      Value<JobTaskType> taskType,
      required InitializationMode mode,
      Value<String?> requestedFieldsJson,
      Value<String?> requestedProvidersJson,
      Value<ProviderStrategy> providerStrategy,
      Value<InitializationStatus> status,
      Value<int> priority,
      Value<int> attemptCount,
      Value<int> maxAttempts,
      Value<int?> availableAt,
      Value<int?> lockedAt,
      Value<String?> lockedBy,
      Value<String?> lastError,
      Value<String?> lastErrorCode,
      required int createdAt,
      required int updatedAt,
      Value<int?> completedAt,
    });
typedef $$InitializationJobsTableUpdateCompanionBuilder =
    InitializationJobsCompanion Function({
      Value<int> id,
      Value<int> wordId,
      Value<JobTaskType> taskType,
      Value<InitializationMode> mode,
      Value<String?> requestedFieldsJson,
      Value<String?> requestedProvidersJson,
      Value<ProviderStrategy> providerStrategy,
      Value<InitializationStatus> status,
      Value<int> priority,
      Value<int> attemptCount,
      Value<int> maxAttempts,
      Value<int?> availableAt,
      Value<int?> lockedAt,
      Value<String?> lockedBy,
      Value<String?> lastError,
      Value<String?> lastErrorCode,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> completedAt,
    });

final class $$InitializationJobsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $InitializationJobsTable,
          InitializationJobRow
        > {
  $$InitializationJobsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('initialization_jobs__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ProviderAttemptsTable, List<ProviderAttemptRow>>
  _providerAttemptsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.providerAttempts,
    aliasName:
        'initialization_jobs__id__provider_attempts__initialization_job_id',
  );

  $$ProviderAttemptsTableProcessedTableManager get providerAttemptsRefs {
    final manager =
        $$ProviderAttemptsTableTableManager($_db, $_db.providerAttempts).filter(
          (f) => f.initializationJobId.id.sqlEquals($_itemColumn<int>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _providerAttemptsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$InitializationJobsTableFilterComposer
    extends Composer<_$AppDatabase, $InitializationJobsTable> {
  $$InitializationJobsTableFilterComposer({
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

  ColumnWithTypeConverterFilters<JobTaskType, JobTaskType, String>
  get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<InitializationMode, InitializationMode, String>
  get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get requestedFieldsJson => $composableBuilder(
    column: $table.requestedFieldsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestedProvidersJson => $composableBuilder(
    column: $table.requestedProvidersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ProviderStrategy, ProviderStrategy, String>
  get providerStrategy => $composableBuilder(
    column: $table.providerStrategy,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    InitializationStatus,
    InitializationStatus,
    String
  >
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxAttempts => $composableBuilder(
    column: $table.maxAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get availableAt => $composableBuilder(
    column: $table.availableAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lockedAt => $composableBuilder(
    column: $table.lockedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lockedBy => $composableBuilder(
    column: $table.lockedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> providerAttemptsRefs(
    Expression<bool> Function($$ProviderAttemptsTableFilterComposer f) f,
  ) {
    final $$ProviderAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.providerAttempts,
      getReferencedColumn: (t) => t.initializationJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProviderAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.providerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$InitializationJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $InitializationJobsTable> {
  $$InitializationJobsTableOrderingComposer({
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

  ColumnOrderings<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestedFieldsJson => $composableBuilder(
    column: $table.requestedFieldsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestedProvidersJson => $composableBuilder(
    column: $table.requestedProvidersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerStrategy => $composableBuilder(
    column: $table.providerStrategy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxAttempts => $composableBuilder(
    column: $table.maxAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get availableAt => $composableBuilder(
    column: $table.availableAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lockedAt => $composableBuilder(
    column: $table.lockedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lockedBy => $composableBuilder(
    column: $table.lockedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InitializationJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InitializationJobsTable> {
  $$InitializationJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<JobTaskType, String> get taskType =>
      $composableBuilder(column: $table.taskType, builder: (column) => column);

  GeneratedColumnWithTypeConverter<InitializationMode, String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get requestedFieldsJson => $composableBuilder(
    column: $table.requestedFieldsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestedProvidersJson => $composableBuilder(
    column: $table.requestedProvidersJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ProviderStrategy, String>
  get providerStrategy => $composableBuilder(
    column: $table.providerStrategy,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<InitializationStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxAttempts => $composableBuilder(
    column: $table.maxAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<int> get availableAt => $composableBuilder(
    column: $table.availableAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lockedAt =>
      $composableBuilder(column: $table.lockedAt, builder: (column) => column);

  GeneratedColumn<String> get lockedBy =>
      $composableBuilder(column: $table.lockedBy, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> providerAttemptsRefs<T extends Object>(
    Expression<T> Function($$ProviderAttemptsTableAnnotationComposer a) f,
  ) {
    final $$ProviderAttemptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.providerAttempts,
      getReferencedColumn: (t) => t.initializationJobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProviderAttemptsTableAnnotationComposer(
            $db: $db,
            $table: $db.providerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$InitializationJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InitializationJobsTable,
          InitializationJobRow,
          $$InitializationJobsTableFilterComposer,
          $$InitializationJobsTableOrderingComposer,
          $$InitializationJobsTableAnnotationComposer,
          $$InitializationJobsTableCreateCompanionBuilder,
          $$InitializationJobsTableUpdateCompanionBuilder,
          (InitializationJobRow, $$InitializationJobsTableReferences),
          InitializationJobRow,
          PrefetchHooks Function({bool wordId, bool providerAttemptsRefs})
        > {
  $$InitializationJobsTableTableManager(
    _$AppDatabase db,
    $InitializationJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InitializationJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InitializationJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InitializationJobsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> wordId = const Value.absent(),
                Value<JobTaskType> taskType = const Value.absent(),
                Value<InitializationMode> mode = const Value.absent(),
                Value<String?> requestedFieldsJson = const Value.absent(),
                Value<String?> requestedProvidersJson = const Value.absent(),
                Value<ProviderStrategy> providerStrategy = const Value.absent(),
                Value<InitializationStatus> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> maxAttempts = const Value.absent(),
                Value<int?> availableAt = const Value.absent(),
                Value<int?> lockedAt = const Value.absent(),
                Value<String?> lockedBy = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> completedAt = const Value.absent(),
              }) => InitializationJobsCompanion(
                id: id,
                wordId: wordId,
                taskType: taskType,
                mode: mode,
                requestedFieldsJson: requestedFieldsJson,
                requestedProvidersJson: requestedProvidersJson,
                providerStrategy: providerStrategy,
                status: status,
                priority: priority,
                attemptCount: attemptCount,
                maxAttempts: maxAttempts,
                availableAt: availableAt,
                lockedAt: lockedAt,
                lockedBy: lockedBy,
                lastError: lastError,
                lastErrorCode: lastErrorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int wordId,
                Value<JobTaskType> taskType = const Value.absent(),
                required InitializationMode mode,
                Value<String?> requestedFieldsJson = const Value.absent(),
                Value<String?> requestedProvidersJson = const Value.absent(),
                Value<ProviderStrategy> providerStrategy = const Value.absent(),
                Value<InitializationStatus> status = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> maxAttempts = const Value.absent(),
                Value<int?> availableAt = const Value.absent(),
                Value<int?> lockedAt = const Value.absent(),
                Value<String?> lockedBy = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> completedAt = const Value.absent(),
              }) => InitializationJobsCompanion.insert(
                id: id,
                wordId: wordId,
                taskType: taskType,
                mode: mode,
                requestedFieldsJson: requestedFieldsJson,
                requestedProvidersJson: requestedProvidersJson,
                providerStrategy: providerStrategy,
                status: status,
                priority: priority,
                attemptCount: attemptCount,
                maxAttempts: maxAttempts,
                availableAt: availableAt,
                lockedAt: lockedAt,
                lockedBy: lockedBy,
                lastError: lastError,
                lastErrorCode: lastErrorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InitializationJobsTable, InitializationJobRow>(
                    table,
                  ),
                  $$InitializationJobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({wordId = false, providerAttemptsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (providerAttemptsRefs) db.providerAttempts,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (wordId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.wordId,
                            referencedTable: $$InitializationJobsTableReferences
                                ._wordIdTable(db),
                            referencedColumn:
                                $$InitializationJobsTableReferences
                                    ._wordIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (providerAttemptsRefs)
                        await $_getPrefetchedData<
                          InitializationJobRow,
                          $InitializationJobsTable,
                          ProviderAttemptRow
                        >(
                          currentTable: table,
                          referencedTable: $$InitializationJobsTableReferences
                              ._providerAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$InitializationJobsTableReferences(
                                db,
                                table,
                                p0,
                              ).providerAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.initializationJobId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$InitializationJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InitializationJobsTable,
      InitializationJobRow,
      $$InitializationJobsTableFilterComposer,
      $$InitializationJobsTableOrderingComposer,
      $$InitializationJobsTableAnnotationComposer,
      $$InitializationJobsTableCreateCompanionBuilder,
      $$InitializationJobsTableUpdateCompanionBuilder,
      (InitializationJobRow, $$InitializationJobsTableReferences),
      InitializationJobRow,
      PrefetchHooks Function({bool wordId, bool providerAttemptsRefs})
    >;
typedef $$ProviderAttemptsTableCreateCompanionBuilder =
    ProviderAttemptsCompanion Function({
      Value<int> id,
      Value<int?> initializationJobId,
      required int wordId,
      required String providerId,
      required ProviderAttemptStatus status,
      Value<int?> durationMs,
      Value<String?> fieldsReturnedJson,
      Value<String?> errorCode,
      Value<String?> errorMessage,
      Value<String?> metadataJson,
      required int createdAt,
    });
typedef $$ProviderAttemptsTableUpdateCompanionBuilder =
    ProviderAttemptsCompanion Function({
      Value<int> id,
      Value<int?> initializationJobId,
      Value<int> wordId,
      Value<String> providerId,
      Value<ProviderAttemptStatus> status,
      Value<int?> durationMs,
      Value<String?> fieldsReturnedJson,
      Value<String?> errorCode,
      Value<String?> errorMessage,
      Value<String?> metadataJson,
      Value<int> createdAt,
    });

final class $$ProviderAttemptsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ProviderAttemptsTable,
          ProviderAttemptRow
        > {
  $$ProviderAttemptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $InitializationJobsTable _initializationJobIdTable(_$AppDatabase db) =>
      db.initializationJobs.createAlias(
        'provider_attempts__initialization_job_id__initialization_jobs__id',
      );

  $$InitializationJobsTableProcessedTableManager? get initializationJobId {
    final $_column = $_itemColumn<int>('initialization_job_id');
    if ($_column == null) return null;
    final manager = $$InitializationJobsTableTableManager(
      $_db,
      $_db.initializationJobs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_initializationJobIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $WordsTable _wordIdTable(_$AppDatabase db) =>
      db.words.createAlias('provider_attempts__word_id__words__id');

  $$WordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<int>('word_id')!;

    final manager = $$WordsTableTableManager(
      $_db,
      $_db.words,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProviderAttemptsTableFilterComposer
    extends Composer<_$AppDatabase, $ProviderAttemptsTable> {
  $$ProviderAttemptsTableFilterComposer({
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

  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    ProviderAttemptStatus,
    ProviderAttemptStatus,
    String
  >
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldsReturnedJson => $composableBuilder(
    column: $table.fieldsReturnedJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$InitializationJobsTableFilterComposer get initializationJobId {
    final $$InitializationJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.initializationJobId,
      referencedTable: $db.initializationJobs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InitializationJobsTableFilterComposer(
            $db: $db,
            $table: $db.initializationJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableFilterComposer get wordId {
    final $$WordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableFilterComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProviderAttemptsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProviderAttemptsTable> {
  $$ProviderAttemptsTableOrderingComposer({
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

  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldsReturnedJson => $composableBuilder(
    column: $table.fieldsReturnedJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$InitializationJobsTableOrderingComposer get initializationJobId {
    final $$InitializationJobsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.initializationJobId,
      referencedTable: $db.initializationJobs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InitializationJobsTableOrderingComposer(
            $db: $db,
            $table: $db.initializationJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WordsTableOrderingComposer get wordId {
    final $$WordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableOrderingComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProviderAttemptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProviderAttemptsTable> {
  $$ProviderAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ProviderAttemptStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fieldsReturnedJson => $composableBuilder(
    column: $table.fieldsReturnedJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$InitializationJobsTableAnnotationComposer get initializationJobId {
    final $$InitializationJobsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.initializationJobId,
          referencedTable: $db.initializationJobs,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InitializationJobsTableAnnotationComposer(
                $db: $db,
                $table: $db.initializationJobs,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$WordsTableAnnotationComposer get wordId {
    final $$WordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.words,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WordsTableAnnotationComposer(
            $db: $db,
            $table: $db.words,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProviderAttemptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProviderAttemptsTable,
          ProviderAttemptRow,
          $$ProviderAttemptsTableFilterComposer,
          $$ProviderAttemptsTableOrderingComposer,
          $$ProviderAttemptsTableAnnotationComposer,
          $$ProviderAttemptsTableCreateCompanionBuilder,
          $$ProviderAttemptsTableUpdateCompanionBuilder,
          (ProviderAttemptRow, $$ProviderAttemptsTableReferences),
          ProviderAttemptRow,
          PrefetchHooks Function({bool initializationJobId, bool wordId})
        > {
  $$ProviderAttemptsTableTableManager(
    _$AppDatabase db,
    $ProviderAttemptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProviderAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProviderAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProviderAttemptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> initializationJobId = const Value.absent(),
                Value<int> wordId = const Value.absent(),
                Value<String> providerId = const Value.absent(),
                Value<ProviderAttemptStatus> status = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> fieldsReturnedJson = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => ProviderAttemptsCompanion(
                id: id,
                initializationJobId: initializationJobId,
                wordId: wordId,
                providerId: providerId,
                status: status,
                durationMs: durationMs,
                fieldsReturnedJson: fieldsReturnedJson,
                errorCode: errorCode,
                errorMessage: errorMessage,
                metadataJson: metadataJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> initializationJobId = const Value.absent(),
                required int wordId,
                required String providerId,
                required ProviderAttemptStatus status,
                Value<int?> durationMs = const Value.absent(),
                Value<String?> fieldsReturnedJson = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                required int createdAt,
              }) => ProviderAttemptsCompanion.insert(
                id: id,
                initializationJobId: initializationJobId,
                wordId: wordId,
                providerId: providerId,
                status: status,
                durationMs: durationMs,
                fieldsReturnedJson: fieldsReturnedJson,
                errorCode: errorCode,
                errorMessage: errorMessage,
                metadataJson: metadataJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProviderAttemptsTable, ProviderAttemptRow>(
                    table,
                  ),
                  $$ProviderAttemptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({initializationJobId = false, wordId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (initializationJobId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.initializationJobId,
                            referencedTable: $$ProviderAttemptsTableReferences
                                ._initializationJobIdTable(db),
                            referencedColumn: $$ProviderAttemptsTableReferences
                                ._initializationJobIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (wordId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.wordId,
                            referencedTable: $$ProviderAttemptsTableReferences
                                ._wordIdTable(db),
                            referencedColumn: $$ProviderAttemptsTableReferences
                                ._wordIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ProviderAttemptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProviderAttemptsTable,
      ProviderAttemptRow,
      $$ProviderAttemptsTableFilterComposer,
      $$ProviderAttemptsTableOrderingComposer,
      $$ProviderAttemptsTableAnnotationComposer,
      $$ProviderAttemptsTableCreateCompanionBuilder,
      $$ProviderAttemptsTableUpdateCompanionBuilder,
      (ProviderAttemptRow, $$ProviderAttemptsTableReferences),
      ProviderAttemptRow,
      PrefetchHooks Function({bool initializationJobId, bool wordId})
    >;
typedef $$DailyAiSuggestionsTableCreateCompanionBuilder =
    DailyAiSuggestionsCompanion Function({
      required String dateKey,
      required String sourceDateKey,
      Value<int?> qualityScore,
      Value<String> metricsJson,
      Value<String> contentJson,
      Value<String> recommendedItemsJson,
      Value<SuggestionGenerator> generator,
      Value<String?> providerId,
      Value<String?> model,
      Value<String?> generationWarning,
      required int generatedAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$DailyAiSuggestionsTableUpdateCompanionBuilder =
    DailyAiSuggestionsCompanion Function({
      Value<String> dateKey,
      Value<String> sourceDateKey,
      Value<int?> qualityScore,
      Value<String> metricsJson,
      Value<String> contentJson,
      Value<String> recommendedItemsJson,
      Value<SuggestionGenerator> generator,
      Value<String?> providerId,
      Value<String?> model,
      Value<String?> generationWarning,
      Value<int> generatedAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$DailyAiSuggestionsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyAiSuggestionsTable> {
  $$DailyAiSuggestionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDateKey => $composableBuilder(
    column: $table.sourceDateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get qualityScore => $composableBuilder(
    column: $table.qualityScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricsJson => $composableBuilder(
    column: $table.metricsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recommendedItemsJson => $composableBuilder(
    column: $table.recommendedItemsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    SuggestionGenerator,
    SuggestionGenerator,
    String
  >
  get generator => $composableBuilder(
    column: $table.generator,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generationWarning => $composableBuilder(
    column: $table.generationWarning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyAiSuggestionsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyAiSuggestionsTable> {
  $$DailyAiSuggestionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDateKey => $composableBuilder(
    column: $table.sourceDateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get qualityScore => $composableBuilder(
    column: $table.qualityScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricsJson => $composableBuilder(
    column: $table.metricsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recommendedItemsJson => $composableBuilder(
    column: $table.recommendedItemsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generator => $composableBuilder(
    column: $table.generator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generationWarning => $composableBuilder(
    column: $table.generationWarning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyAiSuggestionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyAiSuggestionsTable> {
  $$DailyAiSuggestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get dateKey =>
      $composableBuilder(column: $table.dateKey, builder: (column) => column);

  GeneratedColumn<String> get sourceDateKey => $composableBuilder(
    column: $table.sourceDateKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get qualityScore => $composableBuilder(
    column: $table.qualityScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metricsJson => $composableBuilder(
    column: $table.metricsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recommendedItemsJson => $composableBuilder(
    column: $table.recommendedItemsJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<SuggestionGenerator, String> get generator =>
      $composableBuilder(column: $table.generator, builder: (column) => column);

  GeneratedColumn<String> get providerId => $composableBuilder(
    column: $table.providerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get generationWarning => $composableBuilder(
    column: $table.generationWarning,
    builder: (column) => column,
  );

  GeneratedColumn<int> get generatedAt => $composableBuilder(
    column: $table.generatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DailyAiSuggestionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyAiSuggestionsTable,
          DailyAiSuggestionRow,
          $$DailyAiSuggestionsTableFilterComposer,
          $$DailyAiSuggestionsTableOrderingComposer,
          $$DailyAiSuggestionsTableAnnotationComposer,
          $$DailyAiSuggestionsTableCreateCompanionBuilder,
          $$DailyAiSuggestionsTableUpdateCompanionBuilder,
          (
            DailyAiSuggestionRow,
            BaseReferences<
              _$AppDatabase,
              $DailyAiSuggestionsTable,
              DailyAiSuggestionRow
            >,
          ),
          DailyAiSuggestionRow,
          PrefetchHooks Function()
        > {
  $$DailyAiSuggestionsTableTableManager(
    _$AppDatabase db,
    $DailyAiSuggestionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyAiSuggestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyAiSuggestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyAiSuggestionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> dateKey = const Value.absent(),
                Value<String> sourceDateKey = const Value.absent(),
                Value<int?> qualityScore = const Value.absent(),
                Value<String> metricsJson = const Value.absent(),
                Value<String> contentJson = const Value.absent(),
                Value<String> recommendedItemsJson = const Value.absent(),
                Value<SuggestionGenerator> generator = const Value.absent(),
                Value<String?> providerId = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> generationWarning = const Value.absent(),
                Value<int> generatedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyAiSuggestionsCompanion(
                dateKey: dateKey,
                sourceDateKey: sourceDateKey,
                qualityScore: qualityScore,
                metricsJson: metricsJson,
                contentJson: contentJson,
                recommendedItemsJson: recommendedItemsJson,
                generator: generator,
                providerId: providerId,
                model: model,
                generationWarning: generationWarning,
                generatedAt: generatedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String dateKey,
                required String sourceDateKey,
                Value<int?> qualityScore = const Value.absent(),
                Value<String> metricsJson = const Value.absent(),
                Value<String> contentJson = const Value.absent(),
                Value<String> recommendedItemsJson = const Value.absent(),
                Value<SuggestionGenerator> generator = const Value.absent(),
                Value<String?> providerId = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> generationWarning = const Value.absent(),
                required int generatedAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DailyAiSuggestionsCompanion.insert(
                dateKey: dateKey,
                sourceDateKey: sourceDateKey,
                qualityScore: qualityScore,
                metricsJson: metricsJson,
                contentJson: contentJson,
                recommendedItemsJson: recommendedItemsJson,
                generator: generator,
                providerId: providerId,
                model: model,
                generationWarning: generationWarning,
                generatedAt: generatedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailyAiSuggestionsTable, DailyAiSuggestionRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $DailyAiSuggestionsTable,
                    DailyAiSuggestionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyAiSuggestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyAiSuggestionsTable,
      DailyAiSuggestionRow,
      $$DailyAiSuggestionsTableFilterComposer,
      $$DailyAiSuggestionsTableOrderingComposer,
      $$DailyAiSuggestionsTableAnnotationComposer,
      $$DailyAiSuggestionsTableCreateCompanionBuilder,
      $$DailyAiSuggestionsTableUpdateCompanionBuilder,
      (
        DailyAiSuggestionRow,
        BaseReferences<
          _$AppDatabase,
          $DailyAiSuggestionsTable,
          DailyAiSuggestionRow
        >,
      ),
      DailyAiSuggestionRow,
      PrefetchHooks Function()
    >;
typedef $$GameHighScoresTableCreateCompanionBuilder =
    GameHighScoresCompanion Function({
      Value<int> id,
      required String gameMode,
      required int score,
      Value<int> maxCombo,
      Value<int> accuracy,
      Value<int> elapsedMs,
      required int playedAt,
      required int createdAt,
    });
typedef $$GameHighScoresTableUpdateCompanionBuilder =
    GameHighScoresCompanion Function({
      Value<int> id,
      Value<String> gameMode,
      Value<int> score,
      Value<int> maxCombo,
      Value<int> accuracy,
      Value<int> elapsedMs,
      Value<int> playedAt,
      Value<int> createdAt,
    });

class $$GameHighScoresTableFilterComposer
    extends Composer<_$AppDatabase, $GameHighScoresTable> {
  $$GameHighScoresTableFilterComposer({
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

  ColumnFilters<String> get gameMode => $composableBuilder(
    column: $table.gameMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxCombo => $composableBuilder(
    column: $table.maxCombo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GameHighScoresTableOrderingComposer
    extends Composer<_$AppDatabase, $GameHighScoresTable> {
  $$GameHighScoresTableOrderingComposer({
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

  ColumnOrderings<String> get gameMode => $composableBuilder(
    column: $table.gameMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxCombo => $composableBuilder(
    column: $table.maxCombo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GameHighScoresTableAnnotationComposer
    extends Composer<_$AppDatabase, $GameHighScoresTable> {
  $$GameHighScoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gameMode =>
      $composableBuilder(column: $table.gameMode, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get maxCombo =>
      $composableBuilder(column: $table.maxCombo, builder: (column) => column);

  GeneratedColumn<int> get accuracy =>
      $composableBuilder(column: $table.accuracy, builder: (column) => column);

  GeneratedColumn<int> get elapsedMs =>
      $composableBuilder(column: $table.elapsedMs, builder: (column) => column);

  GeneratedColumn<int> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$GameHighScoresTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GameHighScoresTable,
          GameHighScoreRow,
          $$GameHighScoresTableFilterComposer,
          $$GameHighScoresTableOrderingComposer,
          $$GameHighScoresTableAnnotationComposer,
          $$GameHighScoresTableCreateCompanionBuilder,
          $$GameHighScoresTableUpdateCompanionBuilder,
          (
            GameHighScoreRow,
            BaseReferences<
              _$AppDatabase,
              $GameHighScoresTable,
              GameHighScoreRow
            >,
          ),
          GameHighScoreRow,
          PrefetchHooks Function()
        > {
  $$GameHighScoresTableTableManager(
    _$AppDatabase db,
    $GameHighScoresTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GameHighScoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GameHighScoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GameHighScoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> gameMode = const Value.absent(),
                Value<int> score = const Value.absent(),
                Value<int> maxCombo = const Value.absent(),
                Value<int> accuracy = const Value.absent(),
                Value<int> elapsedMs = const Value.absent(),
                Value<int> playedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => GameHighScoresCompanion(
                id: id,
                gameMode: gameMode,
                score: score,
                maxCombo: maxCombo,
                accuracy: accuracy,
                elapsedMs: elapsedMs,
                playedAt: playedAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String gameMode,
                required int score,
                Value<int> maxCombo = const Value.absent(),
                Value<int> accuracy = const Value.absent(),
                Value<int> elapsedMs = const Value.absent(),
                required int playedAt,
                required int createdAt,
              }) => GameHighScoresCompanion.insert(
                id: id,
                gameMode: gameMode,
                score: score,
                maxCombo: maxCombo,
                accuracy: accuracy,
                elapsedMs: elapsedMs,
                playedAt: playedAt,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GameHighScoresTable, GameHighScoreRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $GameHighScoresTable,
                    GameHighScoreRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GameHighScoresTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GameHighScoresTable,
      GameHighScoreRow,
      $$GameHighScoresTableFilterComposer,
      $$GameHighScoresTableOrderingComposer,
      $$GameHighScoresTableAnnotationComposer,
      $$GameHighScoresTableCreateCompanionBuilder,
      $$GameHighScoresTableUpdateCompanionBuilder,
      (
        GameHighScoreRow,
        BaseReferences<_$AppDatabase, $GameHighScoresTable, GameHighScoreRow>,
      ),
      GameHighScoreRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String valueJson,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> valueJson,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                valueJson: valueJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String valueJson,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                valueJson: valueJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WordsTableTableManager get words =>
      $$WordsTableTableManager(_db, _db.words);
  $$WordContentsTableTableManager get wordContents =>
      $$WordContentsTableTableManager(_db, _db.wordContents);
  $$WordReviewStatsTableTableManager get wordReviewStats =>
      $$WordReviewStatsTableTableManager(_db, _db.wordReviewStats);
  $$StudySessionsTableTableManager get studySessions =>
      $$StudySessionsTableTableManager(_db, _db.studySessions);
  $$StudySessionItemsTableTableManager get studySessionItems =>
      $$StudySessionItemsTableTableManager(_db, _db.studySessionItems);
  $$ReviewCardsTableTableManager get reviewCards =>
      $$ReviewCardsTableTableManager(_db, _db.reviewCards);
  $$ReviewLogsTableTableManager get reviewLogs =>
      $$ReviewLogsTableTableManager(_db, _db.reviewLogs);
  $$WrongWordStatesTableTableManager get wrongWordStates =>
      $$WrongWordStatesTableTableManager(_db, _db.wrongWordStates);
  $$ImportBatchesTableTableManager get importBatches =>
      $$ImportBatchesTableTableManager(_db, _db.importBatches);
  $$ImportRowsTableTableManager get importRows =>
      $$ImportRowsTableTableManager(_db, _db.importRows);
  $$InitializationJobsTableTableManager get initializationJobs =>
      $$InitializationJobsTableTableManager(_db, _db.initializationJobs);
  $$ProviderAttemptsTableTableManager get providerAttempts =>
      $$ProviderAttemptsTableTableManager(_db, _db.providerAttempts);
  $$DailyAiSuggestionsTableTableManager get dailyAiSuggestions =>
      $$DailyAiSuggestionsTableTableManager(_db, _db.dailyAiSuggestions);
  $$GameHighScoresTableTableManager get gameHighScores =>
      $$GameHighScoresTableTableManager(_db, _db.gameHighScores);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
