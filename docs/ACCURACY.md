# Accuracy validation

Unit tests establish code behavior, not orchard accuracy. The three supplied JPEGs have no annotations or verified ripeness labels. No labeled dataset or training checkpoint was supplied, and the bundled weights have not been retrained.

## Field benchmark

1. Collect original-resolution images and slow pans across multiple trees, cultivars, distances, lighting conditions, and phones. Include negative scenes: leaves, flowers, hands, ground, empty trees, bags, and other fruit.
2. Annotate visible fruit, including small/occluded examples. Agree on ambiguous-object policy and have a second reviewer check labels. Verify ripeness against a cultivar-specific inspection protocol; peel color is not ground truth for internal maturity.
3. Split by tree/orchard/capture session before augmentation. Keep adjacent video frames, crops, and duplicates together. Reserve an untouched test set.
4. Record model hash, class order, dataset/package versions, seed, confidence, IoU, tiling, and AI settings. Compare candidates on identical inputs.
5. Tune thresholds on validation data, then lock them before testing. The app's automatic sensitivity is an existing score-distribution heuristic, not measured calibration.
6. Report precision/recall/F1, small-fruit recall, per-class ripeness confusion, count MAE and bias. For video, annotate identities and measure double counts/missed tracks separately.
7. Compare exported TFLite with the trained checkpoint; validate quantized models with representative calibration images. Measure latency, memory, battery/thermal behavior, and responsiveness on target phones.

## Offline evaluator

`tool/evaluate_detections.dart` accepts reference and predicted boxes in the same pixel coordinate system:

```json
{"images":[{"id":"tree-01","truth":[{"box":[100,80,140,135],"class":"unripe"}],"predictions":[{"box":[101,81,141,136],"class":"unripe","confidence":0.8}]}]}
```

```sh
dart run tool/evaluate_detections.dart evaluation.json 0.25 0.5
```

Classes: `over_ripe`, `ripe`, `unripe`. Empty truth lists represent negative scenes. Export predictions before manual/AI corrections when evaluating the detector alone. Matching is one-to-one, confidence-ordered, and class-independent; ripeness is scored on matched fruit. Output includes precision, recall, F1, count MAE/bias, ripeness confusion, and per-image counts. Undefined ratios are null. This is fixed-threshold evaluation, not COCO mAP.

## Training priorities

- Add small green fruit among leaves, occluded fruit, and hard negatives from false-positive overlays.
- Keep class semantics fixed. Legacy `half_ripe` fields currently mean over-ripe, not a fourth class.
- Evaluate larger training resolution and crop-aware training while retaining full-canopy examples.
- Audit hue/saturation augmentation for distortion of ripeness labels; tune it on validation data.
- Group data splits before training to prevent near-duplicate leakage.
- Add and validate motion compensation/re-identification before promising walk-around unique counts.
- Use rights-cleared orchard captures. One supplied sample is watermarked; these three photos should not become an independent training/test benchmark without provenance and labeling.

## References

- [LiteRT quantization specification](https://developers.google.com/edge/litert/quantization/quantization_spec): tensor scale and zero-point encoding.
- [Ultralytics sliced inference](https://docs.ultralytics.com/guides/sahi-tiled-inference): retaining small-object detail through crops, subject to domain validation.
- [Ultralytics export](https://docs.ultralytics.com/modes/export): deployment format and calibration settings.
