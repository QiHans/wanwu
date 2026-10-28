package response

type KnowledgeTagListResp struct {
	KnowledgeTagList []*KnowledgeTag `json:"knowledgeTagList"`
}

type TagBindResp struct {
	BindCount int64 `json:"tagBindCount"`
}

type KnowledgeTag struct {
	TagId    string `json:"tagId"`    //知识库标签id
	TagName  string `json:"tagName"`  //知识库标签名称
	Selected bool   `json:"selected"` //此表标签是否选中
}

type CreateKnowledgeTagResp struct {
	KnowledgeId string `json:"knowledgeId"`
}
