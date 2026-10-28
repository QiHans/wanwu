package util

import (
	"errors"
	"io"
	"strings"

	"github.com/UnicomAI/wanwu/pkg/util"
)

func FileEOF(err error) bool {
	return errors.Is(err, io.EOF) || (err != nil && err.Error() == "EOF")
}

func BuildFilePath(fileDir, fileExt string) string {
	return fileDir + util.GenUUID() + fileExt
}

func ReplaceLast(s, old, new string) string {
	i := strings.LastIndex(s, old)
	if i == -1 {
		return s
	}
	return s[:i] + new + s[i+len(old):]
}
