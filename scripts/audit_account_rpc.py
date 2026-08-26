#!/usr/bin/python3
"""Probe Codex account RPC methods and emit schema keys only, never values."""
import argparse, json, os, queue, subprocess, threading, time
from pathlib import Path


def key_shape(value,depth=0):
    if depth>=3: return type(value).__name__
    if isinstance(value,dict): return {key:key_shape(value[key],depth+1) for key in sorted(value)}
    if isinstance(value,list): return [key_shape(value[0],depth+1)] if value else []
    return type(value).__name__


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--codex-home',default=os.environ.get('CODEX_HOME',str(Path.home()/'.codex')))
    parser.add_argument('--codex',default='/usr/local/bin/codex')
    parser.add_argument('--output',default='build/account-rpc-schema-audit.json')
    args=parser.parse_args()
    env=os.environ.copy(); env['CODEX_HOME']=args.codex_home
    process=subprocess.Popen([args.codex,'-s','read-only','-a','never','app-server'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,bufsize=1,env=env)
    messages=queue.Queue()
    def read():
        for line in process.stdout:
            try: messages.put(json.loads(line))
            except Exception: pass
    threading.Thread(target=read,daemon=True).start()
    next_id=1
    def request(method,params=None,timeout=20):
        nonlocal next_id
        ident=next_id; next_id+=1
        msg={'jsonrpc':'2.0','id':ident,'method':method}
        if params is not None: msg['params']=params
        process.stdin.write(json.dumps(msg,separators=(',',':'))+'\n'); process.stdin.flush()
        end=time.time()+timeout
        while time.time()<end:
            try: reply=messages.get(timeout=max(0.1,end-time.time()))
            except queue.Empty: break
            if reply.get('id')==ident: return reply
        return {'error':{'message':'timeout'}}
    report={'schema':1,'scope':'RPC method availability and redacted result schema only','methods':{}}
    try:
        init=request('initialize',{'clientInfo':{'name':'CodexTokenLedgerAudit','version':'1.2.0'}})
        report['initialize']='ok' if 'result' in init else 'error'
        process.stdin.write(json.dumps({'jsonrpc':'2.0','method':'initialized'})+'\n'); process.stdin.flush()
        for method in ('account/read','account/rateLimits/read','account/usage/read'):
            reply=request(method,{})
            if 'result' in reply:
                report['methods'][method]={'status':'ok','shape':key_shape(reply['result'])}
            else:
                report['methods'][method]={'status':'unavailable','error_type':type((reply.get('error') or {}).get('code')).__name__}
    finally:
        try: process.terminate(); process.wait(timeout=3)
        except Exception: process.kill()
    output=Path(args.output); output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,ensure_ascii=False,sort_keys=True))

if __name__=='__main__': main()
