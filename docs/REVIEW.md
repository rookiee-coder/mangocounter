# Code review — 2026-10-09

## Implemented fixes

| Area | Change |
| --- | --- |
| Model | Validate square RGB input, raw three-class output, types, and label order. Remove incompatible optional classifier code that guessed preprocessing and mapped half-ripe to over-ripe. |
| Quantization | Use signed/unsigned scale and zero point for RGB encoding and warm-up; use compatible output buffers. |
| Photo detail | Bounded overlapping crops for all high-resolution image shapes; discard internal-edge fragments and merge globally. |
| Output parser | Explicit embedded-NMS mode, small candidate tensor support, finite-coordinate checks, non-mutating NMS. Remove unvalidated photo size/aspect vetoes. Deployment explicitly uses normalized YOLO boxes. |
| Lifecycle | Close receive ports, bound worker waits, register disposal, release native interpreter. |
| Failure integrity | Model initialization errors no longer create fabricated demo counts. Video frame/inference errors cannot silently produce partial/zero results. |
| Tracker | New tracks no longer immediately accrue a miss; retain distant fruit previously rejected by relative area; reject invalid geometry. |
| Video | Read actual duration off the Android UI thread; sample through clip end, up to 32 frames; 1280-pixel extraction; explicit 30-second limit. |
| Settings/telemetry | Honor video confidence/IoU/tiling settings; retain thresholds and real inference timing. Photo picker honors resolution setting. |
| Canopy | Offline foliage color no longer vetoes a scan; skip network probe without credentials. High-confidence online first-frame rejection remains. |
| Async state | Guard stale photo/chat responses and concurrent requests; preserve manual edits/deletions while AI crop review is pending. |
| Storage | Save photo bytes in app documents instead of image-picker cache; guard concurrent saves and show errors. |
| Release network | Add INTERNET permission to main Android manifest. |
| Training | Remove embedded credential, assert class order, seed training, evaluate/export best checkpoint, disable embedded NMS. |
| Validation | Add regression tests, local sample-model probe, and offline fixed-threshold evaluator. |

Rotate the removed Roboflow credential. Removing it from the working file does not revoke it or erase it from Git history.

## Actual model/sample inspection

Bundled model: float32 input `[1,3,640,640]`, output `[1,7,8400]`; classes Over ripe, Ripe, Unripe.

SHA256: `45417371B2CA93094E4A6CF0D3DA3310084D6FDF68EE2F58DE95E8406B4247BB`.

The model ran locally with LiteRT 2.1.3 on all three supplied photos. Pillow bilinear resizing approximates Flutter preprocessing, so this is not a device parity test. At confidence 0.25 / NMS IoU 0.45:

| Image prefix | Baseline boxes | Updated boxes | Experimental aggressive crops |
| --- | ---: | ---: | ---: |
| `0e03d7b9` | 7 | 7 | 7 |
| `6e3fd1c9` | 7 | 7 | 8 |
| `9ee262e2` | 36 | 36 | 39 |

Unchanged counts do not establish an accuracy gain. Visual inspection found missed fruit in the watermarked cluster and leaf/fragment ambiguity in the canopy. Aggressive crops recovered a partly hidden fruit in the second photo but introduced a leaf false positive in the third. That strategy remains probe-only. No accuracy percentage is claimed without reference labels.

Detailed predictions/overlays: `build/sample-evaluation/`. Source photos were not uploaded or committed.

## Verification and limits

- Expanded suite: 75 passing tests (56 existing, 19 new) at the review checkpoint. Android debug APK compiled with the native metadata channel. Final check results are recorded in the task response.
- No Android device was attached. Camera/orientation, native frame extraction, sustained memory/thermal behavior, and release operation need device tests.
- No training was performed. Dataset coverage, leakage, label quality, and model provenance cannot be established from this repository.
- Tracking remains greedy IoU matching, not ByteTrack/Kalman or camera-pose recovery. Re-entry, fast pans, and hidden fruit remain limitations. UI now calls counts a visible estimate.
- Automatic confidence and remaining video geometry filters are uncalibrated heuristics. Benchmark them.
- Video history stores aggregate counts and one frame, not a complete track timeline.
- Legacy half-ripe database names remain for compatibility; semantic migration requires a versioned decision.
- Keys remain in local preferences; production credential provisioning, retained-file cleanup, startup/storage failure handling, package identifier, and release signing remain release-hardening work. Release currently uses debug signing.
- Tiling can run up to five passes per frame. Desktop timing does not establish phone performance.

This is an indexed review and a set of verified fixes, not a guarantee that every defect or field failure has been eliminated.
