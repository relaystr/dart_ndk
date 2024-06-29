import 'package:dart_ndk/event_filter.dart';
import 'package:dart_ndk/nips/nip01/event.dart';

import 'nips/nip02/contact_list.dart';
import 'nips/nip65/nip65.dart';

class PTagCountEventFilter extends EventFilter {
  int maxTagCount;

  PTagCountEventFilter(this.maxTagCount);

  @override
  bool filter(Nip01Event event) {
    return event.kind == ContactList.KIND ||
        event.kind == Nip65.KIND ||
        event.pTags.length <= maxTagCount;
  }
}
