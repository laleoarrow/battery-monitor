#!/usr/bin/env python3
"""Losslessly package a recorded native PNG sweep; preserve input files."""

import argparse
import fractions
import hashlib
import json
from pathlib import Path
import signal
import struct
import subprocess
import tempfile
import zlib


def digest(data):
    return hashlib.sha256(data).hexdigest()


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def read_png(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Not a PNG")
    parts, offset = [], 8
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + size]
        crc = struct.unpack_from(">I", data, offset + 8 + size)[0]
        if crc != zlib.crc32(kind + body):
            raise ValueError("PNG CRC mismatch")
        parts.append((kind, body))
        offset += size + 12
    if offset != len(data) or parts[-1] != (b"IEND", b"") or any(k == b"acTL" for k, _ in parts):
        raise ValueError("Expected a complete static native PNG")
    return data, parts


def rgba_hashes(ffmpeg, arguments):
    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-v", "error", *arguments, "-fps_mode", "passthrough",
         "-pix_fmt", "rgba", "-f", "framehash", "-hash", "sha256", "-"],
        check=True, capture_output=True, text=True, timeout=90)
    return [line.split(",")[-1].strip() for line in result.stdout.splitlines()
            if line and not line.startswith("#")]


def main():
    def interrupted(number, _frame):
        raise SystemExit(128 + number)
    for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", help="New PNG filename beside this script")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()
    destination = Path(__file__).resolve().parent
    if Path(args.output).name != args.output or not args.output.endswith(".png"):
        parser.error("Output must be a PNG basename")
    output = destination / args.output
    report = output.with_suffix(".json")
    if output.exists() or report.exists():
        parser.error("Refusing to overwrite an existing output")
    raw_manifest = args.manifest.read_bytes()
    metadata = json.loads(raw_manifest)
    frames = metadata["frames"]
    if len(frames) != metadata["frameCount"] or len(frames) < 2:
        raise ValueError("Incomplete sweep")
    scratch = destination / ".encoding.noindex"
    created = []
    try:
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="run.", dir=scratch) as temporary:
            temporary = Path(temporary)
            image = bytearray(b"\x89PNG\r\n\x1a\n")
            records, concat, sequence, prefix = [], [], 0, None
            for index, frame in enumerate(frames):
                source = (args.manifest.resolve().parent / frame["file"]).resolve()
                if source.parent != args.manifest.resolve().parent or not frame["pointerOverrideNil"]:
                    raise ValueError("Unexpected input path or DEBUG pointer override")
                original, parts = read_png(source)
                first_idat = next(i for i, part in enumerate(parts) if part[0] == b"IDAT")
                if index == 0:
                    prefix = parts[:first_idat]
                    image.extend(chunk(*prefix[0]))
                    image.extend(chunk(b"acTL", struct.pack(">II", len(frames), 0)))
                    image.extend(b"".join(chunk(k, v) for k, v in prefix[1:]))
                elif prefix != parts[:first_idat]:
                    raise ValueError("Frame dimensions or color metadata changed")
                width, height = struct.unpack_from(">II", parts[0][1])
                if [width, height] != [frame["pixelWidth"], frame["pixelHeight"]]:
                    raise ValueError("Frame dimensions disagree with capture metadata")
                timestamp = fractions.Fraction(str(frame["timestampSeconds"]))
                end = fractions.Fraction(str(frames[index + 1]["timestampSeconds"] if index + 1 < len(frames)
                                             else metadata["endTimestampSeconds"]))
                duration = end - timestamp
                delay = duration.limit_denominator(65535)
                if not 0 < delay.numerator <= 65535 or abs(float(delay - duration)) > 0.000001:
                    raise ValueError("APNG cannot represent the recorded frame interval")
                image.extend(chunk(b"fcTL", struct.pack(">IIIIIHHBB", sequence, width, height, 0, 0,
                                                        delay.numerator, delay.denominator, 0, 0)))
                sequence += 1
                for kind, body in parts[first_idat:]:
                    if kind == b"IDAT":
                        image.extend(chunk(b"IDAT", body) if index == 0 else chunk(b"fdAT", struct.pack(">I", sequence) + body))
                        if index != 0:
                            sequence += 1
                concat.append("file '" + str(source).replace("'", "'\\''") + "'\nduration 0.04\n")
                records.append({"file": frame["file"], "sourcePNG_SHA256": digest(original),
                                "timestampSeconds": frame["timestampSeconds"], "durationSeconds": float(duration),
                                "APNGDelayFraction": [delay.numerator, delay.denominator],
                                "timingErrorSeconds": float(delay - duration), "captureCG": frame["captureCG"],
                                "actualCGPointer": frame["actualCGPointer"], "pointerOverrideNil": True})
            image.extend(chunk(b"IEND", b""))
            staged = temporary / "animation.png"
            staged.write_bytes(image)
            playlist = temporary / "frames.ffconcat"
            playlist.write_text("ffconcat version 1.0\n" + "".join(concat))
            original_hashes = rgba_hashes(args.ffmpeg, ["-f", "concat", "-safe", "0", "-i", str(playlist)])
            decoded_hashes = rgba_hashes(args.ffmpeg, ["-f", "apng", "-ignore_loop", "1", "-i", str(staged)])
            if len(original_hashes) != len(frames) or original_hashes != decoded_hashes:
                raise ValueError("Decoded RGBA pixels or frame order changed")
            for record, pixel_hash in zip(records, original_hashes):
                record["decodedRGBA_SHA256"] = pixel_hash
            result = {"schema": 1, "file": output.name, "SHA256": digest(image),
                      "case": metadata["case"], "target": metadata["target"], "frameCount": len(frames),
                      "pixelDimensions": [width, height], "loopCount": 0,
                      "sourceManifestSHA256": digest(raw_manifest),
                      "endTimestampSeconds": metadata["endTimestampSeconds"],
                      "cursorDrawnInPixels": metadata["cursorDrawnInPixels"],
                      "encoding": "Original PNG IDAT streams in APNG; recorded frame intervals; no pixel processing",
                      "encodingScriptSHA256": digest(Path(__file__).read_bytes()),
                      "decoder": subprocess.check_output([args.ffmpeg, "-version"], text=True, timeout=10).splitlines()[0],
                      "decodedFramesRGBAIdentical": True, "frames": records}
            with output.open("xb") as handle:
                created.append(output)
                handle.write(image)
            with report.open("x") as handle:
                created.append(report)
                json.dump(result, handle, indent=2)
                handle.write("\n")
    except BaseException:
        for path in created:
            path.unlink(missing_ok=True)
        raise
    finally:
        try:
            scratch.rmdir()
        except OSError:
            pass
    print(json.dumps({"file": output.name, "SHA256": result["SHA256"], "frameCount": len(frames),
                      "decodedFramesRGBAIdentical": True}))


if __name__ == "__main__":
    main()
