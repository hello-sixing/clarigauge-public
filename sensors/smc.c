// SPDX-License-Identifier: Apache-2.0
// Adapted from the Mini Agent bridge's macos-smc.c.
// ClariGauge added optional sensor keys supplied as command-line arguments.
// Read-only AppleSMC user client: selector 2, key-info (9) and read (5) only.
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct { uint8_t major,minor,build,reserved; uint16_t release; } Version;
typedef struct { uint16_t version,length; uint32_t cpuPLimit,gpuPLimit,memPLimit; } PLimit;
typedef struct { uint32_t size,type; uint8_t attributes; } KeyInfo;
typedef struct { uint32_t key; Version version; PLimit limit; KeyInfo info; uint8_t result,status,command; uint32_t data32; uint8_t bytes[32]; } Data;
_Static_assert(sizeof(Data)==80,"SMC ABI");
static io_connect_t connection;
static uint32_t four(const char *s) {return (uint32_t)s[0]<<24|(uint32_t)s[1]<<16|(uint32_t)s[2]<<8|s[3];}
static int call(Data *in,Data *out){size_t size=sizeof(*out);return IOConnectCallStructMethod(connection,2,in,sizeof(*in),out,&size)==KERN_SUCCESS&&size==sizeof(*out)&&out->result==0;}
static double readKey(const char *key) {
 Data in={0},out={0};in.key=four(key);in.command=9;if(!call(&in,&out)||!out.info.size||out.info.size>32)return -1;
 in.info.size=out.info.size;uint32_t type=out.info.type;in.command=5;memset(&out,0,sizeof(out));if(!call(&in,&out))return -1;
 if(type==four("flt ")){float f;memcpy(&f,out.bytes,4);return f;}
 if(type==four("sp78"))return (int16_t)((out.bytes[0]<<8)|out.bytes[1])/256.0;
 if(type==four("fpe2"))return ((out.bytes[0]<<8)|out.bytes[1])/4.0;
 if(type==four("ui8 "))return out.bytes[0];return -1;
}
int main(int argc,char **argv){io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
 if(!service||IOServiceOpen(service,mach_task_self(),0,&connection)!=KERN_SUCCESS){puts("{\"temperatures\":[],\"fans\":[]}");return 0;}IOObjectRelease(service);
 const char *keys[]={"TC0P","TC0D","Tp09","Tp0T","Tp01","Tg0D","TG0P","Ts0P","TN0P"};int n=0;printf("{\"temperatures\":[");
 for(int i=0;i<9+argc-1;i++){const char *key=i<9?keys[i]:argv[i-8];if(strlen(key)!=4)continue;double v=readKey(key);if(v>0&&v<130)printf("%s{\"sensor\":\"%s\",\"celsius\":%.1f}",n++?",":"",key,v);}
 printf("],\"fans\":[");int count=(int)readKey("FNum");n=0;for(int i=0;i<count&&i<8;i++){char key[5];snprintf(key,5,"F%dAc",i);double v=readKey(key);if(v>=0&&v<20000)printf("%s{\"sensor\":\"Fan %d\",\"rpm\":%.0f}",n++?",":"",i+1,v);}puts("]}");IOServiceClose(connection);return 0;}
