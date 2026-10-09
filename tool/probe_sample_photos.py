"""Exploratory desktop model probe, not a substitute for Android/field validation.

Uses Pillow bilinear resizing (Flutter uses package:image linear resizing), so
pixel-level parity is not guaranteed. Never uploads source photos.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import time

import numpy as np
from PIL import Image, ImageDraw, ImageOps
from ai_edge_litert.interpreter import Interpreter


def iou(a, b):
    intersection = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
    union = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - intersection
    return intersection / union if union > 0 else 0


def nms(boxes, threshold=0.45):
    result = []
    for box in sorted(boxes, key=lambda b: -b['confidence']):
        if all(iou(box['box'], other['box']) <= threshold for other in result):
            result.append(box)
    return result


def tiles(w, h, size, mode):
    result = [(0, 0, w, h)]
    if mode == 'baseline':
        if max(w, h) / min(w, h) > 1.5:
            if h > w:
                result += [(0, 0, w, round(h * .6)), (0, round(h * .4), w, h - round(h * .4))]
            else:
                result += [(0, 0, round(w * .6), h), (round(w * .4), 0, w - round(w * .4), h)]
    elif mode == 'detail' and min(w, h) >= 256:
        tw, th = math.ceil(w*.6), math.ceil(h*.6)
        result += [(x, y, tw, th) for y in sorted({0, h-th}) for x in sorted({0, w-tw})]
    elif max(w, h) > size:
        tw, th = min(w, max(size, math.ceil(w*.6))), min(h, max(size, math.ceil(h*.6)))
        result += [(x, y, tw, th) for y in sorted({0, h-th}) for x in sorted({0, w-tw})]
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('photos', type=Path)
    parser.add_argument('--model', type=Path, default=Path('assets/models/mango_yolo.tflite'))
    parser.add_argument('--output', type=Path, default=Path('build/sample-evaluation'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    interpreter = Interpreter(model_path=str(args.model), num_threads=4)
    interpreter.allocate_tensors()
    inp, out = interpreter.get_input_details()[0], interpreter.get_output_details()[0]
    nchw = inp['shape'][1] == 3
    size = int(inp['shape'][2] if nchw else inp['shape'][1])
    labels = ['over_ripe', 'ripe', 'unripe']
    report = {'model_sha256': hashlib.sha256(args.model.read_bytes()).hexdigest(),
              'input_shape': inp['shape'].tolist(), 'output_shape': out['shape'].tolist(),
              'status': 'Unlabeled exploratory probe; no accuracy claim', 'images': []}
    for path in sorted(args.photos.glob('*.jpg')):
        source = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
        w, h = source.size
        entry = {'id': path.stem, 'width': w, 'height': h, 'modes': {}}
        for mode in ['baseline', 'updated', 'detail']:
            started = time.perf_counter()
            candidates = []
            for x, y, cw, ch in tiles(w, h, size, mode):
                scale = size / max(cw, ch)
                rw, rh = math.floor(cw*scale+.5), math.floor(ch*scale+.5)
                px, py = (size-rw)//2, (size-rh)//2
                canvas = Image.new('RGB', (size, size), (114, 114, 114))
                canvas.paste(source.crop((x, y, x+cw, y+ch)).resize((rw, rh), Image.Resampling.BILINEAR), (px, py))
                tensor = np.asarray(canvas, dtype=np.float32) / 255
                if nchw:
                    tensor = tensor.transpose(2, 0, 1)
                interpreter.set_tensor(inp['index'], np.expand_dims(tensor, 0))
                interpreter.invoke()
                output = interpreter.get_tensor(out['index'])[0]
                if output.shape[0] == 7:
                    output = output.T
                crop_boxes = []
                for row in output:
                    cls = int(np.argmax(row[4:]))
                    score = float(row[4+cls])
                    if score < .05:
                        continue
                    cx, cy, bw, bh = row[:4] * size
                    box = [max(0., min(cw, (cx-bw/2-px)/scale)), max(0., min(ch, (cy-bh/2-py)/scale)),
                           max(0., min(cw, (cx+bw/2-px)/scale)), max(0., min(ch, (cy+bh/2-py)/scale))]
                    bw, bh = box[2]-box[0], box[3]-box[1]
                    if bw <= 0 or bh <= 0:
                        continue
                    if mode == 'baseline' and score < .45 and (bw > bh*2 or bh > bw*3.5 or bw*bh/(cw*ch) > .1):
                        continue
                    if mode != 'baseline' and ((x > 0 and box[0] <= 1) or (y > 0 and box[1] <= 1) or
                        (x+cw < w and box[2] >= cw-1) or (y+ch < h and box[3] >= ch-1)):
                        continue
                    crop_boxes.append({'box': [float(box[0]+x), float(box[1]+y), float(box[2]+x), float(box[3]+y)],
                                       'class': labels[cls], 'confidence': score})
                candidates.extend(nms(crop_boxes))
            predictions = nms(candidates)
            entry['modes'][mode] = {'elapsed_ms': round((time.perf_counter()-started)*1000),
                'passes': len(tiles(w, h, size, mode)), 'predictions': predictions,
                'counts_by_threshold': {str(t): sum(d['confidence'] >= t for d in predictions) for t in [.12, .25, .35, .5]}}
            overlay = source.copy()
            draw = ImageDraw.Draw(overlay)
            for index, det in enumerate(d for d in predictions if d['confidence'] >= .25):
                draw.rectangle(det['box'], outline='red', width=2)
                draw.text((det['box'][0], det['box'][1]), f"{index+1}:{det['class']} {det['confidence']:.2f}", fill='white', stroke_width=1, stroke_fill='black')
            overlay.save(args.output / f'{path.stem}-{mode}.png')
        report['images'].append(entry)
        print(path.name, {m: v['counts_by_threshold'] for m, v in entry['modes'].items()}, flush=True)
    (args.output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
