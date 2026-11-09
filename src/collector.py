#!/usr/bin/python3
"""Local read-only sampler. No remote server, packet inspection, or credential reads."""
import pty
import collections, csv, datetime, json, os, pathlib, plistlib, re, shutil, signal, sqlite3, subprocess, sys, threading, time
from sensor_catalog import sensor_catalog

WINDOW = 3600
MAX_CACHE_AGE = 24 * 3600
MAX_CACHE_BYTES = 4 * 1024 * 1024
MAX_TRAFFIC_EVENTS = 16000
TRAFFIC_BUCKET_SECONDS = 15

def run(argv, timeout=6):
    p = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if p.returncode: raise RuntimeError(p.stderr.decode(errors='replace')[:180] or '采样不可用')
    return p.stdout

def app_name(command):
    m = re.search(r'/([^/]+)\.app/', command)
    return m.group(1) if m else pathlib.Path(command).name or '未知进程'

def processes():
    rows = {}
    for line in run(['/bin/ps','-axo','pid=,ppid=,rss=,%cpu=,lstart=,comm=']).decode().splitlines():
        p = line.split(None, 9)
        if len(p) < 10: continue
        try:
            pid = int(p[0]); rows[pid] = dict(pid=pid, parent=int(p[1]), memory=int(p[2])*1024,
                cpu=float(p[3]), identity=p[0]+':'+ ' '.join(p[4:9]), name=app_name(p[9]), command=p[9])
        except ValueError: pass
    return rows

class Traffic:
    def __init__(self, events=None):
        self.previous = {}; self.events = collections.deque(events or [], maxlen=MAX_TRAFFIC_EVENTS); self.last = None
        self.bucket_start = None
        self.bucket_apps = {}
    def sample(self, counters, now, identities):
        if self.last is not None and 0 < now-self.last < 30:
            bucket_start = int(now) // TRAFFIC_BUCKET_SECONDS * TRAFFIC_BUCKET_SECONDS
            if bucket_start != self.bucket_start:
                self.bucket_start = bucket_start
                self.bucket_apps.clear()
            for pid, pair in counters.items():
                meta = identities.get(pid, {})
                identity = meta.get('identity', str(pid))
                old = self.previous.get(pid)
                # New processes/connections require a baseline; never count lifetime bytes as recent bytes.
                if old and old[0] == identity:
                    down, up = max(0, pair[0]-old[1]), max(0, pair[1]-old[2])
                    if down or up:
                        name = meta.get('name', 'PID '+str(pid))
                        totals = self.bucket_apps.get(name)
                        if totals is None:
                            totals = dict(t=bucket_start, name=name, down=0, up=0)
                            self.bucket_apps[name] = totals
                            self.events.append(totals)
                        totals['down'] += down
                        totals['up'] += up
        self.previous = {pid:(identities.get(pid,{}).get('identity',str(pid)),*v) for pid,v in counters.items()}
        self.last = now
        self.prune(now)
    def prune(self, now):
        while self.events and self.events[0]['t'] <= now-WINDOW: self.events.popleft()
    def totals(self, now):
        self.prune(now); rows = {}
        for e in self.events:
            r = rows.setdefault(e['name'], dict(name=e['name'], down=0, up=0))
            r['down'] += e['down']; r['up'] += e['up']
        return sorted(rows.values(), key=lambda r:r['down']+r['up'], reverse=True)

def memory():
    total = int(run(['/usr/sbin/sysctl','-n','hw.memsize']))
    text = run(['/usr/bin/vm_stat']).decode(); page=int(re.search(r'page size of (\d+)',text)[1])
    vals={k.strip():int(v) for k,v in re.findall(r'^([^:\n]+):\s+(\d+)',text,re.M)}
    wired=vals.get('Pages wired down',0)*page; compressed=vals.get('Pages occupied by compressor',0)*page
    app=max(0,vals.get('Anonymous pages',0)-vals.get('Pages purgeable',0))*page
    return dict(total=total,used=min(total,app+wired+compressed),app=app,wired=wired,compressed=compressed)

def battery():
    raw=plistlib.loads(run(['/usr/sbin/ioreg','-r','-c','AppleSmartBattery','-a']))
    if not raw: return dict(available=False)
    b=raw[0]; maximum=b.get('MaxCapacity',0); current=b.get('CurrentCapacity',0)
    return dict(available=bool(maximum),percent=100*current/maximum if maximum else 0,
        charging=bool(b.get('IsCharging')),external=bool(b.get('ExternalConnected')),cycles=b.get('CycleCount',0))

