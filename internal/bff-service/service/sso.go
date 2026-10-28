package service

import (
	"context"
	"encoding/json"
	"fmt"

	iam_service "github.com/UnicomAI/wanwu/api/proto/iam-service"
	"github.com/UnicomAI/wanwu/internal/bff-service/config"
	"github.com/UnicomAI/wanwu/internal/bff-service/model/request"
	"github.com/UnicomAI/wanwu/internal/bff-service/model/response"
	gin_util "github.com/UnicomAI/wanwu/pkg/gin-util"
	jwt_util "github.com/UnicomAI/wanwu/pkg/jwt-util"
	trace_util "github.com/UnicomAI/wanwu/pkg/trace-util"
	"github.com/UnicomAI/wanwu/pkg/util"
	"github.com/gin-gonic/gin"
)

// OA SSO 相关 HTTP 响应结构体

type oaTokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
	Scope       string `json:"scope"`
}

type oaUserInfoResponse struct {
	Account  string `json:"Account"`
	FullName string `json:"FullName"`
}

// OASinglePoint OA 单点登录入口
// 1. 用 code 向 OA 换 access_token
// 2. 用 access_token 换用户信息 (Account + FullName)
// 3. 按 Account 查找/创建本系统用户
// 4. 签发 JWT → 跳转前端首页
func OASinglePoint(ctx *gin.Context, req *request.OASinglePoint) (*response.OASinglePoint, error) {
	cfg := config.Cfg().OASSO

	// 1. 用 code 交换 access_token
	accessToken, err := oaExchangeToken(ctx, cfg, req.Code)
	if err != nil {
		return nil, fmt.Errorf("OA token exchange failed: %w", err)
	}

	// 2. 用 access_token 获取用户信息
	account, fullName, err := oaGetUserInfo(ctx, cfg, accessToken)
	if err != nil {
		return nil, fmt.Errorf("OA user info failed: %w", err)
	}

	if account == "" {
		return nil, fmt.Errorf("OA returned empty account")
	}

	// 3. 按 Account 查找或创建用户
	userID, err := findOrCreateUser(ctx, account, fullName)
	if err != nil {
		return nil, fmt.Errorf("find or create user failed: %w", err)
	}

	// 4. 获取用户所属组织（取第一个组织作为默认）
	orgID, err := getFirstOrgID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("get user org failed: %w", err)
	}
	fmt.Printf("[SSO DEBUG] userID=%s, resolved orgID=%s\n", userID, orgID)

	// 5. 签发 JWT token
	// 5. 签发 JWT token
	claims, token, err := jwt_util.GenerateToken(userID, jwt_util.UserTokenTimeout)
	if err != nil {
		return nil, fmt.Errorf("generate token failed: %w", err)
	}
	ctx.Set(gin_util.CLAIMS, &claims)

	// 6. 构建前端跳转 URL（跳转到 SSO 回调页，由回调页处理 token 和 orgId）
	redirectURL := config.Cfg().Server.WebBaseUrl + "/aibase/oa/sso?token=" + token + "&orgId=" + orgID

	return &response.OASinglePoint{
		Token:       token,
		RedirectURL: redirectURL,
		OrgID:       orgID,
	}, nil
}

// oaExchangeToken 用授权码交换 access_token
func oaExchangeToken(ctx context.Context, cfg config.OASSOConfig, code string) (string, error) {
	resp, err := trace_util.NewResty(ctx).
		R().
		SetContext(ctx).
		SetHeader("Content-Type", "application/x-www-form-urlencoded").
		SetFormData(map[string]string{
			"grant_type":  "authorization_code",
			"code":        code,
			"app_id":      cfg.AppID,
			"app_secret":  cfg.AppSecret,
		}).
		Post(cfg.TokenURL)
	if err != nil {
		return "", fmt.Errorf("http request failed: %w", err)
	}
	if resp.StatusCode() != 200 {
		return "", fmt.Errorf("OA token endpoint returned %d: %s", resp.StatusCode(), string(resp.Body()))
	}

	var tokenResp oaTokenResponse
	if err := json.Unmarshal(resp.Body(), &tokenResp); err != nil {
		return "", fmt.Errorf("parse OA token response failed: %w", err)
	}
	if tokenResp.AccessToken == "" {
		return "", fmt.Errorf("OA token response missing access_token, raw body: %s", string(resp.Body()))
	}
	return tokenResp.AccessToken, nil
}

// oaGetUserInfo 用 access_token 获取用户信息
func oaGetUserInfo(ctx context.Context, cfg config.OASSOConfig, accessToken string) (string, string, error) {
	resp, err := trace_util.NewResty(ctx).
		R().
		SetContext(ctx).
		SetHeader("Content-Type", "application/json").
		SetBody(map[string]string{
			"interface_code": "getCurrentUserInfo",
			"access_token":   accessToken,
		}).
		Post(cfg.ResourceURL)
	if err != nil {
		return "", "", fmt.Errorf("http request failed: %w", err)
	}
	if resp.StatusCode() != 200 {
		return "", "", fmt.Errorf("OA resource endpoint returned %d: %s", resp.StatusCode(), string(resp.Body()))
	}

	var userResp oaUserInfoResponse
	if err := json.Unmarshal(resp.Body(), &userResp); err != nil {
		return "", "", fmt.Errorf("parse OA user response failed: %w", err)
	}
	return userResp.Account, userResp.FullName, nil
}

