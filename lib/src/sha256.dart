import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Pure-Dart streaming SHA-256 (FIPS 180-4) implementation used for cross-platform
/// verification and fallback when verifying large installer packages without
/// loading the entire file into memory.
class StreamingSha256 {
  StreamingSha256._();

  static const List<int> _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;

  /// Computes the lowercase hexadecimal SHA-256 digest of a file by streaming
  /// its contents in chunks.
  static Future<String> computeFileSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Package file does not exist', filePath);
    }
    return computeStreamSha256(file.openRead());
  }

  /// Computes the lowercase hexadecimal SHA-256 digest of a byte [stream].
  static Future<String> computeStreamSha256(Stream<List<int>> stream) async {
    int h0 = 0x6a09e667;
    int h1 = 0xbb67ae85;
    int h2 = 0x3c6ef372;
    int h3 = 0xa54ff53a;
    int h4 = 0x510e527f;
    int h5 = 0x9b05688c;
    int h6 = 0x1f83d9ab;
    int h7 = 0x5be0cd19;

    final w = Uint32List(64);
    final block = Uint8List(64);
    final blockView = ByteData.sublistView(block);
    int blockOffset = 0;
    int totalBytes = 0;

    void processBlock() {
      for (int i = 0; i < 16; i++) {
        w[i] = blockView.getUint32(i * 4, Endian.big);
      }
      for (int i = 16; i < 64; i++) {
        final s0 =
            _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 =
            _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      int a = h0;
      int b = h1;
      int c = h2;
      int d = h3;
      int e = h4;
      int f = h5;
      int g = h6;
      int h = h7;

      for (int i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    await for (final chunk in stream) {
      int offset = 0;
      final length = chunk.length;
      totalBytes += length;

      while (offset < length) {
        final copyLen = (64 - blockOffset) < (length - offset)
            ? (64 - blockOffset)
            : (length - offset);
        block.setRange(blockOffset, blockOffset + copyLen, chunk, offset);
        blockOffset += copyLen;
        offset += copyLen;

        if (blockOffset == 64) {
          processBlock();
          blockOffset = 0;
        }
      }
    }

    // Append 0x80 padding byte
    block[blockOffset++] = 0x80;
    if (blockOffset > 56) {
      while (blockOffset < 64) {
        block[blockOffset++] = 0;
      }
      processBlock();
      blockOffset = 0;
    }
    while (blockOffset < 56) {
      block[blockOffset++] = 0;
    }

    final totalBits = totalBytes * 8;
    blockView.setUint32(56, (totalBits >>> 32) & 0xffffffff, Endian.big);
    blockView.setUint32(60, totalBits & 0xffffffff, Endian.big);
    processBlock();

    final digest = ByteData(32)
      ..setUint32(0, h0, Endian.big)
      ..setUint32(4, h1, Endian.big)
      ..setUint32(8, h2, Endian.big)
      ..setUint32(12, h3, Endian.big)
      ..setUint32(16, h4, Endian.big)
      ..setUint32(20, h5, Endian.big)
      ..setUint32(24, h6, Endian.big)
      ..setUint32(28, h7, Endian.big);

    final sb = StringBuffer();
    for (int i = 0; i < 32; i++) {
      sb.write(digest.getUint8(i).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Computes the SHA-256 digest of a UTF-8 string.
  static Future<String> computeStringSha256(String input) {
    return computeStreamSha256(Stream<List<int>>.value(utf8.encode(input)));
  }

  /// Compares two hexadecimal SHA-256 digests in constant time (case-insensitive).
  static bool equalsDigest(String actualHex, String expectedHex) {
    final cleanActual = actualHex.trim().toLowerCase();
    final cleanExpected = expectedHex.trim().toLowerCase();
    if (cleanActual.length != 64 || cleanExpected.length != 64) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < 64; i++) {
      diff |= cleanActual.codeUnitAt(i) ^ cleanExpected.codeUnitAt(i);
    }
    return diff == 0;
  }
}
