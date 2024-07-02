class Filter {
  List<String>? ids;
  List<String>? authors;
  List<int>? kinds;
  String? search;

  List<String>? eTags; // event tags
  List<String>? pTags; // pubKey tags
  List<String>? tTags; // # tags
  List<String>? aTags; // a tags
  List<String>? dTags; // a tags

  int? since;
  int? until;
  int? limit;

  Filter(
      {this.ids,
      this.authors,
      this.kinds,
      this.eTags,
      this.pTags,
      this.tTags,
      this.aTags,
      this.dTags,
      this.since,
      this.until,
      this.limit});

  Filter.fromMap(Map<String, dynamic> map) {
    ids = map['ids'] == null ? null : List<String>.from(map['ids']);
    authors = map['authors'] == null ? null : List<String>.from(map['authors']);
    kinds = map['kinds'] == null ? null : List<int>.from(map['kinds']);
    eTags = map['#e'] == null ? null : List<String>.from(map['#e']);
    pTags = map['#p'] == null ? null : List<String>.from(map['#p']);
    tTags = map['#t'] == null ? null : List<String>.from(map['#t']);
    aTags = map['#a'] == null ? null : List<String>.from(map['#a']);
    dTags = map['#d'] == null ? null : List<String>.from(map['#d']);
    search = map['search'];
    since = map['since'];
    until = map['until'];
    limit = map['limit'];
  }

  Map<String, dynamic> toMap() {
    var body = {
      "ids": ids,
      "authors": authors,
      "kinds": kinds,
      "#e": eTags,
      "#p": pTags,
      "#t": tTags,
      "#d": dTags,
      "#a": aTags,
      "since": since,
      "until": until,
      "search": search,
      "limit": limit,
    };
    // remove null values
    body.removeWhere((key, value) => value == null);

    return body;
  }

  @override
  String toString() {
    return toMap().toString();
  }

  Filter cloneWithAuthors(List<String> authors) {
    Map<String, dynamic> map = toMap();
    map['authors'] = authors;
    return Filter.fromMap(map);
  }

  Filter cloneWithPTags(List<String> pTags) {
    Map<String, dynamic> map = toMap();
    map['#p'] = pTags;
    return Filter.fromMap(map);
  }

  Filter.mergeAuthors(Filter filter1, Filter filter2) {
    Map<String, dynamic> map = filter1.toMap();
    if (filter1.authors == null || filter2.authors == null) {
      throw Exception("Filter does not contain authors");
    }
    map['authors'] = [...filter1.authors!, ...filter2.authors!];
    // remove duplicates
    map['authors'] = map['authors'].toSet().toList();
    Filter.fromMap(map);
  }
}
