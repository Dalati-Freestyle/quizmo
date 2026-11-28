/// The order in which items of ordering and matching questions are shown.
///
/// Every device (players, TV, host, preview, on the web and natively) shows
/// the same order for a question, but never the solution: items are mixed
/// with a seed per question and a generator of their own, because
/// `String.hashCode` and `Random` are not guaranteed to agree between
/// platforms.
library;

/// [items] mixed deterministically by [seed]. With two or more items the
/// result never equals [avoid] (default: [items] itself, i.e. the order as
/// entered, which is the solution of an ordering question).
List<T> displayOrder<T>(List<T> items, String seed, {List<T>? avoid}) {
  final result = [...items];
  if (result.length < 2) return result;
  var state = _hash(seed);
  int next(int bound) {
    // xorshift32, kept inside 32 bits so JavaScript and the VM agree.
    state ^= (state << 13) & 0xffffffff;
    state ^= state >> 17;
    state ^= (state << 5) & 0xffffffff;
    state &= 0xffffffff;
    return state % bound;
  }

  for (var i = result.length - 1; i > 0; i--) {
    final j = next(i + 1);
    final swap = result[i];
    result[i] = result[j];
    result[j] = swap;
  }
  final forbidden = avoid ?? items;
  if (_sameOrder(result, forbidden)) {
    // A rotation of an order is never that order itself.
    result.add(result.removeAt(0));
  }
  return result;
}

bool _sameOrder<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// FNV-1a over the UTF-16 code units of [seed]; never 0 (xorshift needs a
/// state other than 0).
int _hash(String seed) {
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash ^= unit;
    // hash * 0x01000193 (= 2^24 + 0x193), split so that no intermediate
    // value leaves the exact integer range of JavaScript.
    hash = ((((hash & 0xff) << 24) & 0xffffffff) + hash * 0x193) & 0xffffffff;
  }
  return hash == 0 ? 0x9e3779b9 : hash;
}
