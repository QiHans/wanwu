package knowledge_keywords

import (
	knowledgebase_keywords_service "github.com/UnicomAI/wanwu/api/proto/knowledgebase-keywords-service"
	grpc_provider "github.com/UnicomAI/wanwu/internal/knowledge-service/pkg/grpc-provider"
	"google.golang.org/grpc"
)

type Service struct {
	knowledgebase_keywords_service.UnimplementedKnowledgeBaseKeywordsServiceServer
}

var keywordsService = Service{}

func init() {
	grpc_provider.AddGrpcContainer(&keywordsService)
}

func (s *Service) GrpcType() string {
	return "grpc_knowledge_keywords_service"
}

func (s *Service) Register(serv *grpc.Server) error {
	knowledgebase_keywords_service.RegisterKnowledgeBaseKeywordsServiceServer(serv, s)
	return nil
}
