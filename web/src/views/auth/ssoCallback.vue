<template>
  <div class="sso-callback">
    <div class="sso-loading">
      <i class="el-icon-loading"></i>
      <p>正在登录中，请稍候...</p>
    </div>
  </div>
</template>

<script>
import { mapActions } from 'vuex';

export default {
  name: 'OASsoCallback',
  async created() {
    const token = this.$route.query.token;
    const orgId = this.$route.query.orgId;
    if (!token) {
      this.$message.error('登录失败，缺少授权令牌');
      this.$router.replace({ path: '/login' });
      return;
    }

    // 存储 token 和 orgId 并跳转首页
    await this.handleSSOToken(token, orgId);
  },
  methods: {
    ...mapActions('user', ['getPermissionInfo', 'getCommonInfo']),
    async handleSSOToken(token, orgId) {
      try {
        // 存储 token 到 store，并立即持久化到 localStorage
        this.$store.commit('user/setToken', token);
        if (orgId) {
          this.$store.commit('user/setUserInfo', { orgId });
        }
        // 强制持久化到 localStorage（vuex-persist 异步，手动触发保存）
        localStorage.setItem(
          'access_cert',
          JSON.stringify(this.$store.state.user),
        );

        // SSO 用户不需要修改密码，先标记为已设置（getPermissionInfo 内部会保留这个值）
        this.$store.commit('user/setPermission', { isUpdatePassword: true });

        // 先拉取权限和通用信息，再跳转首页
        try {
          await this.getPermissionInfo();
          await this.getCommonInfo();
        } catch (e) {
          // 权限或通用信息获取失败不阻塞跳转
          console.warn('SSO: getPermissionInfo/getCommonInfo failed', e);
        }

        // 跳转到首页（和正常登录一样的行为，取菜单第一个有权限的页面）
        const { fetchPermFirPath } = await import('@/utils/util');
        const { path } = fetchPermFirPath();
        this.$router.replace({ path: path || '/portal/generalAgent' });
      } catch (e) {
        console.error('SSO login error:', e);
        this.$message.error('登录失败，请重试');
        this.$router.replace({ path: '/login' });
      }
    },
  },
};
</script>

<style lang="scss" scoped>
.sso-callback {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  background: #f7f8fa;
  .sso-loading {
    text-align: center;
    i {
      font-size: 48px;
      color: #5983ff;
    }
    p {
      margin-top: 16px;
      font-size: 14px;
      color: #686f82;
    }
  }
}
</style>
