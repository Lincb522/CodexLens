#!/usr/bin/python3
"""Audit Codex accounting-event integrity without reading or printing chat text."""
import argparse, json, os
from pathlib import Path


def valid(counter):
    try:
        input_tokens=int(counter['input_tokens'])
        output_tokens=int(counter['output_tokens'])
        cached=int(counter.get('cached_input_tokens',0))
        cache_write=int(counter.get('cache_write_input_tokens',0))
        reasoning=int(counter.get('reasoning_output_tokens',0))
    except (KeyError,TypeError,ValueError):
        return False
    return all(x>=0 for x in (input_tokens,output_tokens,cached,cache_write,reasoning)) \
        and cached+cache_write<=input_tokens and reasoning<=output_tokens


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--codex-home',default=os.environ.get('CODEX_HOME',str(Path.home()/'.codex')))
    parser.add_argument('--output',default='build/token-evidence-audit.json')
    args=parser.parse_args()
    roots=[Path(args.codex_home)/'sessions',Path(args.codex_home)/'archived_sessions']
    report={
        'schema':1,'scope':'Codex token_count structural integrity; message bodies are never inspected',
        'files':0,'token_count_events':0,'events_with_last_counter':0,'events_with_cumulative_counter':0,
        'invalid_last_counters':0,'invalid_cumulative_counters':0,
        'last_counter_total_only_events':0,'cumulative_reported_total_mismatches':0,
        'duplicate_cumulative_events':0,'cumulative_regressions':0,'files_with_cumulative_counter':0,
    }
    for root in roots:
        if not root.is_dir(): continue
        for path in root.rglob('*.jsonl'):
            if path.is_symlink() or not path.is_file(): continue
            report['files']+=1
            last_total=None
            file_has_total=False
            try:
                with path.open('rb') as handle:
                    for raw in handle:
                        if b'token_count' not in raw: continue
                        try: obj=json.loads(raw)
                        except Exception: continue
                        payload=obj.get('payload') or {}
                        if obj.get('type')!='event_msg' or payload.get('type')!='token_count': continue
                        info=payload.get('info') or {}
                        report['token_count_events']+=1
                        for key,present_key,invalid_key in (
                            ('last_token_usage','events_with_last_counter','invalid_last_counters'),
                            ('total_token_usage','events_with_cumulative_counter','invalid_cumulative_counters')):
                            counter=info.get(key)
                            if not isinstance(counter,dict): continue
                            report[present_key]+=1
                            if not valid(counter): report[invalid_key]+=1
                            if 'total_tokens' in counter:
                                try:
                                    component_total=int(counter['input_tokens'])+int(counter['output_tokens'])
                                    reported_total=int(counter['total_tokens'])
                                    if key=='last_token_usage' and component_total==0 and reported_total>0:
                                        report['last_counter_total_only_events']+=1
                                    elif key=='total_token_usage' and reported_total!=component_total:
                                        report['cumulative_reported_total_mismatches']+=1
                                except Exception:
                                    if key=='total_token_usage':
                                        report['cumulative_reported_total_mismatches']+=1
                        total=info.get('total_token_usage')
                        if isinstance(total,dict) and valid(total):
                            file_has_total=True
                            current=(int(total['input_tokens']),int(total.get('cached_input_tokens',0)),int(total.get('cache_write_input_tokens',0)),int(total['output_tokens']),int(total.get('reasoning_output_tokens',0)))
                            if current==last_total: report['duplicate_cumulative_events']+=1
                            elif last_total is not None and any(a<b for a,b in zip(current,last_total)):
                                report['cumulative_regressions']+=1
                            last_total=current
            except OSError:
                continue
            if file_has_total: report['files_with_cumulative_counter']+=1
    output=Path(args.output)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,ensure_ascii=False,sort_keys=True))

if __name__=='__main__': main()
