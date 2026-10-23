"""YOLO recycling: preserve sources, audit labels, measure background FP; never train by default."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import zipfile

import yaml

NAMES = {0: 'plastic', 1: 'paper', 2: 'metal'}
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def image_files(folder):
    return sorted(p for p in Path(folder).rglob('*') if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS)


def normalize_names(names):
    if isinstance(names, list):
        return dict(enumerate(names))
    if isinstance(names, dict):
        return {int(k): v for k, v in names.items()}
    raise ValueError('names must be a list or dict')


def load_config(path):
    path = Path(path).resolve()
    cfg = yaml.safe_load(path.read_text(encoding='utf-8'))
    if normalize_names(cfg.get('names')) != NAMES:
        raise ValueError(f'Class mapping must be {NAMES}')
    root = Path(cfg.get('path', path.parent))
    if not root.is_absolute():
        root = path.parent / root
    root = root.resolve()
    for split in ('train', 'val', 'test'):
        if cfg.get(split) != f'images/{split}':
            raise ValueError(f'Expected images/{split}; confirm dataset layout before using this tool')
        if not (root / 'images' / split).is_dir() or not (root / 'labels' / split).is_dir():
            raise FileNotFoundError(f'Missing actual images/labels for {split}: {root}')
    return cfg, root


def parse_labels(text, context='label'):
    rows = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            values = list(map(float, line.split()))
            if len(values) != 5 or not all(math.isfinite(v) for v in values):
                raise ValueError('five finite numbers required')
            cls, x, y, w, h = values
            if not cls.is_integer() or int(cls) not in NAMES:
                raise ValueError('class id outside 0..2')
            if not (0 <= x <= 1 and 0 <= y <= 1 and 0 < w <= 1 and 0 < h <= 1):
                raise ValueError('invalid normalized coordinates')
            if min(x-w/2, y-h/2) < -1e-5 or max(x+w/2, y+h/2) > 1+1e-5:
                raise ValueError('box crosses image boundary')
            rows.append((int(cls), x, y, w, h))
        except ValueError as exc:
            raise ValueError(f'{context}:{number}: {exc}') from exc
    return rows


def xyxy(row):
    _, x, y, w, h = row
    return (x-w/2, y-h/2, x+w/2, y+h/2)


def overlap(a, b):
    a, b = xyxy(a), xyxy(b)
    inter = max(0, min(a[2], b[2])-max(a[0], b[0])) * max(0, min(a[3], b[3])-max(a[1], b[1]))
    aa, ab = (a[2]-a[0])*(a[3]-a[1]), (b[2]-b[0])*(b[3]-b[1])
    return inter / min(aa, ab), min(aa, ab) / max(aa, ab)


def split_hashes(root):
    return {str(p.relative_to(root)): digest(p) for kind in ('images', 'labels')
            for split in ('val', 'test') for p in sorted((root/kind/split).rglob('*')) if p.is_file()}


def inspect_dataset(data_yaml):
    _, root = load_config(data_yaml)
    summaries, candidates, all_hashes = {}, [], defaultdict(list)
    for split in ('train', 'val', 'test'):
        images = image_files(root/'images'/split)
        objects, per_class_images, large_images = Counter(), Counter(), Counter()
        negatives = 0
        label_paths = set()
        for image in images:
            rel = image.relative_to(root/'images'/split)
            label = (root/'labels'/split/rel).with_suffix('.txt')
            if not label.is_file():
                raise FileNotFoundError(f'Actual label missing; will not invent it: {label}')
            if label in label_paths:
                raise ValueError(f'Multiple images share one label path: {label}')
            label_paths.add(label)
            rows = parse_labels(label.read_text(encoding='utf-8'), str(label))
            objects.update(r[0] for r in rows)
            per_class_images.update({r[0] for r in rows})
            large_images.update({r[0] for r in rows if r[3]*r[4] >= .8})
            negatives += not rows
            all_hashes[digest(image)].append({'split': split, 'path': str(image.relative_to(root))})
            for i, a in enumerate(rows):
                for j, b in enumerate(rows[i+1:], i+1):
                    if a[0] == b[0]:
                        containment, area_ratio = overlap(a, b)
                        if containment >= .95 and area_ratio <= .6:
                            candidates.append({'split': split, 'image': str(image), 'label': str(label),
                                               'class_name': NAMES[a[0]], 'box_a': i+1, 'box_b': j+1,
                                               'containment': containment, 'area_ratio': area_ratio,
                                               'review_decision': '', 'review_reason': ''})
        actual_labels = set((root/'labels'/split).rglob('*.txt'))
        if actual_labels != label_paths:
            raise ValueError(f'Orphan labels in {split}: {sorted(map(str, actual_labels-label_paths))[:5]}')
        summaries[split] = {'images': len(images), 'class_images': dict(per_class_images),
                            'objects': dict(objects), 'negative_images': negatives,
                            'large_box_images_area_at_least_80pct': dict(large_images),
                            'review_candidate_images': len({c['image'] for c in candidates if c['split']==split})}
    duplicates = [v for v in all_hashes.values() if len(v)>1]
    return {'class_mapping': NAMES, 'splits': summaries, 'exact_byte_duplicates': duplicates,
            'review_note': 'Candidates are not confirmed errors; never delete/merge boxes automatically.'}, candidates


def extract_checked(archive, target):
    with zipfile.ZipFile(archive) as z:
        infos = z.infolist()
        if len(infos)>20000 or sum(i.file_size for i in infos)>2_000_000_000:
            raise ValueError('Archive exceeds inspection limits')
        if len({i.filename for i in infos}) != len(infos):
            raise ValueError('Duplicate archive entries')
        for info in infos:
            rel = PurePosixPath(info.filename)
            if rel.is_absolute() or '..' in rel.parts or '\\' in info.filename:
                raise ValueError('Unsafe archive path')
            if ((info.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError('Archive symlink rejected')
            if not (target/info.filename).resolve().is_relative_to(target.resolve()):
                raise ValueError('Archive path escapes target')
        z.extractall(target)


def prepare(args):
    out = Path(args.out).resolve()
    if out.exists():
        raise FileExistsError(f'Existing output is preserved: {out}')
    inputs = {k: Path(getattr(args,k)).resolve() for k in ('starter', 'supplement', 'patch')}
    for p in inputs.values():
        if not p.is_file():
            raise FileNotFoundError(f'Actual input required: {p}')
    negatives = image_files(args.negative_dir) if args.negative_dir else []
    if args.negative_dir and (not args.confirm_negatives or not negatives):
        raise ValueError('Negative images must exist and be manually confirmed with --confirm-negatives')
    if any(p.suffix.lower() not in {'.jpg','.jpeg','.png'} for p in negatives):
        raise ValueError('Use actual JPG/PNG negative images')
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='recycling_prepare_', dir=out.parent) as temp:
        temp = Path(temp)
        extract_checked(inputs['starter'], temp/'starter')
        extract_checked(inputs['supplement'], temp/'supplement')
        root = temp/'starter/recycling_yolo_starter'
        # Rewrite only the extracted copy when a ZIP retains an old /content path.
        cfg = yaml.safe_load((root/'data.yaml').read_text(encoding='utf-8'))
        cfg['path'] = str(root)
        (root/'data.yaml').write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding='utf-8')
        load_config(root/'data.yaml')
        protected = split_hashes(root)
        extra = temp/'supplement/recycling_supplement_v1'
        pics = image_files(extra/'images/train')
        if len(pics) != 11:
            raise ValueError(f'Expected supplied supplement v1: 11 images; got {len(pics)}')
        for pic in pics:
            for src, dst in [(pic, root/'images/train'/pic.name),
                             (extra/'labels/train'/pic.with_suffix('.txt').name, root/'labels/train'/pic.with_suffix('.txt').name)]:
                if not src.is_file():
                    raise FileNotFoundError(src)
                if dst.exists():
                    raise FileExistsError(f'Supplement collision: {dst}')
                shutil.copy2(src, dst)
        patch = json.loads(inputs['patch'].read_text(encoding='utf-8'))
        if patch.get('version') != 1 or len(patch.get('changes', [])) != 27:
            raise ValueError('Expected actual reviewed v1 patch with 27 changes')
        seen = set()
        for item in patch['changes']:
            rel = PurePosixPath(item['path'])
            if rel.parts[:2] != ('labels','train') or len(rel.parts)!=3 or rel.suffix!='.txt' or rel in seen:
                raise ValueError(f'Patch must have unique train label paths: {rel}')
            seen.add(rel)
            current = (root/str(rel)).read_text(encoding='utf-8').strip()
            if current not in (item['before'].strip(), item['after'].strip()):
                raise ValueError(f'Patch before/after does not match: {rel}')
            parse_labels(item['after'], str(rel))
        for item in patch['changes']:
            path = root/item['path']
            backup = root/'label_backup_v1'/item['path']
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
            path.write_text(item['after'], encoding='utf-8')
        known = {digest(p) for split in ('train','val','test') for p in image_files(root/'images'/split)}
        additions = []
        if negatives:
            from PIL import Image, ImageOps
            for source in negatives:
                sha = digest(source)
                if sha in known:
                    raise ValueError(f'Negative duplicates an existing image: {source}')
                # Only actual, explicitly confirmed empty scenes receive empty labels.
                with Image.open(source) as im:
                    rgb = ImageOps.exif_transpose(im).convert('RGB')
                    name = f'negative_{sha}.png'
                    rgb.save(root/'images/train'/name)
                (root/'labels/train'/Path(name).with_suffix('.txt')).write_text('', encoding='utf-8')
                additions.append({'source': str(source), 'source_sha256': sha, 'saved_name': name})
                known.add(sha)
        for cache in (root/'labels').rglob('*.cache'):
            cache.unlink()
        if split_hashes(root) != protected:
            raise AssertionError('val/test files must remain byte-identical')
        cfg['path'] = str(root)
        (root/'data.yaml').write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding='utf-8')
        summary, _ = inspect_dataset(root/'data.yaml')
        expected = {'train':731+len(additions), 'val':90, 'test':90}
        if any(summary['splits'][s]['images'] != count for s,count in expected.items()):
            raise ValueError('Unexpected image counts; do not continue training')
        write_json(root/'preparation_history.json', {'inputs':{k:{'path':str(v),'sha256':digest(v)} for k,v in inputs.items()},
                   'applied_existing_patch_changes':27, 'new_label_fixes_invented':False,
                   'confirmed_negative_additions':additions, 'unchanged_val_test_hashes':protected,
                   'note':'No additional label changes were inferred from overlap candidates.'})
        cfg['path'] = str(out)
        (root/'data.yaml').write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding='utf-8')
        shutil.move(str(root), str(out))
    print(out/'data.yaml')


def audit(args):
    out = Path(args.out)
    if out.exists():
        raise FileExistsError(out)
    summary, candidates = inspect_dataset(args.data)
    out.mkdir(parents=True)
    write_json(out/'audit.json', summary)
    fields = ['split','image','label','class_name','box_a','box_b','containment','area_ratio','review_decision','review_reason']
    with (out/'label_review.csv').open('w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader(); writer.writerows(candidates)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


def apply_reviewed(args):
    """Apply only an actual image-verified train patch to another fresh dataset copy."""
    cfg, source = load_config(args.data)
    out = Path(args.out).resolve()
    if out.exists() or out.is_relative_to(source):
        raise FileExistsError('Use a new output folder outside the source dataset')
    patch_path = Path(args.patch)
    patch = json.loads(patch_path.read_text(encoding='utf-8'))
    if patch.get('version') != 2 or not patch.get('changes'):
        raise ValueError('Expected image-reviewed v2 patch')
    seen = set()
    for item in patch['changes']:
        rel = PurePosixPath(item['path'])
        if rel.parts[:2] != ('labels','train') or len(rel.parts)!=3 or rel.suffix!='.txt' or rel in seen:
            raise ValueError('Only unique, actual train labels may be changed')
        seen.add(rel)
        if (source/str(rel)).read_text(encoding='utf-8') != item['before']:
            raise ValueError(f'Actual source label differs: {rel}')
        image = source/'images/train'/item['image_filename']
        if Path(item['image_filename']).name != item['image_filename'] or digest(image) != item['image_sha256']:
            raise ValueError('Image does not match the visually reviewed source')
        if Path(item['image_filename']).stem != rel.stem:
            raise ValueError('Image and label stem mismatch')
        parse_labels(item['after'], str(rel))
    protected = split_hashes(source)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='recycling_review_', dir=out.parent) as temp:
        target = Path(temp)/'data'
        shutil.copytree(source,target)
        for item in patch['changes']:
            path = target/item['path']
            backup = target/'label_backup_v2'/item['path']
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path,backup)
            path.write_text(item['after'],encoding='utf-8')
        for cache in (target/'labels').rglob('*.cache'):
            cache.unlink()
        if split_hashes(target) != protected:
            raise AssertionError('val/test must remain byte-identical')
        cfg['path'] = str(target)
        (target/'data.yaml').write_text(yaml.safe_dump(cfg,allow_unicode=True),encoding='utf-8')
        inspect_dataset(target/'data.yaml')
        write_json(target/'reviewed_patch_history.json',{'patch_sha256':digest(patch_path),
                   'source_data':str(source), 'patch':patch, 'val_test_unchanged':True})
        cfg['path'] = str(out)
        (target/'data.yaml').write_text(yaml.safe_dump(cfg,allow_unicode=True),encoding='utf-8')
        shutil.move(str(target),str(out))
    print(out/'data.yaml')


def load_model(weights):
    import ultralytics
    from ultralytics import YOLO
    if ultralytics.__version__ != '8.4.182':
        raise RuntimeError('Use ultralytics==8.4.182 for comparable results')
    weights = Path(weights)
    if not weights.is_file():
        raise FileNotFoundError('Local actual weights required; no automatic download')
    model = YOLO(str(weights))
    if normalize_names(model.names) != NAMES:
        raise ValueError(f'Checkpoint class mapping mismatch: {model.names}')
    return model


def predict_one(model, path, args):
    from PIL import Image, ImageOps
    with Image.open(path) as raw:
        original_size = raw.size
        image = ImageOps.exif_transpose(raw).convert('RGB')
    result = model.predict(image, conf=args.conf, iou=args.iou, imgsz=args.imgsz,
                           device=args.device, verbose=False, save=False)[0]
    records = []
    for box in result.boxes:
        x1,y1,x2,y2 = map(float, box.xyxy[0].tolist())
        cls = int(box.cls.item())
        records.append({'class_id':cls, 'class_name':model.names[cls], 'confidence':float(box.conf.item()),
                        'xyxy_px':[x1,y1,x2,y2],
                        'image_area_pct':100*(x2-x1)*(y2-y1)/(image.width*image.height)})
    return image, result, {'source':str(path), 'source_sha256':digest(path), 'original_size':original_size,
                           'corrected_size':image.size, 'detections':records,
                           'detection_count':len(records)}


def inference(args):
    images = [Path(p).resolve() for p in args.images]
    for p in images:
        if not p.is_file():
            raise FileNotFoundError(p)
    out = Path(args.out)
    if out.exists():
        raise FileExistsError(out)
    model = load_model(args.weights)
    weight_hash = digest(args.weights)
    out.mkdir(parents=True)
    records = []
    for index, path in enumerate(images, 1):
        _, result, record = predict_one(model, path, args)
        result.save(filename=str(out/f'{index:02d}_annotated.jpg'))
        records.append(record)
    if digest(args.weights) != weight_hash:
        raise AssertionError('Weights changed unexpectedly')
    write_json(out/'predictions.json', {'weights_sha256':weight_hash, 'weights':str(Path(args.weights).resolve()),
               'class_mapping':NAMES, 'preprocessing':'EXIF corrected; RGB PIL; Ultralytics letterbox; no manual stretch/normalization',
               'settings':{'conf':args.conf,'iou':args.iou,'imgsz':args.imgsz,'device':args.device},
               'note':'No forced top class, box-size rejection, or invented confidence. Empty results remain empty.',
               'images':records})
    print(out/'predictions.json')


def evaluate(args):
    _, root = load_config(args.data)
    out = Path(args.out).resolve()
    if out.exists():
        raise FileExistsError(out)
    negatives = image_files(args.negative_eval_dir) if args.negative_eval_dir else []
    if args.negative_eval_dir and (not args.confirm_negatives or not negatives):
        raise ValueError('Provide actual manually confirmed empty evaluation scenes')
    # Prevent evaluating backgrounds already present in train, including prepared PNG copies.
    if negatives:
        from PIL import Image, ImageOps
        def pixel_hash(path):
            with Image.open(path) as im:
                im = ImageOps.exif_transpose(im).convert('RGB')
                return hashlib.sha256(str(im.size).encode()+im.tobytes()).hexdigest()
        train_hashes = {pixel_hash(p) for p in image_files(root/'images/train')}
        if any(pixel_hash(p) in train_hashes for p in negatives):
            raise ValueError('Negative evaluation contains a training image; use independent photos')
    model = load_model(args.weights)
    weights_hash = digest(args.weights)
    # Cache files are restricted to this scratch copy; source dataset is read only.
    with tempfile.TemporaryDirectory(prefix='recycling_eval_') as temp:
        temp = Path(temp)
        for kind in ('images','labels'):
            shutil.copytree(root/kind/args.split, temp/kind/args.split)
        cfg = {'path':str(temp), 'train':f'images/{args.split}', 'val':f'images/{args.split}',
               'test':f'images/{args.split}', 'names':NAMES}
        local_yaml = temp/'data.yaml'
        local_yaml.write_text(yaml.safe_dump(cfg), encoding='utf-8')
        metrics = model.val(data=str(local_yaml), split=args.split, imgsz=args.imgsz,
                            batch=8, device=args.device, workers=0, conf=.001, iou=args.iou,
                            project=str(out), name='object_metrics', plots=False, verbose=False)
    # Negative scenes have zero GT objects: report false positives, not mAP/recall on empty GT.
    rows = [predict_one(model,p,args)[2] for p in negatives]
    false_positives = sum(r['detection_count'] for r in rows)
    report = {'weights_sha256':weights_hash, 'split':args.split, 'object_metrics':metrics.results_dict,
              'per_class':[{'name':NAMES[i], 'precision':float(metrics.box.p[j]),
                            'recall':float(metrics.box.r[j]), 'mAP50':float(metrics.box.ap50[j]),
                            'mAP50-95':float(metrics.box.ap[j])}
                           for j,i in enumerate(map(int,metrics.box.ap_class_index))],
              'settings':{'imgsz':args.imgsz, 'iou':args.iou,'device':args.device,
                          'object_val_conf':.001, 'negative_operating_conf':args.conf},
              'negative_evaluation':{'images':len(rows),'false_positive_boxes':false_positives if rows else None,
                'images_with_false_positives':sum(r['detection_count']>0 for r in rows) if rows else None,
                'false_positive_image_rate':sum(r['detection_count']>0 for r in rows)/len(rows) if rows else None,
                'false_positives_per_image':false_positives/len(rows) if rows else None,
                'status':'measured' if rows else 'not run; no independent negative photos provided',
                'details':rows}}
    if digest(args.weights) != weights_hash:
        raise AssertionError('Weights changed unexpectedly')
    write_json(out/'evaluation.json', report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


def training_plan(args):
    summary, _ = inspect_dataset(args.data)
    plan = {'data':str(Path(args.data).resolve()),'pretrained':str(Path(args.pretrained).resolve()),
            'epochs':20,'imgsz':640,'batch':8,'device':args.device,'seed':42,
            'project':str(Path(args.out).resolve()),'name':'controlled_v2','exist_ok':False,
            'reviewed':args.reviewed,'training_executed':False,
            'note':'Whole/part review candidates require human decisions; no automated label merge.'}
    print(json.dumps({'plan':plan,'dataset':summary}, ensure_ascii=False, indent=2))
    if not args.execute:
        print('DRY RUN ONLY: no training or model initialization performed.')
        return
    if not args.reviewed:
        raise ValueError('Complete label review and specify --reviewed before any training')
    if not Path(args.pretrained).is_file():
        raise FileNotFoundError('Actual local yolo11n.pt required')
    if (Path(args.out)/'controlled_v2').exists():
        raise FileExistsError('Use a new experiment output folder')
    model = load_pretrained(args.pretrained)
    model.train(data=plan['data'], epochs=20, imgsz=640, batch=8, device=args.device,
                seed=42, project=plan['project'], name='controlled_v2', exist_ok=False)
    print('Actual new weights:',Path(model.trainer.save_dir)/'weights/best.pt')


def load_pretrained(path):
    import ultralytics
    from ultralytics import YOLO
    if ultralytics.__version__ != '8.4.182':
        raise RuntimeError('Expected ultralytics==8.4.182')
    return YOLO(str(path))  # original COCO class names are expected before fine-tuning


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('prepare')
    for name in ('starter','supplement','patch','out'):
        p.add_argument('--'+name, required=True)
    p.add_argument('--negative-dir'); p.add_argument('--confirm-negatives', action='store_true')
    p.set_defaults(func=prepare)
    p = sub.add_parser('audit');p.add_argument('--data',required=True);p.add_argument('--out',required=True)
    p.set_defaults(func=audit)
    p = sub.add_parser('apply-reviewed')
    p.add_argument('--data',required=True);p.add_argument('--patch',required=True);p.add_argument('--out',required=True)
    p.set_defaults(func=apply_reviewed)
    def inference_args(p):
        p.add_argument('--weights',required=True);p.add_argument('--out',required=True)
        p.add_argument('--conf',type=float,default=.25);p.add_argument('--iou',type=float,default=.7)
        p.add_argument('--imgsz',type=int,default=640);p.add_argument('--device',default='cpu')
    p = sub.add_parser('predict');inference_args(p);p.add_argument('--images',nargs='+',required=True)
    p.set_defaults(func=inference)
    p = sub.add_parser('evaluate');inference_args(p);p.add_argument('--data',required=True)
    p.add_argument('--split',choices=['val','test'],default='val')
    p.add_argument('--negative-eval-dir');p.add_argument('--confirm-negatives',action='store_true')
    p.set_defaults(func=evaluate)
    p = sub.add_parser('train-plan');p.add_argument('--data',required=True);p.add_argument('--pretrained',required=True)
    p.add_argument('--out',required=True);p.add_argument('--device',default='0')
    p.add_argument('--execute',action='store_true');p.add_argument('--reviewed',action='store_true')
    p.set_defaults(func=training_plan)
    args = parser.parse_args()
    if hasattr(args,'conf') and not 0 < args.conf < 1:
        parser.error('--conf must be between 0 and 1')
    if hasattr(args,'iou') and not 0 < args.iou <= 1:
        parser.error('--iou must be between 0 and 1')
    args.func(args)


if __name__ == '__main__':
    main()
