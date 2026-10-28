package util

import (
	"github.com/UnicomAI/wanwu/pkg/log"
	"github.com/bwmarrin/snowflake"
)

var _generator *idGenerator

type idGenerator struct {
	node *snowflake.Node
}

func init() {
	// 创建节点
	node, err := snowflake.NewNode(1)
	if err != nil {
		log.Errorf("snowflake-generator init err: %s", err.Error())
		panic(err)
	}
	_generator = &idGenerator{node: node}
}

func NewID() string {
	return _generator.node.Generate().String()
}
