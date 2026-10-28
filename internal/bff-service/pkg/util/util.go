// @Author wangxm 8/21/星期四 16:01:00
package util

import "strings"

// 拼接 UniqueId
func ConcatAssistantToolUniqueId(typeStr, IdStr string) string {
	if typeStr == "" || IdStr == "" {
		return ""
	}
	return typeStr + "_" + IdStr
}

// ext 扩展数据的分隔标记，用于在 desc 字段中携带额外结构化信息（如外部智能体的 webUrl/source），
// 避免修改 proto 定义。
const extPrefix = "__WANWU_EXT__"
const extSuffix = "__WANWU_EXT_END__"

// EncodeExt 将扩展 JSON 数据编码到 desc 字段末尾，返回新的 desc。
func EncodeExt(desc, extJson string) string {
	return desc + extPrefix + extJson + extSuffix
}

// DecodeExt 从 desc 字段中解析扩展 JSON 数据。
// 返回：纯净的 desc、扩展 JSON 字符串（无扩展时为空）。
func DecodeExt(desc string) (string, string) {
	if !strings.Contains(desc, extPrefix) {
		return desc, ""
	}
	idx := strings.Index(desc, extPrefix)
	clean := desc[:idx]
	rest := desc[idx+len(extPrefix):]
	endIdx := strings.Index(rest, extSuffix)
	if endIdx == -1 {
		return clean, rest
	}
	return clean, rest[:endIdx]
}
