package model

// ApiKey 存储的老版本应用生成的key信息(目前mcp server还在用)，暂不修改表名。
// note: app_key命名的相关文件是针对应用生成的key（老版本），而api_key是针对用户生成的openapi key。
type ApiKey struct {
	ID        uint32 `gorm:"primary_key"`
	CreatedAt int64  `gorm:"autoCreateTime:milli;index:idx_api_key_created_at"`
	UpdatedAt int64  `gorm:"autoUpdateTime:milli"`
	// 组织ID
	OrgID string `gorm:"index:idx_api_key_org_id"`
	// 用户ID
	UserID string `gorm:"index:idx_api_key_user_id"`
	// 应用ID
	AppID string `gorm:"index:idx_api_key_app_id"`
	// 应用类型
	AppType string `gorm:"index:idx_api_key_app_type"`
	// Api Key
	ApiKey string `gorm:"index:idx_api_key_api_key"`
}
