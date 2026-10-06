/// The vendored Windows camera list appends its opaque device link after the
/// friendly name. Display and capture use separate fields; never persist/log ID.
class WindowsCameraIdentity {
  const WindowsCameraIdentity(this.name, this.deviceId);
  final String name;
  final String? deviceId;
  factory WindowsCameraIdentity.parse(String value) {
    final start = value.lastIndexOf(' <');
    final framed = start > 0 && value.endsWith('>');
    final name = (start > 0 ? value.substring(0, start) : value).trim();
    final link = framed ? value.substring(start + 2, value.length - 1) : '';
    return WindowsCameraIdentity(
      name.isEmpty ? 'Camera' : name,
      link.isEmpty || link.contains('\u0000') ? null : link,
    );
  }
}
