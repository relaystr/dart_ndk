/// nip65 read/write marker
enum ReadWriteMarker {
  readOnly,
  writeOnly,
  readWrite;

  static ReadWriteMarker from({required bool read, required bool write}) {
    if (read) {
      if (write) {
        return ReadWriteMarker.readWrite;
      }
      return ReadWriteMarker.readOnly;
    }
    if (write) {
      return ReadWriteMarker.writeOnly;
    }
    throw Exception("illegal read & write false values for this marker");
  }

  bool get isRead =>
      this == ReadWriteMarker.readOnly || this == ReadWriteMarker.readWrite;

  bool get isWrite =>
      this == ReadWriteMarker.writeOnly || this == ReadWriteMarker.readWrite;

  /// Returns true if this marker is a subset of the other marker.
  /// returns true for readOnly == readWrite and writeOnly == readWrite
  bool isPartialMatch(ReadWriteMarker other) {
    return isRead == other.isRead || isWrite == other.isWrite;
  }
}
