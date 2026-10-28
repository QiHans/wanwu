package operate

import (
	errs "github.com/UnicomAI/wanwu/api/proto/err-code"
	operate_service "github.com/UnicomAI/wanwu/api/proto/operate-service"
	"github.com/UnicomAI/wanwu/internal/operate-service/client"
	grpc_util "github.com/UnicomAI/wanwu/pkg/grpc-util"
)

type Service struct {
	operate_service.UnimplementedOperateServiceServer
	cli client.IClient
}

func NewService(cli client.IClient) *Service {
	return &Service{
		cli: cli,
	}
}

func errStatus(code errs.Code, status *errs.Status) error {
	return grpc_util.ErrorStatusWithKey(code, status.TextKey, status.Args...)
}
