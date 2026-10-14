// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BookModelAdapter extends TypeAdapter<BookModel> {
  @override
  final int typeId = 0;

  @override
  BookModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BookModel(
      id: fields[0] as String,
      title: fields[1] as String,
      author: fields[2] as String,
      coverUrl: fields[3] as String?,
      localCoverPath: fields[4] as String?,
      localPath: fields[5] as String,
      format: fields[6] as String,
      totalPages: fields[7] as int,
      lastReadPage: fields[8] as int,
      lastReadProgress: fields[9] as double,
      lastReadCfi: fields[10] as String?,
      lastReadTime: fields[11] as DateTime?,
      addedTime: fields[12] as DateTime?,
      md5: fields[13] as String?,
      fileSize: fields[14] as int?,
      storeBookId: fields[15] as String?,
      epubCheckpoint: (fields[16] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, BookModel obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.coverUrl)
      ..writeByte(4)
      ..write(obj.localCoverPath)
      ..writeByte(5)
      ..write(obj.localPath)
      ..writeByte(6)
      ..write(obj.format)
      ..writeByte(7)
      ..write(obj.totalPages)
      ..writeByte(8)
      ..write(obj.lastReadPage)
      ..writeByte(9)
      ..write(obj.lastReadProgress)
      ..writeByte(10)
      ..write(obj.lastReadCfi)
      ..writeByte(11)
      ..write(obj.lastReadTime)
      ..writeByte(12)
      ..write(obj.addedTime)
      ..writeByte(13)
      ..write(obj.md5)
      ..writeByte(14)
      ..write(obj.fileSize)
      ..writeByte(15)
      ..write(obj.storeBookId)
      ..writeByte(16)
      ..write(obj.epubCheckpoint);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
