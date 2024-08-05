RegExp RELAY_URL_REGEX = RegExp(
    r'^(wss?:\/\/)([0-9]{1,3}(?:\.[0-9]{1,3}){3}|[^:]+):?([0-9]{1,5})?$');

String? cleanRelayUrl(String adr) {
  if (adr.endsWith("/")) {
    adr = adr.substring(0, adr.length - 1);
  }
  if (adr.contains("%")) {
    adr = Uri.decodeComponent(adr);
  }
  adr = adr.trim();
  if (!adr.contains(RELAY_URL_REGEX)) {
    return null;
  }
  return adr;
}

List<String> cleanRelayUrls(List<String> urls) {
  final List<String> cleanUrls = [];
  for (var url in urls) {
    String? cleanUrl = cleanRelayUrl(url);
    if (cleanUrl == null) {
      continue;
    }
    cleanUrls.add(cleanUrl);
  }
  return cleanUrls;
}
