package model

type RagPublish struct {
	ID          int64  `gorm:"primaryKey;column:id;type:bigint(20);autoIncrement;comment:主键id" json:"id"`
	RagID       string `gorm:"column:rag_id;uniqueIndex:idx_rag_id_version;type:varchar(64);not null;comment:ragId" json:"ragId" `
	Version     string `gorm:"column:version;uniqueIndex:idx_rag_id_version;type:varchar(64);not null;comment:版本号(与ragId构成唯一复合索引)"`
	Description string `gorm:"column:description;type:varchar(255);comment:版本描述;default:''"`
	RagInfo     string `gorm:"column:rag_info;type:longtext;comment:文本问答基本配置"`
	UserId      string `gorm:"column:user_id;type:varchar(64);comment:用户id"`
	OrgId       string `gorm:"column:org_id;type:varchar(64);comment:组织id"`
	CreatedAt   int64  `gorm:"column:created_at;type:bigint(20);autoCreateTime:milli;not null;comment:创建时间"`
	UpdatedAt   int64  `gorm:"column:updated_at;type:bigint(20);autoUpdateTime:milli;not null;comment:更新时间"`
}

func (r RagPublish) TableName() string {
	return "rag_publish"
}
