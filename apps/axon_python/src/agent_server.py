import grpc
from concurrent import futures
import axon_pb2
import axon_pb2_grpc
import inspect
import importlib

class AgentService(axon_pb2_grpc.AgentServiceServicer):
    def ProcessData(self, request, context):
        module_name = "agents.example_agent"
        function_name = "process_data"

        module = importlib.import_module(module_name)
        func = getattr(module, function_name)

        # Convert the map to a dictionary
        data = dict(request.data)

        result = func(data)
        return axon_pb2.OutputData(result=result)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    axon_pb2_grpc.add_AgentServiceServicer_to_server(AgentService(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
