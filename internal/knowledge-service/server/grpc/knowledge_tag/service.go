package knowledge_tag

import (
	knowledgebase_tag_service "github.com/UnicomAI/wanwu/api/proto/knowledgebase-tag-service"
	grpc_provider "github.com/UnicomAI/wanwu/internal/knowledge-service/pkg/grpc-provider"
	"google.golang.org/grpc"
)

type Service struct {
	knowledgebase_tag_service.UnimplementedKnowledgeBaseTagServiceServer
}

var tagService = Service{}

func init() {
	grpc_provider.AddGrpcContainer(&tagService)
}

func (s *Service) GrpcType() string {
	return "grpc_knowledge_tag_service"
}

func (s *Service) Register(serv *grpc.Server) error {
	knowledgebase_tag_service.RegisterKnowledgeBaseTagServiceServer(serv, s)
	return nil
}
