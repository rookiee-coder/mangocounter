# MangoCount

Flutter Android app for estimating visible mango counts and visual ripeness from photos and short videos. The bundled YOLO TFLite model runs locally. Optional Gemini crop review/chat require internet and an API key.

## Run and verify

```sh
flutter pub get
flutter test
dart analyze lib test tool
flutter run --release
```

Configure production signing before publishing: Android release currently uses a debug key.

## Model contract

- Model: `assets/models/mango_yolo.tflite`; labels: `assets/models/labels.txt`.
- Class order: **Over ripe, Ripe, Unripe**. Single/two-class models are incompatible replacements.
- Square RGB input, batch 1, NHWC or NCHW. Float32 uses RGB/255; int8/uint8 use tensor scale and zero point.
- Raw YOLO output `[1,7,N]` or `[1,N,7]`, normalized center/size boxes. Export with `nms=False`.
- Bundled model: float32 `[1,3,640,640]` input and `[1,7,8400]` output.
- Full-frame inference plus up to four overlapping detail crops and global NMS. Disable tiling in Settings for speed. Accuracy gains require dataset validation.
- Production model failures display errors; mock counts require explicit test/demo injection.

## Video

Pan slowly across one side of the canopy without revisiting branches. Clips up to 30 seconds are sampled across their real duration, at most 32 frames with 1280-pixel extraction width. In-app recording is capped at 20 seconds.

Counts are visible-fruit estimates, not total tree yield. The tracker uses greedy IoU association and repeated observations. It does not implement ByteTrack, Kalman filtering, camera-pose recovery, or long-term re-identification. Hidden fruit cannot be counted reliably; revisiting branches can double-count. Visual ripeness predictions do not measure internal maturity.

## Training and evaluation

Use `train_mango_yolov11.ipynb` with the `ROBOFLOW_API_KEY` environment variable. It checks class order, seeds training, evaluates the best checkpoint, and exports without embedded NMS. This review did not retrain the weights.

See [review findings](docs/REVIEW.md), [codebase index](docs/CODEBASE_INDEX.md), and [accuracy procedure](docs/ACCURACY.md).

Optional local Windows sample probe:

```powershell
./tool/setup_evaluation_runtime.ps1
./build/evaluation-runtime/python.exe ./tool/probe_sample_photos.py 'C:\path\to\photos'
```

The optional runtime and diagnostics stay in ignored `build/` output. No photos are uploaded. The probe uses Pillow resizing and is not pixel-identical to Flutter. Its `detail` mode is experimental, not the deployed crop strategy.