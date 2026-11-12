/// Native Windows WLAN access (wlanapi.dll via `package:win32`).
///
/// Only imported from `system_wifi_io.dart` and only called on Windows.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// `WLAN_PROFILE_GET_PLAINTEXT_KEY` from wlanapi.h.
const int _plainTextKey = 0x00000004;

/// Profile of the connected network: its name and, if readable, its XML.
typedef ConnectedWlanProfile = ({String profile, String? xml});

/// Reads the profile of the first connected Wi-Fi interface.
///
/// Returns `null` when no Wi-Fi interface is connected. The XML contains the
/// plain-text key only when Windows grants it to this process (by default to
/// elevated administrators); otherwise `keyMaterial` stays encrypted.
ConnectedWlanProfile? readConnectedWlanProfile() => using((arena) {
  final version = arena<Uint32>();
  final handlePointer = arena<Pointer>();
  if (WlanOpenHandle(2, version, handlePointer) != 0) {
    throw StateError('The Windows WLAN service is not available.');
  }
  final handle = HANDLE(handlePointer.value);
  try {
    final list = arena<Pointer<WLAN_INTERFACE_INFO_LIST>>();
    if (WlanEnumInterfaces(handle, list) != 0) return null;
    try {
      final interfaces = list.value.ref;
      for (var i = 0; i < interfaces.dwNumberOfItems; i++) {
        final info = interfaces.InterfaceInfo[i];
        if (info.isState != wlan_interface_state_connected) continue;
        final guid = arena<GUID>()..ref = info.InterfaceGuid;
        final size = arena<Uint32>();
        final data = arena<Pointer>();
        if (WlanQueryInterface(
              handle,
              guid,
              wlan_intf_opcode_current_connection,
              size,
              data,
              null,
            ) !=
            0) {
          continue;
        }
        final String profile;
        try {
          profile = data.value
              .cast<WLAN_CONNECTION_ATTRIBUTES>()
              .ref
              .strProfileName;
        } finally {
          WlanFreeMemory(data.value);
        }
        if (profile.isEmpty) continue;
        final xml = arena<Pointer<Utf16>>();
        final flags = arena<Uint32>()..value = _plainTextKey;
        final granted = arena<Uint32>();
        final status = WlanGetProfile(
          handle,
          guid,
          PCWSTR(profile.toNativeUtf16(allocator: arena)),
          xml,
          flags,
          granted,
        );
        if (status != 0) return (profile: profile, xml: null);
        try {
          return (profile: profile, xml: xml.value.toDartString());
        } finally {
          WlanFreeMemory(xml.value);
        }
      }
      return null;
    } finally {
      WlanFreeMemory(list.value);
    }
  } finally {
    WlanCloseHandle(handle);
  }
});