def interfaces():
    result={}
    for line in run(['/usr/sbin/netstat','-ibn']).decode().splitlines():
        p=line.split()
        if len(p)>=10 and re.fullmatch(r'en\d+',p[0].rstrip('*')) and p[2].startswith('<Link'):
            try: result[p[0].rstrip('*')]=(int(p[6]),int(p[9]))
            except ValueError: pass
    return result

def parse_network_addresses(text, primary):
    result = []
    for section in re.split(r'(?m)(?=^[^\s:]+: flags=)', text):
        header = re.match(r'([^\s:]+): flags=\d+<([^>]+)>', section)
        if not header or 'UP' not in header[2].split(','):
            continue
        name = header[1]
        if 'status: inactive' in section:
            continue
        if name != primary and not re.fullmatch(r'en\d+', name):
            continue
        if name != primary and 'status: active' not in section:
            continue
        ipv4 = re.findall(r'(?m)^\s+inet\s+(\S+)', section)
        ipv6 = re.findall(r'(?m)^\s+inet6\s+(\S+)', section)
        if ipv4 or ipv6:
            result.append(dict(name=name, primary=name == primary, ipv4=ipv4, ipv6=ipv6))
    return sorted(result, key=lambda row: (not row['primary'], row['name']))

def network_addresses():
    primary = ''
    try:
        route = run(['/sbin/route', '-n', 'get', 'default']).decode()
        match = re.search(r'interface:\s*(\S+)', route)
        if match:
            primary = match[1]
    except RuntimeError:
        pass
    text = run(['/sbin/ifconfig']).decode()
    return dict(defaultInterface=primary, interfaces=parse_network_addresses(text, primary))

class CodexUsage:
    """Reads only metadata and token_count records; never saves message content."""
    def __init__(self): self.files={}; self.error=None
    def sample(self, now):
        root=pathlib.Path.home()/'.codex'
        dbs=sorted(root.glob('state_*.sqlite'),key=lambda p:p.stat().st_mtime,reverse=True)
        if not dbs: self.error='未发现 Codex 本地数据库'; return []
        out=[]
        try:
            with sqlite3.connect(f'file:{dbs[0]}?mode=ro',uri=True,timeout=1) as db:
                rows=db.execute('SELECT id,title,rollout_path,tokens_used FROM threads WHERE updated_at>? ORDER BY updated_at DESC LIMIT 60',(int(now-WINDOW),)).fetchall()
            for tid,title,path,total in rows:
                f=pathlib.Path(path)
                # Restrict transcript paths to local Codex sessions, never arbitrary database paths.
                try:
                    resolved=f.resolve()
                    if not any(resolved.is_relative_to(root/d) for d in ('sessions','archived_sessions')): continue
                    st=f.stat()
                except (OSError,ValueError): continue
                cached=self.files.get(path)
                if cached is None or cached['inode']!=st.st_ino or st.st_size<cached['offset']:
                    cached=dict(offset=max(0,st.st_size-4*1024*1024),inode=st.st_ino,events=[],previous=None,partial=b'',truncated=st.st_size>4*1024*1024)
                    self.files[path]=cached
                    initial=True
                else: initial=False
                with f.open('rb') as handle:
                    handle.seek(cached['offset']); data=handle.read(4*1024*1024); cached['offset']+=len(data)
                if initial and cached['truncated']: data=data.partition(b'\n')[2]
                lines=(cached['partial']+data).split(b'\n'); cached['partial']=lines.pop()[-1024*1024:]
                for line in lines:
                    if b'"token_count"' not in line or len(line)>1024*1024: continue
                    try:
                        r=json.loads(line); p=r.get('payload',{})
                        if r.get('type')!='event_msg' or p.get('type')!='token_count': continue
                        info=p.get('info') or {}; usage=info.get('total_token_usage') or {}
                        value=usage.get('total_tokens')
                        if not isinstance(value,int): continue
                        stamp=datetime.datetime.fromisoformat(r['timestamp'].replace('Z','+00:00')).timestamp()
                        prev=cached['previous']; cached['previous']=value
                        # Ignore rate-limit-only repeats and negative resets; first record is baseline.
                        if prev is not None and value>prev: cached['events'].append((stamp,value-prev))
                    except (ValueError,KeyError,TypeError): pass
                cached['events']=[e for e in cached['events'] if e[0]>now-WINDOW]
                out.append(dict(id=tid,title=title or tid,totalTokens=total,recentTokens=sum(e[1] for e in cached['events']),partial=cached['truncated']))
            self.error=None
        except (sqlite3.Error,OSError) as e:
            self.error='Codex 本地用量暂不可读（'+str(e)+'）'
        alive={r[2] for r in rows} if 'rows' in locals() else set()
        self.files={k:v for k,v in self.files.items() if k in alive}
        return sorted(out,key=lambda r:r['recentTokens'],reverse=True)

