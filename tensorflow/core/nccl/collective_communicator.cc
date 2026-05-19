#include "tensorflow/core/nccl/collective_communicator.h"
namespace tensorflow {
std::unique_ptr<NcclCommunicator> MaybeCreateNcclCommunicator(
    const ConfigProto& config) {
  return nullptr;
}
}  // namespace tensorflow
