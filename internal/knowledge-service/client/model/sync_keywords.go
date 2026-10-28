package model

type AddKeywords struct {
	Id               uint32   `json:"id"`
	UserId           string   `json:"user_id"`
	Action           string   `json:"action"`
	Name             string   `json:"name"`
	Alias            []string `json:"alias"`
	KnowledgeBaseIds []string `json:"knowledge_base_list"`
}