class Collector:
    def __init__(self, directory, resources):
        self.directory=pathlib.Path(directory); self.directory.mkdir(parents=True,exist_ok=True,mode=0o700)
        self.resources=pathlib.Path(resources); self.lock=threading.Lock(); self.stop=threading.Event()
        self.processes={}; self.networkError='等待网络采样'; self.networkAt=0; self.started=time.time()
        self.traffic=Traffic(); self.nic=Traffic(); self.coverage=collections.deque(); self.netproc=None
        self.codex=CodexUsage(); self.lastSave=0; self.lastNic=None; self.nicPrevious={}
        try:
            self.chip = run(['/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string']).decode().strip()
        except (RuntimeError, OSError, subprocess.TimeoutExpired):
            self.chip = ''
        self.sensor_catalog = sensor_catalog(self.chip)

    def restore_history(self):
        now = time.time()
        for name in ('history.json', 'snapshot.json'):
            path = self.directory/name
            path.with_suffix('.tmp').unlink(missing_ok=True)
            try:
                stat = path.stat()
                if now-stat.st_mtime >= MAX_CACHE_AGE or stat.st_size > MAX_CACHE_BYTES:
                    path.unlink()
            except FileNotFoundError:
                pass
        try:
            saved=json.loads((self.directory/'history.json').read_text())
            self.traffic = Traffic(e for e in saved['events'] if e['t'] > now-WINDOW)
            self.nic = Traffic(e for e in saved.get('interfaces',[]) if e['t'] > now-WINDOW)
            self.coverage = collections.deque(e for e in saved.get('coverage',[]) if e['t'] > now-WINDOW)
        except (OSError,ValueError,KeyError): pass
    def network(self):
        while not self.stop.is_set():
            try:
                master,slave=pty.openpty()
                try:
                    self.netproc=subprocess.Popen(['/usr/bin/nettop','-n','-P','-L','0','-s','2','-J','bytes_in,bytes_out'],stdout=slave,stderr=subprocess.DEVNULL,stdin=subprocess.DEVNULL)
                finally: os.close(slave)
                stream=os.fdopen(master, 'r')
                current={}; stamp=None
                for line in stream:
                    if self.stop.is_set(): break
                    row=next(csv.reader([line]))
                    if len(row)<3: continue
                    if row[1]=='bytes_in':
                        with self.lock:
                            if stamp is not None:
                                self.traffic.sample(current,stamp,self.processes)
                                self.networkAt=time.time(); self.networkError=None
                            current={}; stamp=time.time()
                    else:
                        m=re.search(r'\.(\d+)$',row[0])
                        if m:
                            try: current[int(m[1])]=(int(row[1]),int(row[2]))
                            except ValueError: pass
                if not self.stop.is_set(): self.networkError='网络采样中断，正在重连'
            except OSError: self.networkError='无法启动 nettop'
            finally:
                if 'stream' in locals(): stream.close()
                if self.netproc and self.netproc.poll() is None:
                    self.netproc.terminate()
                    try: self.netproc.wait(timeout=2)
                    except subprocess.TimeoutExpired: self.netproc.kill(); self.netproc.wait()
                self.traffic.previous={}; self.traffic.last=None
            self.stop.wait(5)
    def snapshot(self):
        now=time.time(); errors=[]; result=dict(time=now,started=self.started,chip=self.chip)
        try:
            result['networkInfo'] = network_addresses()
        except Exception as e:
            result['networkInfo'] = dict(interfaces=[], error='网络地址暂不可用')
            errors.append('网络地址: '+str(e))
        for key,fn in [('memory',memory),('battery',battery)]:
            try: result[key]=fn()
            except Exception as e: errors.append(key+': '+str(e))
        try:
            procs=processes()
            with self.lock: self.processes=procs
            grouped={}
            for p in procs.values():
                r=grouped.setdefault(p['name'],dict(name=p['name'],memory=0,cpu=0.,count=0,processes=[]))
                r['memory']+=p['memory'];r['cpu']+=p['cpu'];r['count']+=1
                r['processes'].append(dict(pid=p['pid'],memory=p['memory'],name=pathlib.Path(p['command']).name))
            result['apps']=sorted(grouped.values(),key=lambda r:r['memory'],reverse=True)
        except Exception as e: errors.append('进程: '+str(e))
        try:
            d=shutil.disk_usage(pathlib.Path.home()); result['disk']=dict(total=d.total,used=d.used,free=d.free)
        except OSError: errors.append('磁盘不可用')
        result['fans']=[];result['temperatures']=[]
        try:
            baseline = {'TC0P','TC0D','Tp09','Tp0T','Tp01','Tg0D','TG0P','Ts0P','TN0P'}
            extra_keys = [key for key in self.sensor_catalog if key not in baseline]
            smc=json.loads(run([str(self.resources/'smc'), *extra_keys]))
            for sensor in smc['temperatures']:
                sensor.update(self.sensor_catalog.get(sensor['sensor'], {}))
            result['fans']=smc['fans'];result['temperatures']=smc['temperatures']
        except Exception as e: errors.append('SMC: '+str(e))
        try:
            hid=json.loads(run([str(self.resources/'temperature')]))
            result['thermal']=hid.get('thermal_state',0)
            result['temperatures'] += [dict(sensor=k,celsius=v) for k,v in hid.get('sensors_celsius',{}).items()]
        except Exception as e: errors.append('温度: '+str(e))
        try:
            nic=interfaces()
            if self.lastNic and 0<now-self.lastNic<30:
                down=sum(max(0,v[0]-self.nicPrevious[k][0]) for k,v in nic.items() if k in self.nicPrevious)
                up=sum(max(0,v[1]-self.nicPrevious[k][1]) for k,v in nic.items() if k in self.nicPrevious)
                dt=now-self.lastNic
                self.nic.events.append(dict(t=now,duration=dt,name='物理网卡',down=down,up=up))
                result['rateDown']=down/dt;result['rateUp']=up/dt
                self.coverage.append(dict(t=now,seconds=dt))
            self.nicPrevious=nic;self.lastNic=now; self.nic.prune(now)
        except Exception as e: errors.append('网卡: '+str(e));self.lastNic=None
        while self.coverage and self.coverage[0]['t']<=now-WINDOW:self.coverage.popleft()
        result['coverage']=min(3600,sum(e['seconds'] for e in self.coverage))
        result['coverageSamples'] = list(self.coverage)
        result['history']=[dict(time=e['t'],down=e['down']/e['duration'],up=e['up']/e['duration']) for e in self.nic.events]
        with self.lock:
            result['traffic']=self.traffic.totals(now);result['networkAt']=self.networkAt
            result['trafficSamples'] = list(self.traffic.events)
            result['networkError']=self.networkError if now-self.networkAt<10 else '采样未就绪或已中断'
        result['conversations']=self.codex.sample(now);result['codexError']=self.codex.error
        result['errors']=errors
        self.atomic('snapshot.json',result)
        if now-self.lastSave>=60:
            with self.lock: saved=dict(events=list(self.traffic.events),interfaces=list(self.nic.events),coverage=list(self.coverage))
            while len(json.dumps(saved,ensure_ascii=False,separators=(',',':')).encode()) > MAX_CACHE_BYTES:
                saved['events'] = saved['events'][len(saved['events'])//2 + 1:]
                if not saved['events']:
                    break
            self.atomic('history.json',saved); self.lastSave=now
        return result
    def atomic(self,name,value):
        dest=self.directory/name; temp=dest.with_suffix('.tmp')
        payload = json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()
        if len(payload) > MAX_CACHE_BYTES:
            raise ValueError(f'{name} exceeds the cache limit')
        temp.write_bytes(payload);temp.chmod(0o600);temp.replace(dest)
    def close(self):
        self.stop.set()
        if self.netproc and self.netproc.poll() is None:self.netproc.terminate()

def main():
    import argparse,fcntl
    parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True);parser.add_argument('--resources',required=True);parser.add_argument('--once',action='store_true')
    args=parser.parse_args(); c=Collector(args.directory,args.resources)
    lock=open(c.directory/'collector.lock','w')
    try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError: return
    c.restore_history()
    signal.signal(signal.SIGTERM,lambda *_:c.stop.set());signal.signal(signal.SIGINT,lambda *_:c.stop.set())
    thread=threading.Thread(target=c.network,daemon=True);thread.start()
    try:
        while not c.stop.is_set():
            start=time.monotonic()
            try: c.snapshot()
            except Exception as e: print(type(e).__name__,str(e),file=sys.stderr,flush=True)
            if args.once: break
            c.stop.wait(max(.1,5-(time.monotonic()-start)))
            if os.getppid()==1: break
    finally: c.close();thread.join(timeout=4)
if __name__=='__main__': main()
