// RCCL stub for gfx1031 (single-GPU, no RCCL).
// Provides the types, constants, and function declarations that TF/xla
// nccl code needs.  All functions return success/empty values.
#ifndef RCCL_STUB_H_
#define RCCL_STUB_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Types
typedef struct ncclComm* ncclComm_t;
typedef int ncclResult_t;
typedef struct { char internal[128]; } ncclUniqueId;

// Reduction ops
typedef enum { ncclSum = 0, ncclProd = 1, ncclMin = 2, ncclMax = 3 } ncclRedOp_t;

// Data types
typedef enum {
  ncclInt8 = 0, ncclChar = 0, ncclUint8 = 1,
  ncclInt32 = 2, ncclInt = 2,
  ncclUint32 = 3,
  ncclInt64 = 4, ncclInt64_t = 4,
  ncclUint64 = 5,
  ncclFloat16 = 6, ncclHalf = 6,
  ncclFloat32 = 7, ncclFloat = 7,
  ncclFloat64 = 8, ncclDouble = 8,
  ncclBfloat16 = 9,
  ncclNumTypes = 10
} ncclDataType_t;

// Constants
enum {
  ncclSuccess = 0,
  ncclInProgress = 2,
  ncclInvalidArgument = 1,
  ncclUnhandledCudaError = 3,
  ncclSystemError = 4,
  NCCL_UNIQUE_ID_BYTES = 128
};

// Functions
const char* ncclGetErrorString(ncclResult_t code);
const char* ncclGetLastError(ncclComm_t comm);
ncclResult_t ncclGetVersion(int* ver);
ncclResult_t ncclGetUniqueId(ncclUniqueId* id);
ncclResult_t ncclCommInitRank(ncclComm_t* comm, int nranks, ncclUniqueId commId, int rank);
ncclResult_t ncclCommInitAll(ncclComm_t* comms, int ndev, const int* devlist);
ncclResult_t ncclCommDestroy(ncclComm_t comm);
ncclResult_t ncclCommAbort(ncclComm_t comm);
ncclResult_t ncclCommSplit(ncclComm_t comm, int color, int key, ncclComm_t* newcomm, void* config);
ncclResult_t ncclCommCount(const ncclComm_t comm, int* count);
ncclResult_t ncclCommCuDevice(const ncclComm_t comm, int* device);
ncclResult_t ncclCommUserRank(const ncclComm_t comm, int* rank);
ncclResult_t ncclCommGetAsyncError(ncclComm_t comm, ncclResult_t* async_err);
ncclResult_t ncclCommFinalize(ncclComm_t comm);
ncclResult_t ncclGroupStart();
ncclResult_t ncclGroupEnd();
ncclResult_t ncclAllReduce(const void* sendbuff, void* recvbuff, size_t count,
                           ncclDataType_t datatype, ncclRedOp_t op,
                           ncclComm_t comm, void* stream);
ncclResult_t ncclReduce(const void* sendbuff, void* recvbuff, size_t count,
                        ncclDataType_t datatype, ncclRedOp_t op,
                        int root, ncclComm_t comm, void* stream);
ncclResult_t ncclBcast(void* buff, size_t count, ncclDataType_t datatype,
                       int root, ncclComm_t comm, void* stream);
ncclResult_t ncclBroadcast(const void* sendbuff, void* recvbuff, size_t count,
                          ncclDataType_t datatype, int root,
                          ncclComm_t comm, void* stream);
ncclResult_t ncclAllGather(const void* sendbuff, void* recvbuff, size_t sendcount,
                          ncclDataType_t datatype, ncclComm_t comm, void* stream);
ncclResult_t ncclReduceScatter(const void* sendbuff, void* recvbuff,
                               size_t recvcount, ncclDataType_t datatype,
                               ncclRedOp_t op, ncclComm_t comm, void* stream);
ncclResult_t ncclAllToAll(const void* sendbuff, void* recvbuff, size_t count,
                         ncclDataType_t datatype, ncclComm_t comm, void* stream);
ncclResult_t ncclSend(const void* sendbuff, size_t count, ncclDataType_t datatype,
                     int peer, ncclComm_t comm, void* stream);
ncclResult_t ncclRecv(void* recvbuff, size_t count, ncclDataType_t datatype,
                     int peer, ncclComm_t comm, void* stream);

#ifdef __cplusplus
}
#endif

#endif // RCCL_STUB_H_
