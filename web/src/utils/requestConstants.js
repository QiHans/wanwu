// 本地开发直连 BFF（BFF 路由不带 nginx 前缀）
// 生产环境通过 nginx 代理，nginx 剥离前缀后转发到 BFF
const DEV = process.env.NODE_ENV === 'development';

export const USER_API = DEV ? '/v1' : '/user/api/v1';
export const OPENURL_API = DEV ? '/openurl/v1' : '/service/url/openurl/v1';
export const OPENAPI_API = DEV ? '/openapi/v1' : '/service/api/openapi/v1';
export const MODEL_API = DEV ? '/v1' : '/use/model/api/v1';
export const WORKFLOW_API = DEV ? '/api' : '/workflow/api';
export const SERVICE_API = DEV ? '/v1' : '/service/api/v1';
