import unittest,sys,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'src'))
from collector import Traffic,app_name,parse_network_addresses
class TrafficTests(unittest.TestCase):
    def test_baseline_delta_expiry(self):
        t=Traffic();meta={10:{'identity':'10:a','name':'ClashX Pro'}}
        t.sample({10:(10000,5000)},100,meta)
        self.assertEqual(t.totals(100),[])
        t.sample({10:(11000,5200)},102,meta)
        self.assertEqual(t.totals(102)[0]['down'],1000)
        self.assertEqual(t.totals(3703),[])
    def test_reset_pid_reuse_and_sleep_are_not_traffic(self):
        t=Traffic();a={1:{'identity':'a','name':'Test'}}
        t.sample({1:(100,100)},0,a);t.sample({1:(20,20)},2,a)
        t.sample({1:(99999,99999)},4,{1:{'identity':'b','name':'Test'}})
        t.sample({1:(999999,999999)},400,{1:{'identity':'b','name':'Test'}})
        self.assertEqual(t.totals(400),[])
    def test_proxy_kept_separate(self):
        t=Traffic();meta={1:{'name':'Codex','identity':'a'},2:{'name':'ClashX Pro','identity':'b'}}
        t.sample({1:(0,0),2:(0,0)},100,meta);t.sample({1:(80,10),2:(100,20)},102,meta)
        self.assertEqual({r['name']:r['down'] for r in t.totals(102)},{'Codex':80,'ClashX Pro':100})
    def test_bundle_group(self):
        self.assertEqual(app_name('/Applications/Codex.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper'),'Codex')
        self.assertEqual(app_name('/usr/bin/ssh'),'ssh')
class NetworkAddressTests(unittest.TestCase):
    def test_active_physical_and_default_tunnel(self):
        sample = """lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
    inet 127.0.0.1 netmask 0xff000000
en0: flags=8863<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500
    inet 192.0.2.44 netmask 0xffffff00 broadcast 192.0.2.255
    inet6 fe80::1%en0 prefixlen 64 scopeid 0x6
    status: active
en1: flags=8863<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500
    inet 192.0.2.99 netmask 0xffffff00
    status: inactive
utun2: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
    inet 198.18.0.1 --> 198.18.0.1 netmask 0xffffffff
"""
        physical = parse_network_addresses(sample, 'en0')
        self.assertEqual([r['name'] for r in physical], ['en0'])
        self.assertEqual(physical[0]['ipv4'], ['192.0.2.44'])
        self.assertEqual(physical[0]['ipv6'], ['fe80::1%en0'])
        tunnel = parse_network_addresses(sample, 'utun2')
        self.assertEqual([r['name'] for r in tunnel], ['utun2','en0'])
        self.assertTrue(tunnel[0]['primary'])
        self.assertEqual(parse_network_addresses('', 'en0'), [])

if __name__=='__main__':unittest.main()
