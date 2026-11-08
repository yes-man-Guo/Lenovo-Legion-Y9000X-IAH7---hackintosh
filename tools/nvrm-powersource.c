// nvrm-powersource: tell the NVRM RM whether the machine is on AC or battery.
//
// The NullMoth driver's nv_xnu_power.cpp reports the real power source to the
// GPU firmware, and on mains the firmware runs its high-performance clock
// policy all the time (P0, full clocks) — issue #310/#500 on the driver repo.
// NV2080_CTRL_CMD_PERF_SET_POWERSTATE (0x2080205b) lets a user client override
// that answer, so the firmware picks its battery clock/power policy instead.
//
// Usage:
//   nvrm-powersource battery    # firmware uses its battery policy (low clocks)
//   nvrm-powersource ac         # back to the normal mains policy
// The override lasts until the next RmPowerSourceChangeEvent (unplug/plug,
// sleep/wake) or reboot. Read the effect with nvgfx-smi.
//
// <zcode> derived from nvgfx-smi transport by watchthelight (MIT-style header in that repo)

#include <IOKit/IOKitLib.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "nvtypes.h"
#include "nvmisc.h"
#include "nvos.h"
#include "nvstatus.h"
#include "nv-ioctl.h"
#include "nv-ioctl-numbers.h"
#include "nv_escape.h"
#include "nv-unix-nvos-params-wrappers.h"
#include "class/cl0000.h"
#include "class/cl0080.h"
#include "class/cl2080.h"
#include "ctrl/ctrl0000/ctrl0000gpu.h"
#include "ctrl/ctrl2080/ctrl2080perf.h"

#ifndef NV2080_CTRL_CMD_PERF_SET_POWERSTATE
#define NV2080_CTRL_CMD_PERF_SET_POWERSTATE 0x2080205bU
#endif

enum { SEL_ESC = 1, SEL_BINDFD = 3 };

typedef struct { io_connect_t conn; int fd; } Conn;

static int conn_open(Conn *c)
{
    memset(c, 0, sizeof *c);
    c->fd = -1;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("NVAccel"));
    kern_return_t kr = KERN_FAILURE;
    if (svc) {
        kr = IOServiceOpen(svc, mach_task_self(), 0x4E560000u | 0, &c->conn);
        IOObjectRelease(svc);
    }
    if (kr != KERN_SUCCESS) {
        svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("NVRM"));
        if (!svc) { fprintf(stderr, "no NVAccel and no NVRM service\n"); return -1; }
        kr = IOServiceOpen(svc, mach_task_self(), 0, &c->conn);
        IOObjectRelease(svc);
    }
    if (kr != KERN_SUCCESS) { fprintf(stderr, "IOServiceOpen -> 0x%08x\n", kr); return -1; }
    c->fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
    if (c->fd < 0) { IOServiceClose(c->conn); c->conn = 0; return -1; }
    uint64_t in = (uint64_t)c->fd;
    IOConnectCallScalarMethod(c->conn, SEL_BINDFD, &in, 1, NULL, NULL);
    return 0;
}

static kern_return_t esc(Conn *c, uint32_t cmd, void *data, uint32_t size)
{
    uint64_t in = cmd; size_t out = size;
    return IOConnectCallMethod(c->conn, SEL_ESC, &in, 1, data, size, NULL, NULL, data, &out);
}

typedef struct { Conn ctl; NvHandle hClient, hDevice, hSubdev; nv_ioctl_card_info_t card; } Rm;

static NvU32 rm_alloc(Rm *rm, NvHandle parent, NvHandle *h, NvU32 cls, void *params, NvU32 psize)
{
    NVOS21_PARAMETERS p; memset(&p, 0, sizeof p);
    p.hRoot = rm->hClient; p.hObjectParent = parent; p.hObjectNew = *h; p.hClass = cls;
    p.pAllocParms = params; p.paramsSize = psize;
    esc(&rm->ctl, NV_ESC_RM_ALLOC, &p, sizeof p);
    *h = p.hObjectNew;
    return p.status;
}

static NvU32 rm_free(Rm *rm, NvHandle h)
{
    NVOS00_PARAMETERS p; memset(&p, 0, sizeof p);
    p.hRoot = rm->hClient; p.hObjectParent = h == rm->hClient ? 0 : rm->hClient; p.hObjectOld = h;
    esc(&rm->ctl, NV_ESC_RM_FREE, &p, sizeof p);
    return p.status;
}

static NvU32 rm_ctrl(Rm *rm, NvHandle h, NvU32 cmd, void *params, NvU32 psize)
{
    NVOS54_PARAMETERS p; memset(&p, 0, sizeof p);
    p.hClient = rm->hClient; p.hObject = h; p.cmd = cmd; p.params = params; p.paramsSize = psize;
    esc(&rm->ctl, NV_ESC_RM_CONTROL, &p, sizeof p);
    return p.status;
}

