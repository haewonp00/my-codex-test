"""Evaluate supplied YOLO checkpoints only. No training; preserve source files."""
from pathlib import Path
from collections import Counter
import argparse,csv,hashlib,inspect,json,platform,shutil,tempfile
import numpy as np
import pandas as pd
from PIL import Image,ImageOps
import torch,ultralytics,yaml
from ultralytics import YOLO

NAMES={0:'plastic',1:'paper',2:'metal'}
EXPECTED_OLD='2f65acc39ad05d21ef3531e64a727adfd5e1f003215c49be5e1f2640c336bc47'
DATA_COMMIT='6eefd2426392645d35653c23a422c86a1e626136'

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def save(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
def harmonic(p,r):return 2*p*r/(p+r) if p+r else 0.0

def checked_sources(repo,split):
    root=Path(repo)/'배경오탐_실험_v1/데이터셋'
    history=json.loads((root/'preparation.json').read_text())
    for rel,expected in history['val_test_hashes'].items():
        if sha(root/'data'/rel)!=expected:raise ValueError(f'Original val/test mismatch: {rel}')
    images=sorted((root/f'data/images/{split}').glob('*.jpg'))
    objects,counts=Counter(),Counter()
    for image in images:
        classes=[]
        for line in (root/f'data/labels/{split}'/image.with_suffix('.txt').name).read_text().splitlines():
            if line.strip():classes.append(int(line.split()[0]))
        objects.update(classes);counts.update(set(classes))
    assert len(images)==90
    negatives=sorted((root/'development_eval/images').glob('*.jpg'))
    expected={f"background_{r['index']:02d}.jpg":r['sha256'] for r in history['images'] if r['proposed_role']=='development_evaluation_proposal'}
    assert len(negatives)==16 and {p.name for p in negatives}==set(expected)
    for p in negatives:
        if sha(p)!=expected[p.name]:raise ValueError('Background photo mismatch')
    fingerprints={rel:sha(root/'data'/rel) for rel in history['val_test_hashes'] if f'/{split}/' in rel}
    return root,negatives,objects,counts,fingerprints

def historical(repo,split):
    repo=Path(repo)
    old=json.loads((repo/'수정안_v2/검증기록/existing_model_val_evaluation.json').read_text())
    negative=json.loads((repo/'배경오탐_실험_v1/측정결과/baseline_negative_evaluation.json').read_text())
    assert old['weights_sha256']==negative['weights_sha256']==EXPECTED_OLD
    if split!='val':return None,negative
    rows=[]
    d=old['object_metrics'];p=d['metrics/precision(B)'];r=d['metrics/recall(B)']
    rows.append(dict(model='old_record',class_name='ALL',precision=p,recall=r,F1_from_P_R=harmonic(p,r),mAP50=d['metrics/mAP50(B)'],mAP50_95=d['metrics/mAP50-95(B)']))
    for item in old['per_class']:
        p,r=item['precision'],item['recall']
        rows.append(dict(model='old_record',class_name=item['name'],precision=p,recall=r,F1_from_P_R=harmonic(p,r),mAP50=item['mAP50'],mAP50_95=item['mAP50-95']))
    return rows,negative

def evaluate_one(weights,name,root,negatives,objects,counts,args,out):
    before=sha(weights);model=YOLO(str(weights))
    if {int(k):v for k,v in model.names.items()}!=NAMES:raise ValueError('Checkpoint class mapping mismatch')
    # Create scratch copies: Ultralytics label caches never touch the source dataset.
    with tempfile.TemporaryDirectory(prefix='portfolio_val_') as td:
        temp=Path(td)
        for kind in ('images','labels'):
            shutil.copytree(root/f'data/{kind}/{args.split}',temp/kind/args.split)
        config={'path':str(temp),'train':f'images/{args.split}','val':f'images/{args.split}','test':f'images/{args.split}','names':NAMES}
        (temp/'data.yaml').write_text(yaml.safe_dump(config))
        metrics=model.val(data=str(temp/'data.yaml'),split=args.split,imgsz=640,batch=8,device=args.device,workers=0,
                          conf=.001,iou=.7,max_det=300,half=False,augment=False,plots=True,
                          project=str(out),name=f'{name}_object',exist_ok=False,verbose=False)
    box=metrics.box;result=metrics.results_dict
    p,r=float(result['metrics/precision(B)']),float(result['metrics/recall(B)'])
    rows=[dict(model=name,class_name='ALL',images=90,objects=sum(objects.values()),precision=p,recall=r,
               F1_from_P_R=harmonic(p,r),mAP50=float(box.map50),mAP75=float(box.map75),mAP50_95=float(box.map))]
    ap_rows=[]
    for j,i in enumerate(map(int,box.ap_class_index)):
        p,r=float(box.p[j]),float(box.r[j])
        rows.append(dict(model=name,class_name=NAMES[i],images=counts[i],objects=objects[i],precision=p,recall=r,
                         F1_from_P_R=harmonic(p,r),mAP50=float(box.ap50[j]),mAP75=float(box.all_ap[j,5]),mAP50_95=float(box.ap[j])))
        for k,ap in enumerate(box.all_ap[j]):
            ap_rows.append(dict(model=name,class_name=NAMES[i],IoU=round(.5+.05*k,2),AP=float(ap)))
    pd.DataFrame(ap_rows).to_csv(out/f'{name}_AP_by_IoU.csv',index=False,encoding='utf-8-sig')
    matrix=getattr(metrics,'confusion_matrix',None)
    if matrix is not None:
        pd.DataFrame(matrix.matrix,index=[*NAMES.values(),'background'],columns=[*NAMES.values(),'background']).to_csv(
            out/f'{name}_confusion_matrix.csv',encoding='utf-8-sig')
    predictions=[];false_classes=Counter();picture_dir=out/f'{name}_background';picture_dir.mkdir()
    for path in negatives:
        with Image.open(path) as raw:image=ImageOps.exif_transpose(raw).convert('RGB')
        pred=model.predict(image,conf=.25,iou=.7,imgsz=640,max_det=300,device=args.device,half=False,augment=False,verbose=False)[0]
        detections=[]
        for b in pred.boxes:
            c=model.names[int(b.cls.item())];false_classes[c]+=1
            detections.append({'class_name':c,'confidence':float(b.conf.item()),'xyxy_px':[float(v) for v in b.xyxy[0].tolist()]})
        predictions.append({'photo':path.name,'sha256':sha(path),'gt_objects':0,'false_positive_boxes':len(detections),'detections':detections})
        pred.save(filename=str(picture_dir/path.name))
    bad=sum(p['false_positive_boxes']>0 for p in predictions);total=sum(p['false_positive_boxes'] for p in predictions)
    negative=dict(model=name,images=16,images_with_false_positives=bad,false_positive_image_rate=bad/16,
                  false_positive_boxes=total,false_positives_per_image=total/16,false_positive_classes=dict(false_classes))
    assert before==sha(weights),'Weights must remain unchanged'
    report={'weights_sha256':before,'object_metrics':rows,'background_metrics':negative,'background_predictions':predictions,
            'speed_ms_per_image':{k:float(v) for k,v in metrics.speed.items()},
            'confusion_matrix_thresholds':{'confidence':.001,'matching_iou':inspect.signature(type(matrix).process_batch).parameters['iou_thres'].default if matrix is not None else None,'nms_iou':.7},
            'settings':{'split':args.split,'imgsz':640,'batch':8,'device':args.device,'object_candidate_conf':.001,
                        'background_conf':.25,'nms_iou':.7,'max_det':300,'half':False},
            'precision_recall_note':'Ultralytics detection metrics use the PR/F1 operating point; not fixed conf=0.25 metrics.',
            'F1_note':'F1_from_P_R is the harmonic mean of displayed P and R; ALL is not necessarily macro mean class F1.'}
    save(out/f'{name}_report.json',report)
    return rows,negative

def run(args):
    if ultralytics.__version__!='8.4.182':raise RuntimeError('Install ultralytics==8.4.182')
    new=Path(args.new).resolve();old=Path(args.old).resolve() if args.old else None
    if not new.is_file():raise FileNotFoundError('Provide actual new best.pt')
    if sha(new)==EXPECTED_OLD:raise ValueError('The new model file is the old checkpoint. Select the new best.pt.')
    if old and (not old.is_file() or sha(old)!=EXPECTED_OLD):raise ValueError('Old best.pt does not match the recorded label_fix_v1 checkpoint')
    out=Path(args.out).resolve()
    if out.exists():raise FileExistsError('Choose a new output directory; previous results are preserved')
    root,negatives,objects,counts,fingerprints=checked_sources(args.repo,args.split)
    record,negative_record=historical(args.repo,args.split)
    out.mkdir(parents=True)
    rows=[];neg_rows=[]
    if old:
        r,n=evaluate_one(old,'old_remeasured',root,negatives,objects,counts,args,out);rows+=r;neg_rows.append(n)
    else:
        if record:
            for r in record:
                i=next((i for i,c in NAMES.items() if c==r['class_name']),None)
                r.update(images=90 if i is None else counts[i],objects=sum(objects.values()) if i is None else objects[i])
            rows+=record
        neg_rows.append({'model':'old_record','images':16,'images_with_false_positives':negative_record['images_with_false_positives'],
                         'false_positive_image_rate':negative_record['false_positive_image_rate'],
                         'false_positive_boxes':negative_record['false_positive_boxes'],
                         'false_positives_per_image':negative_record['false_positives_per_image']})
    r,n=evaluate_one(new,'new',root,negatives,objects,counts,args,out);rows+=r;neg_rows.append(n)
    table=pd.DataFrame(rows);background=pd.DataFrame(neg_rows)
    table.to_csv(out/'object_comparison_raw.csv',index=False,encoding='utf-8-sig')
    scorecols=['precision','recall','F1_from_P_R','mAP50','mAP75','mAP50_95']
    percent=table.copy()
    for col in scorecols:percent[col]=100*percent[col]
    percent.to_csv(out/'object_comparison_percent.csv',index=False,encoding='utf-8-sig')
    background.to_csv(out/'background_comparison.csv',index=False,encoding='utf-8-sig')
    baseline='old_remeasured' if old else 'old_record'
    deltas=[]
    for class_name in ['ALL',*NAMES.values()]:
        a=table[(table.model==baseline)&(table.class_name==class_name)]
        b=table[(table.model=='new')&(table.class_name==class_name)]
        if a.empty or b.empty:continue
        for col in scorecols:
            if pd.notna(a.iloc[0].get(col)) and pd.notna(b.iloc[0].get(col)):
                deltas.append({'class_name':class_name,'metric':col,'old_percent':100*a.iloc[0][col],
                               'new_percent':100*b.iloc[0][col],'change_percentage_points':100*(b.iloc[0][col]-a.iloc[0][col])})
    pd.DataFrame(deltas,columns=['class_name','metric','old_percent','new_percent','change_percentage_points']).to_csv(out/'changes_percentage_points.csv',index=False,encoding='utf-8-sig')
    # Static publication figures: PNG and vector SVG, exported beside the CSVs.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    all_rows=percent[percent.class_name=='ALL'].set_index('model')
    ax=all_rows[['precision','recall','mAP50','mAP50_95']].T.plot.bar(figsize=(10,5),ylim=(0,100),rot=0)
    ax.set_ylabel('Score (%)');ax.set_title(f'Object detection | {args.split} 90 images');ax.grid(axis='y',alpha=.2)
    ax.figure.tight_layout();ax.figure.savefig(out/'object_comparison.png',dpi=200);ax.figure.savefig(out/'object_comparison.svg');plt.close(ax.figure)
    note=('이전·새 체크포인트를 이번 환경에서 동일한 설정으로 재평가했습니다.' if old else
          '이전 수치는 과거 CPU 평가 기록, 새 수치는 이번 평가 결과입니다. 환경 버전·장비 차이가 있을 수 있습니다. 더 엄밀한 비교를 위해 이전 모델도 함께 제공해 재평가하세요.')
    if args.split=='test' and not old:note+=' 과거 Test 수치가 없으므로 이전·새 모델의 Test 물체 성능 비교는 제공하지 않습니다.'
    save(out/'evaluation_manifest.json',{'data_commit':DATA_COMMIT,'split':args.split,'evaluation_files_sha256':fingerprints,
          'new_weights_sha256':sha(new),'old_weights_sha256':sha(old) if old else EXPECTED_OLD,
          'comparison_mode':'same_runtime' if old else 'historical_reference','note':note,
          'environment':{'python':platform.python_version(),'torch':torch.__version__,'ultralytics':ultralytics.__version__,'device':args.device},
          'training_executed':False})
    def markdown(df):
        return '\n'.join(['| '+' | '.join(map(str,df.columns))+' |','| '+' | '.join(['---']*len(df.columns))+' |']+['| '+' | '.join(str(v) if not isinstance(v,float) else f'{v:.2f}' for v in row)+' |' for row in df.itertuples(index=False,name=None)])
    text='# 모델 성능 비교\n\n'+note+'\n\n'+markdown(percent.fillna('미기록'))+'\n\n## 빈 배경 평가\n\n'+markdown(background.drop(columns=['false_positive_classes'],errors='ignore'))
    text+='\n\n점수 표는 % 단위이며 변화량 CSV는 퍼센트포인트(pp)입니다. 역사 기록에 없는 mAP75는 미기록으로 남깁니다. ALL의 F1은 표시한 전체 P/R의 조화평균입니다. P/R은 PR 곡선에서 선택된 운용점 기준이며 고정 confidence 0.25의 P/R이 아닙니다. 배경 오탐만 confidence 0.25로 고정합니다. 빈 배경에서 mAP나 Recall을 계산하지 않습니다.\n\nVal은 학습 중 선택에 사용된 개발 평가이며 최종 독립 성능이 아닙니다. Test 결과도 데이터 출처/장소 중복 검토 전에는 실제 촬영 환경 전체의 성능을 보장하지 않습니다. 배경 16장의 장소 독립성은 미확인입니다. 원본 보존용 사본으로만 평가했고 재학습하지 않았습니다. 새 모델과 기존 모델의 차이만으로 배경 추가가 유일한 원인이라고 단정하지 않습니다.\n\n혼동행렬 CSV의 행은 예측 클래스, 열은 정답 클래스이며 background 행은 미탐, background 열은 오탐입니다. 혼동행렬은 confidence=0.001, 정답 박스 매칭 IoU=0.45 기준입니다. NMS IoU=0.7이나 mAP의 매칭 기준과 구분하세요. 구체 설정은 report.json에도 기록합니다. *_object 폴더의 PR/F1/P/R 곡선과 혼동행렬 PNG, val 예측 샘플을 함께 확인하세요. 속도는 환경 의존 진단용이며 정확도 개선 증거가 아닙니다.\n'
    (out/'포트폴리오_비교보고서.md').write_text(text,encoding='utf-8')
    # Save old-source records as evidence regardless of comparison mode.
    shutil.copy2(Path(args.repo)/'수정안_v2/검증기록/existing_model_val_evaluation.json',out/'historical_old_val.json')
    print('\nOBJECT METRICS (%)\n'+percent.to_string(index=False))
    print('\nBACKGROUND METRICS\n'+background.drop(columns=['false_positive_classes'],errors='ignore').to_string(index=False))
    print('\n'+note+'\nSaved: '+str(out))
    return out

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo',required=True);p.add_argument('--new',required=True);p.add_argument('--old')
    p.add_argument('--split',choices=['val','test'],default='val');p.add_argument('--device',default='cpu');p.add_argument('--out',required=True)
    run(p.parse_args())

if __name__=='__main__':main()
