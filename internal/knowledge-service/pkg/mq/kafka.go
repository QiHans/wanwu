package mq

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/IBM/sarama"
	"github.com/UnicomAI/wanwu/internal/knowledge-service/pkg"
	"github.com/UnicomAI/wanwu/internal/knowledge-service/pkg/config"
	"github.com/UnicomAI/wanwu/pkg/log"
	trace_util "github.com/UnicomAI/wanwu/pkg/trace-util"
	"github.com/UnicomAI/wanwu/pkg/util"
)

var kafka = Kafka{}

type Kafka struct {
	KafkaProducer *trace_util.SyncProducer
}

func init() {
	pkg.AddContainer(kafka)
}

func (c Kafka) LoadType() string {
	return "kafka"
}

func (c Kafka) Load() error {
	admin, err := initKafkaAdmin()
	if err != nil {
		log.Warnf("kafka not available, skipping: %v", err)
		return nil
	}
	producer, err2 := initKafka(admin)
	if err2 != nil {
		log.Warnf("kafka producer init failed, skipping: %v", err2)
		return nil
	}
	kafka.KafkaProducer = producer
	return nil
}

func (c Kafka) Stop() error {
	return nil
}

func (c Kafka) StopPriority() int {
	return pkg.DefaultPriority
}

func configureSASL(kafkaConfig *sarama.Config) {
	user := config.GetConfig().Kafka.User
	password := config.GetConfig().Kafka.Password
	if user != "" && password != "" {
		kafkaConfig.Net.SASL.Enable = true
		kafkaConfig.Net.SASL.User = user
		kafkaConfig.Net.SASL.Password = password
		kafkaConfig.Net.SASL.Handshake = true
	}
}

func initKafkaAdmin() (sarama.ClusterAdmin, error) {
	log.Infof("create new Kafka Admin client")
	kafkaConfig := sarama.NewConfig()
	kafkaConfig.Version = sarama.MaxVersion
	configureSASL(kafkaConfig)
	admin, err := sarama.NewClusterAdmin([]string{config.GetConfig().Kafka.Addr}, kafkaConfig)
	if err != nil {
		log.Errorf("create Kafka Admin client failed: %v", err)
		return nil, err
	}
	log.Infof("Kafka Admin client created successfully")
	return admin, nil
}

func initKafka(kafkaAdmin sarama.ClusterAdmin) (*trace_util.SyncProducer, error) {
	log.Infof("init Kafka config")
	defaultPartitionNum := config.GetConfig().Kafka.DefaultPartitionNum
	var defaultTopic = config.GetConfig().Kafka.Topic
	kafkaConfig := sarama.NewConfig()
	kafkaConfig.ClientID = util.GenUUID()
	kafkaConfig.Version = sarama.MaxVersion
	kafkaConfig.Consumer.Group.Rebalance.Strategy = sarama.NewBalanceStrategyRange()
	kafkaConfig.Consumer.Offsets.Initial = sarama.OffsetNewest
	kafkaConfig.Consumer.MaxProcessingTime = 2 * time.Second
	kafkaConfig.Producer.Return.Successes = true
	kafkaConfig.Producer.RequiredAcks = sarama.NoResponse
	configureSASL(kafkaConfig)
	log.Infof("Kafka config init done, creating producer")

	producer, err := sarama.NewSyncProducer([]string{config.GetConfig().Kafka.Addr}, kafkaConfig)
	if err != nil {
		log.Errorf("create producer failed: %v", err)
		return nil, err
	}
	wrappedProducer := trace_util.WrapSyncProducer(kafkaConfig, producer)
	log.Infof("Producer created, init admin client")

	defer func() { _ = kafkaAdmin.Close() }()
	log.Infof("Admin client init done, list topics")

	topics, err := kafkaAdmin.ListTopics()
	if err != nil {
		log.Errorf("list topics failed: %v", err)
		return nil, err
	}

	topicDetail, exists := topics[defaultTopic]
	if !exists {
		log.Infof("Topic[%s] not exists, creating", defaultTopic)
		topicDetail := sarama.TopicDetail{
			NumPartitions:     defaultPartitionNum,
			ReplicationFactor: 1,
		}
		err = kafkaAdmin.CreateTopic(defaultTopic, &topicDetail, false)
		if err != nil {
			log.Errorf("create Topic[%s] failed: %v", defaultTopic, err)
			return nil, err
		}
		log.Infof("Topic[%s] created", defaultTopic)
	} else if topicDetail.NumPartitions < defaultPartitionNum {
		log.Infof("Topic[%s] partitions[%d] < config[%d], updating", defaultTopic, topicDetail.NumPartitions, defaultPartitionNum)
		err = kafkaAdmin.CreatePartitions(defaultTopic, defaultPartitionNum, nil, false)
		if err != nil {
			log.Errorf("update Topic[%s] partitions failed: %v", defaultTopic, err)
			return nil, err
		}
		log.Infof("Topic[%s] partitions updated", defaultTopic)
	} else {
		log.Infof("Topic[%s] exists with partitions[%d] OK", defaultTopic, topicDetail.NumPartitions)
	}

	log.Infof("Kafka init done")
	return wrappedProducer, nil
}

func SendMessage(ctx context.Context, msg interface{}, topic string) error {
	if msg == nil {
		return errors.New("message is nil")
	}
	message, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	kafkaMsg := &sarama.ProducerMessage{}
	kafkaMsg.Topic = topic
	kafkaMsg.Value = sarama.StringEncoder(message)
	log.Infof("kafka send topic: %s ;send msg>>>>>>>>>>>>> %s", topic, message)
	_, _, err = kafka.KafkaProducer.SendMessage(ctx, kafkaMsg)
	if err != nil {
		log.Errorf("kafka send topic: %s ;send error %v", topic, err)
		return err
	}
	return nil
}