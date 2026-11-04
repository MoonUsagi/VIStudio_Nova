"""Official COCO helpers. Called by MATLAB pyrunfile with JSON text variables.
The optional deps directory is explicit; source datasets are never overwritten.
"""
import sys,json,contextlib,io
if 'deps_path' in globals() and deps_path:
    sys.path.insert(0,str(deps_path))
import numpy as np
from pycocotools import mask as mask_utils
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval
if 'operation' in globals():
    payload=json.loads(str(input_json))
    if operation=='polygon':
        seg=payload['segmentation']; h,w=payload['size']
        r=mask_utils.merge(mask_utils.frPyObjects(seg,int(h),int(w)))
        decoded=mask_utils.decode(r)
        flat=decoded.flatten(order='F').tolist(); counts=[]; last=0; n=0
        for value in flat:
            if value==last:n+=1
            else:counts.append(n); n=1; last=value
        counts.append(n)
        output_json=json.dumps({'size':[h,w],'counts':counts})
    elif operation=='evaluate':
        with contextlib.redirect_stdout(io.StringIO()):
            gt=COCO(); gt.dataset=payload['truth']; gt.createIndex()
            results=payload['predictions']
            for a in results:
                seg=a['segmentation']
                if isinstance(seg['counts'],list):
                    a['segmentation']=mask_utils.frPyObjects(seg,*seg['size'])
            if results:dt=gt.loadRes(results)
            else:
                dt=COCO(); dt.dataset={'images':gt.dataset['images'],'categories':gt.dataset['categories'],'annotations':[]}; dt.createIndex()
            evaluator=COCOeval(gt,dt,'segm'); evaluator.params.imgIds=sorted(gt.getImgIds()); evaluator.evaluate(); evaluator.accumulate(); evaluator.summarize()
        output_json=json.dumps({'Stats':evaluator.stats.tolist(),'Meaning':'Official pycocotools COCOeval segm; default IoU, recall, area and maxDets settings.'})
