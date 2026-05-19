#ifndef TENSORFLOW_CORE_NCCL_COLLECTIVE_COMMUNICATOR_H_
#define TENSORFLOW_CORE_NCCL_COLLECTIVE_COMMUNICATOR_H_
#include <memory>
#include "tensorflow/core/framework/collective.h"
namespace tensorflow {
class NcclCommunicator {};
std::unique_ptr<NcclCommunicator> MaybeCreateNcclCommunicator(
    const ConfigProto& config);
}  // namespace tensorflow
#endif
