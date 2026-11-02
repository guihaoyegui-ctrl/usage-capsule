#!/usr/bin/python3
import sys,json,time,os
count=0
for line in sys.stdin:
 m=json.loads(line)
 if 'id' not in m:continue
 if m['method']=='initialize':
  count+=1;time.sleep(.04)
  out={'id':m['id'],'result':{'initializations':count}}
 elif m['method'] in ['test/large','test/final']:out={'id':m['id'],'result':{'payload':'x'*(2*1024*1024)}}
 elif m['method']=='test/ping':out={'id':m['id'],'result':{'initializations':count}}
 else:out={'id':m['id'],'result':{}}
 data=(json.dumps(out)+'\n').encode()
 for start in range(0,len(data),8192):
  os.write(sys.stdout.fileno(),data[start:start+8192])
  if len(data)>100000:time.sleep(.0003)
 if m['method']=='test/final':sys.exit(0)