int main(int argc, char **argv)
{
    int wantBattery;
    if (argc == 2 && !strcmp(argv[1], "battery")) wantBattery = 1;
    else if (argc == 2 && !strcmp(argv[1], "ac")) wantBattery = 0;
    else { fprintf(stderr, "usage: %s battery|ac\n", argv[0]); return 2; }

    Rm rm; memset(&rm, 0, sizeof rm);
    if (conn_open(&rm.ctl)) return 1;

    kern_return_t kr = esc(&rm.ctl, NV_ESC_CARD_INFO, &rm.card, sizeof rm.card);
    if (kr != KERN_SUCCESS || !rm.card.valid) {
        fprintf(stderr, "NV_ESC_CARD_INFO -> kr 0x%08x valid %d (driver not up?)\n", kr, rm.card.valid);
        return 1;
    }
    printf("gpu_id 0x%x\n", rm.card.gpu_id);

    NvU32 st = rm_alloc(&rm, 0, &rm.hClient, NV01_ROOT_CLIENT, NULL, 0);
    if (st != NV_OK) { fprintf(stderr, "alloc root client -> 0x%08x\n", st); return 1; }

    NV0000_CTRL_GPU_GET_ID_INFO_V2_PARAMS id; memset(&id, 0, sizeof id);
    id.gpuId = rm.card.gpu_id;
    st = rm_ctrl(&rm, rm.hClient, NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2, &id, sizeof id);
    if (st != NV_OK) { fprintf(stderr, "GPU_GET_ID_INFO_V2 -> 0x%08x\n", st); return 1; }

    NV0080_ALLOC_PARAMETERS a80; memset(&a80, 0, sizeof a80);
    a80.deviceId = id.deviceInstance; a80.hClientShare = rm.hClient;
    rm.hDevice = 0xcaf00001;
    st = rm_alloc(&rm, rm.hClient, &rm.hDevice, NV01_DEVICE_0, &a80, sizeof a80);
    if (st != NV_OK) { fprintf(stderr, "alloc device -> 0x%08x\n", st); return 1; }

    NV2080_ALLOC_PARAMETERS a20; memset(&a20, 0, sizeof a20);
    a20.subDeviceId = id.subDeviceInstance;
    rm.hSubdev = 0xcaf00002;
    st = rm_alloc(&rm, rm.hDevice, &rm.hSubdev, NV20_SUBDEVICE_0, &a20, sizeof a20);
    if (st != NV_OK) { fprintf(stderr, "alloc subdevice -> 0x%08x\n", st); return 1; }

    // Read back what the firmware currently thinks, for the record.
    NV2080_CTRL_PERF_GET_CURRENT_PSTATE_PARAMS cp = {0};
    st = rm_ctrl(&rm, rm.hSubdev, NV2080_CTRL_CMD_PERF_GET_CURRENT_PSTATE, &cp, sizeof cp);
    if (st == NV_OK) printf("current pstate: P%u (0x%02x)\n", cp.currPstate, cp.currPstate);

    // The actual switch.
    NV2080_CTRL_PERF_SET_POWERSTATE_PARAMS sp; memset(&sp, 0, sizeof sp);
    sp.powerStateInfo.powerState = wantBattery ? NV2080_CTRL_PERF_POWER_SOURCE_BATTERY
                                               : NV2080_CTRL_PERF_POWER_SOURCE_AC;
    st = rm_ctrl(&rm, rm.hSubdev, NV2080_CTRL_CMD_PERF_SET_POWERSTATE, &sp, sizeof sp);
    printf("PERF_SET_POWERSTATE %s -> RM 0x%08x (%s)\n", wantBattery ? "BATTERY" : "AC", st,
           st == NV_OK ? "accepted" : "rejected");

    if (st == NV_OK) {
        // Let the firmware settle, then read the pstate again.
        sleep(2);
        NV2080_CTRL_PERF_GET_CURRENT_PSTATE_PARAMS cp2 = {0};
        NvU32 st2 = rm_ctrl(&rm, rm.hSubdev, NV2080_CTRL_CMD_PERF_GET_CURRENT_PSTATE, &cp2, sizeof cp2);
        if (st2 == NV_OK) printf("pstate after switch: P%u (0x%02x)\n", cp2.currPstate, cp2.currPstate);
    }

    rm_free(&rm, rm.hSubdev);
    rm_free(&rm, rm.hDevice);
    rm_free(&rm, rm.hClient);
    IOServiceClose(rm.ctl.conn);
    if (rm.ctl.fd >= 0) close(rm.ctl.fd);
    return st == NV_OK ? 0 : 1;
}
