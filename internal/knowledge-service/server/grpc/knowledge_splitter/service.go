package knowledge_splitter

import (
	knowledgebase_splitter_service "github.com/UnicomAI/wanwu/api/proto/knowledgebase-splitter-service"
	grpc_provider "github.com/UnicomAI/wanwu/internal/knowledge-service/pkg/grpc-provider"
	"google.golang.org/grpc"
)

type Service struct {
	knowledgebase_splitter_service.UnimplementedKnowledgeBaseSplitterServiceServer
}

var splitterService = Service{}

func init() {
	grpc_provider.AddGrpcContainer(&splitterService)
}

func (s *Service) GrpcType() string {
	return "grpc_knowledge_splitter_service"
}

func (s *Service) Register(serv *grpc.Server) error {
	knowledgebase_splitter_service.RegisterKnowledgeBaseSplitterServiceServer(serv, s)
	return nil
}
