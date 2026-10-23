"""Prepare confirmed backgrounds and measure existing weights. No training commands."""
import argparse
from collections import Counter
from pathlib import Path
from types import SimpleNamespace
import csv,json,shutil
import yaml
from PIL import Image,ImageOps
import hashlib
from recycling_fix import digest,split_hashes,load_config,inspect_dataset,load_model,predict_one,write_json


def pixel_hash(path):
    with Image.open(path) as raw:
        image=ImageOps.exif_transpose(raw).convert('RGB')
        return hashlib.sha256(str(image.size).encode()+image.tobytes()).hexdigest()


def prepare(args):
    out=Path(args.out).resolve()
    if out.exists():raise FileExistsError(out)
    cfg,base=load_config(args.base)
    rows=json.loads(Path(args.manifest).read_text())['images']
    assert len(rows)==55 and len({r['index'] for r in rows})==55
    for r in rows:
        if not r['zero_target_confirmed'] or r['ground_truth_object_count']!=0:raise ValueError('User-confirmed zero targets required')
        if digest(r['local_path'])!=r['sha256']:raise ValueError('Source hash mismatch')
    train=[r for r in rows if r['proposed_role']=='train_proposal']
    evaluation=[r for r in rows if r['proposed_role']=='development_evaluation_proposal']
    assert len(train)==35 and len(evaluation)==16
    assert not({r['proposed_group'] for r in train}&{r['proposed_group'] for r in evaluation})
    source_hashes=split_hashes(base)
    known={pixel_hash(p) for p in (base/'images').rglob('*') if p.suffix.lower() in ('.jpg','.jpeg','.png')}
    new_hashes=[pixel_hash(r['local_path']) for r in rows]
    if len(set(new_hashes))!=55 or set(new_hashes)&known:raise ValueError('Exact pixel duplicates found')
    shutil.copytree(base,out/'data')
    data=out/'data'
    for r in rows:
        name=f"background_{r['index']:02d}.jpg"
        role=r['proposed_role']
        image_dir=data/'images/train' if role=='train_proposal' else out/('development_eval' if role=='development_evaluation_proposal' else 'quality_hold')/'images'
        label_dir=data/'labels/train' if role=='train_proposal' else image_dir.parent/'labels'
        image_dir.mkdir(parents=True,exist_ok=True);label_dir.mkdir(parents=True,exist_ok=True)
        if (image_dir/name).exists():raise FileExistsError(name)
        shutil.copy2(r['local_path'],image_dir/name)
        (label_dir/Path(name).with_suffix('.txt')).write_text('')
        r['prepared_image']=str(image_dir/name)
    for p in (data/'labels').rglob('*.cache'):p.unlink()
    cfg['path']=str(data)
    (data/'data.yaml').write_text(yaml.safe_dump(cfg,allow_unicode=True))
    assert split_hashes(data)==source_hashes
    for split in ('train','val','test'):
        for kind in ('images','labels'):
            for original in (base/kind/split).iterdir():
                if original.is_file() and original.suffix!='.cache':
                    assert digest(original)==digest(data/kind/split/original.name)
    audit,_=inspect_dataset(data/'data.yaml')
    assert audit['splits']['train']['images']==766
    write_json(out/'preparation.json',{'base':str(base),'base_yaml_sha256':digest(args.base),'manifest_sha256':digest(args.manifest),'train_additions':35,'development_eval':16,'quality_hold':4,'split_status':'provisional visual groups, not verified independent locations','all_original_files_unchanged':True,'val_test_hashes':source_hashes,'audit':audit,'images':rows,'training_executed':False})
    print(json.dumps(audit,ensure_ascii=False))


def measure(args):
    root=Path(args.prepared).resolve();out=Path(args.out)
    if out.exists():raise FileExistsError(out)
    prep=json.loads((root/'preparation.json').read_text())
    rows=[r for r in prep['images'] if r['proposed_role']=='development_evaluation_proposal']
    for r in rows:
        r['prepared_image']=str(root/'development_eval/images'/f"background_{r['index']:02d}.jpg")
        if digest(r['prepared_image'])!=r['sha256']:raise ValueError('Prepared evaluation image hash mismatch')
    train_hashes={pixel_hash(p) for p in (root/'data/images/train').iterdir() if p.suffix.lower() in ('.jpg','.jpeg','.png')}
    if any(pixel_hash(r['prepared_image']) in train_hashes for r in rows):raise ValueError('Train/evaluation leakage')
    before=digest(args.weights);model=load_model(args.weights)
    out.mkdir(parents=True)
    settings=SimpleNamespace(conf=.25,iou=.7,imgsz=640,device='cpu')
    records=[];classes=Counter()
    for r in rows:
        _,result,record=predict_one(model,Path(r['prepared_image']),settings)
        record.update(photo=r['index'],proposed_group=r['proposed_group'],ground_truth_object_count=0)
        records.append(record)
        classes.update(d['class_name'] for d in record['detections'])
        result.save(filename=str(out/f"background_{r['index']:02d}_predicted.jpg"))
    assert before==digest(args.weights)
    bad=sum(r['detection_count']>0 for r in records);boxes=sum(r['detection_count'] for r in records)
    report={'weights':str(Path(args.weights).resolve()),'weights_sha256':before,'settings':vars(settings),'preprocessing':'EXIF transpose, RGB PIL, Ultralytics letterbox','images':len(records),'images_with_false_positives':bad,'false_positive_image_rate':bad/len(records),'false_positive_boxes':boxes,'false_positives_per_image':boxes/len(records),'false_positive_classes':dict(classes),'details':records,'limitations':['Development set of 16, not final test.','Physical location independence is not confirmed.','No inference on training candidates used for selection.','No post-training performance exists.'],'training_executed':False}
    write_json(out/'baseline_negative_evaluation.json',report)
    with (out/'per_image.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.writer(f);w.writerow(['photo','objects_gt','false_positive_boxes','predictions'])
        for r in records:w.writerow([r['photo'],0,r['detection_count'],'; '.join(f"{d['class_name']} {d['confidence']:.4f}" for d in r['detections'])])
    print(json.dumps({k:v for k,v in report.items() if k!='details'},ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('prepare');p.add_argument('--base',required=True);p.add_argument('--manifest',required=True);p.add_argument('--out',required=True);p.set_defaults(func=prepare)
    p=sub.add_parser('measure');p.add_argument('--prepared',required=True);p.add_argument('--weights',required=True);p.add_argument('--out',required=True);p.set_defaults(func=measure)
    args=parser.parse_args();args.func(args)