// findOrCreateUser 按用户名查找用户，不存在则自动创建
func findOrCreateUser(ctx context.Context, account, fullName string) (string, error) {
	// 按配置的组织名查找 orgID，兜底为 TopOrgID
	orgID, err := resolveOrgID(ctx)
	if err != nil {
		return "", fmt.Errorf("resolve org id failed: %w", err)
	}

	// 用 GetUserList 按 userName 模糊查找，然后精确匹配
	userListResp, err := iam.GetUserList(ctx, &iam_service.GetUserListReq{
		OrgId:    orgID,
		UserName: account,
		PageNo:   1,
		PageSize: 10,
	})
	if err != nil {
		return "", fmt.Errorf("get user list failed: %w", err)
	}

	// 精确匹配
	for _, u := range userListResp.Users {
		if u.GetUserName() == account {
			// 用户已存在，更新最后登录时间
			return u.GetUserId(), nil
		}
	}

	// 用户不存在，自动创建
	nickName := fullName
	if nickName == "" {
		nickName = account
	}

	// 查找默认角色，兜底为「普通用户」
	var roleIDs []string
	defaultRoleName := config.Cfg().OASSO.DefaultRoleName
	if defaultRoleName == "" {
		defaultRoleName = "普通用户"
	}
	roleSelectResp, err := iam.GetRoleSelect(ctx, &iam_service.GetRoleSelectReq{
		OrgId: orgID,
	})
	if err != nil {
		return "", fmt.Errorf("get role select failed: %w", err)
	}
	for _, r := range roleSelectResp.Roles {
		if r.GetName() == defaultRoleName {
			roleIDs = append(roleIDs, r.GetId())
			break
		}
	}
	// 如果没匹配到默认角色，再次尝试匹配「普通用户」
	if len(roleIDs) == 0 && defaultRoleName != "普通用户" {
		for _, r := range roleSelectResp.Roles {
			if r.GetName() == "普通用户" {
				roleIDs = append(roleIDs, r.GetId())
				break
			}
		}
	}

	// 生成随机密码
	password := config.Cfg().OASSO.DefaultPassword
	if password == "" {
		password = "wanwu@123456" // fallback
	}

	createResp, err := iam.CreateUser(ctx, &iam_service.CreateUserReq{
		CreatorId: config.SystemAdminUserID,
		OrgId:     orgID,
		UserName:  account,
		NickName:  nickName,
		Password:  util.SHA256(password),
		RoleIds:   roleIDs,
		Company:   "教职工",
	})
	if err != nil {
		return "", fmt.Errorf("create user failed: %w", err)
	}

	return createResp.GetId(), nil
}

// getFirstOrgID 获取用户所属的第一个组织 ID，优先返回配置的 default_org_name
func getFirstOrgID(ctx context.Context, userID string) (string, error) {
	orgSelectResp, err := iam.GetOrgSelect(ctx, &iam_service.GetOrgSelectReq{
		UserId: userID,
	})
	if err != nil {
		return "", fmt.Errorf("get org select failed: %w", err)
	}
	if len(orgSelectResp.Selects) == 0 {
		return "", fmt.Errorf("user %s has no org", userID)
	}

	// 优先匹配配置的 default_org_name
	defaultOrgName := config.Cfg().OASSO.DefaultOrgName
	if defaultOrgName != "" {
		for _, org := range orgSelectResp.Selects {
			if org.GetName() == defaultOrgName {
				return org.GetId(), nil
			}
		}
	}

	return orgSelectResp.Selects[0].GetId(), nil
}

// resolveOrgID 根据配置的 default_org_id 或 default_org_name 查找组织 ID，兜底为 TopOrgID
func resolveOrgID(ctx context.Context) (string, error) {
	// 优先使用配置的 orgID
	if orgID := config.Cfg().OASSO.DefaultOrgID; orgID != "" {
		return orgID, nil
	}

	orgName := config.Cfg().OASSO.DefaultOrgName
	if orgName == "" {
		return config.TopOrgID, nil
	}

	// 通过 GetOrgList 按名称精确匹配（先查顶级组织，再查子组织）
	// 注意：GetOrgList 的 ParentId 为 0 时只查顶级组织
	for _, parentID := range []string{"0", "1", "2"} {
		orgListResp, err := iam.GetOrgList(ctx, &iam_service.GetOrgListReq{
			ParentId: parentID,
			PageNo:   1,
			PageSize: 100,
		})
		if err != nil {
			return "", fmt.Errorf("get org list failed: %w", err)
		}
		for _, org := range orgListResp.Orgs {
			if org.GetName() == orgName {
				return org.GetOrgId(), nil
			}
		}
	}

	// 未匹配到，兜底为 TopOrgID
	return config.TopOrgID, nil
}