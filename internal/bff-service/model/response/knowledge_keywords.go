package response

type GetKnowledgeKeywordListResp struct {
	List     []*KeywordsInfo `json:"list"`
	Total    int64           `json:"total"`
	PageNum  int32           `json:"pageNo"`
	PageSize int32           `json:"pageSize"`
}

type KeywordsInfo struct {
	Id                 uint32   `json:"id"`
	Name               string   `json:"name"`
	Alias              string   `json:"alias"`
	KnowledgeBaseIds   []string `json:"knowledgeBaseIds"`
	KnowledgeBaseNames []string `json:"knowledgeBaseNames"`
	UpdatedAt          string   `json:"updatedAt"`
}
